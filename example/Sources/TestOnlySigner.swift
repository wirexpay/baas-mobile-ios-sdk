import CryptoSwift
import Foundation
import P256K
import WirexMobileSDK

// FOR TESTING ONLY. Signs with a raw private key held in memory, so a tester can trade from this example.
// A real app signs in the user's wallet and never holds a key. Never ship this file or a key with an app.
final class TestOnlySigner: WirexTradeSigner {
    enum Failure: Error, CustomStringConvertible {
        case notAKey
        case notAHash

        var description: String {
            self == .notAKey ? "ownerKey is not a 32-byte hex private key" : "the SDK asked to sign something other than 32 bytes"
        }
    }

    /// The owner's address, in EIP-55 form.
    let address: String
    let addressBytes: [UInt8]
    private let keyBytes: [UInt8]

    init(hexKey: String) throws {
        guard let bytes = Hex.decode(hexKey), bytes.count == 32,
              let key = try? P256K.Recovery.PrivateKey(dataRepresentation: bytes, format: .uncompressed)
        else { throw Failure.notAKey }
        keyBytes = bytes
        // Uncompressed public key: 0x04 ‖ X ‖ Y. The address is the last 20 bytes of keccak(X ‖ Y).
        let publicKey = [UInt8](key.publicKey.dataRepresentation)
        addressBytes = Array(Self.keccak256(Array(publicKey.dropFirst())).suffix(20))
        address = Self.checksummed(addressBytes)
    }

    /// EIP-191 over the 32 bytes as given, answering `r ‖ s ‖ v` in 65 bytes with `v` 27 or 28.
    func signPersonal(hash: Data) async throws -> Data {
        guard hash.count == 32 else { throw Failure.notAHash }
        return Data(try sign(eip191: [UInt8](hash)))
    }

    /// EIP-191 over a text message, as `personal_sign` does. The login signs its message this way.
    func signMessage(_ message: String) throws -> [UInt8] {
        try sign(eip191: Array(message.utf8))
    }

    private func sign(eip191 message: [UInt8]) throws -> [UInt8] {
        let prefix = Array("\u{19}Ethereum Signed Message:\n\(message.count)".utf8)
        let digest = HashDigest(Self.keccak256(prefix + message))
        let key = try P256K.Recovery.PrivateKey(dataRepresentation: keyBytes, format: .uncompressed)
        let compact = try key.signature(for: digest).compactRepresentation
        return [UInt8](compact.signature) + [UInt8(27 + compact.recoveryId)]
    }

    static func keccak256(_ bytes: [UInt8]) -> [UInt8] {
        SHA3(variant: .keccak256).calculate(for: bytes)
    }

    /// EIP-55: a hex letter is upper case where the keccak of the lower-case address has a nibble of 8 or more.
    static func checksummed(_ address: [UInt8]) -> String {
        let lower = Hex.encode(address)
        let hash = keccak256(Array(lower.utf8))
        var out = "0x"
        for (index, char) in lower.enumerated() {
            let nibble = (hash[index / 2] >> (index % 2 == 0 ? 4 : 0)) & 0x0f
            out.append(nibble >= 8 ? Character(char.uppercased()) : char)
        }
        return out
    }
}

/// Lower-case hex without a prefix, and a decoder that takes an optional `0x`.
enum Hex {
    static func encode(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func decode(_ text: String) -> [UInt8]? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s.removeFirst(2) }
        guard s.count % 2 == 0, s.allSatisfy(\.isHexDigit) else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}
