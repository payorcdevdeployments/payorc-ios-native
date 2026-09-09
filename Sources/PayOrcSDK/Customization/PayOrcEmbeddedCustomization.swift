import UIKit

// MARK: - PayOrcEmbeddedCustomization

/// Per-instance styling for a **single** embedded payment control.
///
/// Apple Pay uses the native platform button and does not accept this type — only
/// SDK-built embeds below.
///
/// | View | accepts `customization` |
/// |------|--------------------------|
/// | ``PayOrcEmbeddedPayWithCardButton`` | yes |
/// | ``PayOrcEmbeddedTabbyButton`` | yes |
/// | ``PayOrcEmbeddedApplePayButton`` | no |
///
/// Values here override ``PayOrcUIConstants`` for that one view instance only;
/// omitted fields fall back to the SDK-wide resolved value (host → API → default).
///
/// Mirrors Flutter's `PayorcEmbeddedCustomization`.
public struct PayOrcEmbeddedCustomization {

    // MARK: Button (Pay with Card)

    public var buttonBackgroundColor: UIColor?
    public var buttonTextColor:       UIColor?
    public var buttonBorderRadius:    CGFloat?
    public var buttonHeight:          CGFloat?
    public var buttonBorderColor:     UIColor?

    /// Overrides the button title (default: "Pay with Card").
    public var payWithCardTitle: String?

    // MARK: Tile (Tabby)

    public var tileBackgroundColor:         UIColor?
    public var tileTitleColor:              UIColor?
    public var tileSelectedBackgroundColor: UIColor?
    public var tileSelectedBorderColor:     UIColor?
    public var tileBorderRadius:            CGFloat?
    public var tileHeight:                  CGFloat?

    // MARK: Shared

    public var accentColor: UIColor?
    public var borderColor: UIColor?

    public init(
        buttonBackgroundColor: UIColor? = nil,
        buttonTextColor: UIColor? = nil,
        buttonBorderRadius: CGFloat? = nil,
        buttonHeight: CGFloat? = nil,
        buttonBorderColor: UIColor? = nil,
        payWithCardTitle: String? = nil,
        tileBackgroundColor: UIColor? = nil,
        tileTitleColor: UIColor? = nil,
        tileSelectedBackgroundColor: UIColor? = nil,
        tileSelectedBorderColor: UIColor? = nil,
        tileBorderRadius: CGFloat? = nil,
        tileHeight: CGFloat? = nil,
        accentColor: UIColor? = nil,
        borderColor: UIColor? = nil
    ) {
        self.buttonBackgroundColor = buttonBackgroundColor
        self.buttonTextColor = buttonTextColor
        self.buttonBorderRadius = buttonBorderRadius
        self.buttonHeight = buttonHeight
        self.buttonBorderColor = buttonBorderColor
        self.payWithCardTitle = payWithCardTitle
        self.tileBackgroundColor = tileBackgroundColor
        self.tileTitleColor = tileTitleColor
        self.tileSelectedBackgroundColor = tileSelectedBackgroundColor
        self.tileSelectedBorderColor = tileSelectedBorderColor
        self.tileBorderRadius = tileBorderRadius
        self.tileHeight = tileHeight
        self.accentColor = accentColor
        self.borderColor = borderColor
    }

    /// **Pay with Card** button preset.
    public static func payWithCard(
        backgroundColor: UIColor? = nil,
        textColor: UIColor? = nil,
        borderRadius: CGFloat? = nil,
        height: CGFloat? = nil,
        borderColor: UIColor? = nil,
        title: String? = nil
    ) -> PayOrcEmbeddedCustomization {
        PayOrcEmbeddedCustomization(
            buttonBackgroundColor: backgroundColor,
            buttonTextColor: textColor,
            buttonBorderRadius: borderRadius,
            buttonHeight: height,
            buttonBorderColor: borderColor,
            payWithCardTitle: title
        )
    }

    /// **Tabby** tile preset.
    public static func tabby(
        backgroundColor: UIColor? = nil,
        textColor: UIColor? = nil,
        borderRadius: CGFloat? = nil,
        height: CGFloat? = nil,
        borderColor: UIColor? = nil,
        accent: UIColor? = nil,
        selectedBackground: UIColor? = nil,
        selectedBorder: UIColor? = nil
    ) -> PayOrcEmbeddedCustomization {
        PayOrcEmbeddedCustomization(
            tileBackgroundColor: backgroundColor,
            tileTitleColor: textColor,
            tileSelectedBackgroundColor: selectedBackground,
            tileSelectedBorderColor: selectedBorder,
            tileBorderRadius: borderRadius,
            tileHeight: height,
            accentColor: accent,
            borderColor: borderColor
        )
    }

    // MARK: - Resolved values (fall back to SDK-wide PayOrcUIConstants)

    var effectiveButtonBackground: UIColor { buttonBackgroundColor ?? PayOrcUIConstants.buttonBackgroundColor }
    var effectiveButtonForeground: UIColor { buttonTextColor ?? PayOrcUIConstants.buttonForegroundColor }
    var effectiveButtonRadius: CGFloat { buttonBorderRadius ?? PayOrcUIConstants.buttonCornerRadius }
    var effectiveButtonHeight: CGFloat { buttonHeight ?? PayOrcUIConstants.buttonHeight }
    var effectiveButtonBorderColor: UIColor { buttonBorderColor ?? PayOrcUIConstants.buttonBorderColor }

    var effectiveTileBackground: UIColor? { tileBackgroundColor }
    var effectiveTileTitle: UIColor? { tileTitleColor }
    var effectiveTileBorderRadius: CGFloat { tileBorderRadius ?? 12 }
    var effectiveTileHeight: CGFloat { tileHeight ?? 56 }
}
