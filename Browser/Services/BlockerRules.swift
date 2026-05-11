import Foundation

enum BlockerRules {
    // MARK: - Domain blocklist (full request blocked)

    private static let blockedDomains: [String] = [
        // Google ad stack
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "googletagservices.com", "googletagmanager.com", "google-analytics.com",
        "adservice.google.com", "adservice.google.de", "adservice.google.fr",
        "pagead2.googlesyndication.com", "tpc.googlesyndication.com",
        "securepubads.g.doubleclick.net", "stats.g.doubleclick.net",
        // Facebook / Meta tracking
        "connect.facebook.net", "facebook.net",
        // Amazon / Microsoft / Apple ad systems
        "amazon-adsystem.com", "adsystem.com", "bingads.microsoft.com",
        "clarity.ms", "bat.bing.com",
        // Major DSPs / SSPs / exchanges
        "adnxs.com", "rubiconproject.com", "pubmatic.com", "openx.net", "openx.com",
        "criteo.com", "criteo.net", "adsrvr.org", "adform.net",
        "smartadserver.com", "smaato.net", "media.net", "casalemedia.com",
        "indexww.com", "indexexchange.com", "yieldmo.com", "yieldlab.net",
        "contextweb.com", "spotxchange.com", "sharethrough.com",
        "districtm.io", "33across.com", "appnexus.com", "adsymptotic.com",
        "improvedigital.com", "lijit.com", "freewheel.tv", "kargo.com",
        "advertising.com",
        // Verification / brand safety / DMPs
        "moatads.com", "adsafeprotected.com", "doubleverify.com",
        "serving-sys.com", "flashtalking.com", "mediamath.com", "mathtag.com",
        "demdex.net", "everesttech.net", "omtrdc.net", "krxd.net",
        "rfihub.com", "turn.com", "tubemogul.com", "tribalfusion.com",
        "imrworldwide.com", "innovid.com", "tapad.com", "teads.tv",
        // Native / content recs
        "adroll.com", "outbrain.com", "taboola.com", "revcontent.com",
        "mgid.com", "engageya.com", "ligatus.com", "smartfeedco.com",
        // Pop / clickbait / shady
        "popads.net", "popcash.net", "propellerads.com", "exoclick.com",
        "trafficjunky.com", "juicyads.com", "adcash.com", "clicksor.com",
        "bidvertiser.com", "bidswitch.net",
        // Analytics / session-replay / behavioral
        "scorecardresearch.com", "quantserve.com", "chartbeat.com",
        "hotjar.com", "mxpnl.com", "mixpanel.com", "amplitude.com",
        "segment.com", "segment.io", "fullstory.com", "mouseflow.com",
        "smartlook.com", "heap.io", "newrelic.com", "branch.io",
        "appsflyer.com", "kochava.com", "intercom.io", "drift.com",
        "hs-scripts.com", "hs-analytics.net", "pardot.com", "marketo.com",
        "marketo.net", "munchkin.marketo.net", "6sense.com",
        "twitter.com/i/adsct", "ads-twitter.com", "static.ads-twitter.com",
        // TikTok / Snap / Pinterest ad pixels
        "analytics.tiktok.com", "tiktokcdn.com",
        "sc-static.net", "snapchat.com/p",
        "ct.pinterest.com",
        // EU / CEE specific
        "dotmetrics.net", "dotmetrics.rocks", "adex.dotmetrics.net",
        "iprom.net", "iprom.hr", "iprom.si",
        "adverticum.com", "adverticum.net",
        "gemius.pl", "gemius.com", "gemius.hr",
        "aticdn.net", "atinternet-solutions.com",
        "im-apps.net", "dmp.im-apps.net",
        // Misc trackers seen in the wild
        "defractal.com", "perfdrive.com", "freshatl.azurewebsites.net",
        "cookielaw.org", "onetrust.com",
        "privacy-center.org",
        // Common ad CDN buckets
        "ad-stir.com", "casalemedia.com",
    ]

    // MARK: - Cosmetic (element-hiding) selectors

    /// Selectors that are safe to hide everywhere — they're long-established ad-slot conventions.
    private static let globalAdSelectors: [String] = [
        // Google Publisher Tag (GPT) and AdSense
        "[id^='div-gpt-ad-']",
        "[id^='google_ads_iframe_']",
        "iframe[id^='google_ads_iframe']",
        "ins.adsbygoogle",
        "iframe[src*='doubleclick.net']",
        "iframe[src*='googlesyndication']",
        "iframe[src*='googleadservices']",
        "iframe[src*='adservice.google']",
        // Generic ad container conventions
        ".advertisement", ".advert", ".ads-container",
        ".ad-banner", ".ad-container", ".ad-wrapper", ".ad-slot", ".ad-placeholder",
        ".banner-ad", ".sidebar-ad", ".top-ad", ".bottom-ad", ".sticky-ad",
        ".sponsored-content", ".promoted-content", ".sponsor-strip",
        "[data-ad-slot]", "[data-ad-unit]", "[data-google-query-id]",
        // Outbrain / Taboola widgets
        "[id^='outbrain_widget_']", ".OUTBRAIN", "div[data-widget-id^='Outbrain']",
        ".trc_related_container", "div[id^='taboola-']",
    ]

    /// Site-specific selectors. Keyed by domain suffix.
    private static let siteSpecificSelectors: [(domain: String, selectors: [String])] = [
        (
            domain: "njuskalo.hr",
            selectors: [
                ".adexElement",
                ".Banner",
                ".BannerAlignment", ".BannerAlignment-inner",
                ".BannerHelper-stickyContainer", ".BannerHelper-stickyParent",
                ".BannerSticky", ".BannerFloating", ".BannerFloating-inner",
                ".EntityList-bannerContainer", ".EntityList-item--banner",
                ".Banner--list", ".Banner--listTop", ".Banner--listBottom",
                ".Banner--sky-other", ".Banner--floater", ".Banner--floating",
                ".Banner--adsenseForSearch", ".Banner--verticalSpacing",
                ".Banner--fixedHeight280",
            ]
        ),
        // Index Hr / Jutarnji / 24 sata could go here too; add as users report.
    ]

    // MARK: - JSON output

    /// Path segments that signal an ad endpoint regardless of host.
    private static let adPathSegments: [String] = [
        "ads", "adv", "advert", "advertising", "advertisement",
        "adserver", "adservice", "adsense", "adsystem",
    ]

    /// Hostname prefixes that signal an ad subdomain (`ads.example.com`, `adx.example.com`).
    private static let adSubdomainPrefixes: [String] = [
        "ads", "adsrv", "adserver", "adsystem", "advertising", "adtech", "adx",
    ]

    static var json: String {
        // Important: WKContentRuleList regex is a strict subset of NSRegularExpression.
        // It explicitly DOES NOT support disjunctions (`|`) — not even inside groups.
        // So every pattern below uses single literals, character classes, and
        // anchors only at the very start.
        var rules: [[String: Any]] = []

        // 1. Block requests to known ad/tracker domains.
        //    For each domain we emit two rules — one for the apex (`://example.com/`)
        //    and one for subdomains (`.example.com/`). For path-style entries
        //    that already include a slash, we only emit the apex rule.
        for domain in blockedDomains {
            let escaped = NSRegularExpression.escapedPattern(for: domain)
            if domain.contains("/") {
                rules.append([
                    "trigger": ["url-filter": "://\(escaped)"],
                    "action": ["type": "block"]
                ])
            } else {
                rules.append([
                    "trigger": ["url-filter": "://\(escaped)[/:?]"],
                    "action": ["type": "block"]
                ])
                rules.append([
                    "trigger": ["url-filter": "\\.\(escaped)[/:?]"],
                    "action": ["type": "block"]
                ])
            }
        }

        // 2. Block URLs whose path contains classic ad path segments — one rule per segment.
        for segment in adPathSegments {
            rules.append([
                "trigger": ["url-filter": "/\(segment)/"],
                "action": ["type": "block"]
            ])
        }

        // 3. Block hostnames whose subdomain prefix is ad-related — one rule per prefix.
        for prefix in adSubdomainPrefixes {
            rules.append([
                "trigger": ["url-filter": "^https?://\(prefix)\\.[^/]+/"],
                "action": ["type": "block"]
            ])
        }

        // 4. Cosmetic: hide common ad-slot conventions everywhere.
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": [
                "type": "css-display-none",
                "selector": globalAdSelectors.joined(separator: ", ")
            ]
        ])

        // 5. Cosmetic: site-specific hides.
        //    `if-domain` matches the page's domain or any of its subdomains, so
        //    we pass the bare domain (no `*` prefix).
        for (domain, selectors) in siteSpecificSelectors {
            rules.append([
                "trigger": [
                    "url-filter": ".*",
                    "if-domain": [domain]
                ],
                "action": [
                    "type": "css-display-none",
                    "selector": selectors.joined(separator: ", ")
                ]
            ])
        }

        let data = (try? JSONSerialization.data(withJSONObject: rules, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
