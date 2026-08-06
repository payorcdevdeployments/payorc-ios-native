import UIKit

// MARK: - SubmittingOrderViewController
//
// Bottom sheet shown while card payment is being submitted to PayOrc.
// Mirrors Flutter's `SubmittingOrderFlowSheet` / `SubmittingOrderSheet`:
//   - Circular progress indicator with card brand logo in center
//   - "Submitting your order" title and disclaimer subtitle
//   - Animated linear progress bar with "Processing payment..."
//   - Selected card summary box (masked PAN, cardholder name, lock icon + "Secure")
//   - Amber warning banner ("Do not close or refresh this page...")
//   - "Powered by PayOrc" footer

public final class SubmittingOrderViewController: UIViewController {

    // MARK: - Dependencies

    private let viewModel: CheckoutViewModel
    private let card: CardData
    private var onSuccess: ((PayOrcSDKResult) -> Void)?
    private var onFailure: ((PayOrcError) -> Void)?

    // MARK: - UI Elements

    private let contentStack      = UIStackView()
    private let dragHandle        = UIView()

    // Spinner
    private let spinnerContainer  = UIView()
    private let circularProgress  = UIActivityIndicatorView(style: .large)
    private let brandIconView     = UIImageView()

    // Text
    private let titleLabel        = UILabel()
    private let subtitleLabel     = UILabel()

    // Progress Bar
    private let progressRow       = UIStackView()
    private let progressLabel     = UILabel()
    private let progressBar       = UIProgressView(progressViewStyle: .bar)

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

    // MARK: - Init

    public init(
        viewModel: CheckoutViewModel,
        card: CardData,
        onSuccess: @escaping (PayOrcSDKResult) -> Void,
        onFailure: @escaping (PayOrcError) -> Void
    ) {
        self.viewModel = viewModel
        self.card      = card
        self.onSuccess = onSuccess
        self.onFailure = onFailure
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
        contentStack.spacing = 16
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
        dragHandle.backgroundColor = UIColor.systemGray4
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

        // 2. Circular Spinner Container (88x88)
        spinnerContainer.translatesAutoresizingMaskIntoConstraints = false
        circularProgress.translatesAutoresizingMaskIntoConstraints = false
        circularProgress.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        circularProgress.color = PayOrcUIConstants.brandColor
        circularProgress.startAnimating()

        // Center card logo inside spinner
        brandIconView.contentMode = .scaleAspectFit
        brandIconView.translatesAutoresizingMaskIntoConstraints = false
        let panDigits = card.cardNumber ?? ""
        if let brand = getCardBrandImageName(for: panDigits),
           let img = UIImage(named: brand) {
            brandIconView.image = img
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
            brandIconView.image = UIImage(systemName: "creditcard", withConfiguration: cfg)
            brandIconView.tintColor = PayOrcUIConstants.textSecondaryColor
        }

        let circleBg = UIView()
        circleBg.backgroundColor = .systemBackground
        circleBg.layer.cornerRadius = 32
        circleBg.layer.shadowColor = UIColor.black.cgColor
        circleBg.layer.shadowOpacity = 0.08
        circleBg.layer.shadowOffset = CGSize(width: 0, height: 2)
        circleBg.layer.shadowRadius = 4
        circleBg.translatesAutoresizingMaskIntoConstraints = false

        circleBg.addSubview(brandIconView)
        spinnerContainer.addSubview(circularProgress)
        spinnerContainer.addSubview(circleBg)

        NSLayoutConstraint.activate([
            spinnerContainer.heightAnchor.constraint(equalToConstant: 90),

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
            brandIconView.widthAnchor.constraint(equalToConstant: 36),
            brandIconView.heightAnchor.constraint(equalToConstant: 36)
        ])
        contentStack.addArrangedSubview(spinnerContainer)

        // 3. Title & Subtitle
        titleLabel.text = "Submitting your order"
        titleLabel.font = .boldSystemFont(ofSize: 20)
        titleLabel.textColor = PayOrcUIConstants.textPrimaryColor
        titleLabel.textAlignment = .center

        subtitleLabel.text = "Please don't leave this page before the end of the order submission."
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = PayOrcUIConstants.textSecondaryColor
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 6
        contentStack.addArrangedSubview(titleStack)

        // 4. Progress Row
        progressLabel.text = "Processing payment..."
        progressLabel.font = .systemFont(ofSize: 13, weight: .medium)
        progressLabel.textColor = PayOrcUIConstants.textSecondaryColor

        progressBar.progressTintColor = PayOrcUIConstants.brandColor
        progressBar.trackTintColor = UIColor.systemGray5
        progressBar.layer.cornerRadius = 3
        progressBar.clipsToBounds = true
        progressBar.progress = 0.3
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        progressRow.axis = .horizontal
        progressRow.spacing = 12
        progressRow.alignment = .center
        progressRow.addArrangedSubview(progressLabel)
        progressRow.addArrangedSubview(progressBar)
        contentStack.addArrangedSubview(progressRow)

        // Animate progress bar linearly
        UIView.animate(withDuration: 3.5, delay: 0, options: [.curveEaseInOut, .repeat], animations: {
            self.progressBar.setProgress(0.9, animated: true)
        })

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
        cardSummaryBox.backgroundColor = UIColor.secondarySystemGroupedBackground
        cardSummaryBox.layer.cornerRadius = 12
        cardSummaryBox.layer.borderWidth = 1
        cardSummaryBox.layer.borderColor = PayOrcUIConstants.textFieldBorderColor.cgColor
        cardSummaryBox.translatesAutoresizingMaskIntoConstraints = false

        let pan = card.cardNumber ?? ""
        let last4 = pan.count >= 4 ? String(pan.suffix(4)) : "••••"
        cardNumberLabel.text = "•••• •••• •••• \(last4)"
        cardNumberLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        cardNumberLabel.textColor = PayOrcUIConstants.textPrimaryColor

        let holder = card.cardholderName.isEmpty ? "Cardholder" : card.cardholderName
        let expiry = "\(card.expiryMonth)/\(card.expiryYear)"
        cardDetailLabel.text = "\(holder) · \(expiry)"
        cardDetailLabel.font = .systemFont(ofSize: 12)
        cardDetailLabel.textColor = PayOrcUIConstants.textSecondaryColor

        let textStack = UIStackView(arrangedSubviews: [cardNumberLabel, cardDetailLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        // Lock + "Secure"
        let lockCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        secureIconView.image = UIImage(systemName: "lock.fill", withConfiguration: lockCfg)
        secureIconView.tintColor = PayOrcUIConstants.brandColor
        secureLabel.text = "Secure"
        secureLabel.font = .systemFont(ofSize: 13, weight: .medium)
        secureLabel.textColor = PayOrcUIConstants.brandColor

        let secureStack = UIStackView(arrangedSubviews: [secureIconView, secureLabel])
        secureStack.axis = .horizontal
        secureStack.spacing = 4
        secureStack.alignment = .center

        // Brand logo chip
        let chipView = UIView()
        chipView.backgroundColor = UIColor.systemGray6
        chipView.layer.cornerRadius = 6
        chipView.translatesAutoresizingMaskIntoConstraints = false

        brandBadgeView.contentMode = .scaleAspectFit
        brandBadgeView.translatesAutoresizingMaskIntoConstraints = false
        chipView.addSubview(brandBadgeView)
        NSLayoutConstraint.activate([
            chipView.widthAnchor.constraint(equalToConstant: 44),
            chipView.heightAnchor.constraint(equalToConstant: 28),
            brandBadgeView.centerXAnchor.constraint(equalTo: chipView.centerXAnchor),
            brandBadgeView.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),
            brandBadgeView.widthAnchor.constraint(equalToConstant: 32),
            brandBadgeView.heightAnchor.constraint(equalToConstant: 20)
        ])

        if let brandName = getCardBrandImageName(for: pan),
           let img = UIImage(named: brandName) {
            brandBadgeView.image = img
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            brandBadgeView.image = UIImage(systemName: "creditcard.fill", withConfiguration: cfg)
            brandBadgeView.tintColor = PayOrcUIConstants.textSecondaryColor
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
        warningBox.layer.borderWidth = 1
        warningBox.layer.borderColor = UIColor(red: 1.0, green: 0.80, blue: 0.40, alpha: 0.6).cgColor
        warningBox.translatesAutoresizingMaskIntoConstraints = false

        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        warningIconView.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: cfg)
        warningIconView.tintColor = UIColor.systemOrange
        warningIconView.setContentHuggingPriority(.required, for: .horizontal)

        warningLabel.text = "Do not close or refresh this page during payment processing."
        warningLabel.font = .systemFont(ofSize: 13, weight: .medium)
        warningLabel.textColor = PayOrcUIConstants.textPrimaryColor
        warningLabel.numberOfLines = 0

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

        viewModel.submit(card: card) { [weak self] response in
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
                self.dismiss(animated: true) {
                    self.onSuccess?(sdkResult)
                }
            } else {
                let msg = response.message.isEmpty ? "Transaction failed" : response.message
                let payOrcError = PayOrcError.paymentFailed(code: response.code, message: msg)
                self.dismiss(animated: true) {
                    self.onFailure?(payOrcError)
                }
            }
        } onFailure: { [weak self] error in
            guard let self = self else { return }
            self.dismiss(animated: true) {
                self.onFailure?(error)
            }
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
                self.dismiss(animated: true) {
                    self.onSuccess?(sdkResult)
                }
            } else {
                let msg = (dataMap?["reason"] as? String) ?? (postbackMap["message"] as? String) ?? "Payment failed"
                self.dismiss(animated: true) {
                    self.onFailure?(.requestFailed(underlying: NSError(domain: "PayOrc", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
                }
            }
        }

        let nav = UINavigationController(rootViewController: threeDSVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
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
