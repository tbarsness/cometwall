import Foundation
import WebKit

struct PaneConfig: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var url: URL
    /// Seconds between automatic reloads; nil or 0 means never.
    var refreshSeconds: Double?
    /// Accept a self-signed certificate for this pane's host only (LAN KVMs).
    var trustSelfSigned: Bool?
}

/// Loads the pane list from Application Support and owns one WKWebView per pane.
/// The same web view is reused by the grid and the sidebar, so switching layouts
/// never reloads a page or drops its scroll position.
@MainActor
final class PaneStore: ObservableObject {
    @Published private(set) var panes: [PaneConfig] = []
    /// Last load failure per pane name, shown on the tile; cleared on the next good load.
    @Published var errors: [String: PaneError] = [:]

    /// Hosts trusted with the in-app "Trust this certificate" button, kept across launches.
    @Published private(set) var userTrustedHosts: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "trustedHosts") ?? [])
    private var views: [String: WKWebView] = [:]
    private var timers: [String: Timer] = [:]
    private let uiDelegate = PopupDelegate()
    private lazy var navDelegate = TrustDelegate { [weak self] view, error in
        guard let self, let name = self.views.first(where: { $0.value === view })?.key else { return }
        self.errors[name] = error.map(PaneError.init)
    }

    static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CometWall", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("panes.json")
    }

    init() { reload() }

    func reload() {
        let url = Self.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            let sample = [
                PaneConfig(name: "Example A", url: URL(string: "https://example.com")!, refreshSeconds: nil),
                PaneConfig(name: "Example B", url: URL(string: "https://example.org")!, refreshSeconds: nil),
            ]
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try? enc.encode(sample).write(to: url)
        }
        let loaded = (try? JSONDecoder().decode([PaneConfig].self, from: Data(contentsOf: url))) ?? []

        // Drop web views for panes that left the config; keep the rest live.
        let keep = Set(loaded.map(\.name))
        for name in views.keys where !keep.contains(name) {
            views[name] = nil
            timers[name]?.invalidate()
            timers[name] = nil
        }
        panes = loaded
        updateTrust()
        for pane in loaded { schedule(pane) }
    }

    func webView(for pane: PaneConfig) -> WKWebView {
        if let v = views[pane.name] {
            if v.url == nil || v.url?.host != pane.url.host { v.load(URLRequest(url: pane.url)) }
            return v
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persists cookies, so logins survive relaunch
        // Some identity providers refuse embedded browsers; present as Safari.
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        let v = WKWebView(frame: .zero, configuration: config)
        v.uiDelegate = uiDelegate
        v.navigationDelegate = navDelegate
        v.allowsBackForwardNavigationGestures = true
        v.load(URLRequest(url: pane.url))
        views[pane.name] = v
        return v
    }

    /// Accept whatever certificate this host presents from now on, then retry.
    func trust(host: String, for pane: PaneConfig) {
        userTrustedHosts.insert(host)
        UserDefaults.standard.set(Array(userTrustedHosts).sorted(), forKey: "trustedHosts")
        updateTrust()
        errors[pane.name] = nil
        goHome(pane)
    }

    private func updateTrust() {
        navDelegate.trustedHosts = userTrustedHosts.union(
            panes.filter { $0.trustSelfSigned == true }.compactMap { $0.url.host })
    }

    func refresh(_ pane: PaneConfig) { views[pane.name]?.reload() }

    func goHome(_ pane: PaneConfig) { views[pane.name]?.load(URLRequest(url: pane.url)) }

    private func schedule(_ pane: PaneConfig) {
        timers[pane.name]?.invalidate()
        guard let s = pane.refreshSeconds, s > 0 else { timers[pane.name] = nil; return }
        timers[pane.name] = Timer.scheduledTimer(withTimeInterval: s, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.views[pane.name]?.reload() }
        }
    }
}

/// Opens window.open() popups (OAuth/SSO sign-in) in their own window. Without
/// this, a login button that opens a popup does nothing.
final class PopupDelegate: NSObject, WKUIDelegate {
    private var windows: [WKWebView: NSWindow] = [:]

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
        popup.uiDelegate = self
        let window = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = popup
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows[popup] = window
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        windows[webView]?.close()
        windows[webView] = nil
    }
}

/// Accepts the server certificate only for hosts a pane marked trustSelfSigned.
/// Every other host gets the system's normal certificate check.
final class TrustDelegate: NSObject, WKNavigationDelegate {
    var trustedHosts: Set<String> = []
    private let report: @MainActor (WKWebView, Error?) -> Void

    init(report: @escaping @MainActor (WKWebView, Error?) -> Void) { self.report = report }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { report(webView, nil) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { report(webView, error) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { report(webView, error) }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           trustedHosts.contains(space.host), let trust = space.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

struct PaneError {
    let message: String
    /// Set when the failure was a certificate problem the user can choose to trust.
    let untrustedHost: String?

    init(_ error: Error) {
        let ns = error as NSError
        message = ns.localizedDescription
        let certCodes: Set<Int> = [
            NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid,
            NSURLErrorSecureConnectionFailed,
        ]
        let url = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL
            ?? (ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
        untrustedHost = ns.domain == NSURLErrorDomain && certCodes.contains(ns.code) ? url?.host : nil
    }
}
