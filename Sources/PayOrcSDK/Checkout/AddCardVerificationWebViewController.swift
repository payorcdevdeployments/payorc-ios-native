import UIKit
import WebKit

// MARK: - AddCardVerificationWebViewController
//
// Presents the PayOrc add-card verification URL (the `redirect_url` returned by
// `POST sdk/add-card`) in a WKWebView. Mirrors Flutter's
// `AddCardPaymentWebView(forSdkPayment: false)`:
//   - Same JS bridge as the 3DS payment webview (``ThreeDSWebViewController``) —
//     forwards postMessage and console.log postbacks to Swift.
//   - Different completion signal: a card is verified when the postback's top-level
//     `status == "success"`, `code == "CARD_VERIFIED"`, or a nested
//     `data.status` / `data.order_status` is one of SUCCESS / AUTHORISED /
//     AUTHORIZED / CAPTURED / COMPLETED — not the `/sdk/payment`-specific signals
//     ``ThreeDSWebViewController`` looks for.
//   - Calls onCompleted(body) with the raw terminal postback (success or failure);
//     the caller extracts `m_payment_token` from it.
//   - Does NOT dismiss itself — same pattern as ``ThreeDSWebViewController``: the
//     presenter up the chain owns dismissal.

public final class AddCardVerificationWebViewController: UIViewController {

    // MARK: - Callbacks

    /// Called with the raw response body when card verification terminates (success
    /// or failure). Fired while still presented — the caller owns dismissal.
    public var onCompleted: (([String: Any]) -> Void)?

    // MARK: - Private

    private let url: URL
    private var webView: WKWebView!
    private var userContentController: WKUserContentController!
    private var completed = false

    /// JS channel name — must match the string used in the injected bridge script.
    private static let jsChannelName = "PayOrcAddCard"

    // MARK: - Init

    public init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        setupToolbar()
        webView.load(URLRequest(url: url))
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    // MARK: - Setup

    private func setupWebView() {
        userContentController = WKUserContentController()
        userContentController.add(self, name: Self.jsChannelName)

        let bridgeScript = WKUserScript(
            source: payOrcBridgeJS(channelName: Self.jsChannelName),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(bridgeScript)

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
    }

    private func setupToolbar() {
        let toolbar = UIView()
        toolbar.backgroundColor = PayOrcUIConstants.brandColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        let closeBtn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        closeBtn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        closeBtn.tintColor = .white
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),

            closeBtn.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
            closeBtn.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -8),
            closeBtn.widthAnchor.constraint(equalToConstant: 44),
            closeBtn.heightAnchor.constraint(equalToConstant: 44),

            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Closing without a terminal postback still delivers a terminal result to the
    /// host — same reasoning as ``ThreeDSWebViewController/closeTapped()``.
    @objc private func closeTapped() {
        guard !completed else { return }
        completed = true
        let callback = onCompleted
        onCompleted = nil
        callback?([
            "status":  "failed",
            "code":    "USER_CANCELLED",
            "message": "Card verification cancelled by user"
        ])
    }

    // MARK: - JS Injection

    private func injectBridge() {
        guard !completed else { return }
        let js = payOrcBridgeJS(channelName: Self.jsChannelName)
        webView.evaluateJavaScript(js) { _, _ in }
    }

    private func checkBody() {
        guard !completed else { return }
        webView.evaluateJavaScript("document.body ? document.body.innerText : \"\"") { [weak self] result, _ in
            guard let self, !self.completed else { return }
            guard let raw = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return }
            self.handleRawMessage(raw)
        }
    }

    // MARK: - Message Handling

    private func handleRawMessage(_ raw: String) {
        guard !completed, !raw.isEmpty else { return }
        guard raw.contains("p_order_id") else { return }

        if let data = raw.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            tryComplete(from: decoded)
            return
        }

        if let extracted = extractPostbackJSON(from: raw),
           let data = extracted.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            tryComplete(from: decoded)
            return
        }

        if !completed { tryCompleteLoose(from: raw) }
    }

    /// Mirrors Flutter's `_tryCompleteFromDecoded` (`forSdkPayment: false` branch): a
    /// card is verified on root `status == "success"`, `code == "CARD_VERIFIED"`, or a
    /// nested `data.status` / `data.order_status` success value.
    private func tryComplete(from map: [String: Any]) {
        guard !completed else { return }

        if isFailure(map) {
            finish(with: map)
            return
        }

        let topStatus    = (map["status"] as? String)?.lowercased() ?? ""
        let topCode      = (map["code"] as? String)?.uppercased() ?? ""
        let nested       = map["data"] as? [String: Any]
        let nestedStatus = (nested?["status"] as? String)?.uppercased() ?? ""
        let orderStatus  = (nested?["order_status"] as? String)?.uppercased() ?? ""

        let isSuccess = topStatus == "success" || topCode == "CARD_VERIFIED" ||
            nestedStatus == "SUCCESS" ||
            ["AUTHORISED", "AUTHORIZED", "CAPTURED", "COMPLETED"].contains(orderStatus)

        guard isSuccess else { return }
        finish(with: map)
    }

    private func isFailure(_ map: [String: Any]) -> Bool {
        let status = (map["status"] as? String)?.lowercased() ?? ""
        let code   = (map["code"] as? String)?.uppercased() ?? ""
        if status == "failed" || status == "failure" || status == "error" ||
            code == "PAYMENT_FAILED" || code == "FAILED" {
            return true
        }
        guard let nested = map["data"] as? [String: Any] else { return false }
        let nestedStatus = (nested["status"] as? String)?.uppercased() ?? ""
        let orderStatus  = (nested["order_status"] as? String)?.uppercased() ?? ""
        return nestedStatus == "FAILED" || nestedStatus == "FAILURE" ||
            orderStatus == "FAILED" || orderStatus == "DECLINED"
    }

    /// Loose regex fallback for truncated console-log postbacks — mirrors Flutter's
    /// `_tryCompleteFromPostbackLoose` (`forSdkPayment: false` branch).
    private func tryCompleteLoose(from raw: String) {
        let hasFailed = raw.range(of: #""status"\s*:\s*"(failed|failure|error)""#,
                                  options: [.regularExpression, .caseInsensitive]) != nil
        let hasPaymentFailed = raw.range(of: #""code"\s*:\s*"PAYMENT_FAILED""#,
                                         options: [.regularExpression, .caseInsensitive]) != nil
        let hasOrderFailed = raw.range(of: #""order_status"\s*:\s*"FAILED""#,
                                       options: [.regularExpression, .caseInsensitive]) != nil
        if hasFailed || hasPaymentFailed || hasOrderFailed {
            let message = firstCapture(pattern: #""message"\s*:\s*"([^"]*)""#, in: raw)
            finish(with: ["status": "failed", "code": "ADD_CARD_FAILED", "message": message ?? "Add card failed"])
            return
        }

        let hasCardVerified = raw.range(of: #""code"\s*:\s*"CARD_VERIFIED""#,
                                        options: [.regularExpression, .caseInsensitive]) != nil
        let hasRootSuccess = raw.range(of: #""status"\s*:\s*"success""#,
                                       options: [.regularExpression, .caseInsensitive]) != nil
        let hasTxnSuccess = raw.range(of: #""order_status"\s*:\s*"(AUTHORISED|AUTHORIZED|SUCCESS|CAPTURED|COMPLETED)""#,
                                      options: [.regularExpression, .caseInsensitive]) != nil
        guard hasCardVerified || hasRootSuccess || hasTxnSuccess else { return }

        let token = firstCapture(pattern: #""m_payment_token"\s*:\s*"([^"]*)""#, in: raw) ?? ""
        finish(with: [
            "status": "success",
            "code": hasCardVerified ? "CARD_VERIFIED" : "00",
            "m_payment_token": token
        ])
    }

    // MARK: - Finish

    private func finish(with body: [String: Any]) {
        guard !completed else { return }
        completed = true

        #if DEBUG
        print("[PayOrc AddCard] Terminal postback received.")
        #endif

        let callback = onCompleted
        onCompleted = nil
        callback?(body)
    }

    // MARK: - Helpers

    private func extractPostbackJSON(from message: String) -> String? {
        var s = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("\"") && s.hasSuffix("\"") {
            s = String(s.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
        }
        let lower = s.lowercased()
        if lower.hasPrefix("postback message") {
            s = String(s.dropFirst("postback message".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix(":") { s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces) }
        }
        if let sourceRange = s.range(of: ", source:", options: .caseInsensitive) {
            let before = String(s[s.startIndex..<sourceRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if before.hasSuffix("}") { s = before }
        }
        if s.hasPrefix("{") && s.hasSuffix("}") {
            if (try? JSONSerialization.jsonObject(with: s.data(using: .utf8) ?? Data())) != nil { return s }
        }
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(s[start...end])
        if (try? JSONSerialization.jsonObject(with: slice.data(using: .utf8) ?? Data())) != nil { return slice }
        return nil
    }

    private func firstCapture(pattern: String, in string: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string) else { return nil }
        return String(string[range])
    }

    // MARK: - Deinit

    deinit {
        userContentController.removeScriptMessageHandler(forName: Self.jsChannelName)
    }
}

// MARK: - WKNavigationDelegate

extension AddCardVerificationWebViewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectBridge()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.checkBody()
        }
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}

// MARK: - WKUIDelegate

extension AddCardVerificationWebViewController: WKUIDelegate {
    /// Same window.open() interception reasoning as ``ThreeDSWebViewController``.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - WKScriptMessageHandler

extension AddCardVerificationWebViewController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        guard message.name == Self.jsChannelName else { return }
        let raw = message.body as? String ?? ""
        handleRawMessage(raw)
    }
}
