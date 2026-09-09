import UIKit

// MARK: - SubmittingOrderViewController
//
// Bottom sheet shown while card payment is being submitted to PayOrc.
// Mirrors Flutter's `SubmittingOrderFlowSheet` (the sheet actually wired into
// the submit flow via `SubmittingOrderFlowBloc`):
//   - Circular indeterminate ring (dark rotating arc on a light track) with
//     card brand logo in center
//   - "Submitting your order" title and disclaimer subtitle
//   - Indeterminate linear progress bar with "Processing payment..."
//   - Selected card summary box (masked PAN, cardholder name, lock icon + "Secure")
//   - Amber warning banner ("Do not close or refresh this page...")
//   - "Powered by PayOrc" footer
//
// All text on this sheet (title aside) shares the same resolved text-primary
// color — Flutter's `AppText` defaults every unstyled label to
// `textPrimaryOrDefault`, so the apparent "secondary" look of the subtitle /
// card detail lines comes only from smaller size + regular weight, not a
// different color.

public final class SubmittingOrderViewController: UIViewController {

    // MARK: - Dependencies

    private let viewModel: CheckoutViewModel
    private let card: CardData
    private var onSuccess: ((PayOrcSDKResult) -> Void)?
    /// Second parameter is the PayOrc-assigned order id (`p_order_id`), when the
    /// failure response included one — used to look up saved cards for retry.
    private var onFailure: ((PayOrcError, String?) -> Void)?
    private var onCancel:  (() -> Void)?

    /// Fixed accent used only for the "Secure" lock icon — mirrors Flutter's
    /// hardcoded `AppColors.blue`, which is not host-customizable.
    private static let secureAccentColor = UIColor(red: 0/255, green: 132/255, blue: 208/255, alpha: 1)

    /// Fixed light background for the card summary box — mirrors Flutter's
    /// hardcoded `AppColors.lightGrey`, which is not host-customizable.
    private static let cardSummaryBackgroundColor = UIColor(red: 245/255, green: 247/255, blue: 249/255, alpha: 1)

    // MARK: - UI Elements

    private let contentStack      = UIStackView()
    private let dragHandle        = UIView()

    // Spinner
    private let spinnerContainer  = UIView()
    private let circularProgress  = CircularIndeterminateProgressView()
    private let brandIconView     = UIImageView()

    // Text
    private let titleLabel        = UILabel()
    private let subtitleLabel     = UILabel()

    // Progress Bar
    private let progressRow       = UIStackView()
    private let progressLabel     = UILabel()
    private let progressBar       = IndeterminateProgressBarView()

    // Card Summary
    private let cardSummaryBox    = UIView()
    private let brandBadgeView    = UIImageView()
    private let cardNumberLabel   = UILabel()
    private let cardDetailLabel   = UILabel()
    private let secureLabel       = UILabel()
    private let secureIconView    = UIImageView()

    // Warning Banner
    private let warningBox        = UIView()
    private let warningIconView   = UIImageView()
    private let warningLabel      = UILabel()

    // Footer
    private let poweredByView     = PoweredByView()

    // State
    private var isSubmitting = false

    /// When true, submits via ``CheckoutViewModel/submitSavedCard(card:onSuccess:onFailure:)``
    /// (CVV-only validation, for a saved-card/token retry) instead of the default
    /// ``CheckoutViewModel/submit(card:onSuccess:onFailure:)`` (full PAN/expiry validation).
    private let useTokenSubmission: Bool

    // MARK: - Init

    public init(
        viewModel: CheckoutViewModel,
        card: CardData,
        useTokenSubmission: Bool = false,
        onSuccess: @escaping (PayOrcSDKResult) -> Void,
        onFailure: @escaping (PayOrcError, String?) -> Void,
        onCancel:  (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.card      = card
        self.useTokenSubmission = useTokenSubmission
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        self.onCancel  = onCancel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        configureSheetDetent()
        startSubmission()
    }

    // MARK: - Layout

    private func setupLayout() {
        view.backgroundColor = .systemBackground

        // Content Stack
        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        let padding: CGFloat = 20
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        // 1. Drag Handle
        dragHandle.backgroundColor = PayOrcUIConstants.borderColor
        dragHandle.layer.cornerRadius = 2
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        let handleContainer = UIView()
        handleContainer.addSubview(dragHandle)
        NSLayoutConstraint.activate([
            dragHandle.centerXAnchor.constraint(equalTo: handleContainer.centerXAnchor),
            dragHandle.topAnchor.constraint(equalTo: handleContainer.topAnchor),
            dragHandle.bottomAnchor.constraint(equalTo: handleContainer.bottomAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 40),
            dragHandle.heightAnchor.constraint(equalToConstant: 4)
        ])
        contentStack.addArrangedSubview(handleContainer)

        // 2. Circular Spinner Container (88x88): light track ring + dark
        // rotating arc, matching Flutter's indeterminate CircularProgressIndicator.
        spinnerContainer.translatesAutoresizingMaskIntoConstraints = false
        circularProgress.translatesAutoresizingMaskIntoConstraints = false
        circularProgress.trackColor = PayOrcUIConstants.borderColor
        circularProgress.progressColor = PayOrcUIConstants.textPrimaryColor
        circularProgress.lineWidth = 4

        // Center card logo inside spinner
        brandIconView.contentMode = .scaleAspectFit
        brandIconView.translatesAutoresizingMaskIntoConstraints = false
        let panDigits = card.cardNumber ?? ""
        if let brand = getCardBrandImageName(for: panDigits),
           let img = UIImage(payorcNamed: brand) {
            brandIconView.image = img
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            brandIconView.image = UIImage(systemName: "creditcard", withConfiguration: cfg)
            brandIconView.tintColor = PayOrcUIConstants.textSecondaryColor
        }

        let circleBg = UIView()
        circleBg.backgroundColor = .systemBackground
        circleBg.layer.cornerRadius = 32
        circleBg.translatesAutoresizingMaskIntoConstraints = false

        circleBg.addSubview(brandIconView)
        spinnerContainer.addSubview(circularProgress)
        spinnerContainer.addSubview(circleBg)

        NSLayoutConstraint.activate([
            spinnerContainer.heightAnchor.constraint(equalToConstant: 88),

            circularProgress.centerXAnchor.constraint(equalTo: spinnerContainer.centerXAnchor),
            circularProgress.centerYAnchor.constraint(equalTo: spinnerContainer.centerYAnchor),
            circularProgress.widthAnchor.constraint(equalToConstant: 88),
            circularProgress.heightAnchor.constraint(equalToConstant: 88),

            circleBg.centerXAnchor.constraint(equalTo: spinnerContainer.centerXAnchor),
            circleBg.centerYAnchor.constraint(equalTo: spinnerContainer.centerYAnchor),
            circleBg.widthAnchor.constraint(equalToConstant: 64),
            circleBg.heightAnchor.constraint(equalToConstant: 64),

            brandIconView.centerXAnchor.constraint(equalTo: circleBg.centerXAnchor),
            brandIconView.centerYAnchor.constraint(equalTo: circleBg.centerYAnchor),
            brandIconView.widthAnchor.constraint(equalToConstant: 35),
            brandIconView.heightAnchor.constraint(equalToConstant: 35)
        ])
        contentStack.addArrangedSubview(spinnerContainer)

        // 3. Title & Subtitle — both use the resolved primary text color and
        // the host's custom body font family (if any); only the title's bold
        // weight sets it apart visually. Center alignment is forced (matching
        // Flutter's explicit `textAlign: TextAlign.center` on both) rather
        // than deferring to a host global alignment override, which — same as
        // in Flutter — a per-label explicit value always takes priority over.
        titleLabel.attributedText = styledText(
            "Submitting your order",
            font: PayOrcUIConstants.resolvedBodyFont(size: 20, weight: .bold),
            color: PayOrcUIConstants.textPrimaryColor,
            forcedAlignment: .center
        )
        titleLabel.textAlignment = .center

        subtitleLabel.attributedText = styledText(
            "Please don't leave this page before the end of the order submission.",
            font: PayOrcUIConstants.resolvedBodyFont(size: 14),
            color: PayOrcUIConstants.textPrimaryColor,
            forcedAlignment: .center
        )
        subtitleLabel.textAlignment = .center
        // Host `maxLines` override (if set) wins; otherwise this needs to stay
        // unlimited to wrap — unlike `PayOrcUIConstants.textMaxLines`, whose
        // resolved default of 1 would truncate this disclaimer to one line.
        subtitleLabel.numberOfLines = PayOrcUIConstants._hostTextMaxLines ?? 0

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 6
        contentStack.addArrangedSubview(titleStack)

        // 4. Progress Row
        progressLabel.attributedText = styledText(
            "Processing payment...",
            font: PayOrcUIConstants.resolvedBodyFont(size: 13),
            color: PayOrcUIConstants.textPrimaryColor
        )
        progressLabel.setContentHuggingPriority(.required, for: .horizontal)
        progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        progressBar.trackColor = PayOrcUIConstants.borderColor
        progressBar.progressColor = PayOrcUIConstants.textPrimaryColor
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        progressRow.axis = .horizontal
        progressRow.spacing = 12
        progressRow.alignment = .center
        progressRow.addArrangedSubview(progressLabel)
        progressRow.addArrangedSubview(progressBar)
        contentStack.addArrangedSubview(progressRow)

        NSLayoutConstraint.activate([
            progressBar.heightAnchor.constraint(equalToConstant: 6)
        ])

        // 5. Card Summary Box
        buildCardSummaryBox()
        contentStack.addArrangedSubview(cardSummaryBox)

        // 6. Warning Banner
        buildWarningBanner()
        contentStack.addArrangedSubview(warningBox)

        // 7. Footer
        contentStack.addArrangedSubview(poweredByView)
    }

    private func buildCardSummaryBox() {
        cardSummaryBox.backgroundColor = Self.cardSummaryBackgroundColor
        cardSummaryBox.layer.cornerRadius = 12
        cardSummaryBox.layer.borderWidth = 1
        cardSummaryBox.layer.borderColor = PayOrcUIConstants.borderColor.cgColor
        cardSummaryBox.translatesAutoresizingMaskIntoConstraints = false

        let pan = card.cardNumber ?? ""
        let last4 = pan.count >= 4 ? String(pan.suffix(4)) : "••••"
        cardNumberLabel.attributedText = styledText(
            "•••• •••• •••• \(last4)",
            font: PayOrcUIConstants.resolvedBodyFont(size: 13, weight: .semibold),
            color: PayOrcUIConstants.textPrimaryColor
        )

        let holder = card.cardholderName.isEmpty ? "Cardholder" : card.cardholderName
        let expiry = "\(card.expiryMonth)/\(card.expiryYear)"
        cardDetailLabel.attributedText = styledText(
            "\(holder) · \(expiry)",
            font: PayOrcUIConstants.resolvedBodyFont(size: 13),
            color: PayOrcUIConstants.textPrimaryColor
        )

        let textStack = UIStackView(arrangedSubviews: [cardNumberLabel, cardDetailLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        // Lets this column absorb the row's remaining width so the fixed-size
        // chip and secure badge on either side of it never get stretched.
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Lock + "Secure" — only the lock icon carries the fixed accent color;
        // the label uses the same primary text color as everything else.
        let lockCfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        secureIconView.image = UIImage(systemName: "lock.fill", withConfiguration: lockCfg)
        secureIconView.tintColor = Self.secureAccentColor
        secureIconView.contentMode = .scaleAspectFit
        secureIconView.translatesAutoresizingMaskIntoConstraints = false
        secureIconView.setContentHuggingPriority(.required, for: .horizontal)
        secureIconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        secureLabel.attributedText = styledText(
            "Secure",
            font: PayOrcUIConstants.resolvedBodyFont(size: 13),
            color: PayOrcUIConstants.textPrimaryColor
        )
        secureLabel.setContentHuggingPriority(.required, for: .horizontal)

        let secureStack = UIStackView(arrangedSubviews: [secureIconView, secureLabel])
        secureStack.axis = .horizontal
        secureStack.spacing = 4
        secureStack.alignment = .center
        secureStack.setContentHuggingPriority(.required, for: .horizontal)
        secureStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            secureIconView.widthAnchor.constraint(equalToConstant: 14),
            secureIconView.heightAnchor.constraint(equalToConstant: 14)
        ])

        // Brand logo chip — bare image clipped to rounded corners, no filler
        // background box, matching Flutter's `ClipRRect(child: CardBrandImage(...))`.
        let chipView = UIView()
        chipView.layer.cornerRadius = 6
        chipView.clipsToBounds = true
        chipView.translatesAutoresizingMaskIntoConstraints = false

        brandBadgeView.contentMode = .scaleAspectFit
        brandBadgeView.translatesAutoresizingMaskIntoConstraints = false
        chipView.addSubview(brandBadgeView)

        NSLayoutConstraint.activate([
            chipView.widthAnchor.constraint(equalToConstant: 44),
            chipView.heightAnchor.constraint(equalToConstant: 28),
            brandBadgeView.centerXAnchor.constraint(equalTo: chipView.centerXAnchor),
            brandBadgeView.centerYAnchor.constraint(equalTo: chipView.centerYAnchor)
        ])

        if let brandName = getCardBrandImageName(for: pan),
           let img = UIImage(payorcNamed: brandName) {
            brandBadgeView.image = img
            NSLayoutConstraint.activate([
                brandBadgeView.widthAnchor.constraint(equalTo: chipView.widthAnchor),
                brandBadgeView.heightAnchor.constraint(equalTo: chipView.heightAnchor)
            ])
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            brandBadgeView.image = UIImage(systemName: "creditcard", withConfiguration: cfg)
            brandBadgeView.tintColor = PayOrcUIConstants.textSecondaryColor
            NSLayoutConstraint.activate([
                brandBadgeView.widthAnchor.constraint(equalToConstant: 24),
                brandBadgeView.heightAnchor.constraint(equalToConstant: 24)
            ])
        }

        let mainRow = UIStackView(arrangedSubviews: [chipView, textStack, secureStack])
        mainRow.axis = .horizontal
        mainRow.spacing = 12
        mainRow.alignment = .center
        mainRow.translatesAutoresizingMaskIntoConstraints = false

        cardSummaryBox.addSubview(mainRow)
        NSLayoutConstraint.activate([
            mainRow.topAnchor.constraint(equalTo: cardSummaryBox.topAnchor, constant: 12),
            mainRow.leadingAnchor.constraint(equalTo: cardSummaryBox.leadingAnchor, constant: 14),
            mainRow.trailingAnchor.constraint(equalTo: cardSummaryBox.trailingAnchor, constant: -14),
            mainRow.bottomAnchor.constraint(equalTo: cardSummaryBox.bottomAnchor, constant: -12)
        ])
    }

    private func buildWarningBanner() {
        warningBox.backgroundColor = UIColor(red: 1.0, green: 0.97, blue: 0.88, alpha: 1.0)
        warningBox.layer.cornerRadius = 8
        warningBox.translatesAutoresizingMaskIntoConstraints = false

        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        warningIconView.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: cfg)
        warningIconView.tintColor = UIColor.systemOrange
        warningIconView.setContentHuggingPriority(.required, for: .horizontal)

        warningLabel.attributedText = styledText(
            "Do not close or refresh this page during payment processing.",
            font: PayOrcUIConstants.resolvedBodyFont(size: 13),
            color: PayOrcUIConstants.textPrimaryColor
        )
        // Same reasoning as `subtitleLabel` above: only clamp to a host
        // override, otherwise stay unlimited so this wraps.
        warningLabel.numberOfLines = PayOrcUIConstants._hostTextMaxLines ?? 0

        let row = UIStackView(arrangedSubviews: [warningIconView, warningLabel])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        warningBox.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: warningBox.topAnchor, constant: 10),
            row.leadingAnchor.constraint(equalTo: warningBox.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: warningBox.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: warningBox.bottomAnchor, constant: -10)
        ])
    }

    private func configureSheetDetent() {
        guard #available(iOS 15.0, *), let sheet = sheetPresentationController else { return }
        sheet.prefersGrabberVisible = false
        sheet.preferredCornerRadius = 16
        if #available(iOS 16.0, *) {
            let detent = UISheetPresentationController.Detent.custom(identifier: .init("payorc.submitting")) { _ in
                return 480
            }
            sheet.detents = [detent]
        } else {
            sheet.detents = [.medium()]
        }
    }

    // MARK: - Submission Logic

    private func startSubmission() {
        guard !isSubmitting else { return }
        isSubmitting = true

        let onResponse: (PaymentResponse) -> Void = { [weak self] response in
            guard let self = self else { return }

            let statusLower = response.status.lowercased()

            if response.isAwait3DS,
               let redirectUrlStr = response.redirectUrl,
               let url = URL(string: redirectUrlStr) {
                self.openThreeDSWebView(url: url)
            } else if statusLower == "success" || statusLower == "ok" {
                let sdkResult = PayOrcSDKResult(
                    status:        response.status,
                    code:          response.code,
                    message:       response.message,
                    transactionId: response.transactionId
                )
                // No self-dismiss here — the caller (CheckoutViewController.dismissThen,
                // or PayOrc's own direct-submission dismiss) is the single dismiss point
                // so the whole presented stack collapses in one animation.
                self.onSuccess?(sdkResult)
            } else {
                let msg = response.message.isEmpty ? "Transaction failed" : response.message
                let payOrcError = PayOrcError.paymentFailed(code: response.code, message: msg)
                // No self-dismiss — see the 3DS failure branch in openThreeDSWebView
                // for why the caller must own the single dismiss instead. Keeping this
                // consistent (rather than self-dismissing only when there's no 3DS
                // webview open) means the caller's onFailure never has to guess which
                // path it came from.
                self.onFailure?(payOrcError, response.pOrderId ?? response.mOrderId)
            }
        }
        let onSubmitFailure: (PayOrcError) -> Void = { [weak self] error in
            guard let self = self else { return }
            // No response body to pull an order id from (network/parse failure) —
            // the caller falls back to the original PaymentRequest's m_order_id.
            self.onFailure?(error, nil)
        }

        if useTokenSubmission {
            viewModel.submitSavedCard(card: card, onSuccess: onResponse, onFailure: onSubmitFailure)
        } else {
            viewModel.submit(card: card, onSuccess: onResponse, onFailure: onSubmitFailure)
        }
    }

    private func openThreeDSWebView(url: URL) {
        let threeDSVC = ThreeDSWebViewController(url: url)
        threeDSVC.onCompleted = { [weak self] postbackMap in
            guard let self = self else { return }

            let topStatus   = (postbackMap["status"] as? String)?.lowercased() ?? ""
            let topCode     = (postbackMap["code"] as? String)?.uppercased() ?? ""
            let dataMap     = postbackMap["data"] as? [String: Any]
            let orderStatus = ((dataMap?["order_status"] as? String) ?? (dataMap?["status"] as? String) ?? "").uppercased()
            let txId        = (dataMap?["transaction_id"] as? String) ?? (dataMap?["p_order_id"] as? String)

            let isSuccess = orderStatus == "SUCCESS" || orderStatus == "AUTHORIZED" ||
                            orderStatus == "AUTHORISED" || orderStatus == "CAPTURED" ||
                            orderStatus == "COMPLETED" ||
                            (topStatus == "success" && (topCode == "00" || topCode == "CARD_VERIFIED"))

            if isSuccess {
                let sdkResult = PayOrcSDKResult(
                    status:        "success",
                    code:          topCode.isEmpty ? "00" : topCode,
                    message:       (postbackMap["message"] as? String) ?? "Payment completed successfully",
                    transactionId: txId
                )
                // No self-dismiss — CheckoutViewController.dismissThen collapses this
                // sheet, the still-open 3DS webview, and the card form into one animation.
                self.onSuccess?(sdkResult)
            } else if topCode == "USER_CANCELLED" {
                // User closed the 3DS challenge — end the whole checkout flow
                // (mirrors Flutter's `PayorcCancellation` handling) rather than
                // leaving them on an inline-retry error on the card form. Same
                // single-dismiss-point reasoning as the success branch above.
                self.onCancel?()
            } else {
                let msg = (dataMap?["reason"] as? String) ?? (postbackMap["message"] as? String) ?? "Payment failed"
                #if DEBUG
                print("[PayOrc 3DS] Payment failed via 3DS postback: \(msg) — calling onFailure.")
                #endif
                // No self-dismiss — unlike the direct (non-3DS) failure path below,
                // `self` still has the 3DS webview presented on top of it here, so
                // `self.dismiss()` would only remove the webview (revealing this
                // loading sheet, not the card form) instead of dismissing `self`.
                // The caller does the single dismiss appropriate to its own stack.
                let failureOrderId = (dataMap?["p_order_id"] as? String) ?? (dataMap?["m_order_id"] as? String)
                self.onFailure?(
                    .requestFailed(underlying: NSError(domain: "PayOrc", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])),
                    failureOrderId
                )
            }
        }

        let nav = UINavigationController(rootViewController: threeDSVC)
        // .pageSheet (not .fullScreen) — matches the presentation style of this
        // view controller and CheckoutViewController's nav above it. Cascading a
        // `dismiss()` call from the base of a 3-level chain across mismatched
        // presentation styles (sheet, sheet, fullScreen) is unreliable — it can
        // leave the presentation state inconsistent enough that the dismiss
        // completion handler never fires, silently dropping whatever was meant to
        // happen next (e.g. the payment-failed recovery sheet). A full-bleed
        // large-detent page sheet looks the same to the user as full screen.
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *), let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = 0
        }
        present(nav, animated: true)
    }

    /// Builds an attributed string carrying host ``PayOrcTextCustomization``
    /// extras (letter/word spacing, alignment, underline/strikethrough,
    /// italic, shadow) on top of `font`/`color` — the same
    /// ``PayOrcUIConstants/resolvedTextAttributes(font:color:)`` pattern
    /// `CheckoutViewController` uses for its header title/subtitle.
    ///
    /// - Parameter forcedAlignment: Overrides the host's resolved global
    ///   alignment for this label, mirroring a Flutter `AppText` call that
    ///   passes its own `textAlign` — a per-label explicit value always wins
    ///   over the global customization default.
    private func styledText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        forcedAlignment: NSTextAlignment? = nil
    ) -> NSAttributedString {
        var attributes = PayOrcUIConstants.resolvedTextAttributes(font: font, color: color)
        if let forcedAlignment {
            let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
                as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.alignment = forcedAlignment
            attributes[.paragraphStyle] = paragraph
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private func getCardBrandImageName(for number: String) -> String? {
        let digits = number.replacingOccurrences(of: " ", with: "")
        let prefix = String(digits.prefix(2))
        switch prefix {
        case "4": return "visa"
        case "51","52","53","54","55": return "mastercard"
        case "34","37": return "amex"
        default: return nil
        }
    }
}

// MARK: - CircularIndeterminateProgressView

/// A rotating-arc circular progress ring: a full light track circle with a
/// shorter, darker arc that continuously rotates around it. Mirrors Flutter's
/// indeterminate `CircularProgressIndicator` (light `borderColor` track,
/// `textPrimaryColor` arc) more closely than a dot-based spinner would.
private final class CircularIndeterminateProgressView: UIView {

    var trackColor: UIColor = .systemGray5 {
        didSet { trackLayer.strokeColor = trackColor.cgColor }
    }
    var progressColor: UIColor = .label {
        didSet { arcLayer.strokeColor = progressColor.cgColor }
    }
    var lineWidth: CGFloat = 4 {
        didSet {
            trackLayer.lineWidth = lineWidth
            arcLayer.lineWidth = lineWidth
            setNeedsLayout()
        }
    }

    private let trackLayer = CAShapeLayer()
    private let arcLayer   = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = trackColor.cgColor
        trackLayer.lineWidth = lineWidth

        arcLayer.fillColor = UIColor.clear.cgColor
        arcLayer.strokeColor = progressColor.cgColor
        arcLayer.lineWidth = lineWidth
        arcLayer.lineCap = .round
        arcLayer.strokeEnd = 0.22

        layer.addSublayer(trackLayer)
        layer.addSublayer(arcLayer)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let radius = (min(bounds.width, bounds.height) - lineWidth) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        trackLayer.frame = bounds
        trackLayer.path = path.cgPath
        arcLayer.frame = bounds
        arcLayer.path = path.cgPath

        if arcLayer.animation(forKey: "rotation") == nil {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = CGFloat.pi * 2
            rotation.duration = 1.1
            rotation.repeatCount = .infinity
            arcLayer.add(rotation, forKey: "rotation")
        }
    }
}

// MARK: - IndeterminateProgressBarView

/// A rounded track with a sliding highlight bar that bounces left-to-right on
/// loop. Mirrors Flutter's indeterminate `LinearProgressIndicator` (light
/// `borderColor` track, `textPrimaryColor` fill) more closely than a
/// determinate progress view would.
private final class IndeterminateProgressBarView: UIView {

    var trackColor: UIColor = .systemGray5 {
        didSet { trackLayer.backgroundColor = trackColor.cgColor }
    }
    var progressColor: UIColor = .label {
        didSet { barLayer.backgroundColor = progressColor.cgColor }
    }

    private let trackLayer = CALayer()
    private let barLayer   = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        trackLayer.backgroundColor = trackColor.cgColor
        barLayer.backgroundColor = progressColor.cgColor
        layer.addSublayer(trackLayer)
        trackLayer.addSublayer(barLayer)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.height / 2
        trackLayer.masksToBounds = true

        let barWidth = bounds.width * 0.32
        barLayer.bounds = CGRect(x: 0, y: 0, width: barWidth, height: bounds.height)
        barLayer.position = CGPoint(x: -barWidth / 2, y: bounds.height / 2)
        barLayer.cornerRadius = bounds.height / 2

        if barLayer.animation(forKey: "slide") == nil {
            let slide = CABasicAnimation(keyPath: "position.x")
            slide.fromValue = -barWidth / 2
            slide.toValue = bounds.width + barWidth / 2
            slide.duration = 1.1
            slide.repeatCount = .infinity
            slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            barLayer.add(slide, forKey: "slide")
        }
    }
}
