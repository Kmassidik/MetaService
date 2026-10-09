import CommonCrypto
import Foundation
import MSCore

/// The operator password, kept as a salted PBKDF2-HMAC-SHA256 hash (the same scheme the MAAS panel uses). The password itself is never stored.
public enum PasswordHash {
    public static let iterations = 120_000
    public static let saltBytes = 16
    public static let minLength = 8
    public static let maxLength = 200

    public static func derive(password: String, salt: Data, iterations: Int) -> Data {
        let secret = Array(password.utf8), saltList = [UInt8](salt)
        var out = [UInt8](repeating: 0, count: 32)
        _ = secret.withUnsafeBufferPointer { secretPointer in
            saltList.withUnsafeBufferPointer { saltPointer in
                secretPointer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: max(secret.count, 1)) { chars in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), chars, secret.count, saltPointer.baseAddress, saltList.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &out, out.count)
                }
            }
        }
        return Data(out)
    }

    public static func randomSalt() -> Data {
        Data((0..<saltBytes).map { _ in UInt8.random(in: 0...255) })
    }

    /// True when the password produces the stored hash. The comparison does not stop at the first different byte.
    public static func matches(password: String, salt: Data, iterations: Int, expected: Data) -> Bool {
        let got = derive(password: password, salt: salt, iterations: iterations)
        guard got.count == expected.count else { return false }
        return zip(got, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
