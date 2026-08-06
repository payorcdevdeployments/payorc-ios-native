import UIKit

// MARK: - PayOrcTextCustomization

/// Visual customization for text rendered throughout the PayOrc SDK UI.
///
/// Pass to ``PayOrcSDK/setCustomization(_:)``.
/// Mirrors Flutter's `PayorcSdkTextCustomization`.
public struct PayOrcTextCustomization {

    /// Primary text color (headings, labels, amounts).
    public var primaryColor:    UIColor?

    /// Secondary text color (subtitles, hints, placeholders).
    public var secondaryColor:  UIColor?

    /// Font for body / regular text. Pass the font family name string.
    public var bodyFont:        UIFont?

    /// Font for titles / headers.
    public var titleFont:       UIFont?

    /// Font weight applied globally to SDK text elements.
    public var fontWeight:      UIFont.Weight?

    /// Font size for body text (in points).
    public var fontSize:        CGFloat?

    public init(
        primaryColor:   UIColor? = nil,
        secondaryColor: UIColor? = nil,
        bodyFont:       UIFont?  = nil,
        titleFont:      UIFont?  = nil,
        fontWeight:     UIFont.Weight? = nil,
        fontSize:       CGFloat? = nil
    ) {
        self.primaryColor   = primaryColor
        self.secondaryColor = secondaryColor
        self.bodyFont       = bodyFont
        self.titleFont      = titleFont
        self.fontWeight     = fontWeight
        self.fontSize       = fontSize
    }
}
