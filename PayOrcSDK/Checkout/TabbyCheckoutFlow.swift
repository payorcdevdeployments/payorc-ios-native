import UIKit

// MARK: - TabbyCheckoutFlow

/// Orchestrates the full Tabby BNPL checkout flow.
///
/// This is the direct Swift equivalent of Flutter's `TabbyCheckoutFlow.runHostedCheckout(...)`.
///
/// ## Flow (mirrors Flutter exactly)
///
/// ```
/// 1. POST sdk/tabby/init       — PayOrc back-end (HMAC-signed)
/// 2. TabbyAPI.createSession    — Tabby API (api.tabby.ai)
/// 3. TabbyWebViewController    — in-app WKWebView checkout
/// 4. POST sdk/tabby/confirm    — PayOrc back-end (on .authorized)
/// 5. onAuthorized / onError    — callback to host app
/// ```
///
/// Do not instantiate directly — call ``runHostedCheckout`` from `PayOrc.showTabbyCheckout`.
public enum TabbyCheckoutFlow {

    // MARK: - Public API

    /// Runs the full hosted Tabby BNPL checkout starting from `viewController`.
    ///
    /// Mirrors `TabbyCheckoutFlow.runHostedCheckout(context:paymentRequest:...)` in Flutter.
    @MainActor
    public static func runHostedCheckout(
        from viewController: UIViewController,
        request: PaymentRequest,
        paymentRepository: PaymentRepository,
        fallbackMerchantCode: String,
        onAuthorized: ((PayOrcSDKResult) -> Void)? = nil,
        onError:      ((PayOrcError) -> Void)?      = nil
    ) {
        Task {
            do {
                // ── Step 1: PayOrc Tabby init ─────────────────────────────────
                let initPayload  = try request.tabbyInitPayload()
                let initResponse = try await paymentRepository.initTabby(body: initPayload)

                #if DEBUG
                print("[TabbyFlow] initTabby response: status=\(initResponse.status) code=\(initResponse.code) message=\(initResponse.message)")
                if let d = initResponse.data {
                    print("[TabbyFlow] response.data keys: \(Array(d.keys).sorted())")
                } else {
                    print("[TabbyFlow] response.data is nil after decoding")
                }
                #endif

                guard let initData = TabbyInitData.fromResponseData(initResponse.data) else {
                    let msg = !initResponse.message.isEmpty
                        ? initResponse.message
                        : "Tabby init failed — no data returned."
                    reportError(.apiFailure(code: initResponse.code, message: msg), onError: onError)
                    return
                }

                #if DEBUG
                print("[TabbyFlow] TabbyInitData parsed: orderId=\(initData.orderId) merchantCode=\(initData.merchantCode) password=\(initData.password.isEmpty ? "(empty)" : "(set)")")
                #endif

                let apiKey = initData.password.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !apiKey.isEmpty else {
                    reportError(.invalidConfiguration("Tabby init did not return an API key."), onError: onError)
                    return
                }

                let orderId = initData.orderId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !orderId.isEmpty else {
                    reportError(.invalidConfiguration("Tabby init did not return order_id."), onError: onError)
                    return
                }

                // Use init-response merchantCode if non-empty, else fall back to config value.
                // Mirrors Flutter:
                //   final merchantCode = (initData.merchantCode?.trim().isNotEmpty ?? false)
                //       ? initData.merchantCode!.trim()
                //       : fallbackMerchantCode;
                let rawMerchantCode      = initData.merchantCode.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedMerchantCode = rawMerchantCode.isEmpty ? fallbackMerchantCode : rawMerchantCode

                // Always use production — mirrors Flutter's hardcoded Environment.production
                // in TabbySDK().setup(withApiKey: apiKey, environment: Environment.production)
                #if DEBUG
                print("[TabbyFlow] Using Tabby env=production merchantCode=\(resolvedMerchantCode)")
                #endif

                // ── Step 2: Tabby createSession ───────────────────────────────
                let tabbyAPI      = TabbyAPI(apiKey: apiKey, environment: .production)
                let sessionPayload = try request.tabbySessionPayload(merchantCode: resolvedMerchantCode)
                let session        = try await tabbyAPI.createSession(paymentPayload: sessionPayload)

                // ── Step 3: Session validation ────────────────────────────────
                #if DEBUG
                print("[TabbyFlow] Session: status=\(session.status) paymentId=\(session.paymentId) webUrl=\(session.webUrl ?? "nil") rejectionReason=\(session.rejectionReason ?? "nil")")
                #endif

                if session.status == .rejected {
                    let reason = session.rejectionReason ?? "Tabby rejected the session."
                    reportError(.apiFailure(code: "REJECTED", message: reason), onError: onError)
                    return
                }

                guard let webUrlString = session.webUrl, !webUrlString.isEmpty,
                      let webUrl = URL(string: webUrlString) else {
                    reportError(
                        .invalidConfiguration("Tabby checkout is not available for this order."),
                        onError: onError
                    )
                    return
                }

                // ── Step 4: Present WebView ───────────────────────────────────
                await openWebCheckout(
                    from:              viewController,
                    webUrl:            webUrl,
                    orderId:           orderId,
                    tabbyPaymentId:    session.paymentId,
                    paymentRepository: paymentRepository,
                    onAuthorized:      onAuthorized,
                    onError:           onError
                )

            } catch let payOrcError as PayOrcError {
                print("[TabbyFlow] ❌ PayOrcError: \(payOrcError) — \(payOrcError.localizedDescription)")
                reportError(payOrcError, onError: onError)
            } catch {
                print("[TabbyFlow] ❌ Unexpected error: \(error)")
                reportError(.requestFailed(underlying: error), onError: onError)
            }
        }
    }

    // MARK: - Private helpers

    /// Presents `TabbyWebViewController` and wires up its `onResult` callback.
    ///
    /// Mirrors Flutter's `openWebCheckout(...)` + `TabbyWebView.showWebView(...)`.
    /// Every result case calls `Navigator.of(context).pop()` in Flutter — replicated
    /// here via `dismissThen { ... }` which dismisses the nav sheet before firing
    /// the host-app callback.
    @MainActor
    private static func openWebCheckout(
        from viewController: UIViewController,
        webUrl:              URL,
        orderId:             String,
        tabbyPaymentId:      String,
        paymentRepository:   PaymentRepository,
        onAuthorized:        ((PayOrcSDKResult) -> Void)?,
        onError:             ((PayOrcError) -> Void)?
    ) async {
        // Mirrors Flutter's `_resultHandled` guard.
        var resultHandled = false

        // A simple reference box so `nav` can be weakly captured in the closure
        // before it is assigned below (closures are set up before `nav` exists).
        final class Ref<T: AnyObject> { weak var value: T? }
        let navRef = Ref<UINavigationController>()

        /// Dismiss the sheet then run `completion` — mirrors Flutter's
        /// `Navigator.of(context).pop()` which precedes every callback.
        /// Safe to call even when the sheet is already dismissing (UIKit no-ops).
        @MainActor func dismissThen(_ completion: @escaping @MainActor () -> Void) {
            if let nav = navRef.value, nav.presentingViewController != nil {
                nav.dismiss(animated: true) {
                    Task { @MainActor in completion() }
                }
            } else {
                completion()
            }
        }

        let webVC = TabbyWebViewController(webUrl: webUrl) { result in
            guard !resultHandled else { return }
            resultHandled = true

            switch result {

            case .authorized:
                // ── Step 5: Confirm with PayOrc ───────────────────────────────
                // Mirrors Flutter: Navigator.pop() → unawaited(onAuthorized(...))
                Task {
                    do {
                        let confirmBody: [String: Any] = [
                            "order_id":         orderId,
                            "tabby_payment_id": tabbyPaymentId,
                        ]
                        let confirmResponse = try await paymentRepository.confirmTabby(body: confirmBody)
                        let sdkResult = PayOrcSDKResult(
                            status:        confirmResponse.status,
                            code:          confirmResponse.code,
                            message:       confirmResponse.message,
                            transactionId: orderId
                        )
                        await MainActor.run {
                            dismissThen { onAuthorized?(sdkResult) }
                        }
                    } catch let payOrcError as PayOrcError {
                        print("[TabbyFlow] ❌ Confirm error: \(payOrcError) — \(payOrcError.localizedDescription)")
                        await MainActor.run {
                            dismissThen { reportError(payOrcError, onError: onError) }
                        }
                    } catch {
                        print("[TabbyFlow] ❌ Confirm unexpected error: \(error)")
                        await MainActor.run {
                            dismissThen { reportError(.requestFailed(underlying: error), onError: onError) }
                        }
                    }
                }

            case .rejected:
                // Mirrors Flutter: Navigator.pop() → onError('Tabby rejected the payment')
                dismissThen {
                    reportError(
                        .apiFailure(code: "REJECTED", message: "Tabby rejected the payment"),
                        onError: onError
                    )
                }

            case .expired:
                // Mirrors Flutter: Navigator.pop() — silently, no onError call
                dismissThen {}

            case .close:
                // The close button in TabbyWebViewController already calls dismiss()
                // before firing this result. dismissThen is safe to call again — UIKit
                // ignores a dismiss while one is already in progress.
                // Mirrors Flutter: Navigator.pop() → onError('Transaction was cancelled by user')
                dismissThen {
                    reportError(
                        .apiFailure(code: "CANCELLED", message: "Transaction was cancelled by user"),
                        onError: onError
                    )
                }
            }
        }

        // Present as a full-screen page sheet
        let nav = UINavigationController(rootViewController: webVC)
        navRef.value = nav
        nav.modalPresentationStyle = .pageSheet

        if #available(iOS 15.0, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents               = [.large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = PayOrcUIConstants.bottomSheetCornerRadius
            }
        }

        viewController.present(nav, animated: true)
    }

    /// Delivers `error` to `onError` on the main queue and always prints to console.
    @MainActor
    private static func reportError(
        _ error: PayOrcError,
        onError: ((PayOrcError) -> Void)?
    ) {
        print("[TabbyFlow] ❌ \(error) — \(error.localizedDescription)")
        onError?(error)
    }
}
