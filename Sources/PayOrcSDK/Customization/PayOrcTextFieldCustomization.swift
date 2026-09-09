import UIKit

// MARK: - PayOrcTextFieldCustomization

/// Visual customization for all input text fields in the PayOrc SDK UI.
///
/// Pass to ``PayOrcSDK/setCustomization(_:)``.
/// Mirrors Flutter's `PayorcSdkAppTextFieldCustomization`.
public struct PayOrcTextFieldCustomization {

    /// Fixed height for each input field (in points). `nil` = SDK default.
    public var height:        CGFloat?

    /// Content insets / padding inside each input field.
    public var contentInsets: UIEdgeInsets?

    /// Corner radius of the input field borders.
    public var borderRadius:  CGFloat?

    /// Border color for input fields.
    /// `nil` falls back to the API value (`MerchantDetails.borderColor`), then the SDK default.
    public var borderColor:   UIColor?

    public init(
        height:        CGFloat?       = nil,
        contentInsets: UIEdgeInsets?  = nil,
        borderRadius:  CGFloat?       = nil,
        borderColor:   UIColor?       = nil
    ) {
        self.height        = height
        self.contentInsets = contentInsets
        self.borderRadius  = borderRadius
        self.borderColor   = borderColor
    }
}
