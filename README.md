# Native — Lightweight ARM Browser for Apple Silicon

Native macOS browser built with SwiftUI + WebKit. Built for M1/M2/M3 Macs. **~8 MB installed**, vs Chrome's ~600 MB.

## Highlights

- **Native ARM64** binary (universal: arm64 + x86_64) — runs natively on Apple Silicon
- **WKWebView** (Apple WebKit) — same engine as Safari, not Chromium → better battery life, faster cold start
- **Default ad blocker** — native `WKContentRuleList` (like Safari Content Blocker, no Chrome-style extensions needed)
- **Multi-profile + multi-window** — separate cookies / login state / bookmarks / passwords per profile
- **Memory Saver** — idle tabs are discarded after X minutes, restored on click
- **Passwords** stored in **Apple Keychain** (synced via iCloud Keychain when the app is signed with an Apple Developer ID)
- **Mobile preview** — toggle UA to iPhone + 393×852 viewport
- **Web Inspector** — right-click → Inspect Element (just like Safari)
- **Built-in MCP HTTP server** — Claude Code/Desktop can connect and drive the browser (navigate, click, fill forms, screenshot, run JS)
- **Tab grouping** — tabs Claude is operating on are visually separated with a ✨ indicator

## Installation (for users)

### Download

Easiest path: head to **[Releases](https://github.com/marino143/native-browser/releases)** and grab the latest `Native-Browser-X.X.X.zip`.

### Install

```bash
unzip Native-Browser-0.1.0.zip
mv Browser.app /Applications/
```

Or just double-click the zip in Finder and drag `Browser.app` into your Applications folder.

### First launch — Gatekeeper

The app is not signed with a paid Apple Developer ID (it's an open-source project), so on first launch macOS Gatekeeper will warn: **"Cannot be opened because the developer cannot be verified."**

**Workaround** — pick one:

**Easiest**: in Finder, **right-click** on `Browser.app` → **"Open"** → confirm the dialog. Subsequent launches work normally.

**Faster, via terminal**:

```bash
xattr -cr /Applications/Browser.app
open /Applications/Browser.app
```

`xattr -cr` strips the quarantine attribute macOS adds to downloaded files, so Gatekeeper stops asking.

### System requirements

- macOS **14.0 Sonoma** or newer
- Apple Silicon (M1/M2/M3) or Intel — works on both (universal binary)

## Usage

| Shortcut | Action |
|---|---|
| `Cmd+T` / `Cmd+W` | New / close tab |
| `Cmd+N` | New window |
| `Cmd+L` | Focus address bar |
| `Cmd+R` | Reload |
| `Cmd+D` | Bookmark / unbookmark current page |
| `Cmd+Shift+B` | Toggle bookmarks bar |
| `Cmd+Opt+B` | Open **Bookmarks Manager** |
| `Cmd+Opt+;` | Open **Passwords Manager** |
| `Cmd+Shift+P` | Open **Profile Manager** |
| `Cmd+Shift+M` | Toggle mobile view (iPhone UA + 393×852 viewport) |
| `Cmd+Shift+A` | Toggle ad blocker |
| `Cmd+Shift+C` | Open **Claude Integration** sheet (MCP setup) |
| `Cmd+Opt+I` | Open Web Inspector (or just right-click → Inspect Element) |
| `Cmd+Shift+,` | Manage Profiles from the badge menu |

## Multi-profile

Click the profile badge in the top-right (e.g. ● Personal) → pick a profile from the **"Open in New Window"** section → a separate window opens with its own cookies, login state, bookmarks, and passwords. You can have multiple windows open at once, one per profile.

Deleting a profile wipes **all** of its data (cookies, history, bookmarks, passwords).

## Claude integration (MCP)

`Cmd+Shift+C` → **Claude Integration** sheet → click **"Copy command"** → paste in your terminal. Restart Claude Code and Claude can drive the browser via 18 tools (navigate, click, fill, exec_js, screenshot, list_tabs, switch_profile, set_mobile_mode, ...).

The server runs on `localhost:9876/mcp` with a bearer token (UUID, generated on first launch and persisted in UserDefaults).

## Build from source

For developers:

```bash
git clone https://github.com/marino143/native-browser.git
cd native-browser
open Browser.xcodeproj
# Cmd+R in Xcode
```

Or via the command line:

```bash
xcodebuild -project Browser.xcodeproj -scheme Browser -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/Browser-*/Build/Products/Release/Browser.app
```

Requires macOS Sonoma (14.0+) and Xcode 15+.

## Architecture

```
Browser/
├── BrowserApp.swift                     # @main, WindowGroup, BrowserCommands
├── Models/
│   ├── BrowserState.swift               # per-window state (tabs, current profile, bookmarks)
│   ├── Tab.swift                        # WKWebView wrapper, mobile mode, source (user/agent), discard/reactivate
│   ├── Profile.swift                    # profile + color palette
│   └── Bookmark.swift
├── Views/
│   ├── ContentView.swift                # main layout + sheet bindings
│   ├── TabBarView.swift                 # tabs inline with traffic lights, agent grouping
│   ├── AddressBarView.swift
│   ├── WebView.swift                    # WKWebView NSViewRepresentable + mobile preview
│   ├── BookmarksBarView.swift / BookmarksManagerView.swift
│   ├── PasswordSavePromptView.swift / PasswordsManagerView.swift
│   ├── ProfileMenuView.swift / ProfileManagerView.swift
│   └── ClaudeIntegrationView.swift
└── Services/
    ├── BrowserServices.swift            # singleton: profiles, MCP, ad blocker, memory saver
    ├── MCPServer.swift                  # local HTTP/JSON-RPC server on port 9876
    ├── BrowserTools.swift               # 18 MCP tools targeting the active window
    ├── AutofillBridge.swift             # JS injection + form detection
    ├── PasswordStore.swift              # Keychain Services wrapper
    ├── ProfileManager.swift             # profile JSON persistence
    ├── BookmarksManager.swift           # bookmarks JSON per profile
    ├── AdBlocker.swift                  # WKContentRuleList compile/cache
    └── BlockerRules.swift               # ~70 blocked ad/tracking domains
```

**Singleton**: `BrowserServices.shared` holds cross-window state (profiles, MCP, ad blocker rules, memory saver).
**Per-window**: `BrowserState` owns tabs, currentProfile, bookmarks. Each new window = a new BrowserState.
**MCP target**: `WindowAccessor` maps NSWindow → BrowserState; whenever a window becomes key, MCP retargets to it.

## Privacy

- Everything stays **local** to your Mac
- Profiles → `~/Library/Application Support/Browser/profiles/<UUID>/`
- Passwords → your macOS Keychain (synchronizable flag is set → iCloud sync activates as soon as the app is signed with an Apple Developer ID)
- Cookies / cache / localStorage / IndexedDB → `WKWebsiteDataStore(forIdentifier: profile.UUID)` — system-managed per profile
- Default search engine: **DuckDuckGo** (no tracking)
- Default ad blocker: **on** (blocks ~70 domains: Google Ads, Facebook tracking, Criteo, Outbrain, Taboola, Mixpanel, Hotjar, GA, GTM, ...)
- **No telemetry, no analytics, no "phone home"** logic anywhere in the code

## Status

**v0.1.0** — initial public release. Stable for daily use, but a few v2 things are still missing:

- 🔐 Touch ID gate for password reveal/copy
- 🎲 Strong password generator
- 🔄 Update prompt when a saved password changes
- 📥 Import from Safari/Chrome (CSV)
- 📜 History UI (currently only `WKBackForwardList` per tab)
- 🔍 Find in page (Cmd+F)
- 📥 Downloads UI
- 🌐 Vertical tab bar (for 100+ tab workflows)
- 🧩 Apple Developer Team ID signing (enables iCloud Keychain sync, removes the Gatekeeper warning)

PRs welcome.

## License

MIT
