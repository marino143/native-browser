import Foundation
import WebKit

/// Per-window bridge that:
/// 1. Injects a small content script into every page (detects login forms,
///    posts a message when one is submitted).
/// 2. Receives those messages and either auto-fills a saved credential
///    (when the page first reveals a password field) or queues a save
///    prompt (after the user submits a form with new credentials).
@MainActor
final class AutofillBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "nativeAutofill"

    weak var state: BrowserState?

    init(state: BrowserState) {
        self.state = state
        super.init()
    }

    // MARK: - Plumbing into WKWebView config

    static var userScript: WKUserScript {
        WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    // MARK: - Message handling

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let host = body["host"] as? String,
              let state = state else { return }

        let webView = message.webView
        let profileID = state.currentProfileID

        switch action {
        case "detected":
            // Page just revealed a password field — try to autofill.
            let creds = PasswordStore.shared.credentials(forHost: host, profileID: profileID)
            guard creds.count == 1, let webView = webView else { return }
            let cred = creds[0]
            guard let password = PasswordStore.shared.revealPassword(
                host: cred.host, username: cred.username, profileID: profileID
            ) else { return }
            let js = "window.__nativeAutofillFill(\(jsString(cred.username)), \(jsString(password)));"
            webView.evaluateJavaScript(js, completionHandler: nil)

        case "submit":
            guard let username = body["username"] as? String,
                  let password = body["password"] as? String,
                  !password.isEmpty else { return }
            // Skip if identical credential already saved.
            let existing = PasswordStore.shared.credentials(forHost: host, profileID: profileID)
            if existing.contains(where: { $0.username == username }),
               PasswordStore.shared.revealPassword(host: host, username: username, profileID: profileID) == password {
                return
            }
            state.pendingPasswordSave = PendingPasswordSave(
                host: host, username: username, password: password
            )

        default:
            break
        }
    }

    private func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data()
        let str = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(str.dropFirst().dropLast())
    }

    // MARK: - Injected JS

    private static let js: String = """
    (function() {
        if (window.__nativeAutofillInstalled) return;
        window.__nativeAutofillInstalled = true;

        function findPasswordField() {
            return document.querySelector('input[type="password"]:not([disabled]):not([readonly])');
        }

        function findUsernameField(passwordField) {
            const form = passwordField.closest('form');
            const scope = form || document;
            const all = Array.from(scope.querySelectorAll('input'));
            const idx = all.indexOf(passwordField);
            // Walk backwards from the password field to find the most recent
            // visible text-like input — that's almost always the username.
            for (let i = idx - 1; i >= 0; i--) {
                const t = (all[i].type || 'text').toLowerCase();
                if (['text', 'email', 'tel', 'url', '', 'username'].includes(t) && !all[i].disabled) {
                    return all[i];
                }
            }
            return null;
        }

        function setValue(el, value) {
            if (!el) return;
            const proto = Object.getPrototypeOf(el);
            const setter = (Object.getOwnPropertyDescriptor(proto, 'value')
                           || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value'));
            if (setter && setter.set) {
                setter.set.call(el, value);
            } else {
                el.value = value;
            }
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
        }

        window.__nativeAutofillFill = function(username, password) {
            const pw = findPasswordField();
            if (!pw) return false;
            const un = findUsernameField(pw);
            if (un && username) setValue(un, username);
            if (pw && password) setValue(pw, password);
            return true;
        };

        function notify(msg) {
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeAutofill) {
                    window.webkit.messageHandlers.nativeAutofill.postMessage(msg);
                }
            } catch (_) {}
        }

        const seenForms = new WeakSet();

        function bindForm(form, passwordField) {
            if (!form || seenForms.has(form)) return;
            seenForms.add(form);
            form.addEventListener('submit', function () {
                const u = findUsernameField(passwordField);
                notify({
                    action: 'submit',
                    host: location.host,
                    username: u ? u.value : '',
                    password: passwordField.value || ''
                });
            }, true);
        }

        function scan() {
            const pw = findPasswordField();
            if (!pw) return;
            // Notify only once per password element so we don't autofill on every keystroke.
            if (!pw.__nativeAutofillSeen) {
                pw.__nativeAutofillSeen = true;
                notify({ action: 'detected', host: location.host });
            }
            const form = pw.closest('form');
            if (form) bindForm(form, pw);
            else {
                // Fallback for SPA: capture submit on Enter inside password field.
                if (!pw.__nativeAutofillEnter) {
                    pw.__nativeAutofillEnter = true;
                    pw.addEventListener('keydown', function (e) {
                        if (e.key === 'Enter') {
                            const u = findUsernameField(pw);
                            notify({
                                action: 'submit',
                                host: location.host,
                                username: u ? u.value : '',
                                password: pw.value || ''
                            });
                        }
                    }, true);
                }
            }
        }

        scan();
        // SPAs add login forms after initial render — re-scan on DOM mutations.
        const obs = new MutationObserver(() => scan());
        if (document.body) {
            obs.observe(document.body, { childList: true, subtree: true });
        }
    })();
    """
}

struct PendingPasswordSave: Equatable, Identifiable {
    let host: String
    let username: String
    let password: String
    var id: String { "\(host)-\(username)" }
}
