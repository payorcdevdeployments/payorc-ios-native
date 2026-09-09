import UIKit

// MARK: - PaymentMethodTileView

/// A styled tile row representing a single payment method option.
///
/// Mirrors Flutter's `PayMethodTile`:
/// - Background = `accentColor` from checkout customization (white text/icon on top)
/// - When selected: slightly darker background + white border
/// - Left: SF Symbol icon OR image asset
/// - Center: title label
/// - Right: optional trailing card-scheme logo stack OR chevron arrow
final class PaymentMethodTileView: UIView {

    // MARK: - Config

    struct Config {
        var iconName:      String?   // SF Symbol name
        var imageName:     String?   // local asset name (e.g. "tabby", "samsung_pay")
        var imageURL:      String?   // remote URL for method logo
        var title:         String
        var trailingLogos: [String]  // asset names for trailing card logos
        var isSelected:    Bool
        var backgroundColor: UIColor? // Override for background
        var titleColor:    UIColor? // Override for title
        var selectedBackgroundColor: UIColor? // Override for selected-state background
        var selectedBorderColor: UIColor?     // Override for selected-state border
        var cornerRadius:  CGFloat?           // Override for tile corner radius

        init(
            iconName:      String?   = nil,
            imageName:     String?   = nil,
            imageURL:      String?   = nil,
            title:         String,
            trailingLogos: [String]  = [],
            isSelected:    Bool      = false,
            backgroundColor: UIColor? = nil,
            titleColor:    UIColor? = nil,
            selectedBackgroundColor: UIColor? = nil,
            selectedBorderColor: UIColor? = nil,
            cornerRadius:  CGFloat? = nil
        ) {
            self.iconName      = iconName
            self.imageName     = imageName
            self.imageURL      = imageURL
            self.title         = title
            self.trailingLogos = trailingLogos
            self.isSelected    = isSelected
            self.backgroundColor = backgroundColor
            self.titleColor    = titleColor
            self.selectedBackgroundColor = selectedBackgroundColor
            self.selectedBorderColor = selectedBorderColor
            self.cornerRadius  = cornerRadius
        }
    }

    // MARK: - Callbacks
    var onTap: (() -> Void)?

    // MARK: - Private UI
    private let iconImageView    = UIImageView()
    private let titleLabel       = UILabel()
    private let trailingStack    = UIStackView()
    private let chevronImageView = UIImageView()

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        buildLayout()
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public API

    func configure(with config: Config) {
        // ── Colors ────────────────────────────────────────────────────────────
        layer.cornerRadius = config.cornerRadius ?? 12
        applyColors(
            isSelected: config.isSelected,
            customBg: config.backgroundColor,
            customTitle: config.titleColor,
            customSelectedBg: config.selectedBackgroundColor,
            customSelectedBorder: config.selectedBorderColor
        )

        // ── Icon / image ──────────────────────────────────────────────────────
        let tint = titleLabel.textColor ?? .white
        if let assetName = config.imageName,
           let img = UIImage(payorcNamed: assetName) {
            iconImageView.image       = img
            iconImageView.contentMode = .scaleAspectFit
            iconImageView.tintColor   = nil
            iconImageView.isHidden    = false
        } else if let symbol = config.iconName,
                  let img = UIImage(systemName: symbol) {
            iconImageView.image       = img.withRenderingMode(.alwaysTemplate)
            iconImageView.contentMode = .scaleAspectFit
            iconImageView.tintColor   = tint
            iconImageView.isHidden    = false
        } else if let urlStr = config.imageURL, let url = URL(string: urlStr) {
            // Load remote logo
            iconImageView.image       = UIImage(systemName: "creditcard")?.withRenderingMode(.alwaysTemplate)
            iconImageView.tintColor   = tint
            iconImageView.contentMode = .scaleAspectFit
            iconImageView.isHidden    = false
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async { self?.iconImageView.image = img }
            }.resume()
        } else {
            iconImageView.isHidden = true
        }

        // ── Title ─────────────────────────────────────────────────────────────
        titleLabel.text = config.title

        // ── Trailing logos ─────────────────────────────────────────────────────
        // Skip names with no matching asset (e.g. schemes like "mada" / "unionpay"
        // that aren't in the catalog) — an image view with a nil image still
        // reserves its full width + stack spacing, showing up as a blank gap.
        trailingStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let resolvedLogos = config.trailingLogos.compactMap { name in
            UIImage(payorcNamed: name).map { (name: name, image: $0) }
        }
        if !resolvedLogos.isEmpty {
            for logo in resolvedLogos {
                let iv              = UIImageView(image: logo.image)
                iv.contentMode      = .scaleAspectFit
                iv.clipsToBounds    = true
                iv.widthAnchor.constraint(equalToConstant: 28).isActive = true
                iv.heightAnchor.constraint(equalToConstant: 20).isActive = true
                iv.translatesAutoresizingMaskIntoConstraints = false
                trailingStack.addArrangedSubview(iv)
            }
            trailingStack.isHidden = false
            chevronImageView.isHidden = true
        } else {
            trailingStack.isHidden    = true
            chevronImageView.isHidden = false
            chevronImageView.tintColor = tint.withAlphaComponent(0.7)
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        layer.cornerRadius  = 12
        layer.masksToBounds = true

        // Icon view
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        iconImageView.widthAnchor.constraint(equalToConstant: 28).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 28).isActive = true

        // Title
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Trailing logos stack
        trailingStack.axis      = .horizontal
        trailingStack.spacing   = 4
        trailingStack.alignment = .center
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)

        // Chevron
        let chevronCfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        chevronImageView.image       = UIImage(systemName: "chevron.right", withConfiguration: chevronCfg)?
            .withRenderingMode(.alwaysTemplate)
        chevronImageView.tintColor   = .white
        chevronImageView.contentMode = .scaleAspectFit
        chevronImageView.setContentHuggingPriority(.required, for: .horizontal)
        chevronImageView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false

        // Horizontal row
        let hStack = UIStackView(arrangedSubviews: [iconImageView, titleLabel, trailingStack, chevronImageView])
        hStack.axis      = .horizontal
        hStack.spacing   = 14
        hStack.alignment = .center
        hStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    private func applyColors(
        isSelected: Bool,
        customBg: UIColor? = nil,
        customTitle: UIColor? = nil,
        customSelectedBg: UIColor? = nil,
        customSelectedBorder: UIColor? = nil
    ) {
        let accent = PayOrcUIConstants.accentColor
        let baseBg = customBg ?? accent

        if isSelected {
            // Match Flutter's _defaultSelectedBackground logic:
            // darkened accent + accent border
            backgroundColor = customSelectedBg ?? baseBg.darkened(by: 0.1)
            layer.borderColor = (customSelectedBorder ?? accent).cgColor
            layer.borderWidth = 2
        } else {
            backgroundColor = baseBg
            layer.borderColor = PayOrcUIConstants.borderColor.cgColor
            layer.borderWidth = 1
        }

        // Contrast-based text/icon coloring
        let isDark = backgroundColor?.isDark ?? false
        let textColor = customTitle ?? (isDark ? .white : PayOrcUIConstants.textPrimaryColor)

        titleLabel.textColor = textColor
        iconImageView.tintColor = textColor
        chevronImageView.tintColor = textColor.withAlphaComponent(0.7)
    }

    // MARK: - Interaction

    @objc private func handleTap() {
        UIView.animate(withDuration: 0.08, animations: {
            self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }) { _ in
            UIView.animate(withDuration: 0.1) { self.transform = .identity }
        }
        onTap?()
    }
}

// MARK: - UIColor Helper

private extension UIColor {
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.5
    }

    func darkened(by percentage: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: max(r - percentage, 0),
                       green: max(g - percentage, 0),
                       blue: max(b - percentage, 0),
                       alpha: a)
    }
}
