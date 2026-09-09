import UIKit

// MARK: - PaymentConfirmedViewController
//
// Bottom sheet: "Payment Confirmed" success state with checkmark and card summary.
// Mirrors Flutter's `PaymentConfirmedSheet` — shown after a successful card payment,
// auto-dismisses after `duration`, then hands control back to the host via `onDismissed`.
//
// Presented by `CheckoutViewController` from the original SDK presenter, after the
// whole checkout stack (card form / submitting sheet / 3DS webview) has already been
// dismissed in one animation — this sheet appears on its own, over the host's screen.

public final class PaymentConfirmedViewController: UIViewController {

    // MARK: - Dependencies

    private let card: CardData
    private let duration: TimeInterval
    private var onDismissed: (() -> Void)?
    private var hasFinished = false

    // MARK: - UI Elements

    private let contentStack    = UIStackView()
    private let dragHandle      = UIView()

    private let checkCircle     = UIView()
    private let checkIconView   = UIImageView()

    private let titleLabel      = UILabel()
    private let subtitleLabel   = UILabel()

    private let cardChip        = UIView()
    private let brandImageView  = UIImageView()
    private let cardNumberLabel = UILabel()

    private let poweredByView   = PoweredByView()

    // MARK: - Init

    /// - Parameters:
    ///   - card: The card the payment was made with (shown as a masked-PAN chip).
    ///   - duration: How long the sheet stays up before auto-dismissing. Defaults to 3s, matching Flutter.
    ///   - onDismissed: Called once, after the sheet has been dismissed (auto or by user swipe).
    public init(
        card: CardData,
        duration: TimeInterval = 3.0,
        onDismissed: (() -> Void)? = nil
    ) {
        self.card = card
        self.duration = duration
        self.onDismissed = onDismissed
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        presentationController?.delegate = self
        setupLayout()
        configureSheetDetent()
        scheduleAutoDismiss()
    }

    // MARK: - Layout

    private func setupLayout() {
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .center
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            contentStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        // 1. Drag Handle
        dragHandle.backgroundColor = UIColor.systemGray4
        dragHandle.layer.cornerRadius = 2
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(dragHandle)
        NSLayoutConstraint.activate([
            dragHandle.widthAnchor.constraint(equalToConstant: 40),
            dragHandle.heightAnchor.constraint(equalToConstant: 4)
        ])
        contentStack.setCustomSpacing(20, after: dragHandle)

        // 2. Checkmark circle
        checkCircle.backgroundColor = UIColor(red: 0.910, green: 0.961, blue: 0.914, alpha: 1)
        checkCircle.layer.cornerRadius = 36
        checkCircle.translatesAutoresizingMaskIntoConstraints = false

        let checkCfg = UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold)
        checkIconView.image = UIImage(systemName: "checkmark", withConfiguration: checkCfg)
        checkIconView.tintColor = UIColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1)
        checkIconView.translatesAutoresizingMaskIntoConstraints = false

        checkCircle.addSubview(checkIconView)
        contentStack.addArrangedSubview(checkCircle)
        NSLayoutConstraint.activate([
            checkCircle.widthAnchor.constraint(equalToConstant: 72),
            checkCircle.heightAnchor.constraint(equalToConstant: 72),
            checkIconView.centerXAnchor.constraint(equalTo: checkCircle.centerXAnchor),
            checkIconView.centerYAnchor.constraint(equalTo: checkCircle.centerYAnchor)
        ])

        // 3. Title & Subtitle
        titleLabel.text = "Payment Confirmed"
        titleLabel.font = .boldSystemFont(ofSize: 20)
        titleLabel.textColor = PayOrcUIConstants.textPrimaryColor
        titleLabel.textAlignment = .center
        contentStack.addArrangedSubview(titleLabel)

        subtitleLabel.text = "Your order has been submitted successfully"
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = PayOrcUIConstants.textSecondaryColor
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.setCustomSpacing(20, after: subtitleLabel)

        // 4. Card chip
        buildCardChip()
        contentStack.addArrangedSubview(cardChip)
        contentStack.setCustomSpacing(24, after: cardChip)

        // 5. Footer
        contentStack.addArrangedSubview(poweredByView)
    }

    private func buildCardChip() {
        cardChip.backgroundColor = UIColor(red: 0.910, green: 0.961, blue: 0.914, alpha: 1)
        cardChip.layer.cornerRadius = 10
        cardChip.translatesAutoresizingMaskIntoConstraints = false

        let pan = card.cardNumber ?? ""
        let last4 = pan.count >= 4 ? String(pan.suffix(4)) : "••••"
        cardNumberLabel.text = "•••• •••• •••• \(last4)"
        cardNumberLabel.font = .systemFont(ofSize: 13, weight: .medium)
        cardNumberLabel.textColor = PayOrcUIConstants.textPrimaryColor

        brandImageView.contentMode = .scaleAspectFit
        brandImageView.translatesAutoresizingMaskIntoConstraints = false
        if let brand = cardBrandImageName(for: pan), let img = UIImage(payorcNamed: brand) {
            brandImageView.image = img
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            brandImageView.image = UIImage(systemName: "creditcard.fill", withConfiguration: cfg)
            brandImageView.tintColor = PayOrcUIConstants.textSecondaryColor
        }

        let row = UIStackView(arrangedSubviews: [brandImageView, cardNumberLabel])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        cardChip.addSubview(row)
        NSLayoutConstraint.activate([
            brandImageView.widthAnchor.constraint(equalToConstant: 32),
            brandImageView.heightAnchor.constraint(equalToConstant: 20),

            row.topAnchor.constraint(equalTo: cardChip.topAnchor, constant: 10),
            row.leadingAnchor.constraint(equalTo: cardChip.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: cardChip.trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: cardChip.bottomAnchor, constant: -10)
        ])
    }

    private func configureSheetDetent() {
        guard #available(iOS 15.0, *), let sheet = sheetPresentationController else { return }
        sheet.prefersGrabberVisible = false
        sheet.preferredCornerRadius = PayOrcUIConstants.bottomSheetCornerRadius
        if #available(iOS 16.0, *) {
            let detent = UISheetPresentationController.Detent.custom(identifier: .init("payorc.confirmed")) { _ in
                return 340
            }
            sheet.detents = [detent]
        } else {
            sheet.detents = [.medium()]
        }
    }

    // MARK: - Dismissal

    private func scheduleAutoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, !self.hasFinished else { return }
            self.hasFinished = true
            let callback = self.onDismissed
            self.onDismissed = nil
            self.dismiss(animated: true) {
                callback?()
            }
        }
    }

    private func cardBrandImageName(for number: String) -> String? {
        let digits = number.replacingOccurrences(of: " ", with: "")
        let prefix = String(digits.prefix(2))
        switch prefix {
        case "4": return "visa"
        case "51", "52", "53", "54", "55": return "mastercard"
        case "34", "37": return "amex"
        default: return nil
        }
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension PaymentConfirmedViewController: UIAdaptivePresentationControllerDelegate {
    /// Fires `onDismissed` when the user swipes the sheet away before the auto-dismiss timer fires.
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard !hasFinished else { return }
        hasFinished = true
        let callback = onDismissed
        onDismissed = nil
        callback?()
    }
}
