# Native — laki ARM browser za Apple Silicon

Native macOS preglednik napisan u SwiftUI + WebKit. Built za M1/M2/M3 Mac. **~8 MB instaliran**, vs Chrome ~600 MB.

## Bitno

- **Native ARM64** binary (universal: arm64 + x86_64) — radi native na Apple Silicon
- **WKWebView** (Apple WebKit) — isti engine kao Safari, ne Chromium → bolje baterijsko trajanje, brži cold start
- **Default ad blocker** — nativni `WKContentRuleList` (kao Safari Content Blocker, ne Chrome extension)
- **Multi-profil + multi-window** — odvojeni cookies / login state / bookmarks / passwords po profilu
- **Memory Saver** — idle tabovi se uspavju nakon X min, vraćaju na klik
- **Passwords** spremanje u **Apple Keychain** (sync preko iCloud Keychain ako app potpisan s Apple Developer ID-em)
- **Mobile preview** — toggle UA na iPhone + 393×852 viewport
- **Web Inspector** — right-click → Inspect Element (kao Safari)
- **MCP HTTP server** ugrađen — Claude Code/Desktop se može spojiti i upravljati preglednikom (navigate, click, fill, screenshot, exec JS)
- **Tab grupiranje** — tabovi koje Claude koristi su vizualno odvojeni s ✨ ikonom

## Instalacija (za korisnike)

### Skidanje

Najlakše: idi na **[Releases](https://github.com/marino143/native-browser/releases)** i skini najnoviji `Native-Browser-X.X.X.zip`.

### Otpakiranje

```bash
unzip Native-Browser-0.1.0.zip
mv Browser.app /Applications/
```

Ili dvoklik zip-a u Finderu i drag-drop `Browser.app` u Applications folder.

### Prvi launch — Gatekeeper

App nije signiran s plaćenim Apple Developer ID-em (radi se o open-source projektu), pa će macOS Gatekeeper pri prvom otvaranju pokazati upozorenje **"Cannot be opened because the developer cannot be verified"**.

**Rješenje** — bilo koji od:

**Najlakše**: u Finderu, **right-click** na `Browser.app` → **"Open"** → potvrdi dialog. Drugi launch i kasnije normalno radi.

**Brže preko terminala**:

```bash
xattr -cr /Applications/Browser.app
open /Applications/Browser.app
```

`xattr -cr` ukloni quarantine atribut koji macOS dodaje skinutim fileovima, pa Gatekeeper više ne pita.

### Što ti treba

- macOS **14.0 Sonoma** ili noviji
- Apple Silicon (M1/M2/M3) ili Intel — radi na oboma (universal binary)

## Korištenje

| Shortcut | Akcija |
|---|---|
| `Cmd+T` / `Cmd+W` | Novi / zatvori tab |
| `Cmd+N` | Novi prozor |
| `Cmd+L` | Fokus na address bar |
| `Cmd+R` | Reload |
| `Cmd+D` | Bookmark / unbookmark trenutnu stranicu |
| `Cmd+Shift+B` | Toggle bookmarks bar |
| `Cmd+Opt+B` | Otvori **Bookmarks Manager** |
| `Cmd+Opt+;` | Otvori **Passwords Manager** |
| `Cmd+Shift+P` | Otvori **Profile Manager** |
| `Cmd+Shift+M` | Toggle mobile view (iPhone UA + 393×852 viewport) |
| `Cmd+Shift+A` | Toggle ad blocker |
| `Cmd+Shift+C` | Otvori **Claude Integration** sheet (MCP setup) |
| `Cmd+Opt+I` | Otvori Web Inspector (ili samo right-click → Inspect Element) |
| `Cmd+Shift+,` | Manage Profiles iz badge menija |

## Multi-profil

Klikni profile badge gore desno (npr. ● Osobno) → izaberi profil iz **"Open in New Window"** sekcije → otvara se zasebni prozor sa svojim cookies, login state-om, bookmarks-ima i passwordsima. Možeš imati otvorena oba prozora istovremeno.

Brisanje profila → wipe **svih** podataka (cookies, history, bookmarks, passwords) za taj profil.

## Claude integracija (MCP)

Cmd+Shift+C → **Claude Integration** sheet → klik **"Copy command"** → paste u terminal. Restartaj Claude Code i mu Claude može upravljati preglednikom (18 toolova: navigate, click, fill, exec_js, screenshot, list_tabs, switch_profile, set_mobile_mode...).

Server radi na `localhost:9876/mcp` s bearer auth tokenom (UUID, generiran na prvom launchu, spremljen u UserDefaults).

## Build iz source-a

Za developere:

```bash
git clone https://github.com/marino143/native-browser.git
cd native-browser
open Browser.xcodeproj
# Cmd+R u Xcode
```

Ili komandno:

```bash
xcodebuild -project Browser.xcodeproj -scheme Browser -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/Browser-*/Build/Products/Release/Browser.app
```

Treba ti macOS Sonoma (14.0+) i Xcode 15+.

## Arhitektura

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
    ├── BrowserTools.swift               # 18 MCP tools targeting active window
    ├── AutofillBridge.swift             # JS injection + form detection
    ├── PasswordStore.swift              # Keychain Services wrapper
    ├── ProfileManager.swift             # profile JSON persistence
    ├── BookmarksManager.swift           # bookmarks JSON per profile
    ├── AdBlocker.swift                  # WKContentRuleList compile/cache
    └── BlockerRules.swift               # ~70 blocked ad/tracking domains
```

**Singleton:** `BrowserServices.shared` drži cross-window state (profiles, MCP, ad blocker rules, memory saver).
**Per-window:** `BrowserState` ima tabove, currentProfile, bookmarks. Svaki novi prozor = novi BrowserState.
**MCP target:** `WindowAccessor` mapira NSWindow → BrowserState; kad neki prozor postane key, MCP retargets na njega.

## Privatnost

- Sve ostaje **lokalno** na tvom Macu
- Profili → `~/Library/Application Support/Browser/profiles/<UUID>/`
- Passwords → tvoj macOS Keychain (synchronizable flag postavljen → iCloud sync čim app dobije Apple Developer signing)
- Cookies / cache / localStorage / IndexedDB → `WKWebsiteDataStore(forIdentifier: profile.UUID)` — system-managed po profilu
- Default search engine: **DuckDuckGo** (no tracking)
- Default ad blocker: **on** (blokira ~70 domena: Google Ads, Facebook tracking, Criteo, Outbrain, Taboola, Mixpanel, Hotjar, GA, GTM...)
- **Nema telemetry-a, nema analitike, nema "phone home"** logike u kodu

## Status

**v0.1.0** — početni public release. Stabilno za dnevno korištenje, ali još neke v2 stvari fale:

- 🔐 Touch ID gate za reveal/copy passworda
- 🎲 Strong password generator
- 🔄 Update prompt kad se lozinka promijeni
- 📥 Import iz Safari/Chrome (CSV)
- 📜 History UI (sad samo `WKBackForwardList` per-tab)
- 🔍 Find in page (Cmd+F)
- 📥 Downloads UI
- 🌐 Vertikalni tab bar (za 100+ tabova)
- 🧩 Apple Developer Team ID za potpis (omogućuje iCloud Keychain sync, uklanja Gatekeeper warning)

PR-ovi dobrodošli.

## License

MIT
