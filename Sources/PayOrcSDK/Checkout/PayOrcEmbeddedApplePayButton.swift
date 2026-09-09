import UIKit
import PassKit

// MARK: - PayOrcEmbeddedApplePayButton

/// Native Apple Pay button for embedding directly in host app layouts.
///
/// This is the Swift/PassKit equivalent of Flutter's `PayorcEmbeddedApplePayButton` —
/// a self-contained view that drives the same flow as
/// ``PayOrc/showApplePayCheckout(request:onAuthorized:onError:)`` without requiring the
/// host to present a checkout sheet.
///
/// ## Behavior
///
/// - Uses the platform `PKPaymentButton` (Apple's official Apple Pay mark).
/// - Automatically hides itself (zero size) when Apple Pay is not configured for the
///   merchant, is hidden in checkout customization, or is unavailable on this device.
/// - Re-evaluates availability whenever ``PayOrc/checkoutCustomizationDidChange`` or
///   ``PayOrc/uiCustomizationDidChange`` fires, so the button appears/disappears live
///   as customization data loads.
///
/// ## Usage
///
/// ```swift
/// let button = PayOrcEmbeddedApplePayButton(paymentRequest: request)
/// button.onAuthorized = { result in ... }
/// button.onError = { error in ... }
/// stackView.addArrangedSubview(button)
/// ```
public final class PayOrcEmbeddedApplePayButton: UIView {

    // MARK: - Callbacks

    /// `POST sdk/wallet/payment` succeeded.
    public var onAuthorized: ((PayOrcSDKResult) -> Void)?

    /// Wallet/native errors or a failed `/sdk/wallet/payment` call. User cancellation is
    /// reported as ``PayOrcError/apiFailure(code:message:)`` with code `"CANCELLED"`.
    public var onError: ((PayOrcError) -> Void)?

    /// Whether this view fills the width of its superview (the default, matching the
    /// Flutter embeds). Set to `false` to size it yourself. See
    /// ``PayOrcEmbeddedWidthFiller``.
    public var fillsSuperviewWidth: Bool {
        get { widthFiller.isEnabled }
        set { widthFiller.isEnabled = newValue }
    }

    // MARK: - Private

    private let paymentRequest: PaymentRequest
    private let payButton: PKPaymentButton
    private let buttonHeight: CGFloat
    private var heightConstraint: NSLayoutConstraint!
    private lazy var widthFiller = PayOrcEmbeddedWidthFiller(view: self)

    // MARK: - Init

    public init(
        paymentRequest: PaymentRequest,
        buttonType: PKPaymentButtonType = .buy,
        buttonStyle: PKPaymentButtonStyle = .black,
        height: CGFloat = 48,
        onAuthorized: ((PayOrcSDKResult) -> Void)? = nil,
        onError: ((PayOrcError) -> Void)? = nil
    ) {
        self.paymentRequest = paymentRequest
        self.buttonHeight = height
        self.payButton = PKPaymentButton(paymentButtonType: buttonType, paymentButtonStyle: buttonStyle)
        self.onAuthorized = onAuthorized
        self.onError = onError
        super.init(frame: .zero)
        setupLayout()
        setupObservers()
        refreshAvailability()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — create PayOrcEmbeddedApplePayButton in code.")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        widthFiller.refresh()
    }

    // MARK: - Layout

    private func setupLayout() {
        translatesAutoresizingMaskIntoConstraints = false

        payButton.cornerRadius = 10
        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.addTarget(self, action: #selector(didTap), for: .touchUpInside)
        addSubview(payButton)

        heightConstraint = heightAnchor.constraint(equalToConstant: buttonHeight)
        NSLayoutConstraint.activate([
            payButton.topAnchor.constraint(equalTo: topAnchor),
            payButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            payButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            payButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint
        ])
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshAvailability),
            name: PayOrc.checkoutCustomizationDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshAvailability),
            name: PayOrc.uiCustomizationDidChange, object: nil)
    }

    // MARK: - Availability

    @objc private func refreshAvailability() {
        guard PayOrcEmbeddedVisibility.isMethodVisible(type: "apple_pay"),
              let config = resolvedConfiguration(),
              PKPaymentAuthorizationController.canMakePayments(usingNetworks: config.supportedNetworks) else {
            setHidden(true)
            return
        }
        setHidden(false)
    }

    private func setHidden(_ hidden: Bool) {
        guard isHidden != hidden else { return }
        isHidden = hidden
        heightConstraint.constant = hidden ? 0 : buttonHeight
    }

    private func resolvedConfiguration() -> ApplePayConfiguration? {
        guard let sdk = PayOrc.shared else { return nil }

        var currency = paymentRequest.orderDetails.first?.currency.trimmingCharacters(in: .whitespaces) ?? ""
        if currency.isEmpty { currency = sdk.configuration.checkoutCustomizationCurrency }

        let billingCountry = paymentRequest.billingDetails.country.trimmingCharacters(in: .whitespaces)
        let countryCode = !billingCountry.isEmpty ? billingCountry.uppercased() : "AE"

        return ApplePayConfiguration.resolve(
            customization: sdk.checkoutCustomization,
            currencyCode: currency,
            countryCode: countryCode
        )
    }

    // MARK: - Actions

    @objc private func didTap() {
        guard let sdk = PayOrc.shared else {
            onError?(.sdkNotInitialized)
            return
        }
        sdk.showApplePayCheckout(
            request: paymentRequest,
            onAuthorized: { [weak self] result in self?.onAuthorized?(result) },
            onError: { [weak self] error in self?.onError?(error) }
        )
    }
}
