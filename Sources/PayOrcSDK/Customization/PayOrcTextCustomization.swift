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

    /// Additional spacing between characters (maps to `NSAttributedString.Key.kern`).
    public var letterSpacing:   CGFloat?

    /// Default text alignment for SDK labels.
    public var textAlignment:   NSTextAlignment?

    /// Default max lines for display text (`UILabel.numberOfLines`). `0` = unlimited.
    public var maxLines:        Int?

    /// Default line-break / truncation behavior for display text.
    public var lineBreakMode:   NSLineBreakMode?

    /// Draws an underline beneath SDK text when `true`.
    public var underline:       Bool?

    /// Draws a strikethrough through SDK text when `true`.
    public var strikethrough:   Bool?

    /// Additional spacing between words (in points).
    public var wordSpacing:     CGFloat?

    /// Renders SDK text in italics when `true`.
    public var italic:          Bool?

    /// Optional text shadow applied to display text.
    public var shadow:          NSShadow?

    public init(
        primaryColor:   UIColor? = nil,
        secondaryColor: UIColor? = nil,
        bodyFont:       UIFont?  = nil,
        titleFont:      UIFont?  = nil,
        fontWeight:     UIFont.Weight? = nil,
        fontSize:       CGFloat? = nil,
        letterSpacing:  CGFloat? = nil,
        textAlignment:  NSTextAlignment? = nil,
        maxLines:       Int? = nil,
        lineBreakMode:  NSLineBreakMode? = nil,
        underline:      Bool? = nil,
        strikethrough:  Bool? = nil,
        wordSpacing:    CGFloat? = nil,
        italic:         Bool? = nil,
        shadow:         NSShadow? = nil
    ) {
        self.primaryColor   = primaryColor
        self.secondaryColor = secondaryColor
        self.bodyFont       = bodyFont
        self.titleFont      = titleFont
        self.fontWeight     = fontWeight
        self.fontSize       = fontSize
        self.letterSpacing  = letterSpacing
        self.textAlignment  = textAlignment
        self.maxLines       = maxLines
        self.lineBreakMode  = lineBreakMode
        self.underline      = underline
        self.strikethrough  = strikethrough
        self.wordSpacing    = wordSpacing
        self.italic         = italic
        self.shadow         = shadow
    }
}
