import UIKit

// MARK: - PayOrcEmbeddedPayWithCardButton

/// Embedded "Pay with Card" button for host layouts — the Swift equivalent of
/// Flutter's `payorcEmbeddedOpenPayWithCard`.
///
/// A tap presents the same card-entry sheet as
/// ``PayOrc/presentCheckout(from:request:delegate:)`` and reports the outcome through
/// closures instead of a delegate, so it can be dropped into a layout without any
/// extra wiring.
///
/// ## Behavior
///
/// - Styled with the SDK's own button appearance (``PayOrcUIConstants``), so it matches
///   host customization automatically.
/// - Hidden automatically when `card` is not enabled in checkout customization.
/// - Re-evaluates visibility whenever ``PayOrc/checkoutCustomizationDidChange`` fires,
///   and restyles on ``PayOrc/uiCustomizationDidChange``.
/// - Resolves a presenter automatically via the responder chain; set
///   ``presentingViewController`` explicitly if this view's subtree doesn't sit under
///   the controller you want to present from.
///
/// ## Usage
///
/// ```swift
/// let cardButton = PayOrcEmbeddedPayWithCardButton(paymentRequest: request)
/// cardButton.onComplete = { result in ... }
/// cardButton.onFail = { error in ... }
/// stackView.addArrangedSubview(cardButton)
/// ```
public final class PayOrcEmbeddedPayWithCardButton: UIView {

    // MARK: - Callbacks

    /// Checkout completed successfully.
    public var onComplete: ((PayOrcSDKResult) -> Void)?

    /// Checkout failed with a typed error.
    public var onFail: ((PayOrcError) -> Void)?

    /// The user cancelled/dismissed the card sheet.
    public var onCancel: (() -> Void)?

    /// Optional explicit presenter for the card sheet. When `nil`, resolved from the
    /// responder chain at tap time.
    public weak var presentingViewController: UIViewController?

    /// Per-instance style override, layered on top of the SDK-wide button style.
    /// Set at any time; call ``applyTheme()`` implicitly happens on the next
    /// ``PayOrc/uiCustomizationDidChange`` notification, or immediately via this setter.
    public var customization: PayOrcEmbeddedCustomization? {
        didSet { applyTheme() }
    }

    /// Whether this view fills the width of its superview (the default, matching the
    /// Flutter embeds). Set to `false` to size it yourself. See
    /// ``PayOrcEmbeddedWidthFiller``.
    public var fillsSuperviewWidth: Bool {
        get { widthFiller.isEnabled }
        set { widthFiller.isEnabled = newValue }
    }

    // MARK: - Private

    private let paymentRequest: PaymentRequest
    private let button = PayOrcButton()
    private var heightConstraint: NSLayoutConstraint!
    private var delegateAdapter: PayOrcEmbeddedCardDelegateAdapter?
    private lazy var widthFiller = PayOrcEmbeddedWidthFiller(view: self)

    // MARK: - Init

    public init(
        paymentRequest: PaymentRequest,
        title: String = "Pay with Card",
        customization: PayOrcEmbeddedCustomization? = nil,
        presentingViewController: UIViewController? = nil,
        onComplete: ((PayOrcSDKResult) -> Void)? = nil,
        onFail: ((PayOrcError) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.paymentRequest = paymentRequest
        self.customization = customization
        self.presentingViewController = presentingViewController
        self.onComplete = onComplete
        self.onFail = onFail
        self.onCancel = onCancel
        super.init(frame: .zero)
        setupLayout(title: customization?.payWithCardTitle ?? title)
        setupObservers()
        refreshAvailability()
        applyTheme()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — create PayOrcEmbeddedPayWithCardButton in code.")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        widthFiller.refresh()
    }

    // MARK: - Public API

    /// Updates the button title (default `"Pay with Card"`).
    public func setTitle(_ title: String) {
        button.setTitle(title, for: .normal)
    }

    // MARK: - Layout

    private func setupLayout(title: String) {
        translatesAutoresizingMaskIntoConstraints = false

        button.setTitle(title, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(didTap), for: .touchUpInside)
        addSubview(button)

        heightConstraint = heightAnchor.constraint(equalToConstant: PayOrcUIConstants.buttonHeight)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint
        ])
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshAvailability),
            name: PayOrc.checkoutCustomizationDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme),
            name: PayOrc.uiCustomizationDidChange, object: nil)
    }

    // MARK: - Availability / Theme

    @objc private func refreshAvailability() {
        setHidden(!PayOrcEmbeddedVisibility.isMethodVisible(type: "card"))
    }

    @objc private func applyTheme() {
        if let customization {
            button.applyStyle(override: customization)
        } else {
            button.applyStyle()
        }
        heightConstraint.constant = isHidden ? 0 : resolvedHeight
    }

    private var resolvedHeight: CGFloat {
        customization?.buttonHeight ?? PayOrcUIConstants.buttonHeight
    }

    private func setHidden(_ hidden: Bool) {
        guard isHidden != hidden else { return }
        isHidden = hidden
        heightConstraint.constant = hidden ? 0 : resolvedHeight
    }

    // MARK: - Actions

    @objc private func didTap() {
        guard let sdk = PayOrc.shared else {
            onFail?(.sdkNotInitialized)
            return
        }
        guard let presenter = presentingViewController ?? payorc_nearestViewController() else {
            onFail?(.unsupported(feature: "No presenting view controller available for card checkout."))
            return
        }

        let adapter = PayOrcEmbeddedCardDelegateAdapter(
            onComplete: { [weak self] result in
                self?.onComplete?(result)
                self?.delegateAdapter = nil
            },
            onFail: { [weak self] error in
                self?.onFail?(error)
                self?.delegateAdapter = nil
            },
            onCancel: { [weak self] in
                self?.onCancel?()
                self?.delegateAdapter = nil
            }
        )
        // Retained for the lifetime of the checkout flow — PayOrcSDKDelegate is weak-referenced by callers.
        delegateAdapter = adapter
        sdk.presentCheckout(from: presenter, request: paymentRequest, delegate: adapter)
    }
}

// MARK: - PayOrcEmbeddedCardDelegateAdapter

/// Bridges ``PayOrcSDKDelegate`` callbacks to closures for
/// ``PayOrcEmbeddedPayWithCardButton``.
private final class PayOrcEmbeddedCardDelegateAdapter: NSObject, PayOrcSDKDelegate {
    private let onComplete: (PayOrcSDKResult) -> Void
    private let onFail: (PayOrcError) -> Void
    private let onCancel: () -> Void

    init(
        onComplete: @escaping (PayOrcSDKResult) -> Void,
        onFail: @escaping (PayOrcError) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onComplete = onComplete
        self.onFail = onFail
        self.onCancel = onCancel
    }

    func payOrcDidComplete(result: PayOrcSDKResult) { onComplete(result) }
    func payOrcDidFail(error: PayOrcError) { onFail(error) }
    func payOrcDidCancel() { onCancel() }
}
