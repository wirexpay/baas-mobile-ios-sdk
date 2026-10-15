import UIKit

/// Keeps the focused field above the keyboard, for any scrolling screen in this example.
///
/// Extracted because the collect screen needed the same thing the reveal screen already had, and
/// because the reveal screen's version could not have served it: it looked for the focused field in a
/// hard-coded list of three `UITextView`s. A `WirexSealedInput` is neither a text view nor in that
/// list, so a card field scrolled under the keyboard with nothing reporting a problem.
///
/// Two mechanisms, because they cover different moments:
///
/// - the keyboard's frame CHANGING, which covers it opening, closing, and resizing when a predictive
///   bar appears or a hardware keyboard is toggled;
/// - focus moving between fields while the keyboard is already up, when no frame change fires at all.
///   Text views announce that themselves; the SDK's fields announce it through
///   `WirexCollectForm.onFocusedFieldChanged`, which exists for exactly this.
final class KeyboardAvoider {
    private weak var scrollView: UIScrollView?
    private weak var root: UIView?

    init(scrollView: UIScrollView, root: UIView) {
        self.scrollView = scrollView
        self.root = root

        let center = NotificationCenter.default
        // `willChangeFrame` rather than `willShow`: it also fires when the keyboard changes height,
        // which a predictive-text bar or a hardware-keyboard toggle does without a show/hide pair.
        center.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(focusDidChange),
            name: UITextView.textDidBeginEditingNotification,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Call when focus moves without a system notification — the SDK's own fields.
    @objc func focusDidChange() {
        // Deferred: at this point the keyboard's inset may not have been applied yet, so scrolling
        // now would aim at the pre-keyboard viewport.
        DispatchQueue.main.async { [weak self] in self?.revealFocused() }
    }

    @objc private func keyboardFrameWillChange(_ note: Notification) {
        guard let root,
              let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }
        // Converted into the root's space: the notification reports the frame in screen coordinates,
        // which is not the same thing on an iPad or in a split-screen window.
        let overlap = max(0, root.bounds.maxY - root.convert(frame, from: nil).minY)
        apply(inset: overlap)
    }

    @objc private func keyboardWillHide() { apply(inset: 0) }

    private func apply(inset: CGFloat) {
        guard let scrollView else { return }
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
        if inset > 0 { revealFocused() }
    }

    /// Inset alone only makes room; the focused view still has to be scrolled into it.
    ///
    /// Found by walking for `isFirstResponder` rather than from a list. A list is what broke when a
    /// second kind of field appeared, and it would break again for the next one.
    private func revealFocused() {
        guard let scrollView, let root, let focused = Self.firstResponder(in: root) else { return }
        let rect = scrollView.convert(focused.bounds, from: focused).insetBy(dx: 0, dy: -12)
        scrollView.scrollRectToVisible(rect, animated: true)
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }
}
