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

    // MARK: - UI
    private let scrollView          = UIScrollView()
    private let contentStack        = UIStackView()

    // Header
    private let titleLabel          = UILabel()
    private let subtitleLabel       = UILabel()

    // Form Fields
    private let cardholderNameField = FloatingLabelTextField(label: "Card Holder Name")
    private let emailField          = FloatingLabelTextField(label: "Email", keyboardType: .emailAddress)

    // Card number row (field + scheme logo)
    private let cardNumberContainer = UIView()
    private let cardNumberField     = FloatingLabelTextField(label: "Card Number",
                                                             keyboardType: .numberPad)
    private let schemeLogoView      = UIImageView()

    // Expiry + CVV row
    private let expiryCvvStack      = UIStackView()
    private let monthField          = FloatingLabelTextField(label: "MM", keyboardType: .numberPad)
    private let yearField           = FloatingLabelTextField(label: "YY", keyboardType: .numberPad)
    private let cvvField            = FloatingLabelTextField(label: "CVV", keyboardType: .numberPad)

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
        setupActions()
        bindViewModel()
        prefillFromRequest()
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
        subtitleLabel.text          = "Enter your card details securely"
        subtitleLabel.font          = .systemFont(ofSize: 14)
        subtitleLabel.textColor     = PayOrcUIConstants.textSecondaryColor
        subtitleLabel.numberOfLines = 1
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.setCustomSpacing(12, after: subtitleLabel)

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
        submitButton.setTitle("Verify", for: .normal)
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
        titleLabel.text          = "Use New Card"
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
            schemeLogoView.centerYAnchor.constraint(equalTo: cardNumberContainer.centerYAnchor),
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
        mobileLabel.text      = " Mobile Number "
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
        mobileNumberField.placeholder          = "Mobile Number"
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

    // MARK: - Theme

    private func applyTheme() {
        titleLabel.textColor        = PayOrcUIConstants.textPrimaryColor
        subtitleLabel.textColor     = PayOrcUIConstants.textSecondaryColor
        disclaimerLabel.textColor   = PayOrcUIConstants.textSecondaryColor
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
            showError(validationError.localizedDescription)
            return
        }
        hideError()

        // 2. Present SubmittingOrderViewController bottom sheet (matching Flutter loader)
        let submittingVC = SubmittingOrderViewController(
            viewModel: viewModel,
            card: card,
            onSuccess: { [weak self] result in
                guard let self = self else { return }
                self.dismissThen {
                    self.delegate?.payOrcDidComplete(result: result)
                }
            },
            onFailure: { [weak self] error in
                self?.showError(error.localizedDescription)
            }
        )
        present(submittingVC, animated: true)
    }

    private func dismissThen(completion: @escaping () -> Void) {
        if let nav = navigationController, nav.presentingViewController != nil {
            nav.dismiss(animated: true, completion: completion)
        } else if presentingViewController != nil {
            dismiss(animated: true, completion: completion)
        } else {
            completion()
        }
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
        mobileNumberField.placeholder = nil
        updateMobileLabelVisibility()
        UIView.animate(withDuration: 0.2) {
            self.mobileBorderBox.layer.borderColor = PayOrcUIConstants.accentColor.cgColor
            self.mobileBorderBox.layer.borderWidth = 2
        }
    }

    @objc private func mobileEditingDidEnd() {
        if mobileNumberField.text?.isEmpty ?? true {
            mobileNumberField.placeholder = "Mobile Number"
        }
        updateMobileLabelVisibility()
        UIView.animate(withDuration: 0.2) {
            self.mobileBorderBox.layer.borderColor = PayOrcUIConstants.textFieldBorderColor.cgColor
            self.mobileBorderBox.layer.borderWidth = 1
        }
    }

    private func updateMobileLabelVisibility() {
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
        let prefix = String(digits.prefix(2))
        let prefix4 = String(digits.prefix(4))
        switch prefix {
        case "4":                                logoName = "visa"
        case "51","52","53","54","55":           logoName = "mastercard"
        case "34","37":                          logoName = "amex"
        case "35":                               logoName = "jcb"
        case "60","62","64","65":                logoName = "discover"
        case "30","36","38":                     logoName = "diners"
        default:
            if prefix4 == "6011" || prefix == "65" { logoName = "discover" }
            else if digits.hasPrefix("4") && madaPrefix(digits) { logoName = "mada" }
            else { logoName = nil }
        }
        if let name = logoName, let img = UIImage(named: name) {
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
    private let labelText: String

    init(label: String, keyboardType: UIKeyboardType = .default) {
        self.labelText = label
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
        textField.placeholder           = label // Show as placeholder initially
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
        textField.placeholder = nil
        updateLabelVisibility()
        UIView.animate(withDuration: 0.2) {
            self.borderView.layer.borderColor = PayOrcUIConstants.accentColor.cgColor
            self.borderView.layer.borderWidth = 2
        }
    }

    @objc private func editingDidEnd() {
        if textField.text?.isEmpty ?? true {
            textField.placeholder = labelText
        }
        updateLabelVisibility()
        UIView.animate(withDuration: 0.2) {
            self.borderView.layer.borderColor = PayOrcUIConstants.textFieldBorderColor.cgColor
            self.borderView.layer.borderWidth = 1
        }
    }

    private func updateLabelVisibility() {
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
