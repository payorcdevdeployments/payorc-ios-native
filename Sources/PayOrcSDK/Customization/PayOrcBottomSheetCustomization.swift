import UIKit

// MARK: - PayOrcBottomSheetCustomization

/// Visual customization for modal bottom sheets presented by the PayOrc SDK.
///
/// Pass to ``PayOrcSDK/setCustomization(_:)``.
/// Mirrors Flutter's `PayorcSdkBottomSheetCustomization`.
public struct PayOrcBottomSheetCustomization {

    /// Content padding inside the bottom sheet.
    public var contentInsets:  UIEdgeInsets?

    /// Vertical spacing between items within the bottom sheet.
    public var itemSpacing:    CGFloat?

    /// Corner radius for the top corners of the bottom sheet.
    public var cornerRadius:   CGFloat?

    public init(
        contentInsets: UIEdgeInsets? = nil,
        itemSpacing:   CGFloat?      = nil,
        cornerRadius:  CGFloat?      = nil
    ) {
        self.contentInsets = contentInsets
        self.itemSpacing   = itemSpacing
        self.cornerRadius  = cornerRadius
    }
}
