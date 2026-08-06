import UIKit
import WebKit

// MARK: - ThreeDSWebViewController
//
// Presents the PayOrc 3-D Secure checkout URL in a WKWebView.
// Mirrors Flutter's AddCardPaymentWebView(forSdkPayment: true):
//   - Injects a JS bridge that forwards postMessage and console.log postbacks to Swift.
//   - On each page load, reads document.body.innerText to catch terminal JSON responses.
//   - Calls onCompleted(body) when a terminal result is detected (success or failure).
//   - Dismisses itself BEFORE firing the callback (same pattern as TabbyCheckoutFlow).

public final class ThreeDSWebViewController: UIViewController {

    // MARK: - Callbacks

    /// Called with the raw response body when the 3DS flow terminates (success or failure).
    /// Fired AFTER the view controller has been dismissed.
    public var onCompleted: (([String: Any]) -> Void)?

    // MARK: - Private

    private let url: URL
    private var webView: WKWebView!
    private var userContentController: WKUserContentController!
    private var completed = false

    /// JS channel name — must match the string used in the injected bridge script.
    private static let jsChannelName = "PayOrcCheckout"

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

    // MARK: - Setup

    private func setupWebView() {
        userContentController = WKUserContentController()
        userContentController.add(self, name: Self.jsChannelName)

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
    }

    private func setupToolbar() {
        // Simple top bar with a close button (matches Flutter's iOS close icon on top-right)
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

    @objc private func closeTapped() {
        dismissSelf()
    }

    // MARK: - JS Injection

    /// Injects the PayOrc bridge on every page load — mirrors Flutter's `_injectPayOrcBridge`.
    private func injectBridge() {
        guard !completed else { return }
        let js = payOrcBridgeJS(channelName: Self.jsChannelName)
        webView.evaluateJavaScript(js) { _, _ in }
    }

    /// Reads document.body.innerText and tries to parse a terminal response.
    /// Mirrors Flutter's `_checkBody()`.
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

    /// Entry point for all incoming messages (JS channel + console.log postbacks).
    /// Mirrors Flutter's `_handleBridgeMessage`.
    private func handleRawMessage(_ raw: String) {
        guard !completed, !raw.isEmpty else { return }

        #if DEBUG
        let preview = raw.count > 400 ? String(raw.prefix(400)) + "…" : raw
        print("[PayOrc 3DS] Bridge message: \(preview)")
        #endif

        // 1. Try direct JSON parse
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            tryComplete(from: decoded)
            return
        }

        // 2. Try to extract embedded JSON (e.g. "postback message: {...}")
        if let extracted = extractPostbackJSON(from: raw),
           let data = extracted.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            tryComplete(from: decoded)
            return
        }

        // 3. Loose regex fallback for truncated messages
        if !completed { tryCompleteLoose(from: raw) }
    }

    /// Mirrors Flutter's `_tryCompleteSdkPaymentPostback`.
    /// Accepts any terminal result (success OR failure) and dismisses the WebView.
    private func tryComplete(from map: [String: Any]) {
        guard !completed else { return }

        let orderStatus = ((map["data"] as? [String: Any])?["order_status"]
            ?? (map["data"] as? [String: Any])?["status"] ?? "")
            .flatMap { $0 as? String }?.uppercased() ?? ""
        let topStatus   = (map["status"] as? String)?.lowercased() ?? ""
        let topCode     = (map["code"] as? String)?.uppercased() ?? ""

        // needs3ds — keep waiting
        if orderStatus == "AWAIT_3DS" { return }

        // needsCvv — keep waiting
        if topStatus == "requires_action" && (topCode == "CVV_REQUIRED" || (map["message"] as? String ?? "").lowercased().contains("cvv")) {
            return
        }

        let isSuccess = orderStatus == "SUCCESS" || orderStatus == "AUTHORIZED" ||
                        orderStatus == "AUTHORISED" || orderStatus == "CAPTURED" ||
                        orderStatus == "COMPLETED" ||
                        (topStatus == "success" && topCode == "00")

        let isFailure = topStatus == "failed" || topStatus == "failure" || topStatus == "error" ||
                        topCode == "PAYMENT_FAILED" || topCode == "FAILED" ||
                        orderStatus == "FAILED" || orderStatus == "DECLINED"

        if isSuccess || isFailure {
            finish(with: map)
        }
    }

    /// Loose regex fallback for truncated console log messages.
    /// Mirrors Flutter's `_tryCompleteFromPostbackLoose` (forSdkPayment branch).
    private func tryCompleteLoose(from raw: String) {
        let hasFailed = raw.range(of: #""status"\s*:\s*"(failed|failure|error)""#,
                                  options: [.regularExpression, .caseInsensitive]) != nil
        let hasPaymentFailed = raw.range(of: #""code"\s*:\s*"PAYMENT_FAILED""#,
                                         options: [.regularExpression, .caseInsensitive]) != nil
        let hasOrderFailed = raw.range(of: #""order_status"\s*:\s*"FAILED""#,
                                       options: [.regularExpression, .caseInsensitive]) != nil

        if hasFailed || hasPaymentFailed || hasOrderFailed {
            let message = firstCapture(pattern: #""message"\s*:\s*"([^"]*)""#, in: raw)
            finish(with: [
                "status": "failed",
                "code": "PAYMENT_FAILED",
                "message": message ?? "Payment failed"
            ])
        }
    }

    // MARK: - Finish

    /// Dismisses the WebView first, then fires `onCompleted` on the next run-loop tick.
    /// Mirrors Flutter's `_finishWithPostback` + `_popNavigator`.
    private func finish(with body: [String: Any]) {
        guard !completed else { return }
        completed = true

        #if DEBUG
        print("[PayOrc 3DS] Terminal postback received, dismissing WebView.")
        #endif

        let callback = onCompleted
        onCompleted = nil

        dismissSelf {
            DispatchQueue.main.async {
                callback?(body)
            }
        }
    }

    private func dismissSelf(completion: (() -> Void)? = nil) {
        if let nav = navigationController {
            nav.popViewController(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                completion?()
            }
        } else {
            dismiss(animated: true, completion: completion)
        }
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

extension ThreeDSWebViewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectBridge()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.checkBody()
        }
    }
}

// MARK: - WKScriptMessageHandler

extension ThreeDSWebViewController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        guard message.name == Self.jsChannelName else { return }
        let raw = message.body as? String ?? ""
        handleRawMessage(raw)
    }
}

// MARK: - JS Bridge Script
//
// Mirrors Flutter's `_payOrcBridgeJs` constant in add_card_payment_webview.dart.
// Forwards:
//   - window.postMessage events
//   - console.log / info / warn / debug / error containing postback indicators
// to the Swift message handler via window.webkit.messageHandlers.<channel>.postMessage.

private func payOrcBridgeJS(channelName: String) -> String {
    """
    (function () {
      if (window.__payOrcCheckoutHooked) return;
      window.__payOrcCheckoutHooked = true;

      function forward(raw) {
        try {
          var payload = raw;
          if (typeof payload !== 'string') {
            try { payload = JSON.stringify(payload); } catch (e) { return; }
          }
          window.webkit.messageHandlers.\(channelName).postMessage(payload);
        } catch (e) {}
      }

      function normalize(data) {
        if (data == null || data === '') return null;
        var s;
        if (typeof data === 'string') {
          s = data.trim();
        } else {
          try { s = JSON.stringify(data); } catch (e) { return null; }
        }
        var lower = s.toLowerCase();
        if (lower.indexOf('postback message') === 0) {
          s = s.substring('postback message'.length).trim();
          if (s.charAt(0) === ':') s = s.substring(1).trim();
        }
        try { JSON.parse(s); return s; } catch (e1) {
          var i0 = s.indexOf('{');
          var i1 = s.lastIndexOf('}');
          if (i0 >= 0 && i1 > i0) {
            var slice = s.substring(i0, i1 + 1);
            try { JSON.parse(slice); return slice; } catch (e2) {}
          }
        }
        return null;
      }

      window.addEventListener('message', function (e) {
        var n = normalize(e.data);
        if (n) forward(n);
      }, false);

      ['log', 'info', 'warn', 'debug', 'error'].forEach(function (level) {
        var c = window.console;
        if (!c || !c[level]) return;
        var orig = c[level].bind(c);
        c[level] = function () {
          var text = Array.prototype.slice.call(arguments).map(function (a) {
            if (typeof a === 'object' && a !== null) {
              try { return JSON.stringify(a); } catch (e) { return String(a); }
            }
            return String(a);
          }).join(' ');
          if (/postback\\s*message/i.test(text) ||
              /"p_order_id"\\s*:/.test(text) ||
              /'p_order_id'\\s*:/.test(text) ||
              /"code"\\s*:\\s*"PAYMENT_FAILED"/i.test(text) ||
              /"order_status"\\s*:\\s*"FAILED"/i.test(text) ||
              /"status"\\s*:\\s*"(failed|success)"/i.test(text)) {
            forward(text);
          }
          return orig.apply(null, arguments);
        };
      });
    })();
    """
}
