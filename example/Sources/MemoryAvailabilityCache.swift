import Foundation
import WirexMobileSDK

/// An in-memory implementation of the SDK's storage adapter, so the Availability tab can show every
/// read and write the SDK performs — one key, a value of exactly two booleans — and clear it on a
/// button. A real host backs this with UserDefaults or MMKV; the adapter shape is Web Storage's, so
/// the same store the web SDK uses works here.
///
/// The value is safe to display: it is `{"applePay":<bool>,"googlePay":<bool>}` and nothing else,
/// written only from a REAL probe answer.
final class MemoryAvailabilityCache: WirexWalletAvailabilityCache {
    var onActivity: ((String) -> Void)?
    private var storage: [String: String] = [:]

    func read(key: String) -> String? {
        let value = storage[key]
        onActivity?("cache read  \(key) -> \(value ?? "nil")")
        return value
    }

    func write(key: String, value: String) {
        storage[key] = value
        onActivity?("cache write \(key) = \(value)")
    }

    func clear() {
        storage = [:]
        onActivity?("cache cleared")
    }
}
