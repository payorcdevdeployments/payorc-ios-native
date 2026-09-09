import UIKit

// MARK: - PaymentFailedViewController
//
// Bottom sheet shown when a card payment fails, for checkouts started from the
// payment-options bottom sheet (`PayOrc.presentPaymentOptions`). Mirrors Flutter's
// `PaymentFailedScene` (`PaymentFailedSheetAction.show`):
//   - Failure icon + "Payment Failed" + error card (brand, masked PAN, "Declined")
//   - Saved cards section, fetched from `sdk/customer/cards` on open
//   - "OR TRY ANOTHER METHOD" retry rows (Apple Pay / Tabby / Add New Card)
//   - Retry Payment button (resubmits the same card that just failed)
//
// Not used by the embedded `PayOrcEmbeddedPayWithCardButton` flow — that flow keeps
// the existing inline-error-on-the-card-form behavior.
//
// Simplification vs Flutter: tapping a saved card always switches this sheet into a
// CVV-entry step before resubmitting (Flutter's `askForCVV` mode), rather than
// attempting a token-only submission first and reacting to a `CVV_REQUIRED` response.
// This is simpler and never risks sending an empty CVV for a fresh charge.
public final class PaymentFailedViewController: UIViewController {

    // MARK: - Callbacks

    /// "Retry Payment" with no saved card selected — resubmits `failedCard` unchanged.
    public var onRetryOriginalCard: (() -> Void)?
    /// A saved card was picked and its CVV entered — submit with `(card, cvv)`.
    public var onRetrySavedCard: ((CardData, String) -> Void)?
    public var onAddNewCard: (() -> Void)?
    public var onApplePay: (() -> Void)?
    public var onTabby: (() -> Void)?
    public var onCancel: (() -> Void)?

    // MARK: - Dependencies

    private let failedCard: CardData
    private let errorCode: String
    private let errorMessage: String
    private let paymentRequest: PaymentRequest
    /// PayOrc-assigned order id (`p_order_id`) from the failure response, when
    /// available. Preferred over `paymentRequest.orderDetails.first?.mOrderId` for
    /// the saved-cards lookup, since the merchant's own `m_order_id` is often blank.
    private let resolvedOrderId: String?
    private let paymentRepository: PaymentRepository
    private let applePayEnabled: Bool
    private let tabbyEnabled: Bool

    // MARK: - State

    private var savedCards: [CardData] = []
    private var isLoadingSavedCards = true
    private var savedCardsError: String?
    private var selectedSavedCard: CardData?

    private static let redIconBg    = UIColor(red: 1.00, green: 0.92, blue: 0.93, alpha: 1)
    private static let pinkBox      = UIColor(red: 1.00, green: 0.96, blue: 0.96, alpha: 1)
    private static let declinedRed  = UIColor(red: 0.776, green: 0.157, blue: 0.157, alpha: 1)

    // MARK: - UI

    private let scrollView   = UIScrollView()
    private let contentStack = UIStackView()

    private let normalModeStack = UIStackView()
    private let savedCardsSection = UIStackView()
    private let savedCardsListStack = UIStackView()
    private let retryRowsStack = UIStackView()

    private let cvvModeStack = UIStackView()
    private let cvvField = UITextField()
    private var cvvCardLabel = UILabel()
    private var cvvHolderLabel = UILabel()
    private var cvvBrandImageView = UIImageView()

    private let primaryButton = PayOrcButton()
    private let cancelButton  = UIButton(type: .system)

    // MARK: - Init

    public init(
        failedCard: CardData,
        errorCode: String,
        errorMessage: String,
        paymentRequest: PaymentRequest,
        resolvedOrderId: String? = nil,
        paymentRepository: PaymentRepository,
        applePayEnabled: Bool,
        tabbyEnabled: Bool
    ) {
        self.failedCard = failedCard
        self.errorCode = errorCode.isEmpty ? "TXN_DECLINED" : errorCode
        self.errorMessage = errorMessage
        self.paymentRequest = paymentRequest
        self.resolvedOrderId = resolvedOrderId
        self.paymentRepository = paymentRepository
        self.applePayEnabled = applePayEnabled
        self.tabbyEnabled = tabbyEnabled
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        print("[PayOrc] PaymentFailedViewController.viewDidLoad — errorCode=\(errorCode)")
        #endif
        view.backgroundColor = .systemBackground
        setupLayout()
        configureSheet()
        loadSavedCards()
    }

    private func configureSheet() {
        guard #available(iOS 15.0, *), let sheet = sheetPresentationController else { return }
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = PayOrcUIConstants.bottomSheetCornerRadius
        sheet.detents = [.large()]
    }

    // MARK: - Layout

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 0
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

        buildNormalMode()
        buildCvvMode()
        contentStack.addArrangedSubview(normalModeStack)
        contentStack.addArrangedSubview(cvvModeStack)
        cvvModeStack.isHidden = true

        contentStack.setCustomSpacing(20, after: cvvModeStack.isHidden ? normalModeStack : cvvModeStack)

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.heightAnchor.constraint(equalToConstant: PayOrcUIConstants.buttonHeight).isActive = true
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(primaryButton)
        contentStack.setCustomSpacing(10, after: primaryButton)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cancelButton.backgroundColor = UIColor.systemGray6
        cancelButton.setTitleColor(PayOrcUIConstants.textSecondaryColor, for: .normal)
        cancelButton.layer.cornerRadius = PayOrcUIConstants.buttonCornerRadius
        cancelButton.layer.masksToBounds = true
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.heightAnchor.constraint(equalToConstant: PayOrcUIConstants.buttonHeight).isActive = true
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(cancelButton)
        contentStack.setCustomSpacing(20, after: cancelButton)

        contentStack.addArrangedSubview(PoweredByView())

        updatePrimaryButton()
    }

    private func buildNormalMode() {
        normalModeStack.axis = .vertical
        normalModeStack.alignment = .fill
        normalModeStack.spacing = 0

        normalModeStack.addArrangedSubview(buildFailureIcon())
        normalModeStack.setCustomSpacing(16, after: normalModeStack.arrangedSubviews.last!)

        let title = UILabel()
        title.text = "Payment Failed"
        title.font = .boldSystemFont(ofSize: 20)
        title.textColor = PayOrcUIConstants.textPrimaryColor
        title.textAlignment = .center
        normalModeStack.addArrangedSubview(title)
        normalModeStack.setCustomSpacing(8, after: title)

        let subtitle = UILabel()
        subtitle.text = "Your transaction could not be completed. Please try again or use a different payment method."
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = PayOrcUIConstants.textSecondaryColor
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        normalModeStack.addArrangedSubview(subtitle)
        normalModeStack.setCustomSpacing(16, after: subtitle)

        normalModeStack.addArrangedSubview(buildErrorCardBox())
        normalModeStack.setCustomSpacing(16, after: normalModeStack.arrangedSubviews.last!)

        buildSavedCardsSection()
        normalModeStack.addArrangedSubview(savedCardsSection)
        savedCardsSection.isHidden = true // shown once loaded, if non-empty / erroring
        normalModeStack.setCustomSpacing(16, after: savedCardsSection)

        let orLabel = UILabel()
        orLabel.text = "OR TRY ANOTHER METHOD"
        orLabel.font = .systemFont(ofSize: 13, weight: .medium)
        orLabel.textColor = PayOrcUIConstants.textSecondaryColor
        orLabel.textAlignment = .center
        normalModeStack.addArrangedSubview(orLabel)
        normalModeStack.setCustomSpacing(12, after: orLabel)

        retryRowsStack.axis = .vertical
        retryRowsStack.spacing = PayOrcUIConstants.bottomSheetItemSpacing
        buildRetryRows()
        normalModeStack.addArrangedSubview(retryRowsStack)
    }

    private func buildFailureIcon() -> UIView {
        let circle = UIView()
        circle.backgroundColor = Self.redIconBg
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.widthAnchor.constraint(equalToConstant: 72).isActive = true
        circle.heightAnchor.constraint(equalToConstant: 72).isActive = true
        circle.layer.cornerRadius = 36

        let ring = UIView()
        ring.layer.borderWidth = 3
        ring.layer.borderColor = UIColor.systemRed.cgColor
        ring.layer.cornerRadius = 15
        ring.translatesAutoresizingMaskIntoConstraints = false

        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let x = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: cfg))
        x.tintColor = .systemRed
        x.translatesAutoresizingMaskIntoConstraints = false

        ring.addSubview(x)
        circle.addSubview(ring)
        NSLayoutConstraint.activate([
            ring.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            ring.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            ring.widthAnchor.constraint(equalToConstant: 30),
            ring.heightAnchor.constraint(equalToConstant: 30),
            x.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            x.centerYAnchor.constraint(equalTo: ring.centerYAnchor)
        ])

        let container = UIView()
        container.addSubview(circle)
        NSLayoutConstraint.activate([
            circle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            circle.topAnchor.constraint(equalTo: container.topAnchor),
            circle.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func buildErrorCardBox() -> UIView {
        let box = UIView()
        box.backgroundColor = Self.pinkBox
        box.layer.cornerRadius = 12
        box.layer.borderWidth = 1
        box.layer.borderColor = Self.declinedRed.withAlphaComponent(0.2).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let chip = UIView()
        chip.backgroundColor = .white
        chip.layer.cornerRadius = 8
        chip.translatesAutoresizingMaskIntoConstraints = false
        let brandIV = UIImageView()
        brandIV.contentMode = .scaleAspectFit
        brandIV.translatesAutoresizingMaskIntoConstraints = false
        if let name = Self.brandImageName(for: failedCard), let img = UIImage(payorcNamed: name) {
            brandIV.image = img
        } else {
            brandIV.image = UIImage(systemName: "creditcard.fill")
            brandIV.tintColor = PayOrcUIConstants.textSecondaryColor
        }
        chip.addSubview(brandIV)
        NSLayoutConstraint.activate([
            chip.widthAnchor.constraint(equalToConstant: 44),
            chip.heightAnchor.constraint(equalToConstant: 44),
            brandIV.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
            brandIV.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            brandIV.widthAnchor.constraint(equalToConstant: 36),
            brandIV.heightAnchor.constraint(equalToConstant: 24)
        ])

        let panLabel = UILabel()
        panLabel.text = "•••• •••• •••• \(failedCard.lastFourDigits)"
        panLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        panLabel.textColor = PayOrcUIConstants.textPrimaryColor

        let holderLabel = UILabel()
        let holder = failedCard.cardholderName.trimmingCharacters(in: .whitespaces)
        holderLabel.text = holder
        holderLabel.font = .systemFont(ofSize: 13)
        holderLabel.textColor = PayOrcUIConstants.textSecondaryColor
        holderLabel.isHidden = holder.isEmpty

        let textStack = UIStackView(arrangedSubviews: [panLabel, holderLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let declinedPill = buildDeclinedPill()

        let topRow = UIStackView(arrangedSubviews: [chip, textStack, declinedPill])
        topRow.axis = .horizontal
        topRow.spacing = 12
        topRow.alignment = .center
        topRow.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let messageBox = UIView()
        messageBox.backgroundColor = .white
        messageBox.layer.cornerRadius = 12
        messageBox.translatesAutoresizingMaskIntoConstraints = false

        let infoIcon = UIImageView(image: UIImage(systemName: "info.circle"))
        infoIcon.tintColor = UIColor.systemOrange
        infoIcon.translatesAutoresizingMaskIntoConstraints = false

        let messageLabel = UILabel()
        messageLabel.text = errorMessage
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = PayOrcUIConstants.textPrimaryColor
        messageLabel.numberOfLines = 0

        let messageRow = UIStackView(arrangedSubviews: [infoIcon, messageLabel])
        messageRow.axis = .horizontal
        messageRow.spacing = 8
        messageRow.alignment = .center
        messageRow.translatesAutoresizingMaskIntoConstraints = false
        messageBox.addSubview(messageRow)
        NSLayoutConstraint.activate([
            messageRow.topAnchor.constraint(equalTo: messageBox.topAnchor, constant: 12),
            messageRow.leadingAnchor.constraint(equalTo: messageBox.leadingAnchor, constant: 12),
            messageRow.trailingAnchor.constraint(equalTo: messageBox.trailingAnchor, constant: -12),
            messageRow.bottomAnchor.constraint(equalTo: messageBox.bottomAnchor, constant: -12)
        ])

        let outerStack = UIStackView(arrangedSubviews: [topRow, messageBox])
        outerStack.axis = .vertical
        outerStack.spacing = 12
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: box.topAnchor, constant: 16),
            outerStack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            outerStack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            outerStack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -16)
        ])

        return box
    }

    private func buildDeclinedPill() -> UIView {
        let pill = UIView()
        pill.backgroundColor = Self.declinedRed.withAlphaComponent(0.15)
        pill.layer.cornerRadius = 12
        pill.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Declined"
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Self.declinedRed

        let cfg = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        let icon = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: cfg))
        icon.tintColor = Self.declinedRed

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.spacing = 3
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            row.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6)
        ])
        pill.setContentHuggingPriority(.required, for: .horizontal)
        pill.setContentCompressionResistancePriority(.required, for: .horizontal)
        return pill
    }

    // MARK: - Saved Cards

    private func buildSavedCardsSection() {
        savedCardsSection.axis = .vertical
        savedCardsSection.spacing = PayOrcUIConstants.bottomSheetItemSpacing

        let label = UILabel()
        label.text = "YOUR SAVED CARDS"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = PayOrcUIConstants.textSecondaryColor
        label.textAlignment = .center
        savedCardsSection.addArrangedSubview(label)

        savedCardsListStack.axis = .vertical
        savedCardsListStack.spacing = 8
        savedCardsSection.addArrangedSubview(savedCardsListStack)
    }

    private func loadSavedCards() {
        // Shows the loading spinner immediately — without this, refreshSavedCardsUI()
        // wasn't called until the fetch had already resolved, so the section stayed
        // blank (no spinner ever visible) during the request.
        refreshSavedCardsUI()

        let mCustomerId = paymentRequest.customerDetails.mCustomerId.trimmingCharacters(in: .whitespaces)
        // Prefer the PayOrc-assigned order id from the failure response — the
        // merchant's own m_order_id (in the original request) is frequently left
        // blank, since PayOrc assigns its own p_order_id regardless.
        let resolvedTrimmed = resolvedOrderId?.trimmingCharacters(in: .whitespaces) ?? ""
        let requestOrderId = paymentRequest.orderDetails.first?.mOrderId.trimmingCharacters(in: .whitespaces) ?? ""
        let orderId = !resolvedTrimmed.isEmpty ? resolvedTrimmed : requestOrderId
        guard !mCustomerId.isEmpty, !orderId.isEmpty else {
            #if DEBUG
            print("[PayOrc] loadSavedCards skipped — mCustomerId or orderId is empty (mCustomerId=\"\(mCustomerId)\" orderId=\"\(orderId)\").")
            #endif
            isLoadingSavedCards = false
            savedCardsError = nil
            refreshSavedCardsUI()
            return
        }

        #if DEBUG
        print("[PayOrc] loadSavedCards → fetching sdk/customer/cards for mCustomerId=\(mCustomerId) orderId=\(orderId)")
        #endif
        Task {
            do {
                let cards = try await paymentRepository.listCustomerCards(mCustomerId: mCustomerId, orderId: orderId)
                #if DEBUG
                print("[PayOrc] loadSavedCards succeeded — \(cards.count) saved card(s).")
                #endif
                await MainActor.run {
                    self.savedCards = cards
                    self.isLoadingSavedCards = false
                    self.savedCardsError = nil
                    self.refreshSavedCardsUI()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSavedCards = false
                    self.savedCardsError = (error as? PayOrcError)?.localizedDescription ?? "Unable to load saved cards"
                    self.refreshSavedCardsUI()
                }
            }
        }
    }

    private func refreshSavedCardsUI() {
        savedCardsListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if isLoadingSavedCards {
            savedCardsSection.isHidden = false
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            let wrap = UIView()
            wrap.addSubview(spinner)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
                spinner.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 8),
                spinner.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -8)
            ])
            savedCardsListStack.addArrangedSubview(wrap)
            return
        }

        if let err = savedCardsError, !err.isEmpty {
            savedCardsSection.isHidden = false
            let label = UILabel()
            label.text = err
            label.font = .systemFont(ofSize: 13)
            label.textColor = PayOrcUIConstants.textSecondaryColor
            label.textAlignment = .center
            label.numberOfLines = 0
            savedCardsListStack.addArrangedSubview(label)
            return
        }

        guard !savedCards.isEmpty else {
            savedCardsSection.isHidden = true
            return
        }

        savedCardsSection.isHidden = false
        for card in savedCards {
            savedCardsListStack.addArrangedSubview(buildSavedCardRow(card))
        }
    }

    private func buildSavedCardRow(_ card: CardData) -> UIView {
        let row = UIView()
        row.backgroundColor = UIColor.systemGray6
        row.layer.cornerRadius = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = true
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(savedCardTapped(_:))))

        let radio = UIImageView(image: UIImage(systemName: "circle"))
        radio.tintColor = PayOrcUIConstants.textSecondaryColor
        radio.translatesAutoresizingMaskIntoConstraints = false
        radio.widthAnchor.constraint(equalToConstant: 22).isActive = true
        radio.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let panLabel = UILabel()
        panLabel.text = "**** \(card.lastFourDigits)"
        panLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        panLabel.textColor = PayOrcUIConstants.textPrimaryColor

        let detailLabel = UILabel()
        detailLabel.text = "\(card.cardholderName) · \(card.expiryMonth)/\(card.expiryYear)"
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = PayOrcUIConstants.textSecondaryColor
        detailLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [panLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let brandIV = UIImageView()
        brandIV.contentMode = .scaleAspectFit
        brandIV.translatesAutoresizingMaskIntoConstraints = false
        brandIV.widthAnchor.constraint(equalToConstant: 30).isActive = true
        brandIV.heightAnchor.constraint(equalToConstant: 20).isActive = true
        if let name = Self.brandImageName(for: card), let img = UIImage(payorcNamed: name) {
            brandIV.image = img
        } else {
            brandIV.image = UIImage(systemName: "creditcard")
            brandIV.tintColor = PayOrcUIConstants.textSecondaryColor
        }

        let hStack = UIStackView(arrangedSubviews: [radio, textStack, brandIV])
        hStack.axis = .horizontal
        hStack.spacing = 12
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.isUserInteractionEnabled = false
        row.addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            hStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            hStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            hStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12)
        ])

        row.tag = savedCards.firstIndex(where: { $0.paymentToken == card.paymentToken && $0.cardNumber == card.cardNumber }) ?? -1
        return row
    }

    @objc private func savedCardTapped(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view, row.tag >= 0, row.tag < savedCards.count else { return }
        enterCvvMode(for: savedCards[row.tag])
    }

    // MARK: - Retry Rows (Apple Pay / Tabby / Add New Card)

    private func buildRetryRows() {
        retryRowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if applePayEnabled {
            retryRowsStack.addArrangedSubview(makeRetryTile(
                iconName: "apple.logo", imageName: nil, title: "Apple Pay",
                action: #selector(applePayTapped)
            ))
        }
        if tabbyEnabled {
            retryRowsStack.addArrangedSubview(makeRetryTile(
                iconName: nil, imageName: "tabby", title: "Tabby",
                action: #selector(tabbyTapped)
            ))
        }
        retryRowsStack.addArrangedSubview(makeRetryTile(
            iconName: "plus", imageName: nil, title: "Add New Card",
            backgroundColor: .white, action: #selector(addNewCardTapped)
        ))
    }

    private func makeRetryTile(
        iconName: String?,
        imageName: String?,
        title: String,
        backgroundColor: UIColor = .systemGray6,
        action: Selector
    ) -> PaymentMethodTileView {
        let tile = PaymentMethodTileView()
        tile.configure(with: .init(
            iconName: iconName,
            imageName: imageName,
            title: title,
            isSelected: false,
            backgroundColor: backgroundColor
        ))
        tile.onTap = { [weak self] in self?.perform(action) }
        return tile
    }

    @objc private func applePayTapped() {
        guard let onApplePay else { return }
        dismiss(animated: true) { onApplePay() }
    }

    @objc private func tabbyTapped() {
        guard let onTabby else { return }
        dismiss(animated: true) { onTabby() }
    }

    @objc private func addNewCardTapped() {
        guard let onAddNewCard else { return }
        dismiss(animated: true) { onAddNewCard() }
    }

    // MARK: - CVV Entry Mode

    private func buildCvvMode() {
        cvvModeStack.axis = .vertical
        cvvModeStack.spacing = 0

        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1.5
        card.layer.borderColor = UIColor.label.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        cvvBrandImageView.contentMode = .scaleAspectFit
        cvvBrandImageView.translatesAutoresizingMaskIntoConstraints = false

        let iconWrap = UIView()
        iconWrap.backgroundColor = UIColor.systemGray6
        iconWrap.layer.cornerRadius = 24
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(cvvBrandImageView)
        NSLayoutConstraint.activate([
            iconWrap.widthAnchor.constraint(equalToConstant: 48),
            iconWrap.heightAnchor.constraint(equalToConstant: 48),
            cvvBrandImageView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            cvvBrandImageView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            cvvBrandImageView.widthAnchor.constraint(equalToConstant: 36),
            cvvBrandImageView.heightAnchor.constraint(equalToConstant: 24)
        ])

        cvvCardLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        cvvCardLabel.textColor = PayOrcUIConstants.textPrimaryColor
        cvvHolderLabel.font = .systemFont(ofSize: 13)
        cvvHolderLabel.textColor = PayOrcUIConstants.textSecondaryColor
        let textStack = UIStackView(arrangedSubviews: [cvvCardLabel, cvvHolderLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let topRow = UIStackView(arrangedSubviews: [iconWrap, textStack])
        topRow.axis = .horizontal
        topRow.spacing = 12
        topRow.alignment = .center
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let cvvLabel = UILabel()
        cvvLabel.text = "Enter CVV"
        cvvLabel.font = .systemFont(ofSize: 12, weight: .medium)
        cvvLabel.textColor = PayOrcUIConstants.textSecondaryColor

        cvvField.borderStyle = .roundedRect
        cvvField.keyboardType = .numberPad
        cvvField.isSecureTextEntry = true
        cvvField.placeholder = "..."
        cvvField.translatesAutoresizingMaskIntoConstraints = false
        cvvField.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let secureChip = UIView()
        secureChip.backgroundColor = UIColor.systemGray6
        secureChip.layer.cornerRadius = 8
        secureChip.translatesAutoresizingMaskIntoConstraints = false
        let lockCfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let lockIcon = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: lockCfg))
        lockIcon.tintColor = PayOrcUIConstants.textSecondaryColor
        let secureLabel = UILabel()
        secureLabel.text = "Secure"
        secureLabel.font = .systemFont(ofSize: 12)
        secureLabel.textColor = PayOrcUIConstants.textSecondaryColor
        let secureRow = UIStackView(arrangedSubviews: [lockIcon, secureLabel])
        secureRow.axis = .horizontal
        secureRow.spacing = 6
        secureRow.alignment = .center
        secureRow.translatesAutoresizingMaskIntoConstraints = false
        secureChip.addSubview(secureRow)
        NSLayoutConstraint.activate([
            secureRow.topAnchor.constraint(equalTo: secureChip.topAnchor, constant: 10),
            secureRow.leadingAnchor.constraint(equalTo: secureChip.leadingAnchor, constant: 12),
            secureRow.trailingAnchor.constraint(equalTo: secureChip.trailingAnchor, constant: -12),
            secureRow.bottomAnchor.constraint(equalTo: secureChip.bottomAnchor, constant: -10)
        ])
        secureChip.setContentHuggingPriority(.required, for: .horizontal)

        let cvvFieldStack = UIStackView(arrangedSubviews: [cvvLabel, cvvField])
        cvvFieldStack.axis = .vertical
        cvvFieldStack.spacing = 4

        let bottomRow = UIStackView(arrangedSubviews: [cvvFieldStack, secureChip])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 12
        bottomRow.alignment = .bottom
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let backButton = UIButton(type: .system)
        backButton.setTitle("← Choose a different card", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        backButton.setTitleColor(PayOrcUIConstants.textSecondaryColor, for: .normal)
        backButton.contentHorizontalAlignment = .leading
        backButton.addTarget(self, action: #selector(exitCvvModeTapped), for: .touchUpInside)

        let cardStack = UIStackView(arrangedSubviews: [topRow, bottomRow])
        cardStack.axis = .vertical
        cardStack.spacing = 16
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        cvvModeStack.addArrangedSubview(backButton)
        cvvModeStack.setCustomSpacing(10, after: backButton)
        cvvModeStack.addArrangedSubview(card)
    }

    private func enterCvvMode(for card: CardData) {
        view.endEditing(true)
        selectedSavedCard = card
        cvvField.text = ""
        cvvCardLabel.text = "•••• •••• •••• \(card.lastFourDigits)"
        cvvHolderLabel.text = card.cardholderName
        if let name = Self.brandImageName(for: card), let img = UIImage(payorcNamed: name) {
            cvvBrandImageView.image = img
        } else {
            cvvBrandImageView.image = UIImage(systemName: "creditcard.fill")
            cvvBrandImageView.tintColor = PayOrcUIConstants.textSecondaryColor
        }
        normalModeStack.isHidden = true
        cvvModeStack.isHidden = false
        updatePrimaryButton()
        cvvField.becomeFirstResponder()
    }

    @objc private func exitCvvModeTapped() {
        view.endEditing(true)
        selectedSavedCard = nil
        cvvModeStack.isHidden = true
        normalModeStack.isHidden = false
        updatePrimaryButton()
    }

    // MARK: - Primary Button

    private func updatePrimaryButton() {
        primaryButton.setTitle(selectedSavedCard != nil ? "Pay Now" : "Retry Payment", for: .normal)
        primaryButton.applyStyle()
    }

    @objc private func primaryTapped() {
        if let card = selectedSavedCard {
            let digits = cvvField.text?.filter(\.isNumber) ?? ""
            let expected = (card.cardNetwork ?? "").lowercased().contains("amex") ? 4 : 3
            guard digits.count == expected else {
                shake(cvvField)
                return
            }
            guard let onRetrySavedCard else { return }
            dismiss(animated: true) { onRetrySavedCard(card, digits) }
        } else {
            guard let onRetryOriginalCard else { return }
            dismiss(animated: true) { onRetryOriginalCard() }
        }
    }

    @objc private func cancelTapped() {
        guard let onCancel else { return }
        dismiss(animated: true) { onCancel() }
    }

    private func shake(_ view: UIView) {
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [-8, 8, -5, 5, -3, 3, 0]
        a.duration = 0.35
        view.layer.add(a, forKey: nil)
    }

    // MARK: - Brand Resolution

    private static func brandImageName(for card: CardData) -> String? {
        let network = (card.cardNetwork ?? "").lowercased()
        if !network.isEmpty {
            if network.contains("visa") { return "visa" }
            if network.contains("master") { return "mastercard" }
            if network.contains("amex") || network.contains("american") { return "amex" }
            if network.contains("jcb") { return "jcb" }
            if network.contains("mada") { return "mada" }
            if network.contains("maestro") { return "maestro" }
            if network.contains("discover") { return "discover" }
            if network.contains("diners") { return "diners" }
        }
        let digits = (card.cardNumber ?? "").replacingOccurrences(of: " ", with: "")
        switch String(digits.prefix(2)) {
        case "4": return "visa"
        case "51", "52", "53", "54", "55": return "mastercard"
        case "34", "37": return "amex"
        default: return nil
        }
    }
}
