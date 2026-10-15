import UIKit

/// Keeps `CALayer` borders in step with the trait environment.
///
/// A `UIColor` such as `.separator` is dynamic — it resolves differently in light and dark. A
/// `CGColor` is not: `.cgColor` reads the traits in force at that moment and then keeps the value
/// forever. Assigning one to `layer.borderColor` and walking away leaves a light-mode hairline drawn
/// over a dark background the first time the user switches appearance.
///
/// This lives in the example rather than the SDK because the SDK has no dynamic colours to
/// re-resolve: an appearance is one flat set of ARGB values the host supplies, and a host that wants
/// a dark palette hands over a different appearance. It is here because an example is what partners
/// copy, and copying the pitfall would spread it.
///
/// A struct holding the views rather than a `UIView` subclass, because the bordered controls are
/// `UITextView` and `UITextField` used directly. The owner calls `refresh()` from its own
/// `traitCollectionDidChange(_:)` — soft-deprecated on iOS 17 and still the only callback available
/// at this example's deployment target.
internal struct BorderedViews {
    private var views: [UIView] = []

    /// Applies the border and starts tracking the view.
    internal mutating func track(_ view: UIView, cornerRadius: CGFloat = 6) {
        view.layer.borderWidth = 1
        view.layer.cornerRadius = cornerRadius
        views.append(view)
        refresh(view)
    }

    /// Re-resolves every tracked border against the traits in force now.
    internal func refresh() { views.forEach(refresh) }

    private func refresh(_ view: UIView) {
        // The VIEW's traits, not the screen's: a view inside a controller that overrides the
        // interface style has to follow the override. `resolvedColor(with:)` arrived in iOS 13,
        // which is this example's floor, so no availability check is needed.
        view.layer.borderColor = UIColor.separator.resolvedColor(with: view.traitCollection).cgColor
    }
}
