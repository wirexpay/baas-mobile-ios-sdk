import Foundation

internal extension NSLock {
    /// `NSLock.withLock` is iOS 16+/macOS 13+, and this example runs on the SDK's iOS 13 floor.
    ///
    /// The SDK carries the same helper. It is `internal` there, because a locking primitive is not
    /// part of a card SDK's public surface, so a host writing against the SDK writes this itself —
    /// which is what the example is doing here.
    @discardableResult
    func wirexWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
