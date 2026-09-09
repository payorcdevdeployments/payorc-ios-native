import UIKit
import PassKit

// MARK: - PaymentOptionsViewController

/// A bottom-sheet view controller presenting ALL available payment methods.
///
/// Mirrors Flutter's `PaymentOptionsScene`:
/// - Sheet height wraps content (compact when few tiles, expandable when many)
/// - Tiles use `accentColor` as background with white text/icons
/// - Tile order follows `available_methods.sequence` from the API
/// - ALL visible methods shown (only `google_pay` excluded — Android-only)
public final class PaymentOptionsViewController: UIViewController {

    // MARK: - Callbacks
    public var onSelectCard:        (() -> Void)?
    public var onCancel:            (() -> Void)?
    public var onSelectApplePay:    (() -> Void)?
    public var onSelectTabby:       (() -> Void)?
    public var onSelectOtherMethod: ((String) -> Void)?

    // MARK: - State
    private var selectedMethodType: String?
    private let paymentRequest:     PaymentRequest?
    private var tilePairs:          [(method: AvailablePaymentMethod, tile: PaymentMethodTileView)] = []

    // MARK: - UI
    private let scrollView        = UIScrollView()
    private let contentStack      = UIStackView()  // vertical: loading/tiles + actions + footer
    private let tilesStack        = UIStackView()  // vertical: one tile per method
    private let loadingContainer  = UIStackView()
    private let loadingIndicator  = UIActivityIndicatorView(style: .medium)
    private let loadingLabel      = UILabel()
    private let confirmButton     = PayOrcButton()
    private let applePayButton    = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .black)
    private let cancelButton      = UIButton(type: .system)

    // MARK: - Init
    public init(paymentRequest: PaymentRequest? = nil) {
        self.paymentRequest = paymentRequest
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setupActions()
        buildPaymentMethodTiles()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
        // Rebuild tiles (may already have real data if API returned before sheet opened)
        buildPaymentMethodTiles()
        // Set the detent NOW, before the sheet animation begins —
        // this makes the sheet open directly at the right height with no flash.
        configureSheetDetent(animated: false)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Re-measure with real safe area insets now that we’re fully on screen.
        // Uses animateChanges so any adjustment is smooth, not jarring.
        configureSheetDetent(animated: true)
    }

    // MARK: - Layout

    private func setupLayout() {
        view.backgroundColor = .systemBackground

        // ── Dismiss button (chevron.down, top-right — Flutter iOS style) ──────
        let dismissBtn = UIButton(type: .system)
        let cfg        = UIImage.SymbolConfiguration(pointSize: 24, weight: .light)
        dismissBtn.setImage(
            UIImage(systemName: "chevron.down.circle.fill", withConfiguration: cfg),
            for: .normal
        )
        dismissBtn.tintColor = .tertiaryLabel
        dismissBtn.translatesAutoresizingMaskIntoConstraints = false
        dismissBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(dismissBtn)
        NSLayoutConstraint.activate([
            dismissBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            dismissBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            dismissBtn.widthAnchor.constraint(equalToConstant: 32),
            dismissBtn.heightAnchor.constraint(equalToConstant: 32)
        ])

        // ── Scroll view ────────────────────────────────────────────────────────
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical         = false
        scrollView.keyboardDismissMode          = .interactive
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: dismissBtn.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        // ── Outer vertical stack ───────────────────────────────────────────────
        contentStack.axis      = .vertical
        contentStack.spacing   = 0
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let pad = PayOrcUIConstants.bottomSheetContentInsets
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: pad.top),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: pad.left),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -pad.right),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -pad.bottom),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -(pad.left + pad.right))
        ])

        // ── Loading state ────────────────────────────────────────────────────
        loadingContainer.axis      = .vertical
        loadingContainer.spacing   = 8
        loadingContainer.alignment = .center
        loadingContainer.isHidden   = true
        loadingContainer.translatesAutoresizingMaskIntoConstraints = false

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = PayOrcUIConstants.textSecondaryColor
        loadingIndicator.startAnimating()

//        loadingLabel.text = "Loading payment methods..."
//        loadingLabel.font = .systemFont(ofSize: 15, weight: .medium)
//        loadingLabel.textColor = PayOrcUIConstants.textSecondaryColor
//        loadingLabel.textAlignment = .center
//        loadingLabel.numberOfLines = 0

        loadingContainer.addArrangedSubview(loadingIndicator)
        loadingContainer.addArrangedSubview(loadingLabel)
        contentStack.addArrangedSubview(loadingContainer)
        contentStack.setCustomSpacing(20, after: loadingContainer)

        // ── Tiles sub-stack ────────────────────────────────────────────────────
        tilesStack.axis      = .vertical
        tilesStack.spacing   = PayOrcUIConstants.bottomSheetItemSpacing
        tilesStack.alignment = .fill
        contentStack.addArrangedSubview(tilesStack)
        contentStack.setCustomSpacing(20, after: tilesStack)

        // ── Confirm button ─────────────────────────────────────────────────────
        confirmButton.setTitle("Confirm", for: .normal)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.heightAnchor.constraint(equalToConstant: PayOrcUIConstants.buttonHeight).isActive = true
        contentStack.addArrangedSubview(confirmButton)
        contentStack.setCustomSpacing(10, after: confirmButton)

        // ── Native Apple Pay button — shown in place of Confirm when Apple Pay
        //    is the selected method, matching Flutter's `ApplePayButton` swap. ──
        applePayButton.cornerRadius = PayOrcUIConstants.buttonCornerRadius
        applePayButton.translatesAutoresizingMaskIntoConstraints = false
        applePayButton.heightAnchor.constraint(equalToConstant: PayOrcUIConstants.buttonHeight).isActive = true
        applePayButton.isHidden = true
        contentStack.addArrangedSubview(applePayButton)
        contentStack.setCustomSpacing(10, after: applePayButton)

        // ── Cancel button ──────────────────────────────────────────────────────
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font    = .systemFont(ofSize: 16, weight: .medium)
        cancelButton.backgroundColor     = UIColor.systemGray6
        cancelButton.layer.cornerRadius  = PayOrcUIConstants.buttonCornerRadius
        cancelButton.layer.masksToBounds = true
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.heightAnchor.constraint(equalToConstant: PayOrcUIConstants.buttonHeight).isActive = true
        contentStack.addArrangedSubview(cancelButton)
        contentStack.setCustomSpacing(20, after: cancelButton)

        // ── "Powered by PayOrc" footer ─────────────────────────────────────────
        contentStack.addArrangedSubview(makePoweredByFooter())
    }

    // MARK: - Theme

    private func applyTheme() {
        confirmButton.applyStyle()
        cancelButton.setTitleColor(PayOrcUIConstants.textSecondaryColor, for: .normal)
        for (method, tile) in tilePairs {
            tile.configure(with: tileConfig(for: method))
        }
    }

    // MARK: - Build Tiles

    private func buildPaymentMethodTiles() {
        let methods = orderedVisibleMethods()

        #if DEBUG
        let methodSummary = methods.map { "\($0.type)(show:\($0.show), seq:\($0.sequence))" }
        print("[PayOrc] Payment options methods: \(methodSummary)")
        #endif

        let shouldShowLoading = Self.shouldShowLoadingState(
            for: methods,
            customizationPayload: PayOrc.shared?.checkoutCustomization
        )

        if shouldShowLoading {
            showLoadingState()
            return
        }

        showMethodList(methods)
    }

    static nonisolated func shouldShowLoadingState(
        for methods: [AvailablePaymentMethod],
        customizationPayload: CheckoutCustomizationData?
    ) -> Bool {
        guard customizationPayload != nil else { return true }
        return methods.isEmpty
    }

    private func showLoadingState() {
        loadingIndicator.startAnimating()
        loadingLabel.text = "Loading payment methods..."
        loadingLabel.textColor = PayOrcUIConstants.textSecondaryColor
        loadingContainer.isHidden = false
        tilesStack.isHidden = true
        cancelButton.isHidden = true

        // Keep existing selections cleared while waiting
        selectedMethodType = nil
        updateConfirmButton()
        confirmButton.isHidden  = true
        applePayButton.isHidden = true

        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func showMethodList(_ methods: [AvailablePaymentMethod]) {
        loadingIndicator.stopAnimating()
        loadingContainer.isHidden = true
        tilesStack.isHidden = false
        cancelButton.isHidden = false
        updateConfirmButton()

        // Avoid redundant rebuild if tile list hasn't changed
        let currentTypes = tilePairs.map { $0.method.type }
        let newTypes      = methods.map { $0.type }
        guard currentTypes != newTypes else {
            // Same methods — just refresh selection styles
            for (method, tile) in tilePairs {
                tile.configure(with: tileConfig(for: method))
            }
            updateConfirmButton()
            return
        }

        // Rebuild
        tilesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tilePairs.removeAll()

        for method in methods {
            let tile = PaymentMethodTileView()
            tile.configure(with: tileConfig(for: method))
            tile.onTap = { [weak self] in self?.didSelectMethod(method) }
            tilesStack.addArrangedSubview(tile)
            tilePairs.append((method: method, tile: tile))
        }

        updateConfirmButton()

        // Force layout so tiles reflow immediately
        view.setNeedsLayout()
        view.layoutIfNeeded()

        // If the sheet is already on screen (late API data), resize smoothly
        if viewIfLoaded?.window != nil {
            configureSheetDetent(animated: true)
        }
    }

    // MARK: - Dynamic Sheet Height

    /// Configures `UISheetPresentationController` detent to exactly fit the
    /// current tile count.
    ///
    /// - Parameter animated: Pass `false` in `viewWillAppear` (before the sheet
    ///   animation) so the sheet opens directly at the right height.
    ///   Pass `true` after the sheet is visible to animate any resize.
    private func configureSheetDetent(animated: Bool) {
        guard #available(iOS 15.0, *),
              let sheet = sheetPresentationController else { return }

        let height = contentHeight(tileCount: tilePairs.count)

        let applyDetent = {
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = PayOrcUIConstants.bottomSheetCornerRadius

            if #available(iOS 16.0, *) {
                let h = height
                let custom = UISheetPresentationController.Detent.custom(
                    identifier: .init("payorc.content")
                ) { context in min(h, context.maximumDetentValue) }
                sheet.detents = [custom, .large()]
                sheet.selectedDetentIdentifier = .init("payorc.content")
            } else {
                // iOS 15: pick the closest standard detent
                let windowH = UIScreen.main.bounds.height
                sheet.detents = height > windowH * 0.52 ? [.large()] : [.medium(), .large()]
            }
        }

        if animated {
            sheet.animateChanges { applyDetent() }
        } else {
            applyDetent()
        }
    }

    /// Calculates the total sheet height needed for `tileCount` method tiles.
    /// Uses fixed metrics so it works before layout is complete (in `viewWillAppear`).
    private func contentHeight(tileCount: Int) -> CGFloat {
        let tileH:   CGFloat = 56   // tile row height (icon 28 + 16+16 padding)
        let spacing          = PayOrcUIConstants.bottomSheetItemSpacing
        let tilesH           = CGFloat(tileCount) * tileH
                             + CGFloat(max(0, tileCount - 1)) * spacing

        let btnH  = PayOrcUIConstants.buttonHeight
        let pad   = PayOrcUIConstants.bottomSheetContentInsets

        // Get real safe area if available, otherwise estimate for modern iPhones
        let safeBottom: CGFloat
        if let window = view.window ?? UIApplication.shared.windows.first {
            safeBottom = window.safeAreaInsets.bottom
        } else {
            safeBottom = 34
        }

        return 12          // grabber visual top gap
             + 32 + 4     // dismiss button + gap
             + pad.top    // top content inset
             + tilesH     // all tiles
             + 20         // gap after last tile
             + btnH       // Confirm button
             + 10         // gap
             + btnH       // Cancel button
             + 20         // gap
             + 44         // Powered-by footer
             + pad.bottom // bottom content inset
             + safeBottom // device safe area
             + 8          // breathing room
    }


    // MARK: - Method Resolution

    /// Returns ALL visible, iOS-compatible methods in API sequence order.
    /// Only excludes `google_pay` (Android-only).
    private func orderedVisibleMethods() -> [AvailablePaymentMethod] {
        guard let data = PayOrc.shared?.checkoutCustomization,
              !data.availableMethods.isEmpty else {
            return []
        }

        let methods = data.availableMethods
            .filter { $0.isVisible }
            .filter { $0.type.lowercased() != "google_pay" }
            .sorted { $0.sequence < $1.sequence }

        return methods
    }

    private func tileConfig(for method: AvailablePaymentMethod) -> PaymentMethodTileView.Config {
        let selected = (selectedMethodType == method.type)
        switch method.type.lowercased() {
        case "card":
            return PaymentMethodTileView.Config(
                iconName:      "plus", // Matches Flutter add_rounded
                title:         "Pay with Card",
                trailingLogos: cardSchemeLogos(for: method),
                isSelected:    selected,
                backgroundColor: .systemBackground // Matches Flutter white
            )
        case "stored_card", "savedcard", "use_stored_card":
            return PaymentMethodTileView.Config(
                iconName:   "creditcard.fill",
                title:      "Use Stored Card",
                isSelected: selected,
                backgroundColor: .systemGray6 // Matches Flutter lightGrey
            )
        case "apple_pay":
            return PaymentMethodTileView.Config(
                iconName:   "apple.logo",
                title:      "Apple Pay",
                isSelected: selected,
                backgroundColor: .systemGray6
            )
        case "tabby":
            return PaymentMethodTileView.Config(
                imageName:  "tabby",
                title:      "Tabby",
                isSelected: selected,
                backgroundColor: .systemGray6
            )
        case "samsung_pay":
            return PaymentMethodTileView.Config(
                imageName:  "samsung_pay",
                title:      "Samsung Pay",
                isSelected: selected,
                backgroundColor: .systemGray6
            )
        default:
            return PaymentMethodTileView.Config(
                iconName:   "creditcard",
                title:      methodDisplayName(method.type),
                isSelected: selected,
                backgroundColor: .systemGray6
            )
        }
    }

    private func methodDisplayName(_ type: String) -> String {
        type.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func cardSchemeLogos(for method: AvailablePaymentMethod) -> [String] {
        let map: [String: String] = [
            "visa": "visa", "mastercard": "mastercard", "master": "mastercard",
            "amex": "amex", "american express": "amex",
            "jcb": "jcb", "mada": "mada", "maestro": "maestro",
            "discover": "discover", "diners": "diners", "unionpay": "unionpay"
        ]
        guard !method.schemes.isEmpty else {
            return ["visa", "mastercard", "amex", "jcb"]
        }
        let logos = method.schemes.compactMap { map[$0.lowercased()] }
        return logos.isEmpty ? ["visa", "mastercard", "amex", "jcb"] : logos
    }

    // MARK: - Selection

    private func didSelectMethod(_ method: AvailablePaymentMethod) {
        selectedMethodType = method.type

        // Immediate action for "Pay with Card" matches Flutter
        if method.type.lowercased() == "card" {
            confirmTapped()
            return
        }

        for (m, tile) in tilePairs {
            tile.configure(with: tileConfig(for: m))
        }
        updateConfirmButton()
    }

    // MARK: - Confirm Button

    private func updateConfirmButton() {
        let isApple = selectedMethodType?.lowercased() == "apple_pay"
        applePayButton.isHidden = !isApple
        confirmButton.isHidden  = isApple
        confirmButton.setTitle("Confirm", for: .normal)
        confirmButton.applyStyle()
    }

    // MARK: - Actions

    private func setupActions() {
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        applePayButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        cancelButton.addTarget(self,  action: #selector(cancelTapped),  for: .touchUpInside)

        NotificationCenter.default.addObserver(
            self, selector: #selector(onUiCustomization),
            name: PayOrc.uiCustomizationDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(onCheckoutCustomization),
            name: PayOrc.checkoutCustomizationDidChange, object: nil)
    }

    @objc private func confirmTapped() {
        guard let typeStr = selectedMethodType else { shakeConfirmButton(); return }
        switch typeStr.lowercased() {
        case "card", "stored_card", "savedcard", "use_stored_card":
            dismiss(animated: true) { [weak self] in self?.onSelectCard?() }
        case "apple_pay":
            dismiss(animated: true) { [weak self] in self?.onSelectApplePay?() }
        case "tabby":
            dismiss(animated: true) { [weak self] in self?.onSelectTabby?() }
        default:
            dismiss(animated: true) { [weak self] in self?.onSelectOtherMethod?(typeStr) }
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true) { [weak self] in self?.onCancel?() }
    }

    @objc private func onUiCustomization() {
        DispatchQueue.main.async { [weak self] in self?.applyTheme() }
    }

    @objc private func onCheckoutCustomization() {
        // API data arrived — rebuild the full tile list and stop the loading spinner
        DispatchQueue.main.async { [weak self] in
            self?.buildPaymentMethodTiles()
            self?.loadingIndicator.stopAnimating()
            self?.loadingContainer.isHidden = true
            self?.tilesStack.isHidden = false
            self?.confirmButton.isHidden = false
            self?.cancelButton.isHidden = false
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }
    }

    // MARK: - Powered By Footer

    private func makePoweredByFooter() -> UIView {
        let container = UIView()

        let topLabel       = UILabel()
        topLabel.text      = "Powered by"
        topLabel.font      = .systemFont(ofSize: 11)
        topLabel.textColor = PayOrcUIConstants.textSecondaryColor
        topLabel.textAlignment = .center

        let bottomView: UIView
        if let logoURL = PayOrc.shared?.checkoutCustomization?.payorcLogo,
           !logoURL.isEmpty, let url = URL(string: logoURL) {
            let iv           = UIImageView()
            iv.contentMode   = .scaleAspectFit
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.heightAnchor.constraint(equalToConstant: 20).isActive = true
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async { iv.image = img }
            }.resume()
            bottomView = iv
        } else {
            let lbl             = UILabel()
            lbl.attributedText  = payorcStyledText()
            lbl.textAlignment   = .center
            bottomView          = lbl
        }

        let vStack = UIStackView(arrangedSubviews: [topLabel, bottomView])
        vStack.axis      = .vertical
        vStack.spacing   = 3
        vStack.alignment = .center
        vStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: container.topAnchor),
            vStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            vStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func payorcStyledText() -> NSAttributedString {
        let accent = PayOrcUIConstants.accentColor
        let dark   = PayOrcUIConstants.textPrimaryColor
        let bold   = UIFont.boldSystemFont(ofSize: 16)
        let str    = NSMutableAttributedString()
        str.append(NSAttributedString(string: "Pay",
            attributes: [.foregroundColor: dark, .font: bold]))
        str.append(NSAttributedString(string: "O",
            attributes: [.foregroundColor: accent, .font: bold]))
        str.append(NSAttributedString(string: "rc",
            attributes: [.foregroundColor: dark, .font: bold]))
        return str
    }

    // MARK: - Helpers

    private func shakeConfirmButton() {
        let a      = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values   = [-8, 8, -5, 5, -3, 3, 0]
        a.duration = 0.35
        confirmButton.layer.add(a, forKey: nil)
    }

}
