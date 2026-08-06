import Foundation
import UIKit

// MARK: - PayOrc

/// The central singleton for the PayOrc iOS SDK.
///
/// ## Setup
///
/// Initialize once at app launch, before any payment UI is shown:
///
/// ```swift
/// let config = PayOrcConfiguration(
///     merchantKey:    "YOUR_MERCHANT_KEY",
///     merchantSecret: "YOUR_MERCHANT_SECRET",
///     environment:    .sandbox
/// )
/// PayOrc.initialize(configuration: config)
/// ```
///
/// By default (`fetchCheckoutCustomizationOnInit = true`), the SDK automatically
/// fetches checkout customization from the PayOrc API in the background — exactly
/// mirroring the Flutter SDK's `fetchCheckoutCustomizationOnInit` behaviour.
///
/// ## Host UI Customization
///
/// Override SDK colors, fonts, and layout after `initialize`:
///
/// ```swift
/// PayOrc.setCustomization(PayOrcSDKCustomization(
///     brandColor: .systemIndigo,
///     button: PayOrcButtonCustomization(backgroundColor: .systemIndigo)
/// ))
/// ```
///
/// Host overrides take **highest priority**. They persist across checkout
/// customization refreshes. Resolution order: host override → API value → SDK default.
///
/// ## Manual Customization Refresh
///
/// ```swift
/// PayOrc.refreshCheckoutCustomization(currency: "AED", amount: 100) { result in
///     switch result {
///     case .success(let data): print("Refreshed:", data.availableMethods.count, "methods")
///     case .failure(let error): print("Failed:", error.localizedDescription)
///     }
/// }
/// ```
///
/// ## Notifications
///
/// Subscribe to ``PayOrc.checkoutCustomizationDidChange`` to reload UI after
/// any customization update (auto-fetch or manual refresh).
public final class PayOrc {

    // MARK: - Notification Names

    /// Posted on the main queue whenever checkout customization is successfully
    /// applied (auto-fetch on init or manual refresh).
    ///
    /// Equivalent to Flutter's `checkoutCustomizationRevision` ValueNotifier.
    public static let checkoutCustomizationDidChange =
        Notification.Name("PayOrc.checkoutCustomizationDidChange")

    /// Posted whenever any UI customization changes (host override or API update).
    public static let uiCustomizationDidChange =
        Notification.Name("PayOrc.uiCustomizationDidChange")

    // MARK: - Singleton

    /// The shared SDK instance. Access only after calling ``initialize(configuration:)``.
    public private(set) static var shared: PayOrc?

    /// `true` after ``initialize(configuration:)`` has been called successfully.
    public static var isInitialized: Bool { shared != nil }

    // MARK: - State

    /// The active SDK configuration.
    public private(set) var configuration: PayOrcConfiguration

    /// The most recently fetched checkout customization payload, or `nil` if not yet loaded.
    public private(set) var checkoutCustomization: CheckoutCustomizationData?

    // MARK: - Internal Dependencies

    private let networkClient:       NetworkClient
    private let checkoutRepository:  CheckoutRepository
    private let paymentRepository:   PaymentRepository

    // MARK: - Init

    private init(configuration: PayOrcConfiguration) {
        self.configuration       = configuration
        self.networkClient       = NetworkClient(configuration: configuration)
        self.checkoutRepository  = CheckoutRepository(networkClient: networkClient)
        self.paymentRepository   = PaymentRepository(networkClient: networkClient)
    }

    // MARK: - Public Accessors (for Repository use)

    /// The internal payment repository. Exposed for advanced use cases.
    public var payments: PaymentRepository { paymentRepository }

    // MARK: - Initialization

    /// Initializes the PayOrc SDK with the given configuration.
    ///
    /// - Parameter configuration: SDK credentials, environment, and optional overrides.
    /// - Throws: ``PayOrcError/invalidConfiguration(_:)`` when credentials are blank.
    ///
    /// When `configuration.fetchCheckoutCustomizationOnInit` is `true` (default),
    /// a background fetch is triggered immediately using
    /// `configuration.checkoutCustomizationCurrency` and `configuration.checkoutCustomizationAmount`.
    @discardableResult
    public static func initialize(configuration: PayOrcConfiguration) throws -> PayOrc {
        try configuration.validate()

        PayOrcUIConstants.reset()

        let sdk = PayOrc(configuration: configuration)
        shared  = sdk

        if configuration.fetchCheckoutCustomizationOnInit {
            Task {
                // Refresh geo context first so X-IP / X-IP-COUNTRY are ready
                await GeoContext.refresh()
                await sdk.loadCheckoutCustomization(
                    currency: configuration.checkoutCustomizationCurrency,
                    amount:   configuration.checkoutCustomizationAmount
                )
            }
        } else {
            // Still refresh geo in the background for manual refresh calls later
            Task { await GeoContext.refresh() }
        }

        return sdk
    }

    // MARK: - Checkout Customization

    /// Manually refreshes checkout customization from the PayOrc API.
    ///
    /// Call this when you want to re-fetch using a specific currency/amount pair
    /// before presenting the payment UI — e.g. after loading an order summary.
    ///
    /// Posts ``checkoutCustomizationDidChange`` on success.
    ///
    /// - Parameters:
    ///   - currency:   Currency code (e.g. `"AED"`). Defaults to the configuration value.
    ///   - amount:     Order amount. Defaults to the configuration value.
    ///   - completion: Called on the main queue with the result. `nil` to ignore.
    public static func refreshCheckoutCustomization(
        currency:   String?  = nil,
        amount:     Decimal? = nil,
        completion: ((Result<CheckoutCustomizationData, PayOrcError>) -> Void)? = nil
    ) {
        guard let sdk = shared else {
            completion?(.failure(.sdkNotInitialized))
            return
        }

        let resolvedCurrency = currency ?? sdk.configuration.checkoutCustomizationCurrency
        let resolvedAmount   = amount   ?? sdk.configuration.checkoutCustomizationAmount

        Task {
            await sdk.loadCheckoutCustomization(
                currency:   resolvedCurrency,
                amount:     resolvedAmount,
                completion: completion
            )
        }
    }

    /// Async/await overload of ``refreshCheckoutCustomization(currency:amount:completion:)``.
    ///
    /// - Returns: The freshly fetched ``CheckoutCustomizationData``.
    /// - Throws: ``PayOrcError`` on failure.
    @discardableResult
    public static func refreshCheckoutCustomization(
        currency: String?  = nil,
        amount:   Decimal? = nil
    ) async throws -> CheckoutCustomizationData {
        guard let sdk = shared else {
            throw PayOrcError.sdkNotInitialized
        }

        let resolvedCurrency = currency ?? sdk.configuration.checkoutCustomizationCurrency
        let resolvedAmount   = amount   ?? sdk.configuration.checkoutCustomizationAmount

        return try await sdk.fetchAndApplyCustomization(
            currency: resolvedCurrency,
            amount:   resolvedAmount
        )
    }

    // MARK: - Host Customization Overrides

    /// Applies host UI overrides on top of the checkout API values.
    ///
    /// Call any time — overrides persist across customization refreshes.
    /// Posts ``uiCustomizationDidChange`` after applying.
    ///
    /// - Parameter customization: The ``PayOrcSDKCustomization`` value object.
    public static func setCustomization(_ customization: PayOrcSDKCustomization) {
        applyHostOverrides(customization)
        NotificationCenter.default.post(name: uiCustomizationDidChange, object: nil)
    }

    // MARK: - Present Checkout

    /// Presents the PayOrc checkout UI from the given view controller.
    ///
    /// - Parameters:
    ///   - viewController: The presenting `UIViewController`.
    ///   - request:        The payment request describing the order.
    ///   - delegate:       Receives ``PayOrcSDKDelegate`` callbacks on completion/failure.
    @MainActor
    public func presentCheckout(
        from viewController: UIViewController,
        request:  PaymentRequest,
        delegate: PayOrcSDKDelegate
    ) {
        let viewModel  = CheckoutViewModel(
            paymentRequest:     request,
            paymentRepository:  paymentRepository
        )
        let checkoutVC = CheckoutViewController(
            viewModel: viewModel,
            delegate:  delegate
        )
        let nav = UINavigationController(rootViewController: checkoutVC)
        nav.modalPresentationStyle = .pageSheet
        viewController.present(nav, animated: true)
    }

    // MARK: - Tabby Checkout

    /// Opens the Tabby BNPL checkout from the given view controller.
    ///
    /// Mirrors Flutter's `PayorcSdk.showTabbyCheckout(context, paymentRequest: ...,
    /// onTabbyAuthorized: ..., onTabbyError: ...)`.
    ///
    /// ## Flow
    ///
    /// 1. `POST sdk/tabby/init`    — initialise the Tabby session via PayOrc
    /// 2. `TabbyAPI.createSession` — call the Tabby API with returned credentials
    /// 3. `TabbyWebViewController` — present the Tabby checkout in a WKWebView
    /// 4. `POST sdk/tabby/confirm` — confirm the payment on `authorized`
    /// 5. `onAuthorized` / `onError` — deliver the result to your app
    ///
    /// ## When to call
    ///
    /// Call this from ``PaymentOptionsViewController``'s `onSelectTabby` callback,
    /// or from a custom "Pay with Tabby" button — just as you would call
    /// `showTabbyCheckout` in the Flutter SDK.
    ///
    /// - Parameters:
    ///   - viewController: The presenting `UIViewController`.
    ///   - request:        The ``PaymentRequest`` describing the order.
    ///   - onAuthorized:   Called on the main queue with a ``PayOrcSDKResult``
    ///                     when the Tabby payment is confirmed successfully.
    ///   - onError:        Called on the main queue with a ``PayOrcError`` when
    ///                     the flow fails, is rejected, or is cancelled by the user.
    @MainActor
    public func showTabbyCheckout(
        from viewController: UIViewController,
        request:     PaymentRequest,
        onAuthorized: ((PayOrcSDKResult) -> Void)? = nil,
        onError:      ((PayOrcError) -> Void)?      = nil
    ) {
        TabbyCheckoutFlow.runHostedCheckout(
            from:                viewController,
            request:             request,
            paymentRepository:   paymentRepository,
            fallbackMerchantCode: configuration.tabbyMerchantCode,
            onAuthorized:        onAuthorized,
            onError:             onError
        )
    }

    // MARK: - Apple Pay Checkout

    /// Opens the native Apple Pay sheet and submits the resulting token to
    /// `POST sdk/wallet/payment`.
    ///
    /// Mirrors Flutter's `ApplePayButton` (from the `pay` package) combined with
    /// `PayorcSdk.presentPaymentOptionsSheet`'s Apple Pay submission handling.
    ///
    /// ## Flow
    ///
    /// 1. Resolve Apple Pay configuration from checkout customization (merchant ID, networks).
    /// 2. Present the native `PKPaymentAuthorizationController` sheet.
    /// 3. `POST sdk/wallet/payment` — confirm the token with PayOrc.
    /// 4. `onAuthorized` / `onError` — deliver the result to your app.
    ///
    /// ## When to call
    ///
    /// Call this from ``PaymentOptionsViewController``'s `onSelectApplePay` callback,
    /// or from a custom "Pay with Apple Pay" button.
    ///
    /// - Parameters:
    ///   - request:      The ``PaymentRequest`` describing the order.
    ///   - onAuthorized: Called on the main queue with a ``PayOrcSDKResult``
    ///                   when the wallet payment is confirmed successfully.
    ///   - onError:      Called on the main queue with a ``PayOrcError`` when
    ///                   the flow fails, is unavailable, or is cancelled by the user.
    @MainActor
    public func showApplePayCheckout(
        request:      PaymentRequest,
        onAuthorized: ((PayOrcSDKResult) -> Void)? = nil,
        onError:      ((PayOrcError) -> Void)?      = nil
    ) {
        ApplePayCheckoutFlow.present(
            request:               request,
            paymentRepository:     paymentRepository,
            checkoutCustomization: checkoutCustomization,
            fallbackCurrency:      configuration.checkoutCustomizationCurrency,
            onAuthorized:          onAuthorized,
            onError:               onError
        )
    }

    // MARK: - Private

    /// Background checkout customization loader.
    /// On success: stores data, applies merchant details to UI constants, posts notification.
    private func loadCheckoutCustomization(
        currency:   String,
        amount:     Decimal,
        completion: ((Result<CheckoutCustomizationData, PayOrcError>) -> Void)? = nil
    ) async {
        do {
            let data = try await fetchAndApplyCustomization(currency: currency, amount: amount)
            await MainActor.run {
                completion?(.success(data))
            }
        } catch let error as PayOrcError {
            #if DEBUG
            print("[PayOrc] Checkout customization failed: \(error.localizedDescription)")
            #endif
            await MainActor.run {
                completion?(.failure(error))
            }
        } catch {
            #if DEBUG
            print("[PayOrc] Checkout customization error: \(error)")
            #endif
            await MainActor.run {
                completion?(.failure(.requestFailed(underlying: error)))
            }
        }
    }

    private func fetchAndApplyCustomization(
        currency: String,
        amount:   Decimal
    ) async throws -> CheckoutCustomizationData {
        let data = try await checkoutRepository.fetchCustomization(
            currency: currency,
            amount:   amount
        )

        await MainActor.run { [weak self] in
            guard let self = self,
                  PayOrc.shared === self else {
                #if DEBUG
                print("[PayOrc] Skipped applying customization because shared instance changed")
                #endif
                return
            }

            self.checkoutCustomization = data

            #if DEBUG
            let visibleMethods = data.availableMethods.filter { $0.isVisible && $0.type.lowercased() != "google_pay" }
            print("[PayOrc] Applied customization payload: count=\(data.availableMethods.count), visible=\(visibleMethods.count), types=\(data.availableMethods.map(\.type))")
            #endif

            if let details = data.merchantDetails {
                PayOrcUIConstants.applyMerchantDetails(details)
            }

            NotificationCenter.default.post(
                name:   PayOrc.checkoutCustomizationDidChange,
                object: data
            )
            NotificationCenter.default.post(
                name:   PayOrc.uiCustomizationDidChange,
                object: nil
            )
        }

        return data
    }
}

// MARK: - Host Override Application

private extension PayOrc {

    static func applyHostOverrides(_ c: PayOrcSDKCustomization) {
        // Brand / accent / border
        if let v = c.brandColor,  v.cgColor.alpha > 0 { PayOrcUIConstants._hostBrandColor  = v }
        if let v = c.accentColor, v.cgColor.alpha > 0 { PayOrcUIConstants._hostAccentColor = v }
        if let v = c.borderColor, v.cgColor.alpha > 0 { PayOrcUIConstants._hostBorderColor = v }

        // Input border style
        if let v = c.inputBorderStyle { PayOrcUIConstants._hostInputBorderStyle = v }

        // Button overrides
        if let b = c.button {
            if let v = b.backgroundColor,        v.cgColor.alpha > 0 { PayOrcUIConstants._hostButtonColor        = v }
            if let v = b.foregroundColor,         v.cgColor.alpha > 0 { PayOrcUIConstants._hostButtonForeground   = v }
            if let v = b.disabledBackgroundColor, v.cgColor.alpha > 0 { PayOrcUIConstants._hostButtonDisabled     = v }
            if let v = b.sideBorderColor,         v.cgColor.alpha > 0 { PayOrcUIConstants._hostButtonBorderColor  = v }
            if let v = b.borderRadius   { PayOrcUIConstants._hostButtonBorderRadius = v }
            if let v = b.height         { PayOrcUIConstants._hostButtonHeight        = v }
            if let v = b.fontWeight     { PayOrcUIConstants._hostButtonFontWeight    = v }
            if let v = b.loadingIndicatorColor, v.cgColor.alpha > 0 {
                PayOrcUIConstants._hostButtonLoadingColor = v
            }
        }

        // Text overrides
        if let t = c.text {
            if let v = t.primaryColor,   v.cgColor.alpha > 0 { PayOrcUIConstants._hostTextPrimary   = v }
            if let v = t.secondaryColor, v.cgColor.alpha > 0 { PayOrcUIConstants._hostTextSecondary = v }
            if let v = t.bodyFont   { PayOrcUIConstants._hostBodyFont   = v }
            if let v = t.titleFont  { PayOrcUIConstants._hostTitleFont  = v }
        }

        // TextField overrides
        if let tf = c.textField {
            if let v = tf.borderColor, v.cgColor.alpha > 0 { PayOrcUIConstants._hostFieldBorderColor  = v }
            if let v = tf.borderRadius  { PayOrcUIConstants._hostFieldBorderRadius = v }
            if let v = tf.height        { PayOrcUIConstants._hostFieldHeight        = v }
            if let v = tf.contentInsets { PayOrcUIConstants._hostFieldInsets        = v }
        }

        // Bottom sheet overrides
        if let bs = c.bottomSheet {
            if let v = bs.cornerRadius  { PayOrcUIConstants._hostSheetCornerRadius = v }
            if let v = bs.contentInsets { PayOrcUIConstants._hostSheetPadding      = v }
            if let v = bs.itemSpacing   { PayOrcUIConstants._hostSheetSpacing      = v }
        }
    }
}

// MARK: - PayOrcSDKDelegate

/// Delegate for receiving checkout outcomes.
public protocol PayOrcSDKDelegate: AnyObject {
    /// Called when checkout completes successfully.
    func payOrcDidComplete(result: PayOrcSDKResult)

    /// Called when checkout fails with a typed error.
    func payOrcDidFail(error: PayOrcError)

    /// Called when the user cancels / dismisses the checkout UI.
    func payOrcDidCancel()
}

/// Default empty implementation so conformers can omit `payOrcDidCancel`.
public extension PayOrcSDKDelegate {
    func payOrcDidCancel() {}
}

// MARK: - PayOrcSDKResult

/// The outcome of a successful PayOrc checkout.
public struct PayOrcSDKResult {
    public let status:        String
    public let code:          String
    public let message:       String
    public let transactionId: String?

    public init(status: String, code: String, message: String, transactionId: String? = nil) {
        self.status        = status
        self.code          = code
        self.message       = message
        self.transactionId = transactionId
    }
}
