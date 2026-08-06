import UIKit
import WebKit

// MARK: - TabbyWebResult

/// Mirrors Flutter's `WebViewResult` enum from `tabby_flutter_inapp_sdk`.
///
/// Maps the Tabby JavaScript SDK bridge messages to strongly-typed outcomes:
/// - `.authorized` → user approved; proceed to `POST sdk/tabby/confirm`
/// - `.rejected`   → Tabby declined; surface an error
/// - `.expired`    → session timed out; dismiss silently (no error callback)
/// - `.close`      → user cancelled; surface a cancellation error
public enum TabbyWebResult {
    case authorized
    case rejected
    case expired
    case close
}

// MARK: - TabbyWebViewController

/// A `WKWebView`-based view controller that presents the Tabby BNPL checkout.
///
/// Mirrors Flutter's `TabbyWebView.showWebView(...)` behaviour:
/// - Loads the Tabby-supplied `webUrl` in a full-screen in-app `WKWebView`.
/// - Receives result events from the Tabby page via the **JavaScript message bridge**
///   (`window.webkit.messageHandlers.tabbyMobileSDK.postMessage(status)`) —
///   the same mechanism used by the demo app's existing `TabbyWebViewController`.
/// - Fires `onResult` **exactly once** (guarded by `resultHandled`), even if Tabby
///   fires multiple bridge messages (e.g. rejected → expired).
/// - Shows a `UIProgressView` while the page is loading (consistent with demo app).
/// - Provides a dismiss button (chevron.down.circle.fill) in the navigation bar,
///   matching all other PayOrc sheets.
final class TabbyWebViewController: UIViewController {

    // MARK: - Properties

    private let webUrl: URL
    private let onResult: (TabbyWebResult) -> Void

    /// Guards against multiple result callbacks — identical to Flutter's
    /// `var _resultHandled = false` in `TabbyCheckoutFlow.openWebCheckout`.
    private var resultHandled = false

    // MARK: - UI

    private var webView: WKWebView!
    private let progressView = UIProgressView(progressViewStyle: .bar)

    // MARK: - Init

    init(webUrl: URL, onResult: @escaping (TabbyWebResult) -> Void) {
        self.webUrl = webUrl
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(webUrl:onResult:)") }

    // MARK: - View Loading

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        // Register the JavaScript bridge that Tabby's page uses to post results
        contentController.add(self, name: "tabbyMobileSDK")
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupProgressView()
        setupNavigationBar()
        webView.addObserver(
            self,
            forKeyPath: #keyPath(WKWebView.estimatedProgress),
            options: .new,
            context: nil
        )
        webView.load(URLRequest(url: webUrl))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Sheet was swiped away without a terminal bridge message → treat as .close
        fireResult(.close)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Remove script message handler to prevent retain cycles
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "tabbyMobileSDK")
    }

    // MARK: - KVO

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == #keyPath(WKWebView.estimatedProgress) {
            progressView.progress = Float(webView.estimatedProgress)
            progressView.isHidden = webView.estimatedProgress >= 1.0
        }
    }

    // MARK: - Layout

    private func setupProgressView() {
        progressView.tintColor = PayOrcUIConstants.accentColor
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        ])
    }

    private func setupNavigationBar() {
        title = "Tabby"
        navigationController?.navigationBar.tintColor = PayOrcUIConstants.accentColor

        // Dismiss button — chevron.down.circle.fill (matches other PayOrc sheets)
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .light)
        let dismissBtn = UIBarButtonItem(
            image: UIImage(systemName: "chevron.down.circle.fill", withConfiguration: cfg),
            style: .plain,
            target: self,
            action: #selector(userClosedSheet)
        )
        dismissBtn.tintColor = .tertiaryLabel
        navigationItem.rightBarButtonItem = dismissBtn
    }

    // MARK: - Result

    /// Fires `onResult` at most once — subsequent calls are silently ignored.
    private func fireResult(_ result: TabbyWebResult) {
        guard !resultHandled else { return }
        resultHandled = true
        onResult(result)
    }

    // MARK: - Actions

    @objc private func userClosedSheet() {
        fireResult(.close)
        dismiss(animated: true)
    }

    // MARK: - Bridge Message Handling

    /// Translates a Tabby JS-bridge message string to a `TabbyWebResult`.
    ///
    /// Tabby's checkout page posts one of: `"authorized"`, `"rejected"`,
    /// `"expired"`, or `"close"` via `window.webkit.messageHandlers.tabbyMobileSDK`.
    private func handleBridgeMessage(_ message: String) {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "authorized": fireResult(.authorized)
        case "rejected":   fireResult(.rejected)
        case "expired":    fireResult(.expired)
        case "close":      fireResult(.close)
        default:           break
        }
    }
}

// MARK: - WKScriptMessageHandler

extension TabbyWebViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "tabbyMobileSDK" else { return }
        if let body = message.body as? String {
            handleBridgeMessage(body)
        } else if let body = message.body as? [String: Any],
                  let string = body["message"] as? String {
            handleBridgeMessage(string)
        }
    }
}

// MARK: - WKNavigationDelegate

extension TabbyWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // WebView load failure → close so user can retry
        fireResult(.close)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        fireResult(.close)
    }
}
