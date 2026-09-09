import UIKit

// MARK: - PayOrcEmbeddedPaymentMethodsView

/// All-in-one embedded payment stack — Apple Pay, Tabby, and Pay-with-Card — matching
/// the bottom-sheet ordering. The Swift equivalent of Flutter's
/// `PayorcEmbeddedPaymentCheckout`.
///
/// Each row manages its own visibility (hidden automatically when the corresponding
/// method isn't enabled in checkout customization), so this stack always reflects only
/// the methods currently available — no manual bookkeeping required.
///
/// ## Usage
///
/// ```swift
/// let methods = PayOrcEmbeddedPaymentMethodsView(paymentRequest: request)
/// methods.onAuthorized = { result in ... }   // Apple Pay + Tabby
/// methods.onCardComplete = { result in ... } // Pay with Card
/// methods.onError = { error in ... }
/// view.addSubview(methods)
/// ```
public final class PayOrcEmbeddedPaymentMethodsView: UIStackView {

    // MARK: - Callbacks

    /// Apple Pay or Tabby succeeded.
    public var onAuthorized: ((PayOrcSDKResult) -> Void)?

    /// Pay-with-Card checkout completed successfully.
    public var onCardComplete: ((PayOrcSDKResult) -> Void)?

    /// Any method failed (Apple Pay, Tabby, or card).
    public var onError: ((PayOrcError) -> Void)?

    /// The user cancelled the card sheet.
    public var onCardCancel: (() -> Void)?

    /// Whether this view fills the width of its superview (the default, matching the
    /// Flutter embeds). Set to `false` to size it yourself. See
    /// ``PayOrcEmbeddedWidthFiller``.
    public var fillsSuperviewWidth: Bool {
        get { widthFiller.isEnabled }
        set { widthFiller.isEnabled = newValue }
    }

    // MARK: - Rows

    public let applePayButton: PayOrcEmbeddedApplePayButton
    public let tabbyButton: PayOrcEmbeddedTabbyButton
    public let cardButton: PayOrcEmbeddedPayWithCardButton

    private lazy var widthFiller = PayOrcEmbeddedWidthFiller(view: self)

    // MARK: - Init

    public init(
        paymentRequest: PaymentRequest,
        presentingViewController: UIViewController? = nil,
        spacing: CGFloat = 12,
        cardCustomization: PayOrcEmbeddedCustomization? = nil,
        tabbyCustomization: PayOrcEmbeddedCustomization? = nil
    ) {
        applePayButton = PayOrcEmbeddedApplePayButton(paymentRequest: paymentRequest)
        tabbyButton = PayOrcEmbeddedTabbyButton(
            paymentRequest: paymentRequest,
            customization: tabbyCustomization,
            presentingViewController: presentingViewController
        )
        cardButton = PayOrcEmbeddedPayWithCardButton(
            paymentRequest: paymentRequest,
            customization: cardCustomization,
            presentingViewController: presentingViewController
        )
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        self.spacing = spacing
        alignment = .fill
        distribution = .fill

        addArrangedSubview(applePayButton)
        addArrangedSubview(tabbyButton)
        addArrangedSubview(cardButton)

        wireCallbacks()
    }

    public required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported — create PayOrcEmbeddedPaymentMethodsView in code.")
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        widthFiller.refresh()
    }

    // MARK: - Wiring

    private func wireCallbacks() {
        applePayButton.onAuthorized = { [weak self] result in self?.onAuthorized?(result) }
        applePayButton.onError = { [weak self] error in self?.onError?(error) }

        tabbyButton.onAuthorized = { [weak self] result in self?.onAuthorized?(result) }
        tabbyButton.onError = { [weak self] error in self?.onError?(error) }

        cardButton.onComplete = { [weak self] result in self?.onCardComplete?(result) }
        cardButton.onFail = { [weak self] error in self?.onError?(error) }
        cardButton.onCancel = { [weak self] in self?.onCardCancel?() }
    }
}
