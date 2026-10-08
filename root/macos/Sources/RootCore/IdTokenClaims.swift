import Foundation

public struct VerifiedIdentity: Equatable {
    public let subject: String
    public let email: String
}

public enum ClaimsFailure: Error, Equatable {
    case invalid
    case emailNotVerified
}

/// Checks the claims of a Google ID token (and what Google's own verification endpoint said about it).
public enum IdTokenClaims {
    private static let issuers: Set<String> = ["https://accounts.google.com", "accounts.google.com"]
    private static let maxSubjectLength = 255

    public static func decode(_ idToken: String) throws -> [String: Any] {
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw ClaimsFailure.invalid }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaimsFailure.invalid
        }
        return object
    }

    public static func identity(claims: [String: Any], verified: [String: Any], clientId: String, nonce: String, now: Date) throws -> VerifiedIdentity {
        guard let subject = claims["sub"] as? String, !subject.isEmpty, subject.count <= maxSubjectLength,
              verified["sub"] as? String == subject else { throw ClaimsFailure.invalid }
        guard claims["aud"] as? String == clientId, verified["aud"] as? String == clientId else { throw ClaimsFailure.invalid }
        guard let issuer = claims["iss"] as? String, issuers.contains(issuer) else { throw ClaimsFailure.invalid }
        guard let expiry = claims["exp"] as? Double, expiry > now.timeIntervalSince1970 else { throw ClaimsFailure.invalid }
        guard let sent = claims["nonce"] as? String, Tokens.constantTimeEqual(sent, nonce) else { throw ClaimsFailure.invalid }
        guard claims["email_verified"] as? Bool == true, let email = claims["email"] as? String, !email.isEmpty else { throw ClaimsFailure.emailNotVerified }
        return VerifiedIdentity(subject: subject, email: email.lowercased())
    }
}
