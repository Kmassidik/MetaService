import MSCore
import XCTest
@testable import RootCore

/// The keys below were made with ssh-keygen; the fingerprints are what `ssh-keygen -lf` printed for them.
final class SshKeyRulesTests: XCTestCase {
    private let ed25519Blob = "AAAAC3NzaC1lZDI1NTE5AAAAII8umVmLJjfBjjgpC+plmhdOMZ7oWp0XKj9P6E5rrdCA"
    private let ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII8umVmLJjfBjjgpC+plmhdOMZ7oWp0XKj9P6E5rrdCA alice@laptop"
    private let ecdsa256 = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBANiYMuNazW/GBdZbtWp7qsFDj8PDfufbSHbmJD2u0ydJwCQGFmNRLcqyid3JJ+Vc0B/ipWlx+K7Mj03hVbXX7I= e256"
    private let ecdsa384 = "ecdsa-sha2-nistp384 AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBK/1aPahKGr6Gcp9on59R0OATGIz8R2+QJPVBlGt+iQb7O/h5KjsYwbHL7ULRphpwRaa/aohV/26NVLwRVfVyFwPlAA/c5W6ocgO89e1Eeko8AOG1e3y2L73ILeHZ69TEA== e384"
    private let ecdsa521 = "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAFNHvKPkoGiAuF5sqyK/u10NYyqWA9q7iT9HyqCRo/Hkob3ogn22wfOLkf8Ycip8gQRTCdqLwTz/G9pARo81B08zQBmoFCPBrWpm4nGJFVZgVGndH7/FLuMfj1a9FC9QgsDm8wDCB8GjgWKHHbgnUB76AgbiuaIksuqhlLGYQGOpYi6Dg== e521"
    private let rsa2048 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCpjv+0FfYhqzfA2bq8UMHAUII0CWOhjuHdMiEcqtk4RWXaUyGtZG3QRAp0/F4va6JsEThO0eYYSGzD2temJTD9kI1fXNFzuyU2VtNuGQtBP+wKPOegU+ed6pgbfcT40EAiTGB+yyw1sSZUk1n1UbdKWpRQe9g0qIqCXKMOuuQCFk3sQ/PMwue9lMCo17/Y+vi11H583LWQuZ+u4/UVMNWS1rMJkVt5QIiRHKCiYJzE/gnsd+fHd/1c/HhyHuu4hWqyvzKKb5PoAqaswBlciZ5utedirtcOimj5iqJfIquScE+i2CZdmZZYbFTPAKl2svyTiR95d110MEOGhV7cTWAf rsa2048"
    private let rsa1024 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQDKBdOhoDmQjrnz4423vslNHz3P2F0FlONiV+RwBZU6zVT1foLyCwr0N/HlmNLWurf9siK33Sa/BqGBEiWU+XMtpGOyeNFSzPU5s8b7a9GdcmE4cQAL8WEL1DrvwWS2j7sQnAtuUs93bbRqDv5D/+1VO0hCudBgnVtzui6FpSh4kw== rsa1024"
    private let securityKey = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gAAAABHNzaDo= sk@token"

    private func refusal(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        do {
            _ = try SshKeyRules.parse(text)
            XCTFail("should have been refused: \(text.prefix(60))", file: file, line: line)
            return ""
        } catch let error as InputError {
            return error.message
        } catch {
            XCTFail("wrong error \(error)", file: file, line: line)
            return ""
        }
    }

    // MARK: good keys

    func testEveryAllowedTypeIsAcceptedWithTheFingerprintSshKeygenPrints() throws {
        let expected: [(String, String, String)] = [
            (ed25519, "ssh-ed25519", "SHA256:wcRV5ASFFnhudVdHttpplmBjDQ14KAPHX2yqVl2T2aA"),
            (ecdsa256, "ecdsa-sha2-nistp256", "SHA256:GXnLq8fgk0dAI4/+Xx+OKSlBO2iH1PfqXecB408YnA4"),
            (ecdsa384, "ecdsa-sha2-nistp384", "SHA256:o/5Xcf4a8JOVIXSeMezKiZFADBVb7t+2yw9YwlUsWJw"),
            (ecdsa521, "ecdsa-sha2-nistp521", "SHA256:6aIK7bL5NnJ8zj24mzl3d+YEyZpY/oNQjkcozy2aeb4"),
            (rsa2048, "ssh-rsa", "SHA256:G9tgFNA0fR+pEqZVG0KK+hSeZV+iVbJyOQ/Ht9Y1EBY"),
            (securityKey, "sk-ssh-ed25519@openssh.com", "SHA256:nX0hpi5mKbTIJ10yBq5/sLQhiI1Y0RBAqN0drDdgJWs"),
        ]
        for (text, type, fingerprint) in expected {
            let key = try SshKeyRules.parse(text)
            XCTAssertEqual(key.type, type)
            XCTAssertEqual(key.fingerprint, fingerprint, type)
            XCTAssertEqual(key.line, text, "a good key is stored exactly as pasted")
        }
    }

    func testTheCommentIsOptional() throws {
        let key = try SshKeyRules.parse("ssh-ed25519 \(ed25519Blob)")
        XCTAssertEqual(key.comment, "")
        XCTAssertEqual(key.line, "ssh-ed25519 \(ed25519Blob)")
    }

    func testAnEightHundredCharacterLineIsTheLimit() throws {
        XCTAssertLessThanOrEqual(ecdsa521.count, SshKeyRules.maxLineCharacters)
        let long = "ssh-ed25519 \(ed25519Blob) " + String(repeating: "a", count: SshKeyRules.maxCommentCharacters)
        XCTAssertEqual(try SshKeyRules.parse(long).comment.count, SshKeyRules.maxCommentCharacters)
        XCTAssertTrue(refusal(long + String(repeating: "a", count: SshKeyRules.maxLineCharacters)).contains("too long"))
    }

    // MARK: options and injection

    func testOptionsInFrontOfTheKeyAreRefusedWithAMessageThatSaysSo() {
        for option in ["command=\"touch /tmp/x\"", "from=\"10.0.0.1\"", "restrict", "permitopen=\"a:1\"", "no-pty", "environment=\"A=b\"", "command=\"x\",no-pty"] {
            let message = refusal("\(option) \(ed25519)")
            XCTAssertTrue(message.contains("Options") && message.contains("not allowed"), "\(option): \(message)")
        }
    }

    func testALineBreakNulOrAnyControlCharacterIsRefused() {
        let breaks = ["\n", "\r", "\r\n", "\u{0}", "\t", "\u{1b}", "\u{7f}"]
        for control in breaks {
            XCTAssertTrue(refusal(ed25519 + control).contains("single line"), "trailing \(control.unicodeScalars.map(\.value))")
            XCTAssertTrue(refusal(ed25519 + control + "ssh-ed25519 \(ed25519Blob) second").contains("single line"))
        }
        XCTAssertTrue(refusal("ssh-ed25519 \(ed25519Blob) a\ncommand=\"x\" ssh-ed25519 \(ed25519Blob)").contains("single line"))
    }

    func testSpacesQuotesAndOtherOddCharactersInTheCommentOrAroundTheKeyAreRefusedNotCleaned() {
        let base = "ssh-ed25519 \(ed25519Blob)"
        for text in ["\(base) two words", "\(base) a b c", "\(base)  double", "\(base) ", " \(base)", "ssh-ed25519  \(ed25519Blob)", "\(base) \"quoted\"", "\(base) it's", "\(base) a,b", "\(base) a;b",
                     "\(base) a#b", "\(base) $(id)", "\(base) `id`", "\(base) a\\b", "\(base) é", "\(base) a/b", "\(base) a=b", "\(base) \(String(repeating: "x", count: 65))"] {
            XCTAssertFalse(refusal(text).isEmpty, text)
        }
        XCTAssertTrue(refusal("\(base) a b").contains("comment"))
    }

    func testAnEmptyOrLoneWordIsRefused() {
        for text in ["", " ", "ssh-ed25519", "ssh-ed25519 ", "AAAA"] { XCTAssertFalse(refusal(text).isEmpty, text) }
    }

    // MARK: not the key it says it is

    func testAnUnsupportedKeyTypeIsRefusedInPlainWords() {
        for type in ["ssh-dss", "ssh-ed448", "ecdsa-sha2-nistp192", "sk-ecdsa-sha2-nistp256@openssh.com"] {
            let message = refusal("\(type) \(ed25519Blob) x")
            XCTAssertTrue(message.contains("not supported"), "\(type): \(message)")
        }
    }

    func testABlobThatDoesNotStartWithTheDeclaredTypeIsRefused() {
        XCTAssertTrue(refusal("ecdsa-sha2-nistp256 \(ed25519Blob) x").contains("does not match"))
        XCTAssertTrue(refusal("ssh-rsa \(ed25519Blob) x").contains("does not match"))
        let rsaBlob = rsa2048.split(separator: " ")[1]
        XCTAssertTrue(refusal("ssh-ed25519 \(rsaBlob) x").contains("does not match"))
    }

    func testGarbageBase64AndDamagedBlobsAreRefused() {
        XCTAssertTrue(refusal("ssh-ed25519 not-base64!! x").contains("base64"))
        XCTAssertTrue(refusal("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII8umVmLJjfBjjgpC+plmhdOMZ7oWp0XKj9P6E5rrdC x").contains("base64"), "missing padding")
        XCTAssertTrue(refusal("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII8umVmLJjfBjjgpC+plmhdOMZ7oWp0XKj9P6E5r x").contains("damaged"), "cut short")
        XCTAssertTrue(refusal("ssh-ed25519 AAAAAAAA x").contains("damaged"))
        XCTAssertTrue(refusal("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 x").contains("damaged"), "a type and nothing else")
        XCTAssertTrue(refusal("ssh-ed25519 \(ed25519Blob)AAAA x").contains("damaged"), "bytes left over after the last field")
    }

    func testARsaKeyUnder2048BitsIsRefused() {
        let message = refusal(rsa1024)
        XCTAssertTrue(message.contains("too weak") && message.contains("1024"), message)
    }

    // MARK: fingerprint

    func testTheFingerprintIsUnpaddedBase64OfTheSha256OfTheKeyBlob() throws {
        let blob = try XCTUnwrap(Data(base64Encoded: ed25519Blob))
        let fingerprint = SshKeyRules.fingerprint(of: blob)
        XCTAssertTrue(fingerprint.hasPrefix("SHA256:"))
        XCTAssertFalse(fingerprint.contains("="))
        XCTAssertEqual(fingerprint.count, "SHA256:".count + 43)
    }
}
