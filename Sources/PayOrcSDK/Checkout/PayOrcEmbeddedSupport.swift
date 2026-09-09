import UIKit

// MARK: - PayOrcEmbeddedVisibility

/// Shared visibility resolution for embedded payment components.
///
/// Mirrors Flutter's `checkoutPaymentMethodVisible`: methods are visible by
/// default until checkout customization has loaded (so embeds are usable
/// immediately), then driven by the API `show` flag once data arrives.
enum PayOrcEmbeddedVisibility {

    static func isMethodVisible(type: String, whenNoCustomizationData: Bool = true) -> Bool {
        guard let methods = PayOrc.shared?.checkoutCustomization?.availableMethods,
              !methods.isEmpty else {
            return whenNoCustomizationData
        }
        let key = normalize(type)
        guard let match = methods.first(where: { normalize($0.type) == key }) else {
            return false
        }
        return match.isVisible
    }

    private static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { !" _-".contains($0) }
    }
}

// MARK: - PayOrcEmbeddedWidthFiller

/// Gives an embedded PayOrc view "full width by default, adjustable by the host"
/// sizing — the Swift/Auto Layout equivalent of Flutter's
/// `Column(crossAxisAlignment: CrossAxisAlignment.stretch)` wrapping.
///
/// While ``isEnabled`` is `true` (the default), the owning view's leading/trailing
/// edges are pinned to its superview, so it fills the available width just like the
/// Flutter embeds do. Set ``isEnabled`` to `false` to size the view yourself (fixed
/// width, centered, custom insets, etc.) — the pin constraints are removed and the
/// host is free to add their own.
///
/// No-ops when the superview is a `UIStackView`: with `.fill` alignment (used by
/// ``PayOrcEmbeddedPaymentMethodsView``), the stack already sizes arranged subviews
/// to its own width, so adding a redundant pin risks conflicting with the stack's
/// own margin-relative arrangement.
final class PayOrcEmbeddedWidthFiller {
    private weak var view: UIView?
    private var constraints: [NSLayoutConstraint] = []

    var isEnabled: Bool = true {
        didSet { refresh() }
    }

    init(view: UIView) {
        self.view = view
    }

    /// Call from the owning view's `didMoveToSuperview()`.
    func refresh() {
        NSLayoutConstraint.deactivate(constraints)
        constraints = []
        guard isEnabled,
              let view,
              let superview = view.superview,
              !(superview is UIStackView) else { return }

        let leading  = view.leadingAnchor.constraint(equalTo: superview.leadingAnchor)
        let trailing = view.trailingAnchor.constraint(equalTo: superview.trailingAnchor)
        constraints = [leading, trailing]
        NSLayoutConstraint.activate(constraints)
    }
}

// MARK: - UIResponder + Nearest View Controller

extension UIResponder {
    /// Walks the responder chain upward from `self` to find the nearest containing
    /// `UIViewController`. Lets embedded views resolve a presenter automatically
    /// (mirrors how Flutter embeds default to the enclosing `BuildContext`) when the
    /// host doesn't supply one explicitly.
    func payorc_nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}
