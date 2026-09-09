import UIKit

// MARK: - PayOrcEmbeddedTabbyButton

/// Embedded Tabby (BNPL) row for host layouts — the Swift equivalent of Flutter's
/// `PayorcEmbeddedTabbyButton`.
///
/// A single tap runs the full hosted Tabby flow via
/// ``PayOrc/showTabbyCheckout(from:request:onAuthorized:onError:)`` (init → Tabby
/// session → in-app web checkout → confirm), presenting the Tabby WebView from the
/// nearest containing `UIViewController`.
///
/// ## Behavior
///
/// - Styled like the SDK's own payment-method tile (Tabby logo + title), matching the
///   look of the bottom-sheet checkout.
/// - Hidden automatically when Tabby is not enabled in checkout customization.
/// - Re-evaluates visibility whenever ``PayOrc/checkoutCustomizationDidChange`` or
///   ``PayOrc/uiCustomizationDidChange`` fires.
/// - Resolves a presenter automatically via the responder chain; set
///   ``presentingViewController`` explicitly if this view's subtree doesn't sit under
///   the controller you want to present from.
///
/// ## Usage
///
/// ```swift
/// let tabby = PayOrcEmbeddedTabbyButton(paymentRequest: request)
/// tabby.onAuthorized = { result in ... }
/// tabby.onError = { error in ... }
/// stackView.addArrangedSubview(tabby)
/// ```
public final class PayOrcEmbeddedTabbyButton: UIView {

    // MARK: - Callbacks

    /// Tabby payment confirmed via `POST sdk/tabby/confirm`.
    public var onAuthorized: ((PayOrcSDKResult) -> Void)?

    /// Init, session, or confirm failure — or user cancellation/rejection.
    public var onError: ((PayOrcError) -> Void)?

    /// Optional explicit presenter for the Tabby WebView sheet. When `nil`, resolved
    /// from the responder chain at tap time.
    public weak var presentingViewController: UIViewController?

    /// Per-instance style override, layered on top of the SDK-wide tile style.
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
    private let tile = PaymentMethodTileView()
    private var tileHeight: CGFloat { customization?.tileHeight ?? 56 }
    private var heightConstraint: NSLayoutConstraint!
    private lazy var widthFiller = PayOrcEmbeddedWidthFiller(view: self)

    // MARK: - Init

    public init(
        paymentRequest: PaymentRequest,
        customization: PayOrcEmbeddedCustomization? = nil,
        presentingViewController: UIViewController? = nil,
        onAuthorized: ((PayOrcSDKResult) -> Void)? = nil,
        onError: ((PayOrcError) -> Void)? = nil
    ) {
        self.paymentRequest = paymentRequest
        self.customization = customization
        self.presentingViewController = presentingViewController
        self.onAuthorized = onAuthorized
        self.onError = onError
        super.init(frame: .zero)
        setupLayout()
        setupObservers()
        refreshAvailability()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — create PayOrcEmbeddedTabbyButton in code.")
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

        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.configure(with: PaymentMethodTileView.Config(imageName: "tabby", title: "Tabby"))
        tile.onTap = { [weak self] in self?.didTap() }
        addSubview(tile)

        heightConstraint = heightAnchor.constraint(equalToConstant: tileHeight)
        NSLayoutConstraint.activate([
            tile.topAnchor.constraint(equalTo: topAnchor),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor),
            tile.trailingAnchor.constraint(equalTo: trailingAnchor),
            tile.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        setHidden(!PayOrcEmbeddedVisibility.isMethodVisible(type: "tabby"))
        applyTheme()
    }

    @objc private func applyTheme() {
        let c = customization
        tile.configure(with: PaymentMethodTileView.Config(
            imageName: "tabby",
            title: "Tabby",
            backgroundColor: c?.tileBackgroundColor,
            titleColor: c?.tileTitleColor,
            selectedBackgroundColor: c?.tileSelectedBackgroundColor,
            selectedBorderColor: c?.tileSelectedBorderColor,
            cornerRadius: c?.tileBorderRadius
        ))
        heightConstraint.constant = isHidden ? 0 : tileHeight
    }

    private func setHidden(_ hidden: Bool) {
        guard isHidden != hidden else { return }
        isHidden = hidden
        heightConstraint.constant = hidden ? 0 : tileHeight
    }

    // MARK: - Actions

    private func didTap() {
        guard let sdk = PayOrc.shared else {
            onError?(.sdkNotInitialized)
            return
        }
        guard let presenter = presentingViewController ?? payorc_nearestViewController() else {
            onError?(.unsupported(feature: "No presenting view controller available for Tabby checkout."))
            return
        }
        sdk.showTabbyCheckout(
            from: presenter,
            request: paymentRequest,
            onAuthorized: { [weak self] result in self?.onAuthorized?(result) },
            onError: { [weak self] error in self?.onError?(error) }
        )
    }
}
