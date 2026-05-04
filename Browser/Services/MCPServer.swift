import Foundation
import Network

/// Embedded HTTP MCP server. Listens on localhost only.
/// Single endpoint: POST /mcp — JSON-RPC 2.0 messages.
/// Auth: Authorization: Bearer <token>
@MainActor
final class MCPServer {
    enum Status: Equatable {
        case stopped
        case listening(port: UInt16)
        case error(String)
    }

    private(set) var status: Status = .stopped {
        didSet { onStatusChange?(status) }
    }
    var onStatusChange: ((Status) -> Void)?

    let token: String
    private let tools: BrowserTools
    private var listener: NWListener?

    init(token: String, tools: BrowserTools) {
        self.token = token
        self.tools = tools
    }

    func start(preferredPort: UInt16 = 9876) {
        stop()
        var port = preferredPort
        for attempt in 0..<10 {
            do {
                let nwPort = NWEndpoint.Port(integerLiteral: port)
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.acceptLocalOnly = true
                let listener = try NWListener(using: params, on: nwPort)
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self = self else { return }
                        switch state {
                        case .ready:
                            self.status = .listening(port: port)
                        case .failed(let err):
                            self.status = .error(err.localizedDescription)
                        case .cancelled:
                            self.status = .stopped
                        default:
                            break
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] conn in
                    Task { @MainActor in
                        self?.accept(conn)
                    }
                }
                listener.start(queue: .main)
                self.listener = listener
                _ = attempt // used port loop
                return
            } catch {
                port += 1
            }
        }
        status = .error("Failed to bind any port in 9876-9885")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        status = .stopped
    }

    func regenerateToken() -> String {
        // Caller is responsible for restarting the server with the new token; we hand back a fresh one.
        UUID().uuidString
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        readMore(conn: conn, accumulated: Data())
    }

    private func readMore(conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    NSLog("MCP read error: \(error)")
                    conn.cancel()
                    return
                }
                var combined = accumulated
                if let data = data { combined.append(data) }

                if let request = self.parseHTTPRequest(combined) {
                    await self.respond(to: request, on: conn)
                } else if isComplete {
                    self.sendStatus(400, body: "Bad Request", on: conn)
                } else {
                    self.readMore(conn: conn, accumulated: combined)
                }
            }
        }
    }

    // MARK: - HTTP parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        let separator: [UInt8] = [0x0d, 0x0a, 0x0d, 0x0a] // \r\n\r\n
        guard let splitRange = data.range(of: Data(separator)) else { return nil }
        let headerData = data.subdata(in: 0..<splitRange.lowerBound)
        let bodyStart = splitRange.upperBound
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        let path = parts[1]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let bodyData = data.subdata(in: bodyStart..<data.endIndex)

        if let lengthStr = headers["content-length"], let length = Int(lengthStr) {
            if bodyData.count >= length {
                let body = bodyData.prefix(length)
                return HTTPRequest(method: method, path: path, headers: headers, body: Data(body))
            } else {
                return nil  // need more bytes
            }
        }
        return HTTPRequest(method: method, path: path, headers: headers, body: bodyData)
    }

    // MARK: - Routing

    private func respond(to request: HTTPRequest, on conn: NWConnection) async {
        if request.method == "OPTIONS" {
            sendResponse(status: 204, headers: [
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization",
                "Access-Control-Max-Age": "600"
            ], body: Data(), on: conn)
            return
        }

        if request.method == "GET" && (request.path == "/" || request.path == "/health") {
            sendJSON(status: 200, body: ["status": "ok", "service": "native-browser-mcp"], on: conn)
            return
        }

        let providedToken = (request.headers["authorization"] ?? "")
            .replacingOccurrences(of: "Bearer ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        guard providedToken == token else {
            sendJSON(status: 401, body: ["error": "unauthorized"], on: conn)
            return
        }

        guard request.method == "POST", request.path.hasPrefix("/mcp") else {
            sendJSON(status: 404, body: ["error": "not found"], on: conn)
            return
        }

        let messageJSON: Any
        do {
            messageJSON = try JSONSerialization.jsonObject(with: request.body, options: [])
        } catch {
            sendJSON(status: 400, body: ["error": "invalid json: \(error.localizedDescription)"], on: conn)
            return
        }

        // Support batched requests
        if let batch = messageJSON as? [[String: Any]] {
            var responses: [[String: Any]] = []
            for msg in batch {
                if let res = await processRPC(msg) {
                    responses.append(res)
                }
            }
            let body = (try? JSONSerialization.data(withJSONObject: responses, options: [])) ?? Data()
            sendResponse(status: 200, headers: jsonHeaders(), body: body, on: conn)
        } else if let msg = messageJSON as? [String: Any] {
            if let res = await processRPC(msg) {
                sendJSON(status: 200, body: res, on: conn)
            } else {
                // Notification — no response, but still send 202 Accepted with empty body
                sendResponse(status: 202, headers: jsonHeaders(), body: Data(), on: conn)
            }
        } else {
            sendJSON(status: 400, body: ["error": "expected JSON object or array"], on: conn)
        }
    }

    // MARK: - JSON-RPC dispatch

    private func processRPC(_ rpc: [String: Any]) async -> [String: Any]? {
        let method = rpc["method"] as? String ?? ""
        let id = rpc["id"]
        let isNotification = (id == nil)
        let params = rpc["params"] as? [String: Any] ?? [:]

        func ok(_ result: Any) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        }
        func err(_ code: Int, _ message: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
        }

        switch method {
        case "initialize":
            return ok([
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "native-browser", "version": "1.0.0"]
            ])

        case "ping":
            return ok([:] as [String: Any])

        case "tools/list":
            return ok(["tools": BrowserTools.definitions])

        case "tools/call":
            guard let name = params["name"] as? String else {
                return err(-32602, "missing tool name")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let content = try await tools.call(name, arguments: args)
                return ok(["content": content, "isError": false])
            } catch let e as MCPError {
                return ok([
                    "content": [["type": "text", "text": e.description]],
                    "isError": true
                ])
            } catch {
                return ok([
                    "content": [["type": "text", "text": error.localizedDescription]],
                    "isError": true
                ])
            }

        case "notifications/initialized", "notifications/cancelled":
            return nil  // notifications produce no response

        case "":
            return err(-32600, "missing method")

        default:
            if isNotification { return nil }
            return err(-32601, "method not found: \(method)")
        }
    }

    // MARK: - Response writers

    private func jsonHeaders() -> [String: String] {
        [
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        ]
    }

    private func sendJSON(status: Int, body: [String: Any], on conn: NWConnection) {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data()
        sendResponse(status: status, headers: jsonHeaders(), body: data, on: conn)
    }

    private func sendStatus(_ status: Int, body: String, on conn: NWConnection) {
        sendResponse(status: status, headers: ["Content-Type": "text/plain"],
                     body: Data(body.utf8), on: conn)
    }

    private func sendResponse(status: Int, headers: [String: String], body: Data, on conn: NWConnection) {
        var head = "HTTP/1.1 \(status) \(reasonPhrase(status))\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for (k, v) in headers {
            head += "\(k): \(v)\r\n"
        }
        head += "\r\n"
        var response = Data(head.utf8)
        response.append(body)
        conn.send(content: response, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }
}
