import UIKit

// MARK: - PayOrcButtonCustomization

/// Visual customization for all primary action buttons in the PayOrc SDK UI.
///
/// Pass to ``PayOrcSDK/setCustomization(_:)``.
/// Any `nil` property falls back to the checkout API value, then the SDK default.
///
/// Mirrors Flutter's `PayorcSdkButtonCustomization`.
public struct PayOrcButtonCustomization {

    /// Background color of the button in its normal state.
    public var backgroundColor:          UIColor?

    /// Foreground / text color of the button.
    public var foregroundColor:          UIColor?

    /// Background color of the button when disabled.
    public var disabledBackgroundColor:  UIColor?

    /// Color of the side/border stroke around the button (when bordered).
    public var sideBorderColor:          UIColor?

    /// Corner radius of the button (in points).
    public var borderRadius:             CGFloat?

    /// Fixed height of the button (in points). `nil` uses the SDK default.
    public var height:                   CGFloat?

    /// Font weight used for the button title.
    public var fontWeight:               UIFont.Weight?

    /// Color of the loading spinner shown while a request is in-flight.
    public var loadingIndicatorColor:    UIColor?

    public init(
        backgroundColor:         UIColor? = nil,
        foregroundColor:         UIColor? = nil,
        disabledBackgroundColor: UIColor? = nil,
        sideBorderColor:         UIColor? = nil,
        borderRadius:            CGFloat? = nil,
        height:                  CGFloat? = nil,
        fontWeight:              UIFont.Weight? = nil,
        loadingIndicatorColor:   UIColor? = nil
    ) {
        self.backgroundColor         = backgroundColor
        self.foregroundColor         = foregroundColor
        self.disabledBackgroundColor = disabledBackgroundColor
        self.sideBorderColor         = sideBorderColor
        self.borderRadius            = borderRadius
        self.height                  = height
        self.fontWeight              = fontWeight
        self.loadingIndicatorColor   = loadingIndicatorColor
    }
}
