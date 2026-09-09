import UIKit
import Combine

// MARK: - CheckoutViewController

/// PayOrc card checkout form — mirrors Flutter's `AddCardFormScene`.
///
/// Layout (top → bottom):
///   "Use New Card"  bold title  +  ↓ dismiss button (iOS)
///   "Enter your card details securely"  subtitle
///   ────────────────────────────────────────────────────
///   [Card Number field]              [scheme logo]
///   [MM]  [YY]  [CVV]
///   [Mobile Number:  🇦🇪 +971 | ________]
///   ────────────────────────────────────────────────────
///   disclaimer text
///   [   Verify   ]  ← accent-colored button
///   Powered by  PayOrc
///
public final class CheckoutViewController: UIViewController {

    // MARK: - Dependencies
    private let viewModel: CheckoutViewModel
    private weak var delegate: PayOrcSDKDelegate?
    private var cancellables = Set<AnyCancellable>()

    /// When set, a `/sdk/payment` failure is handed to this closure instead of the
    /// default inline error on the card form — dismissing the whole checkout stack
    /// first. Set internally by ``PayOrc/presentPaymentOptions(from:request:delegate:)``
    /// to show ``PaymentFailedViewController`` (with saved cards + retry). Left `nil`
    /// for direct ``PayOrc/presentCheckout(from:request:delegate:)`` calls and the
    /// embedded `PayOrcEmbeddedPayWithCardButton` flow, which keep today's inline error.
    ///
    /// Third parameter is the PayOrc-assigned order id (`p_order_id`) from the
    /// failure response, when available — needed to look up saved cards for retry,
    /// since the merchant's own `m_order_id` in the original request is often blank.
    public var onSubmitFailed: ((PayOrcError, CardData, String?) -> Void)?

    /// When set, `submitTapped()` hands the validated ``CardData`` to this closure instead of
    /// presenting ``SubmittingOrderViewController`` — mirrors Flutter's `AddCardForm.onAddCard`.
    /// The host owns dismissal (e.g. call `dismiss(animated:)` on the sheet from inside the
    /// closure). Set by ``PayOrc/addNewCard(from:request:onAddCard:onCancel:onError:)``.
    public var onCollectCard: ((CardData) -> Void)?

    // MARK: - UI
    private let scrollView          = UIScrollView()
    private let contentStack        = UIStackView()

    // Header
    private let titleLabel          = UILabel()
    private let subtitleLabel       = UILabel()

    // Form Fields — labels/hints resolve host copy overrides (``PayOrcAddCardFormCustomization``)
    // set via ``PayOrc/setCustomization(_:)`` before this controller is created.
    private static var copy: PayOrcAddCardFormCustomization? { PayOrcUIConstants.addCardFormCustomization }

    private let cardholderNameField = FloatingLabelTextField(
        label: copy?.cardHolderNameLabel ?? "Card Holder Name", hint: copy?.cardHolderNameHint)
    private let emailField          = FloatingLabelTextField(
        label: copy?.emailLabel ?? "Email", hint: copy?.emailHint, keyboardType: .emailAddress)

    // Card number row (field + scheme logo)
    private let cardNumberContainer = UIView()
    private let cardNumberField     = FloatingLabelTextField(
        label: copy?.cardNumberLabel ?? "Card Number", hint: copy?.cardNumberHint, keyboardType: .numberPad)
    private let schemeLogoView      = UIImageView()

    // Expiry + CVV row
    private let expiryCvvStack      = UIStackView()
    // Expiry is two fields in this SDK (unlike Flutter's single combined field); a
    // host `expiryLabel` override, if provided, replaces both "MM"/"YY" labels — a
    // host `expiryHint` overrides just the placeholder, keeping "MM"/"YY" as labels.
    private let monthField          = FloatingLabelTextField(
        label: copy?.expiryLabel ?? "MM", hint: copy?.expiryLabel == nil ? copy?.expiryHint : nil, keyboardType: .numberPad)
    private let yearField           = FloatingLabelTextField(
        label: copy?.expiryLabel ?? "YY", hint: copy?.expiryLabel == nil ? copy?.expiryHint : nil, keyboardType: .numberPad)
    private let cvvField            = FloatingLabelTextField(
        label: copy?.cvvLabel ?? "CVV", hint: copy?.cvvHint, keyboardType: .numberPad)

    // Mobile row (country picker + number)
    private let mobileContainer     = UIView()
    private let mobileLabel         = UILabel()
    private let countryButton       = UIButton(type: .system)
    private let mobileNumberField   = UITextField()
    private let mobileDivider       = UIView()
    private let mobileBorderBox     = UIView()

    // Footer
    private let disclaimerLabel     = UILabel()
    private let submitButton        = PayOrcButton()
    private let poweredByView       = PoweredByView()
    private let errorLabel          = UILabel()

    // Initial loading overlay — shown until checkout customization has loaded
    private let loadingContainer    = UIView()
    private let loadingIndicator    = UIActivityIndicatorView(style: .medium)
    private let loadingLabel        = UILabel()

    // State
    private var selectedCountryCode = "971"    // AE default
    private var selectedCountryFlag = "🇦🇪"
    private var cardSchemeLogos: [String] = [] // updated as user types

    // MARK: - Init
    public init(viewModel: CheckoutViewModel, delegate: PayOrcSDKDelegate) {
        self.viewModel = viewModel
        self.delegate  = delegate
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLayout()
        setupLoadingOverlay()
        setupActions()
        bindViewModel()
        prefillFromRequest()
        applyInitialLoadingState()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        applyTheme()
        configureSheetDetent(animated: false)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureSheetDetent(animated: true)
    }

    // MARK: - Layout

    @available(iOS 15.0, *)
    private func configureSheetDetent(animated: Bool) {
        guard let sheet = sheetPresentationController else { return }
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = PayOrcUIConstants.bottomSheetCornerRadius

        if #available(iOS 16.0, *) {
            let custom = UISheetPresentationController.Detent.custom(
                identifier: .init("payorc.checkout")
            ) { [weak self] context in
                guard let self = self else { return 0 }
                return min(self.sheetContentHeight(), context.maximumDetentValue)
            }

            let applyDetent = {
                sheet.detents = [custom]
                sheet.selectedDetentIdentifier = custom.identifier
            }

            if animated {
                sheet.animateChanges { applyDetent() }
            } else {
                applyDetent()
            }
        } else {
            sheet.detents = [.medium(), .large()]
        }
    }

    private func sheetContentHeight() -> CGFloat {
        let targetWidth = view.bounds.width - 40
        let contentSize = contentStack.systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let safeArea = view.safeAreaInsets.top + view.safeAreaInsets.bottom
        return contentSize.height + safeArea + 24
    }

    // MARK: - Layout

    private func setupLayout() {
        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])

        // Content stack
        contentStack.axis      = .vertical
        contentStack.spacing   = 0
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        // ── Header row: title + dismiss button ────────────────────────────────
        let headerRow = makeHeaderRow()
        contentStack.addArrangedSubview(headerRow)
        contentStack.setCustomSpacing(0, after: headerRow)

        // ── Subtitle ──────────────────────────────────────────────────────────
        subtitleLabel.text          = Self.copy?.subtitleAdd ?? "Enter your card details securely"
        subtitleLabel.font          = .systemFont(ofSize: 14)
        subtitleLabel.textColor     = PayOrcUIConstants.textSecondaryColor
        subtitleLabel.numberOfLines = 1
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.setCustomSpacing(20, after: subtitleLabel)

        // ── Cardholder Name ──────────────────────────────────────────────────
        contentStack.addArrangedSubview(cardholderNameField)
        cardholderNameField.heightAnchor.constraint(
            equalToConstant: PayOrcUIConstants.textFieldHeight).isActive = true
        contentStack.setCustomSpacing(12, after: cardholderNameField)

        // ── Card Number field ─────────────────────────────────────────────────
        buildCardNumberRow()
        contentStack.addArrangedSubview(cardNumberContainer)
        cardNumberContainer.heightAnchor.constraint(
            equalToConstant: PayOrcUIConstants.textFieldHeight).isActive = true
        contentStack.setCustomSpacing(12, after: cardNumberContainer)

        // ── Expiry + CVV row ──────────────────────────────────────────────────
        expiryCvvStack.axis         = .horizontal
        expiryCvvStack.spacing      = 10
        expiryCvvStack.distribution = .fillEqually
        expiryCvvStack.alignment    = .fill
        [monthField, yearField, cvvField].forEach {
            $0.heightAnchor.constraint(equalToConstant: PayOrcUIConstants.textFieldHeight).isActive = true
            expiryCvvStack.addArrangedSubview($0)
        }
        cvvField.textField.isSecureTextEntry = true
        contentStack.addArrangedSubview(expiryCvvStack)
        contentStack.setCustomSpacing(12, after: expiryCvvStack)

        // ── Email Field ───────────────────────────────────────────────────────
        contentStack.addArrangedSubview(emailField)
        emailField.heightAnchor.constraint(
            equalToConstant: PayOrcUIConstants.textFieldHeight).isActive = true
        contentStack.setCustomSpacing(12, after: emailField)

        // ── Mobile number row ──────────────────────────────────────────────────
        buildMobileRow()
        contentStack.addArrangedSubview(mobileContainer)
        contentStack.setCustomSpacing(20, after: mobileContainer)

        // ── Error label ────────────────────────────────────────────────────────
        errorLabel.numberOfLines = 0
        errorLabel.font          = .systemFont(ofSize: 13)
        errorLabel.textColor     = .systemRed
        errorLabel.isHidden      = true
        contentStack.addArrangedSubview(errorLabel)
        contentStack.setCustomSpacing(8, after: errorLabel)

        // ── Disclaimer ────────────────────────────────────────────────────────
        disclaimerLabel.text          = "By providing your card information, you allow us to charge your card for future payments in accordance with their terms."
        disclaimerLabel.font          = .systemFont(ofSize: 12)
        disclaimerLabel.textColor     = PayOrcUIConstants.textSecondaryColor
        disclaimerLabel.numberOfLines = 0
        contentStack.addArrangedSubview(disclaimerLabel)
        contentStack.setCustomSpacing(16, after: disclaimerLabel)

        // ── Verify button ──────────────────────────────────────────────────────
        submitButton.setTitle(Self.copy?.submitButtonTitleVerify ?? "Verify", for: .normal)
        submitButton.heightAnchor.constraint(
            equalToConstant: PayOrcUIConstants.buttonHeight).isActive = true
        contentStack.addArrangedSubview(submitButton)
        contentStack.setCustomSpacing(16, after: submitButton)

        // ── Powered by PayOrc ──────────────────────────────────────────────────
        contentStack.addArrangedSubview(poweredByView)
    }

    // MARK: Build helpers

    private func makeHeaderRow() -> UIView {
        // Title
        titleLabel.text          = Self.copy?.titleUseNewCard ?? "Use New Card"
        titleLabel.font          = .boldSystemFont(ofSize: 20)
        titleLabel.textColor     = PayOrcUIConstants.textPrimaryColor
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // iOS dismiss button (down arrow in circle, top-right — matches Flutter)
        let dismissBtn = UIButton(type: .system)
        let cfg        = UIImage.SymbolConfiguration(pointSize: 20, weight: .light)
        dismissBtn.setImage(
            UIImage(systemName: "chevron.down.circle.fill", withConfiguration: cfg),
            for: .normal
        )
        dismissBtn.tintColor = UIColor.tertiaryLabel
        dismissBtn.setContentHuggingPriority(.required, for: .horizontal)
        dismissBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [titleLabel, dismissBtn])
        row.axis      = .horizontal
        row.alignment = .center
        row.spacing   = 8
        return row
    }

    private func buildCardNumberRow() {
        cardNumberContainer.translatesAutoresizingMaskIntoConstraints = false

        // Floating-label field
        cardNumberField.translatesAutoresizingMaskIntoConstraints = false
        cardNumberContainer.addSubview(cardNumberField)
        NSLayoutConstraint.activate([
            cardNumberField.topAnchor.constraint(equalTo: cardNumberContainer.topAnchor),
            cardNumberField.leadingAnchor.constraint(equalTo: cardNumberContainer.leadingAnchor),
            cardNumberField.trailingAnchor.constraint(equalTo: cardNumberContainer.trailingAnchor),
            cardNumberField.bottomAnchor.constraint(equalTo: cardNumberContainer.bottomAnchor)
        ])

        // Scheme logo (inside field, right side)
        schemeLogoView.contentMode   = .scaleAspectFit
        schemeLogoView.clipsToBounds = true
        schemeLogoView.isHidden      = true
        schemeLogoView.translatesAutoresizingMaskIntoConstraints = false
        cardNumberContainer.addSubview(schemeLogoView)
        NSLayoutConstraint.activate([
            // Centered on the text field itself, not the container — the
            // container's top 8pt is reserved for the floating label above
            // the bordered box (see `FloatingLabelTextField`), so centering
            // against the container's full height pulls the icon up off the
            // box's true visual center.
            schemeLogoView.centerYAnchor.constraint(equalTo: cardNumberField.textField.centerYAnchor),
            schemeLogoView.trailingAnchor.constraint(equalTo: cardNumberContainer.trailingAnchor, constant: -12),
            schemeLogoView.widthAnchor.constraint(equalToConstant: 44),
            schemeLogoView.heightAnchor.constraint(equalToConstant: 28)
        ])

        // Give the field's text input right padding so it doesn't overlap the logo
        cardNumberField.textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 64, height: 1))
        cardNumberField.textField.rightViewMode = .always
    }

    private func buildMobileRow() {
        mobileContainer.translatesAutoresizingMaskIntoConstraints = false

        // "Mobile Number" floating label
        mobileLabel.text      = " \(Self.copy?.mobileLabel ?? "Mobile Number") "
        mobileLabel.font      = .systemFont(ofSize: 11, weight: .medium)
        mobileLabel.textColor = PayOrcUIConstants.textSecondaryColor
        mobileLabel.backgroundColor = .clear
        mobileLabel.alpha = 0
        mobileLabel.translatesAutoresizingMaskIntoConstraints = false

        // Country picker button  [🇦🇪 +971  ˅]
        updateCountryButton()
        countryButton.contentHorizontalAlignment = .leading
        countryButton.titleLabel?.font = .systemFont(ofSize: 15)
        countryButton.setContentHuggingPriority(.required, for: .horizontal)
        countryButton.translatesAutoresizingMaskIntoConstraints = false

        // Vertical divider between country btn and number field
        mobileDivider.backgroundColor = PayOrcUIConstants.textFieldBorderColor
        mobileDivider.translatesAutoresizingMaskIntoConstraints = false
        mobileDivider.widthAnchor.constraint(equalToConstant: 1).isActive = true

        // Number input
        mobileNumberField.placeholder          = Self.copy?.mobileHint ?? Self.copy?.mobileLabel ?? "Mobile Number"
        mobileNumberField.keyboardType         = .phonePad
        mobileNumberField.font                 = .systemFont(ofSize: 15)
        mobileNumberField.textColor            = PayOrcUIConstants.textPrimaryColor
        mobileNumberField.tintColor            = PayOrcUIConstants.accentColor
        mobileNumberField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mobileNumberField.translatesAutoresizingMaskIntoConstraints = false

        mobileNumberField.addTarget(self, action: #selector(mobileEditingChanged), for: .editingChanged)
        mobileNumberField.addTarget(self, action: #selector(mobileEditingDidBegin), for: .editingDidBegin)
        mobileNumberField.addTarget(self, action: #selector(mobileEditingDidEnd), for: .editingDidEnd)

        // Horizontal input row: [countryBtn | divider | numberField]
        let inputRow = UIStackView(arrangedSubviews: [countryButton, mobileDivider, mobileNumberField])
        inputRow.axis      = .horizontal
        inputRow.spacing   = 10
        inputRow.alignment = .center
        inputRow.translatesAutoresizingMaskIntoConstraints = false

        // Outer bordered container
        mobileBorderBox.layer.cornerRadius = PayOrcUIConstants.textFieldCornerRadius
        mobileBorderBox.layer.borderWidth  = 1
        mobileBorderBox.layer.borderColor  = PayOrcUIConstants.textFieldBorderColor.cgColor
        mobileBorderBox.translatesAutoresizingMaskIntoConstraints = false
        mobileBorderBox.addSubview(mobileLabel)
        mobileBorderBox.addSubview(inputRow)
        NSLayoutConstraint.activate([
            mobileLabel.bottomAnchor.constraint(equalTo: mobileBorderBox.topAnchor, constant: -2),
            mobileLabel.leadingAnchor.constraint(equalTo: mobileBorderBox.leadingAnchor, constant: 10),

            inputRow.topAnchor.constraint(equalTo: mobileBorderBox.topAnchor, constant: 10),
            inputRow.leadingAnchor.constraint(equalTo: mobileBorderBox.leadingAnchor, constant: 12),
            inputRow.trailingAnchor.constraint(equalTo: mobileBorderBox.trailingAnchor, constant: -12),
            inputRow.bottomAnchor.constraint(equalTo: mobileBorderBox.bottomAnchor, constant: -10),
            mobileDivider.heightAnchor.constraint(equalTo: inputRow.heightAnchor, multiplier: 0.6)
        ])

        mobileContainer.addSubview(mobileBorderBox)
        NSLayoutConstraint.activate([
            mobileBorderBox.topAnchor.constraint(equalTo: mobileContainer.topAnchor, constant: 8),
            mobileBorderBox.leadingAnchor.constraint(equalTo: mobileContainer.leadingAnchor),
            mobileBorderBox.trailingAnchor.constraint(equalTo: mobileContainer.trailingAnchor),
            mobileBorderBox.bottomAnchor.constraint(equalTo: mobileContainer.bottomAnchor),
            mobileBorderBox.heightAnchor.constraint(equalToConstant: PayOrcUIConstants.textFieldHeight)
        ])
    }

    // MARK: - Initial Loading Overlay

    /// Full-sheet spinner shown until checkout customization (branding, supported card
    /// schemes, billing-section visibility) has loaded — mirrors Flutter's
    /// `PaymentOptionsSheetFlowScene` spinner-in-sheet behavior for the card form.
    private func setupLoadingOverlay() {
        loadingContainer.backgroundColor = .systemBackground
        loadingContainer.isHidden = true
        loadingContainer.translatesAutoresizingMaskIntoConstraints = false

        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        loadingLabel.text = "Loading payment details..."
        loadingLabel.font = .systemFont(ofSize: 14, weight: .medium)
        loadingLabel.textAlignment = .center
        loadingLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [loadingIndicator, loadingLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        loadingContainer.addSubview(stack)
        view.addSubview(loadingContainer)

        NSLayoutConstraint.activate([
            loadingContainer.topAnchor.constraint(equalTo: view.topAnchor),
            loadingContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: loadingContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: loadingContainer.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: loadingContainer.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: loadingContainer.trailingAnchor, constant: -24)
        ])
    }

    /// Shows the loading overlay when checkout customization hasn't arrived yet
    /// (e.g. the sheet opened right after app launch, before the SDK's background
    /// fetch completed); otherwise leaves the form visible immediately, as today.
    private func applyInitialLoadingState() {
        guard PayOrc.shared?.checkoutCustomization == nil else {
            loadingContainer.isHidden = true
            return
        }
        loadingContainer.isHidden = false
        loadingLabel.textColor = PayOrcUIConstants.textSecondaryColor
        loadingIndicator.color = PayOrcUIConstants.textSecondaryColor
        loadingIndicator.startAnimating()

        NotificationCenter.default.addObserver(
            self, selector: #selector(onCheckoutCustomizationLoaded),
            name: PayOrc.checkoutCustomizationDidChange, object: nil)
    }

    @objc private func onCheckoutCustomizationLoaded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.loadingContainer.isHidden else { return }
            NotificationCenter.default.removeObserver(
                self, name: PayOrc.checkoutCustomizationDidChange, object: nil)
            self.loadingIndicator.stopAnimating()
            UIView.animate(withDuration: 0.2, animations: {
                self.loadingContainer.alpha = 0
            }, completion: { _ in
                self.loadingContainer.isHidden = true
                self.loadingContainer.alpha = 1
            })
        }
    }

    // MARK: - Theme

    private func applyTheme() {
        titleLabel.textColor        = PayOrcUIConstants.textPrimaryColor
        subtitleLabel.textColor     = PayOrcUIConstants.textSecondaryColor
        disclaimerLabel.textColor   = PayOrcUIConstants.textSecondaryColor
        applyExtendedTextAttributes()
        mobileLabel.textColor       = PayOrcUIConstants.textSecondaryColor
        mobileNumberField.textColor = PayOrcUIConstants.textPrimaryColor
        mobileDivider.backgroundColor = PayOrcUIConstants.textFieldBorderColor
        mobileBorderBox.layer.borderColor = mobileNumberField.isFirstResponder
            ? PayOrcUIConstants.accentColor.cgColor
            : PayOrcUIConstants.textFieldBorderColor.cgColor
        submitButton.applyStyle()
        [cardholderNameField, cardNumberField, monthField, yearField, cvvField, emailField].forEach { $0.applyStyle() }
        updateMobileLabelVisibility()
    }

    /// Applies host ``PayOrcTextCustomization`` extras (alignment, letter/word
    /// spacing, underline/strikethrough, italic, shadow, max lines) to the header
    /// title and subtitle — the form's most prominent free-standing text.
    private func applyExtendedTextAttributes() {
        let titleFont = PayOrcUIConstants.titleFont
        titleLabel.attributedText = NSAttributedString(
            string: titleLabel.text ?? "",
            attributes: PayOrcUIConstants.resolvedTextAttributes(font: .boldSystemFont(ofSize: titleFont.pointSize + 4), color: PayOrcUIConstants.textPrimaryColor)
        )
        titleLabel.numberOfLines = PayOrcUIConstants.textMaxLines

        subtitleLabel.attributedText = NSAttributedString(
            string: subtitleLabel.text ?? "",
            attributes: PayOrcUIConstants.resolvedTextAttributes(font: .systemFont(ofSize: 14), color: PayOrcUIConstants.textSecondaryColor)
        )
        subtitleLabel.numberOfLines = PayOrcUIConstants.textMaxLines
    }

    // MARK: - Prefill

    private func prefillFromRequest() {
        let req = viewModel.paymentRequest
        let c = req.customerDetails

        cardholderNameField.textField.text = c.name
        emailField.textField.text = c.email

        // Country code → flag
        let code = c.code
        if !code.isEmpty {
            selectedCountryCode = code
            selectedCountryFlag = flag(from: code)
            updateCountryButton()
        }
        let mobile = c.mobile
        if !mobile.isEmpty {
            mobileNumberField.text = mobile
        }

        applyMerchantProvidedFieldVisibility(customerDetails: c)
    }

    /// Hides fields the merchant already supplied a value for via
    /// ``PaymentRequest/customerDetails``, and shows only the fields the user still
    /// needs to fill in. Each field is evaluated independently — e.g. a merchant may
    /// supply `name` and `email` but leave `mobile` blank for the user to enter.
    private func applyMerchantProvidedFieldVisibility(customerDetails c: CustomerDetails) {
        let hasName   = !c.name.trimmingCharacters(in: .whitespaces).isEmpty
        let hasEmail  = !c.email.trimmingCharacters(in: .whitespaces).isEmpty
        let hasMobile = !c.mobile.trimmingCharacters(in: .whitespaces).isEmpty

        cardholderNameField.isHidden = hasName
        emailField.isHidden          = hasEmail
        mobileContainer.isHidden     = hasMobile
    }

    // MARK: - Actions

    private func setupActions() {
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        cardNumberField.textField.addTarget(self, action: #selector(cardNumberChanged), for: .editingChanged)
        countryButton.addTarget(self, action: #selector(countryPickerTapped), for: .touchUpInside)

        NotificationCenter.default.addObserver(
            self, selector: #selector(customizationDidChange),
            name: PayOrc.uiCustomizationDidChange, object: nil)
    }

    @objc private func cancelTapped() {
        delegate?.payOrcDidCancel()
        dismiss(animated: true)
    }

    @objc private func submitTapped() {
        view.endEditing(true)
        let card = CardData(
            cardNumber:     cardNumberField.textField.text?.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces),
            cardholderName: cardholderNameField.textField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            expiryMonth:    monthField.textField.text?.trimmingCharacters(in: .whitespaces) ?? "",
            expiryYear:     yearField.textField.text?.trimmingCharacters(in: .whitespaces)  ?? "",
            cvv:            cvvField.textField.text?.trimmingCharacters(in: .whitespaces)   ?? "",
            email:          emailField.textField.text?.trimmingCharacters(in: .whitespaces),
            mobile:         mobileNumberField.text?.trimmingCharacters(in: .whitespaces)
        )

        // 1. Local validation check first
        if let validationError = viewModel.validate(card: card) {
            showError(PayOrcUIConstants.cardFieldErrorMessage(for: validationError))
            return
        }
        hideError()

        if let onCollectCard {
            onCollectCard(card)
            return
        }

        // 2. Present SubmittingOrderViewController bottom sheet (matching Flutter loader)
        let submittingVC = SubmittingOrderViewController(
            viewModel: viewModel,
            card: card,
            onSuccess: { [weak self] result in
                guard let self = self else { return }
                // Dismissing from the ORIGINAL presenter (not from `self`/`nav`) is
                // what collapses the whole checkout stack — card form, submitting
                // sheet, and 3DS webview if it was shown — into a single animation.
                // Calling dismiss on `nav` itself only removes what `nav` presented
                // (i.e. leaves the card form on screen), since `nav` still has a
                // presentedViewController at this point.
                guard let originalPresenter = self.navigationController?.presentingViewController
                    ?? self.presentingViewController else {
                    self.delegate?.payOrcDidComplete(result: result)
                    return
                }
                originalPresenter.dismiss(animated: true) {
                    // Mirrors Flutter's PaymentConfirmedSheet: show the success
                    // sheet over the host's screen, then hand back to the host.
                    let confirmedVC = PaymentConfirmedViewController(card: card) {
                        self.delegate?.payOrcDidComplete(result: result)
                    }
                    originalPresenter.present(confirmedVC, animated: true)
                }
            },
            onFailure: { [weak self] error, orderId in
                guard let self = self else { return }
                #if DEBUG
                print("[PayOrc] CheckoutViewController.onFailure fired: \(error.localizedDescription) orderId=\(orderId ?? "nil")")
                #endif
                // Nothing has dismissed itself by the time onFailure fires — the
                // submitting sheet (and 3DS webview, if any) are still on screen above
                // `self`/`nav`. Always dismiss the WHOLE checkout stack (card form +
                // submitting sheet + 3DS webview) from the original presenter in one
                // animation — i.e. straight back to the host's screen — rather than
                // leaving an inline retry UI up, then decide what happens next.
                guard let originalPresenter = self.navigationController?.presentingViewController
                    ?? self.presentingViewController else {
                    #if DEBUG
                    print("[PayOrc] No originalPresenter found — reporting failure without a dismiss.")
                    #endif
                    self.reportSubmitFailure(error, card: card, orderId: orderId)
                    return
                }
                originalPresenter.dismiss(animated: true) {
                    #if DEBUG
                    print("[PayOrc] originalPresenter.dismiss completed — reporting failure.")
                    #endif
                    self.reportSubmitFailure(error, card: card, orderId: orderId)
                }
            },
            onCancel: { [weak self] in
                guard let self = self else { return }
                guard let originalPresenter = self.navigationController?.presentingViewController
                    ?? self.presentingViewController else {
                    self.delegate?.payOrcDidCancel()
                    return
                }
                originalPresenter.dismiss(animated: true) {
                    self.delegate?.payOrcDidCancel()
                }
            }
        )
        present(submittingVC, animated: true)
    }


    @objc private func cardNumberChanged() {
        let raw     = cardNumberField.textField.text?.replacingOccurrences(of: " ", with: "") ?? ""
        let display = formatCardNumber(raw)
        if cardNumberField.textField.text != display {
            cardNumberField.textField.text = display
        }
        updateSchemeLogoForNumber(raw)
    }

    @objc private func countryPickerTapped() {
        let alert = UIAlertController(title: "Country Code", message: nil, preferredStyle: .actionSheet)
        let common = [("971", "🇦🇪", "UAE"), ("966", "🇸🇦", "Saudi Arabia"),
                      ("965", "🇰🇼", "Kuwait"), ("968", "🇴🇲", "Oman"),
                      ("974", "🇶🇦", "Qatar"), ("973", "🇧🇭", "Bahrain"),
                      ("91",  "🇮🇳", "India"), ("1",   "🇺🇸", "USA"), ("44",  "🇬🇧", "UK")]
        for (code, flag, name) in common {
            alert.addAction(UIAlertAction(title: "\(flag) +\(code) \(name)", style: .default) { [weak self] _ in
                self?.selectedCountryCode = code
                self?.selectedCountryFlag = flag
                self?.updateCountryButton()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func customizationDidChange() {
        DispatchQueue.main.async { self.applyTheme() }
    }

    // MARK: - Mobile Field Handlers

    @objc private func mobileEditingChanged() {
        updateMobileLabelVisibility()
    }

    @objc private func mobileEditingDidBegin() {
        if PayOrcUIConstants.guidanceStyle == .label {
            mobileNumberField.placeholder = nil
        }
        updateMobileLabelVisibility()
        UIView.animate(withDuration: 0.2) {
            self.mobileBorderBox.layer.borderColor = PayOrcUIConstants.accentColor.cgColor
            self.mobileBorderBox.layer.borderWidth = 2
        }
    }

    @objc private func mobileEditingDidEnd() {
        if mobileNumberField.text?.isEmpty ?? true {
            mobileNumberField.placeholder = Self.copy?.mobileHint ?? Self.copy?.mobileLabel ?? "Mobile Number"
        }
        updateMobileLabelVisibility()
        UIView.animate(withDuration: 0.2) {
            self.mobileBorderBox.layer.borderColor = PayOrcUIConstants.textFieldBorderColor.cgColor
            self.mobileBorderBox.layer.borderWidth = 1
        }
    }

    private func updateMobileLabelVisibility() {
        guard PayOrcUIConstants.guidanceStyle == .label else {
            mobileLabel.alpha = 0
            return
        }
        let shouldShow = !(mobileNumberField.text?.isEmpty ?? true) || mobileNumberField.isFirstResponder
        UIView.animate(withDuration: 0.2) {
            self.mobileLabel.alpha = shouldShow ? 1 : 0
        }
    }

    // MARK: - ViewModel Binding

    private func bindViewModel() {
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in self?.submitButton.setLoading(loading) }
            .store(in: &cancellables)

        viewModel.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error { self?.showError(error.localizedDescription) }
                else         { self?.hideError() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Error

    private func showError(_ message: String) {
        errorLabel.text     = message
        errorLabel.isHidden = false
    }

    private func hideError() {
        errorLabel.isHidden = true
    }

    /// Delivers a `/sdk/payment` failure after the checkout stack has already been
    /// dismissed — ``onSubmitFailed`` (presentPaymentOptions) if set, otherwise the
    /// default: hand the error straight to the delegate so the host lands back on its
    /// own screen with the error response (matching Apple Pay / Tabby's behavior).
    private func reportSubmitFailure(_ error: PayOrcError, card: CardData, orderId: String?) {
        if let handler = onSubmitFailed {
            handler(error, card, orderId)
        } else {
            delegate?.payOrcDidFail(error: error)
        }
    }

    // MARK: - Helpers

    private func updateCountryButton() {
        let title = "\(selectedCountryFlag) +\(selectedCountryCode)  ▾"
        countryButton.setTitle(title, for: .normal)
        countryButton.setTitleColor(PayOrcUIConstants.textPrimaryColor, for: .normal)
    }

    private func formatCardNumber(_ digits: String) -> String {
        var result = ""
        for (i, ch) in digits.prefix(19).enumerated() {
            if i > 0 && i % 4 == 0 { result += " " }
            result.append(ch)
        }
        return result
    }

    /// Shows a card-scheme logo to the right of the card number field
    /// based on the leading digits.
    private func updateSchemeLogoForNumber(_ digits: String) {
        let logoName: String?
        let prefix  = String(digits.prefix(2))
        let prefix4 = String(digits.prefix(4))
        // Visa is identified by a single leading digit for the *whole* number,
        // not a fixed-length code, so it needs `hasPrefix` rather than an exact
        // match against the 2-character `prefix` — a `case "4":` there only
        // matched while exactly one digit had been typed, hiding the icon again
        // as soon as a second digit landed. Checked before the other cases so a
        // Mada BIN (which also starts with "4") takes priority.
        if madaPrefix(digits) {
            logoName = "mada"
        } else if digits.hasPrefix("4") {
            logoName = "visa"
        } else {
            switch prefix {
            case "51","52","53","54","55":           logoName = "mastercard"
            case "34","37":                          logoName = "amex"
            case "35":                               logoName = "jcb"
            case "60","62","64","65":                logoName = "discover"
            case "30","36","38":                     logoName = "diners"
            default:
                logoName = (prefix4 == "6011") ? "discover" : nil
            }
        }
        if let name = logoName, let img = UIImage(payorcNamed: name) {
            schemeLogoView.image   = img
            schemeLogoView.isHidden = false
        } else {
            schemeLogoView.isHidden = true
        }
    }

    private func madaPrefix(_ digits: String) -> Bool {
        let madaPrefixes = ["588845","440647","440795","446404","457865",
                            "968208","457997","474491","543357","434107"]
        return madaPrefixes.contains { digits.hasPrefix($0) }
    }

    /// Converts a calling code like "971" or country code "AE" to a flag emoji.
    private func flag(from code: String) -> String {
        let map: [String: String] = [
            "971":"🇦🇪","966":"🇸🇦","965":"🇰🇼","968":"🇴🇲","974":"🇶🇦","973":"🇧🇭",
            "91":"🇮🇳","1":"🇺🇸","44":"🇬🇧","AE":"🇦🇪","SA":"🇸🇦","IN":"🇮🇳","US":"🇺🇸"
        ]
        return map[code.uppercased()] ?? "🌍"
    }
}

// MARK: - FloatingLabelTextField

/// Text field with a floating label border (outline style), matching Flutter's `AppTextField`.
final class FloatingLabelTextField: UIView {

    let textField = UITextField()
    private let floatLabel = UILabel()
    private let borderView = UIView()
    private let placeholderText: String

    /// - Parameters:
    ///   - label: Floating label text, shown above the field once focused/filled
    ///     (in ``PayOrcGuidanceStyle/label`` mode).
    ///   - hint: Placeholder shown inside the empty field. Defaults to `label` when
    ///     `nil`, matching the SDK's original single-string behavior.
    init(label: String, hint: String? = nil, keyboardType: UIKeyboardType = .default) {
        self.placeholderText = hint ?? label
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        // Border box
        borderView.layer.cornerRadius = PayOrcUIConstants.textFieldCornerRadius
        borderView.layer.borderWidth  = 1
        borderView.layer.borderColor  = PayOrcUIConstants.textFieldBorderColor.cgColor
        borderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(borderView)
        NSLayoutConstraint.activate([
            borderView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            borderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            borderView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Floating label
        floatLabel.text          = " \(label) " // Add spaces to padding
        floatLabel.font          = .systemFont(ofSize: 11, weight: .medium)
        floatLabel.textColor     = PayOrcUIConstants.textSecondaryColor
        floatLabel.backgroundColor = .clear
        floatLabel.alpha         = 0 // Start hidden
        floatLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(floatLabel)
        NSLayoutConstraint.activate([
            floatLabel.bottomAnchor.constraint(equalTo: borderView.topAnchor, constant: -2),
            floatLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
        ])

        // Text field inside border box
        textField.keyboardType          = keyboardType
        textField.font                  = .systemFont(ofSize: 15)
        textField.borderStyle           = .none
        textField.autocorrectionType    = .no
        textField.autocapitalizationType = .none
        textField.placeholder           = placeholderText // Show as placeholder initially
        textField.translatesAutoresizingMaskIntoConstraints = false
        borderView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: borderView.topAnchor, constant: 8),
            textField.leadingAnchor.constraint(equalTo: borderView.leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: borderView.trailingAnchor, constant: -12),
            textField.bottomAnchor.constraint(equalTo: borderView.bottomAnchor, constant: -8)
        ])

        setupObservers()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupObservers() {
        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        textField.addTarget(self, action: #selector(editingDidBegin), for: .editingDidBegin)
        textField.addTarget(self, action: #selector(editingDidEnd), for: .editingDidEnd)
    }

    @objc private func editingChanged() {
        updateLabelVisibility()
    }

    @objc private func editingDidBegin() {
        if PayOrcUIConstants.guidanceStyle == .label {
            textField.placeholder = nil
        }
        updateLabelVisibility()
        UIView.animate(withDuration: 0.2) {
            self.borderView.layer.borderColor = PayOrcUIConstants.accentColor.cgColor
            self.borderView.layer.borderWidth = 2
        }
    }

    @objc private func editingDidEnd() {
        if textField.text?.isEmpty ?? true {
            textField.placeholder = placeholderText
        }
        updateLabelVisibility()
        UIView.animate(withDuration: 0.2) {
            self.borderView.layer.borderColor = PayOrcUIConstants.textFieldBorderColor.cgColor
            self.borderView.layer.borderWidth = 1
        }
    }

    /// The floating label above the border only appears in ``PayOrcGuidanceStyle/label``
    /// mode; in ``PayOrcGuidanceStyle/hint`` mode, guidance is placeholder-only.
    private func updateLabelVisibility() {
        guard PayOrcUIConstants.guidanceStyle == .label else {
            floatLabel.alpha = 0
            return
        }
        let shouldShow = !(textField.text?.isEmpty ?? true) || textField.isFirstResponder
        UIView.animate(withDuration: 0.2) {
            self.floatLabel.alpha = shouldShow ? 1 : 0
        }
    }

    func applyStyle() {
        borderView.layer.borderColor = textField.isFirstResponder
            ? PayOrcUIConstants.accentColor.cgColor
            : PayOrcUIConstants.textFieldBorderColor.cgColor
        borderView.backgroundColor   = .systemBackground
        textField.textColor          = PayOrcUIConstants.textPrimaryColor
        textField.tintColor          = PayOrcUIConstants.accentColor
        updateLabelVisibility()
    }
}

// MARK: - PoweredByView

/// "Powered by  PayOrc" footer — matches Flutter's `PayorcPoweredBy`.
final class PoweredByView: UIView {

    private let topLabel    = UILabel()
    private let bottomLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        topLabel.text          = "Powered By"
        topLabel.font          = .systemFont(ofSize: 11)
        topLabel.textColor     = UIColor.secondaryLabel
        topLabel.textAlignment = .center

        bottomLabel.attributedText = payorcText()
        bottomLabel.textAlignment  = .center

        let stack = UIStackView(arrangedSubviews: [topLabel, bottomLabel])
        stack.axis      = .vertical
        stack.spacing   = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func payorcText() -> NSAttributedString {
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
}

// MARK: - PayOrcTextField (kept for any existing usages)

final class PayOrcTextField: UITextField {
    init(placeholder: String, keyboardType: UIKeyboardType = .default) {
        super.init(frame: .zero)
        self.placeholder         = placeholder
        self.keyboardType        = keyboardType
        self.autocorrectionType  = .no
        self.autocapitalizationType = .none
        self.translatesAutoresizingMaskIntoConstraints = false
        applyStyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    func applyStyle() {
        borderStyle        = .none
        layer.borderColor  = PayOrcUIConstants.textFieldBorderColor.cgColor
        layer.borderWidth  = 1
        layer.cornerRadius = PayOrcUIConstants.textFieldCornerRadius
        font               = PayOrcUIConstants.bodyFont
        textColor          = PayOrcUIConstants.textPrimaryColor
        tintColor          = PayOrcUIConstants.brandColor
        let pad = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        leftView     = pad; leftViewMode  = .always
        rightView    = UIView(frame: pad.frame); rightViewMode = .always
    }
}

// MARK: - PayOrcButton

final class PayOrcButton: UIButton {
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupActivityIndicator()
        applyStyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    func applyStyle() {
        backgroundColor    = PayOrcUIConstants.buttonBackgroundColor
        tintColor          = PayOrcUIConstants.buttonForegroundColor
        setTitleColor(PayOrcUIConstants.buttonForegroundColor, for: .normal)
        setTitleColor(PayOrcUIConstants.buttonForegroundColor.withAlphaComponent(0.6), for: .disabled)
        layer.cornerRadius = PayOrcUIConstants.buttonCornerRadius
        layer.borderColor  = PayOrcUIConstants.buttonBorderColor.cgColor
        layer.borderWidth  = PayOrcUIConstants.buttonBorderColor == .clear ? 0 : 1
        titleLabel?.font   = .systemFont(ofSize: 16, weight: PayOrcUIConstants.buttonFontWeight)
        activityIndicator.color = PayOrcUIConstants.buttonLoadingIndicatorColor
    }

    /// Applies a per-instance ``PayOrcEmbeddedCustomization`` on top of the SDK-wide
    /// style — used by embedded views that accept their own `customization`.
    func applyStyle(override: PayOrcEmbeddedCustomization) {
        backgroundColor    = override.effectiveButtonBackground
        tintColor          = override.effectiveButtonForeground
        setTitleColor(override.effectiveButtonForeground, for: .normal)
        setTitleColor(override.effectiveButtonForeground.withAlphaComponent(0.6), for: .disabled)
        layer.cornerRadius = override.effectiveButtonRadius
        layer.borderColor  = override.effectiveButtonBorderColor.cgColor
        layer.borderWidth  = override.effectiveButtonBorderColor == .clear ? 0 : 1
        titleLabel?.font   = .systemFont(ofSize: 16, weight: PayOrcUIConstants.buttonFontWeight)
        activityIndicator.color = PayOrcUIConstants.buttonLoadingIndicatorColor
    }

    func setLoading(_ loading: Bool) {
        isEnabled = !loading
        loading ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
        if loading { setTitle(nil, for: .normal) }
        backgroundColor = loading
            ? PayOrcUIConstants.buttonDisabledBackgroundColor
            : PayOrcUIConstants.buttonBackgroundColor
    }

    private func setupActivityIndicator() {
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

// MARK: - CheckoutHeaderView (kept for compatibility)

final class CheckoutHeaderView: UIView {
    private let titleLabel = UILabel()
    override init(frame: CGRect) { super.init(frame: frame); applyTheme() }
    required init?(coder: NSCoder) { fatalError() }
    func applyTheme() {
        titleLabel.textColor = PayOrcUIConstants.textPrimaryColor
        titleLabel.font      = PayOrcUIConstants.titleFont
    }
}
