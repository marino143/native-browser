# Native — lagani ARM browser za Apple Silicon

Native macOS preglednik napisan u SwiftUI + WebKit. Built za M1/M2/M3 chip.

## Što dobivaš

- **Native ARM64** binary (2 MB, vs Chrome ~600 MB)
- **WKWebView** (Apple WebKit) — isti engine kao Safari, ne Chromium
- **Ad blocking by default** — nativni `WKContentRuleList` (kao Safari Content Blocker, ne extension)
- **Tabovi, bookmarks, dark mode** — sve native SwiftUI
- **Jedan "Browser" proces** u Activity Monitoru — WebKit helperi (`WebContent`, `Networking`, `GPU`) su system-level, dijeljeni sa Safarijem
- **Manje RAM-a, bolja baterija** — WebKit je optimiziraniji za Apple Silicon nego Chromium

## Build

```bash
# Iz ovog direktorija:
xcodebuild -project Browser.xcodeproj -scheme Browser -configuration Release build

# Ili otvori u Xcode i pritisni Cmd+R
open Browser.xcodeproj
```

App se nalazi u `~/Library/Developer/Xcode/DerivedData/Browser-*/Build/Products/Release/Browser.app`

Premjesti u `/Applications`:
```bash
cp -r ~/Library/Developer/Xcode/DerivedData/Browser-*/Build/Products/Release/Browser.app /Applications/
```

## Keyboard shortcuts

| Shortcut | Akcija |
|---|---|
| `Cmd+T` | Novi tab |
| `Cmd+W` | Zatvori tab |
| `Cmd+R` | Reload |
| `Cmd+L` | Fokus address bar |
| `Cmd+Shift+D` | Toggle dark mode |
| `Cmd+Shift+B` | Toggle bookmarks bar |
| `Cmd+,` (back) `Cmd+]` (forward) | Native gesture na trackpadu radi |

## Adresna traka

- Upiši URL → otvara
- Upiši riječi → DuckDuckGo search
- ⭐ za bookmark
- 🔒 lock icon = HTTPS, ⚠️ = HTTP

## Ad blocker

Nativni WebKit Content Rule List blokira:
- Google Ads (DoubleClick, AdSense, AdServices)
- Facebook tracking
- Glavne ad networks (Criteo, Outbrain, Taboola, Amazon Ads, AdNexus, itd.)
- Analytics (GA, GTM, Mixpanel, Hotjar, Amplitude, Segment, FullStory)
- Pop ads (PopAds, ExoClick, JuicyAds)

Pravila u [Browser/Services/BlockerRules.swift](Browser/Services/BlockerRules.swift) — proširi listu po želji.

## Struktura

```
Browser/
├── BrowserApp.swift          App entry, menu commands
├── Models/
│   ├── Tab.swift              Tab + WKWebView
│   ├── BrowserState.swift     Glavni state (tabovi, bookmarks, dark mode)
│   └── Bookmark.swift
├── Views/
│   ├── ContentView.swift      Glavni layout
│   ├── TabBarView.swift       Tab bar
│   ├── AddressBarView.swift   URL bar + nav buttons
│   ├── WebView.swift          NSViewRepresentable za WKWebView
│   └── BookmarksBarView.swift
└── Services/
    ├── AdBlocker.swift        WKContentRuleList compile/cache
    ├── BookmarksManager.swift JSON na disk u ~/Library/Application Support/Browser/
    └── BlockerRules.swift     Lista blokiranih domena
```

## Što fali (idući koraci)

- Bookmarks tree / folderi
- History (trenutno samo sessionski via WKBackForwardList)
- Find in page (Cmd+F)
- Downloads UI
- Picture-in-picture za video
- AppIcon (sad generic)
- Sync preko iCloud
- Per-tab favicon (sad generic globe)

## Tech notes

- **Deployment target:** macOS 13.0
- **Universal binary:** arm64 + x86_64 (na M1 izvršava arm64)
- **Code signing:** ad-hoc (`-`) za lokalni build, ne treba Apple Developer account
- **Sandbox:** isključen (osobni preglednik); za distribuciju dodati App Sandbox entitlement
- **Process model:** zajednički `WKProcessPool` (default u macOS 12+) — svi tabovi dijele iste WebKit helper procese
