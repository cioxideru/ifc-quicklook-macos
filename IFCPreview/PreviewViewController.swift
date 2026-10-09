import Cocoa
import Quartz
import WebKit
import os

/// Quick Look preview controller. Hosts a WKWebView that runs the bundled
/// web-ifc + three.js viewer, served over the `ifcql://` scheme.
final class PreviewViewController: NSViewController, QLPreviewingController {

    private static let log = Logger(subsystem: "com.ibaranov.IFCQuickLook", category: "preview")

    /// Files above this size are not parsed; the page shows a message instead.
    static let maxBytes = 250 * 1024 * 1024
    /// A preview must be ready within this long after the load starts, or we show what there is.
    static let readyTimeout: TimeInterval = 5

    private let schemeHandler = AppSchemeHandler()
    private var webView: WKWebView!
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var currentNavigation: WKNavigation?
    private var didFinishLoad = false

    // MARK: - View

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: AppSchemeHandler.scheme)
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(WeakMessageHandler(self), name: "host")

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 600), configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        self.webView = webView
        view = webView
    }

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(at url: URL) async throws {
        _ = view

        // Quick Look may reuse this controller for the next file. Resume the previous request
        // before replacing it, otherwise its continuation leaks and that preview hangs.
        if continuation != nil {
            Self.log.error("a new preview was requested while one was still pending")
            finish(.failure(CocoaError(.userCancelled)))
        }
        didFinishLoad = false

        // The token ties /model.ifc requests to this load, so the page left over from the
        // previous file cannot be served this one's bytes.
        let token = UUID().uuidString
        schemeHandler.fileURL = url
        schemeHandler.modelToken = token

        // Fail closed: a size we could not read is treated as too large rather than as zero,
        // which would slip past the limit exactly when the file is least understood.
        let probedSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let size = probedSize ?? 0
        let tooBig = probedSize == nil || size > Self.maxBytes

        var components = URLComponents()
        components.scheme = AppSchemeHandler.scheme
        components.host = AppSchemeHandler.host
        components.path = "/index.html"
        components.queryItems = [
            URLQueryItem(name: "name", value: url.lastPathComponent),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "tooBig", value: tooBig ? "1" : "0"),
            URLQueryItem(name: "t", value: token),
        ]
        let pageURL = components.url!
        // The file name is the user's data: keep it out of the unified log.
        Self.log.info("preview \(url.lastPathComponent, privacy: .private) (\(size) bytes, tooBig: \(tooBig))")

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            currentNavigation = webView.load(URLRequest(url: pageURL))
            // Armed here rather than in didFinish: a load that stalls before its first
            // navigation callback would otherwise never resume this continuation.
            startReadyTimeout()
        }
    }

    // MARK: - Completion

    private func finish(_ result: Result<Void, Error>) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        guard let c = continuation else { return }
        continuation = nil
        c.resume(with: result)
    }

    private func startReadyTimeout() {
        guard continuation != nil, timeoutWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.didFinishLoad {
                Self.log.info("ready timeout; showing page as is")
                self.finish(.success(()))
            } else {
                Self.log.error("the preview page did not load in time")
                self.finish(.failure(URLError(.timedOut)))
            }
        }
        timeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readyTimeout, execute: item)
    }

    /// Once the continuation has been resumed, Quick Look is already showing the web view, so
    /// a later failure has to be reported inside it rather than thrown.
    private func showFallback(_ message: String) {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let html = """
        <!doctype html><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <style>html,body{margin:0;height:100%;display:flex;align-items:center;justify-content:center;\
        background:#eef0f3;color:#1d1d1f;font:13px/1.5 -apple-system,system-ui,sans-serif;text-align:center}\
        @media(prefers-color-scheme:dark){html,body{background:#1c1c1e;color:#f2f2f7}}\
        b{display:block;font-size:14px;color:#ff453a;margin-bottom:6px}</style>
        <div><b>Preview failed</b>\(escaped)</div>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Callbacks carry no load identity of their own, so ignore ones belonging to a
    /// navigation this controller has already replaced.
    private func isCurrent(_ navigation: WKNavigation?) -> Bool {
        guard let currentNavigation, let navigation else { return true }
        return navigation === currentNavigation
    }
}

// MARK: - WKNavigationDelegate

extension PreviewViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard isCurrent(navigation) else { return }
        didFinishLoad = true
        startReadyTimeout()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isCurrent(navigation) else { return }
        Self.log.error("navigation failed: \(error.localizedDescription, privacy: .public)")
        if continuation != nil {
            finish(.failure(error))
        } else {
            showFallback("The preview page stopped loading.")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard isCurrent(navigation) else { return }
        Self.log.error("provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        if continuation != nil {
            finish(.failure(error))
        } else {
            showFallback("The preview page could not be loaded.")
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Self.log.error("web content process terminated")
        if continuation != nil {
            finish(.failure(CocoaError(.executableLoad)))
        } else {
            showFallback("This model needed more memory than the preview has. Open it in a BIM application.")
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only our own scheme and the in-place fallback page may navigate.
        let scheme = navigationAction.request.url?.scheme
        decisionHandler(scheme == nil || scheme == AppSchemeHandler.scheme || scheme == "about" ? .allow : .cancel)
    }
}

// MARK: - Messages from JavaScript

extension PreviewViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let text = (body["message"] as? String) ?? ""
        switch type {
        case "ready":
            Self.log.info("viewer ready: \(text, privacy: .public)")
            finish(.success(()))
        case "error":
            // Parse/render errors are shown inside the page; keep the preview visible.
            // The page keeps the file name out of this text so it is safe to log.
            Self.log.error("viewer error: \(text, privacy: .public)")
            finish(.success(()))
        case "log":
            Self.log.debug("js: \(text, privacy: .public)")
        default:
            break
        }
    }
}

/// Breaks the retain cycle WKUserContentController → handler → controller.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
