import Foundation

enum BlockerRules {
    private static let blockedDomains = [
        // Google ads / analytics
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "adservice.google.com", "g.doubleclick.net", "stats.g.doubleclick.net",
        // Facebook tracking
        "facebook.net", "connect.facebook.net",
        // Major ad networks
        "adnxs.com", "rubiconproject.com", "pubmatic.com", "openx.net",
        "amazon-adsystem.com", "adsystem.com", "advertising.com",
        "criteo.com", "criteo.net", "adsrvr.org", "adform.net",
        "smartadserver.com", "smaato.net", "media.net",
        "casalemedia.com", "indexww.com", "yieldmo.com",
        "moatads.com", "adsafeprotected.com", "doubleverify.com",
        "serving-sys.com", "flashtalking.com", "mediamath.com",
        "demdex.net", "everesttech.net", "krxd.net", "rfihub.com",
        "turn.com", "tubemogul.com", "tribalfusion.com", "spotxchange.com",
        "sharethrough.com", "imrworldwide.com", "innovid.com", "tapad.com",
        "teads.tv", "bttrack.com", "adroll.com", "outbrain.com", "taboola.com",
        // Analytics / tracking
        "scorecardresearch.com", "quantserve.com", "chartbeat.com",
        "hotjar.com", "mxpnl.com", "mixpanel.com", "amplitude.com",
        "segment.com", "segment.io", "fullstory.com", "mouseflow.com",
        "newrelic.com", "heap.io", "branch.io", "appsflyer.com",
        "kochava.com", "intercom.io", "drift.com",
        // Video / pop ads
        "popads.net", "popcash.net", "propellerads.com", "exoclick.com",
        "trafficjunky.com", "juicyads.com",
    ]

    static var json: String {
        let domains = blockedDomains.map { "\"*\($0)\"" }.joined(separator: ",")
        return """
        [
            {"trigger":{"url-filter":".*","if-domain":[\(domains)]},"action":{"type":"block"}},
            {"trigger":{"url-filter":"/(ads|adv|advert|advertising|advertisement)/"},"action":{"type":"block"}},
            {"trigger":{"url-filter":"/(banners|pop-?up|pop-?under)/"},"action":{"type":"block"}},
            {"trigger":{"url-filter":"\\\\.(doubleclick|googlesyndication|googleadservices)\\\\."},"action":{"type":"block"}},
            {"trigger":{"url-filter":"^https?://[^/]*\\\\.(ads|adsrv|adserver|adsystem|advertising)\\\\."},"action":{"type":"block"}},
            {"trigger":{"url-filter":".*","resource-type":["script","raw"],"if-domain":["*google-analytics.com","*googletagmanager.com","*googletagservices.com"]},"action":{"type":"block"}}
        ]
        """
    }
}
