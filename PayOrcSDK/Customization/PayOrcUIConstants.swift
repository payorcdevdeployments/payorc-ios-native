import UIKit

// MARK: - PayOrcSDKCustomization

/// Root customization options passed to ``PayOrcSDK/setCustomization(_:)``.
///
/// Any `nil` field falls back to the checkout API value, then the SDK default.
/// Mirrors the parameters of Flutter's `PayorcSdk.customization(...)`.
public struct PayOrcSDKCustomization {

    // MARK: Core Color

    /// Brand / primary color used for highlights, active states, and logos.
    public var brandColor:  UIColor?

    /// Accent color (secondary highlights).
    public var accentColor: UIColor?

    /// Global border color for form elements (overrides `MerchantDetails.borderColor`).
    public var borderColor: UIColor?

    // MARK: Sub-customizations

    /// Button appearance overrides.
    public var button:      PayOrcButtonCustomization?

    /// Text color and font overrides.
    public var text:        PayOrcTextCustomization?

    /// Input field appearance overrides.
    public var textField:   PayOrcTextFieldCustomization?

    /// Bottom sheet appearance overrides.
    public var bottomSheet: PayOrcBottomSheetCustomization?

    // MARK: Input Style

    /// Input field border style. `nil` falls back to `MerchantDetails.fieldBorder`.
    public var inputBorderStyle: PayOrcInputBorderStyle?

    public init(
        brandColor:        UIColor? = nil,
        accentColor:       UIColor? = nil,
        borderColor:       UIColor? = nil,
        button:            PayOrcButtonCustomization?      = nil,
        text:              PayOrcTextCustomization?        = nil,
        textField:         PayOrcTextFieldCustomization?   = nil,
        bottomSheet:       PayOrcBottomSheetCustomization? = nil,
        inputBorderStyle:  PayOrcInputBorderStyle?         = nil
    ) {
        self.brandColor        = brandColor
        self.accentColor       = accentColor
        self.borderColor       = borderColor
        self.button            = button
        self.text              = text
        self.textField         = textField
        self.bottomSheet       = bottomSheet
        self.inputBorderStyle  = inputBorderStyle
    }
}

// MARK: - PayOrcInputBorderStyle

/// Style of input field borders throughout the SDK UI.
///
/// Mirrors Flutter's `PayorcInputBorderStyle`.
public enum PayOrcInputBorderStyle {
    /// Full rectangular border around the field.
    case outline
    /// Bottom border only (Material-style underline).
    case underline
}

// MARK: - PayOrcUIConstants

/// Resolved, live-read UI constants used by all SDK UI components.
///
/// Values are resolved in priority order:
/// 1. Host override (set via ``PayOrcSDK/setCustomization(_:)``)
/// 2. API value (from ``CheckoutCustomizationData/merchantDetails``)
/// 3. SDK default
///
/// Mirrors Flutter's `PayorcSdkUiConstants`.
///
/// Consumers should read values from this type directly — do not cache them,
/// as they may change after ``PayOrcSDK/refreshCheckoutCustomization(currency:amount:completion:)``.
public final class PayOrcUIConstants {

    private init() {}

    // MARK: - Internal State (set by PayOrcSDK)

    // Host overrides
    static var _hostBrandColor:          UIColor?
    static var _hostButtonColor:         UIColor?
    static var _hostButtonForeground:    UIColor?
    static var _hostButtonDisabled:      UIColor?
    static var _hostButtonBorderColor:   UIColor?
    static var _hostButtonBorderRadius:  CGFloat?
    static var _hostButtonHeight:        CGFloat?
    static var _hostButtonFontWeight:    UIFont.Weight?
    static var _hostButtonLoadingColor:  UIColor?
    static var _hostAccentColor:         UIColor?
    static var _hostTextPrimary:         UIColor?
    static var _hostTextSecondary:       UIColor?
    static var _hostBodyFont:            UIFont?
    static var _hostTitleFont:           UIFont?
    static var _hostBorderColor:         UIColor?
    static var _hostFieldBorderRadius:   CGFloat?
    static var _hostFieldBorderColor:    UIColor?
    static var _hostFieldHeight:         CGFloat?
    static var _hostFieldInsets:         UIEdgeInsets?
    static var _hostSheetCornerRadius:   CGFloat?
    static var _hostSheetPadding:        UIEdgeInsets?
    static var _hostSheetSpacing:        CGFloat?
    static var _hostInputBorderStyle:    PayOrcInputBorderStyle?

    // API values (applied from MerchantDetails after fetch)
    static var _apiBrandColor:           UIColor?
    static var _apiButtonColor:          UIColor?
    static var _apiAccentColor:          UIColor?
    static var _apiBorderColor:          UIColor?
    static var _apiTextPrimary:          UIColor?
    static var _apiTextSecondary:        UIColor?
    static var _apiInputBorderStyle:     PayOrcInputBorderStyle?
    static var _apiAutoselectColor:      Int?

    // MARK: - Resolved Values

    // MARK: Brand / Accent

    /// Resolved brand color: host → API → system blue.
    public static var brandColor: UIColor {
        _hostBrandColor ?? _apiBrandColor ?? .systemBlue
    }

    /// Resolved accent color: host → API → system blue.
    public static var accentColor: UIColor {
        _hostAccentColor ?? _apiAccentColor ?? brandColor
    }

    // MARK: Button

    /// Resolved button background color: host → API → brand color.
    public static var buttonBackgroundColor: UIColor {
        _hostButtonColor ?? _apiButtonColor ?? brandColor
    }

    /// Resolved button foreground (title) color: host → white.
    public static var buttonForegroundColor: UIColor {
        _hostButtonForeground ?? .white
    }

    /// Resolved button disabled background: host → 40% opacity brand.
    public static var buttonDisabledBackgroundColor: UIColor {
        _hostButtonDisabled ?? buttonBackgroundColor.withAlphaComponent(0.4)
    }

    /// Resolved button side border color: host → clear.
    public static var buttonBorderColor: UIColor {
        _hostButtonBorderColor ?? .clear
    }

    /// Resolved button corner radius: host → 8pt.
    public static var buttonCornerRadius: CGFloat {
        _hostButtonBorderRadius ?? 8
    }

    /// Resolved button height: host → 50pt.
    public static var buttonHeight: CGFloat {
        _hostButtonHeight ?? 50
    }

    /// Resolved button font weight: host → `.semibold`.
    public static var buttonFontWeight: UIFont.Weight {
        _hostButtonFontWeight ?? .semibold
    }

    /// Resolved loading indicator color: host → white.
    public static var buttonLoadingIndicatorColor: UIColor {
        _hostButtonLoadingColor ?? .white
    }

    // MARK: Text

    /// Resolved primary text color: host → API → `.label`.
    public static var textPrimaryColor: UIColor {
        _hostTextPrimary ?? _apiTextPrimary ?? .label
    }

    /// Resolved secondary text color: host → API → `.secondaryLabel`.
    public static var textSecondaryColor: UIColor {
        _hostTextSecondary ?? _apiTextSecondary ?? .secondaryLabel
    }

    /// Resolved body font: host → system 14pt.
    public static var bodyFont: UIFont {
        _hostBodyFont ?? .systemFont(ofSize: 14)
    }

    /// Resolved title font: host → system bold 16pt.
    public static var titleFont: UIFont {
        _hostTitleFont ?? .boldSystemFont(ofSize: 16)
    }

    // MARK: Border

    /// Resolved global border color: host → API → `.separator`.
    public static var borderColor: UIColor {
        _hostBorderColor ?? _apiBorderColor ?? .separator
    }

    // MARK: Text Field

    /// Resolved text field border color: host → global border color.
    public static var textFieldBorderColor: UIColor {
        _hostFieldBorderColor ?? borderColor
    }

    /// Resolved text field corner radius: host → 8pt.
    public static var textFieldCornerRadius: CGFloat {
        _hostFieldBorderRadius ?? 8
    }

    /// Resolved text field height: host → 48pt.
    public static var textFieldHeight: CGFloat {
        _hostFieldHeight ?? 48
    }

    /// Resolved text field content insets: host → uniform 12pt.
    public static var textFieldContentInsets: UIEdgeInsets {
        _hostFieldInsets ?? UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }

    // MARK: Bottom Sheet

    /// Resolved bottom sheet top corner radius: host → 20pt.
    public static var bottomSheetCornerRadius: CGFloat {
        _hostSheetCornerRadius ?? 20
    }

    /// Resolved bottom sheet content padding: host → uniform 20pt H / 16pt V.
    public static var bottomSheetContentInsets: UIEdgeInsets {
        _hostSheetPadding ?? UIEdgeInsets(top: 16, left: 20, bottom: 20, right: 20)
    }

    /// Resolved bottom sheet item spacing: host → 12pt.
    public static var bottomSheetItemSpacing: CGFloat {
        _hostSheetSpacing ?? 12
    }

    // MARK: Input Border Style

    /// Resolved input border style: host → API → `.underline`.
    public static var inputBorderStyle: PayOrcInputBorderStyle {
        _hostInputBorderStyle ?? _apiInputBorderStyle ?? .underline
    }

    // MARK: Autoselect Color

    /// Resolved autoselect tint color (raw int from API). `nil` when not set.
    public static var autoselectColor: Int? {
        _apiAutoselectColor
    }

    // MARK: - Apply from MerchantDetails

    /// Applies resolved API values from a ``MerchantDetails`` response.
    /// Called internally after a successful checkout customization fetch.
    static func applyMerchantDetails(_ details: MerchantDetails) {
        _apiBrandColor    = details.brandColor.flatMap { UIColor(hex: $0) }
        _apiButtonColor   = details.buttonColor.flatMap { UIColor(hex: $0) }
        _apiAccentColor   = details.accentColor.flatMap { UIColor(hex: $0) }
        _apiBorderColor   = details.borderColor.flatMap { UIColor(hex: $0) }
        _apiTextPrimary   = details.textPrimary.flatMap  { UIColor(hex: $0) }
        _apiTextSecondary = details.textSecondary.flatMap { UIColor(hex: $0) }
        _apiAutoselectColor = details.autoselectColor

        _apiInputBorderStyle = details.fieldBorder.flatMap {
            switch $0.lowercased() {
            case "outline":   return .outline
            case "underline": return .underline
            default:          return nil
            }
        }
    }

    // MARK: - Reset

    /// Clears all host overrides and API values (called on ``PayOrcSDK/initialize``).
    static func reset() {
        _hostBrandColor = nil; _hostButtonColor = nil; _hostButtonForeground = nil
        _hostButtonDisabled = nil; _hostButtonBorderColor = nil
        _hostButtonBorderRadius = nil; _hostButtonHeight = nil
        _hostButtonFontWeight = nil; _hostButtonLoadingColor = nil
        _hostAccentColor = nil; _hostTextPrimary = nil; _hostTextSecondary = nil
        _hostBodyFont = nil; _hostTitleFont = nil; _hostBorderColor = nil
        _hostFieldBorderRadius = nil; _hostFieldBorderColor = nil
        _hostFieldHeight = nil; _hostFieldInsets = nil
        _hostSheetCornerRadius = nil; _hostSheetPadding = nil
        _hostSheetSpacing = nil; _hostInputBorderStyle = nil

        _apiBrandColor = nil; _apiButtonColor = nil; _apiAccentColor = nil
        _apiBorderColor = nil; _apiTextPrimary = nil; _apiTextSecondary = nil
        _apiInputBorderStyle = nil; _apiAutoselectColor = nil
    }
}

// MARK: - UIColor Hex Extension

private extension UIColor {
    /// Creates a `UIColor` from a hex string.
    /// Supports `#RGB`, `#RRGGBB`, and `#AARRGGBB` / `#RRGGBBAA` formats.
    convenience init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }

        switch cleaned.count {
        case 6:
            let r = CGFloat((rgb >> 16) & 0xFF) / 255
            let g = CGFloat((rgb >>  8) & 0xFF) / 255
            let b = CGFloat( rgb        & 0xFF) / 255
            self.init(red: r, green: g, blue: b, alpha: 1)
        case 8:
            let r = CGFloat((rgb >> 24) & 0xFF) / 255
            let g = CGFloat((rgb >> 16) & 0xFF) / 255
            let b = CGFloat((rgb >>  8) & 0xFF) / 255
            let a = CGFloat( rgb        & 0xFF) / 255
            self.init(red: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }
}
