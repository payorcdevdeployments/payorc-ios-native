// PayOrcStaticAPI.swift
// Static, drop-in-anywhere entry points on `PayOrc` — the Swift equivalent of Flutter's
// static `PayOrc.applePay(...)`, `PayOrc.addNewCard(...)`, `PayOrc.tabby(...)`,
// `PayOrc.submitOrder(...)`.
//
// Each function is a thin wrapper around the existing instance-based flows on
// `PayOrc.shared` — no networking, validation, theming, or presentation logic is
// duplicated here. Call these directly from any button's action, anywhere in the host
// app, once `PayOrc.initialize(configuration:)` has run.

import UIKit

public extension PayOrc {

    // MARK: - Apple Pay

    /// Opens the native Apple Pay sheet and submits the resulting token to PayOrc. No
    /// presenter is needed — the system `PKPaymentAuthorizationController` presents
    /// itself. Mirrors Flutter's `PayOrc.applePay`.
    ///
    /// - Parameters:
    ///   - request: The ``PaymentRequest`` describing the order.
    ///   - onAuthorized: Called on the main queue with a ``PayOrcSDKResult`` when the
    ///     wallet payment is confirmed successfully.
    ///   - onError: Called on the main queue with a ``PayOrcError`` when the flow fails,
    ///     is unavailable, or is cancelled by the user.
    static func applePay(
        request: PaymentRequest,
        onAuthorized: ((PayOrcSDKResult) -> Void)? = nil,
        onError: ((PayOrcError) -> Void)? = nil
    ) {
        guard let sdk = shared else { onError?(.sdkNotInitialized); return }
        sdk.showApplePayCheckout(request: request, onAuthorized: onAuthorized, onError: onError)
    }

    // MARK: - Tabby

    /// Opens the Tabby BNPL hosted checkout from `viewController`. Mirrors Flutter's
    /// `PayOrc.tabby`.
    ///
    /// - Parameters:
    ///   - viewController: The presenting `UIViewController` — pass the one behind
    ///     whatever button triggered this call.
    ///   - request: The ``PaymentRequest`` describing the order.
    ///   - onAuthorized: Called on the main queue with a ``PayOrcSDKResult`` when the
    ///     Tabby payment is confirmed successfully.
    ///   - onError: Called on the main queue with a ``PayOrcError`` when the flow fails,
    ///     is rejected, or is cancelled by the user.
    static func tabby(
        from viewController: UIViewController,
        request: PaymentRequest,
        onAuthorized: ((PayOrcSDKResult) -> Void)? = nil,
        onError: ((PayOrcError) -> Void)? = nil
    ) {
        guard let sdk = shared else { onError?(.sdkNotInitialized); return }
        sdk.showTabbyCheckout(
            from: viewController, request: request,
            onAuthorized: onAuthorized, onError: onError
        )
    }

    // MARK: - Add New Card

    /// Opens the add-card form, tokenises the entered card via `POST sdk/add-card`,
    /// runs the card-verification step when required, and hands the resulting
    /// token-enriched ``CardData`` back via `onAddCard`. This does **not** charge the
    /// card — pair with ``submitOrder(from:card:request:onSuccess:onError:onCancel:)``
    /// once the host is ready to charge it (immediately, or any time later using the
    /// saved token). Mirrors Flutter's `PayOrc.addNewCard`.
    ///
    /// ## Flow
    ///
    /// 1. Card-entry sheet — local validation only, same UI as ``presentCheckout``'s form.
    /// 2. `POST sdk/add-card` — tokenises the card (form stays open with a loading
    ///    button; on failure the form stays open and `onError` fires so the host can
    ///    show a message and let the user retry).
    /// 3. On a `redirect_url` response, the form sheet dismisses and
    ///    ``AddCardVerificationWebViewController`` presents to complete verification.
    /// 4. `onAddCard` fires with `card.paymentToken` populated once verification
    ///    succeeds; `onError` fires (verification sheet dismissed first) on failure or
    ///    cancellation.
    ///
    /// - Parameters:
    ///   - viewController: The presenting `UIViewController`.
    ///   - request: The ``PaymentRequest`` describing the order (used to prefill the
    ///     form and build the `/sdk/add-card` payload).
    ///   - onAddCard: Called with the token-enriched ``CardData`` once verification
    ///     completes successfully.
    ///   - onCancel: Called after the card-entry sheet dismisses itself, when the user
    ///     cancels before submitting.
    ///   - onError: Called on add-card / verification failure, or with
    ///     ``PayOrcError/sdkNotInitialized`` when the SDK hasn't been initialized yet.
    static func addNewCard(
        from viewController: UIViewController,
        request: PaymentRequest,
        onAddCard: @escaping (_ card: CardData) -> Void,
        onCancel: (() -> Void)? = nil,
        onError: ((PayOrcError) -> Void)? = nil
    ) {
        guard let sdk = shared else { onError?(.sdkNotInitialized); return }

        let viewModel = CheckoutViewModel(paymentRequest: request, paymentRepository: sdk.payments)
        let adapter = PayOrcStaticAddCardDelegateAdapter(onCancel: { onCancel?() })
        let checkoutVC = CheckoutViewController(viewModel: viewModel, delegate: adapter)
        checkoutVC.onCollectCard = { [weak viewController, adapter] card in
            _ = adapter // keep the delegate adapter alive for checkoutVC's lifetime
            guard let viewController else { return }

            viewModel.addCard(
                card: card,
                onSuccess: { response in
                    guard let redirectUrl = response.redirectUrl, !redirectUrl.isEmpty,
                          let url = URL(string: redirectUrl) else {
                        onError?(.apiFailure(
                            code: response.code.isEmpty ? "ADD_CARD_FAILED" : response.code,
                            message: response.message.isEmpty ? "Add card failed" : response.message
                        ))
                        return
                    }
                    // Dismiss the card-entry sheet first, then present verification
                    // fresh from the original presenter — same single-dismiss-point
                    // pattern used throughout PayOrc.swift's checkout flow.
                    viewController.dismiss(animated: true) {
                        presentAddCardVerification(
                            from: viewController, url: url, card: card,
                            onAddCard: onAddCard, onError: onError
                        )
                    }
                },
                onFailure: { error in onError?(error) }
            )
        }

        let nav = UINavigationController(rootViewController: checkoutVC)
        nav.modalPresentationStyle = .pageSheet
        viewController.present(nav, animated: true)
    }

    /// Presents ``AddCardVerificationWebViewController`` and, on a terminal postback,
    /// dismisses it before delivering the token-enriched ``CardData`` (or error) to
    /// the host — used only by ``addNewCard(from:request:onAddCard:onCancel:onError:)``.
    private static func presentAddCardVerification(
        from viewController: UIViewController,
        url: URL,
        card: CardData,
        onAddCard: @escaping (CardData) -> Void,
        onError: ((PayOrcError) -> Void)?
    ) {
        let webVC = AddCardVerificationWebViewController(url: url)
        webVC.onCompleted = { [weak viewController] body in
            guard let viewController else { return }
            viewController.dismiss(animated: true) {
                let status = (body["status"] as? String ?? "").lowercased()
                if status == "failed" || status == "failure" || status == "error" {
                    let code = (body["code"] as? String) ?? "ADD_CARD_FAILED"
                    let message = (body["message"] as? String) ?? "Card verification failed"
                    onError?(.apiFailure(code: code, message: message))
                    return
                }
                let data = body["data"] as? [String: Any]
                let token = (body["m_payment_token"] as? String) ?? (data?["m_payment_token"] as? String) ?? ""
                let enrichedCard = CardData(
                    cardNumber: card.cardNumber,
                    cardholderName: card.cardholderName,
                    expiryMonth: card.expiryMonth,
                    expiryYear: card.expiryYear,
                    cvv: card.cvv,
                    email: card.email,
                    countryCode: card.countryCode,
                    mobile: card.mobile,
                    paymentToken: token.isEmpty ? card.paymentToken : token,
                    cardNetwork: card.cardNetwork
                )
                onAddCard(enrichedCard)
            }
        }

        // Present directly (no UINavigationController wrapper) so the VC's own
        // .fullScreen style — set in its init — actually takes effect. Wrapping it in
        // a .pageSheet nav, as CheckoutViewController's 3DS webview does, overrides
        // that and leaves a gap above the toolbar where it doesn't reach the top edge.
        viewController.present(webVC, animated: true)
    }

    // MARK: - Submit Order

    /// Submits `card` for `request` — no card-entry UI — via the existing
    /// ``SubmittingOrderViewController`` flow. Pair with
    /// ``addNewCard(from:request:onAddCard:onCancel:onError:)``: call this once the host
    /// has collected (or already has) a ``CardData``. Mirrors Flutter's
    /// `PayOrc.submitOrder`.
    ///
    /// - Parameters:
    ///   - viewController: The presenting `UIViewController`.
    ///   - card: The card to charge.
    ///   - request: The ``PaymentRequest`` describing the order.
    ///   - onSuccess: Called on the main queue with a ``PayOrcSDKResult`` when the
    ///     payment is confirmed successfully.
    ///   - onError: Called on the main queue with a ``PayOrcError`` when submission
    ///     fails.
    ///   - onCancel: Called when the user cancels the submitting sheet.
    static func submitOrder(
        from viewController: UIViewController,
        card: CardData,
        request: PaymentRequest,
        onSuccess: ((PayOrcSDKResult) -> Void)? = nil,
        onError: ((PayOrcError) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        guard let sdk = shared else { onError?(.sdkNotInitialized); return }

        let viewModel = CheckoutViewModel(paymentRequest: request, paymentRepository: sdk.payments)
        let submittingVC = SubmittingOrderViewController(
            viewModel: viewModel,
            card: card,
            onSuccess: { result in
                viewController.dismiss(animated: true) { onSuccess?(result) }
            },
            onFailure: { error, _ in
                viewController.dismiss(animated: true) { onError?(error) }
            },
            onCancel: {
                viewController.dismiss(animated: true) { onCancel?() }
            }
        )
        viewController.present(submittingVC, animated: true)
    }
}

// MARK: - PayOrcStaticAddCardDelegateAdapter

/// Bridges ``PayOrcSDKDelegate`` to a single cancel closure for
/// ``PayOrc/addNewCard(from:request:onAddCard:onCancel:onError:)`` — collect-only mode
/// never triggers `payOrcDidComplete`/`payOrcDidFail` since nothing submits
/// automatically.
private final class PayOrcStaticAddCardDelegateAdapter: NSObject, PayOrcSDKDelegate {
    private let onCancel: () -> Void

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func payOrcDidComplete(result: PayOrcSDKResult) {}
    func payOrcDidFail(error: PayOrcError) {}
    func payOrcDidCancel() { onCancel() }
}
