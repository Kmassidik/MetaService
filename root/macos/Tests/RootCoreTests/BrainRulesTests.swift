import XCTest
@testable import RootCore

final class BrainRulesTests: XCTestCase {
    func testOnlySafeProviderAddressesAreAccepted() {
        for good in ["https://api.example.com/v1", "https://api.example.com", "http://127.0.0.1:8000/v1", "http://192.168.1.20:11434/v1", "http://localhost:9000/v1"] {
            XCTAssertTrue(BrainRules.isAcceptableBaseURL(good), good)
        }
        for bad in ["http://api.example.com/v1", "file:///etc/passwd", "ftp://x.example.com", "https://user:pw@api.example.com/v1", "https://api.example.com/v1?key=1",
                    "https://api.example.com/v1#frag", "nonsense", "", "http://8.8.8.8/v1"] {
            XCTAssertFalse(BrainRules.isAcceptableBaseURL(bad), bad)
        }
    }

    func testTheCompletionsAddressIsTheBaseWithOneSlash() {
        XCTAssertEqual(BrainRules.completionsURL(base: "https://a.example/v1")?.absoluteString, "https://a.example/v1/chat/completions")
        XCTAssertEqual(BrainRules.completionsURL(base: "https://a.example/v1/")?.absoluteString, "https://a.example/v1/chat/completions")
    }

    func testTheUpstreamRequestHoldsOneUserMessageTheFixedModelAndTheTokenLimit() throws {
        let data = try BrainRules.upstreamBody(message: "hi \"there\"", model: "m-1", maxTokens: 300)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["model", "max_tokens", "stream", "messages"])
        XCTAssertEqual(object["model"] as? String, "m-1")
        XCTAssertEqual(object["max_tokens"] as? Int, 300)
        XCTAssertEqual(object["stream"] as? Bool, false)
        XCTAssertEqual((object["messages"] as? [[String: String]]) ?? [], [["role": "user", "content": "hi \"there\""]])
    }

    func testAReplyIsReadFromTheFirstChoiceWithTheProvidersTokenCounts() throws {
        let reply = #"{"choices":[{"message":{"role":"assistant","content":"hello"}},{"message":{"content":"ignored"}}],"usage":{"prompt_tokens":12,"completion_tokens":3,"extra":1}}"#
        XCTAssertEqual(BrainRules.parseReply(Data(reply.utf8)), BrainAnswer(text: "hello", promptTokens: 12, completionTokens: 3))
    }

    func testMissingOrOddUsageCountsAsZeroAndAnOverlongReplyIsCut() throws {
        let odd = #"{"choices":[{"message":{"content":"x"}}],"usage":{"prompt_tokens":-5,"completion_tokens":"many"}}"#
        XCTAssertEqual(BrainRules.parseReply(Data(odd.utf8)), BrainAnswer(text: "x", promptTokens: 0, completionTokens: 0))
        let long = String(repeating: "a", count: BrainRules.maxReplyCharacters + 50)
        let cut = BrainRules.parseReply(Data(#"{"choices":[{"message":{"content":"\#(long)"}}]}"#.utf8))
        XCTAssertEqual(cut?.text.count, BrainRules.maxReplyCharacters)
    }

    func testRepliesWithoutTextAreRefused() {
        for bad in ["", "[]", "{}", #"{"choices":[]}"#, #"{"choices":[{"message":{"content":""}}]}"#, #"{"choices":[{"message":{"content":5}}]}"#, #"{"choices":[{"message":{}}]}"#] {
            XCTAssertNil(BrainRules.parseReply(Data(bad.utf8)), bad)
        }
    }
}
