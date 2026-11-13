import XCTest
@testable import RootCore

final class OfficeSettingsTests: XCTestCase {
    private let secret = "office-test-secret-7731"

    private func env(host: String? = "192.0.2.1", indexes: String? = "19,20", interval: String? = nil) -> [String: String] {
        var values = [OfficeSnmpSettings.communityKey: secret]
        values[OfficeSnmpSettings.hostKey] = host
        values[OfficeSnmpSettings.wanIndexesKey] = indexes
        values[OfficeSnmpSettings.intervalKey] = interval
        return values.compactMapValues { $0 }
    }

    func testOfficeSettingsGoodValuesAreConfigured() throws {
        let settings = try OfficeSnmpSettings.parse(env(interval: "120"))
        XCTAssertEqual(settings.host, "192.0.2.1")
        XCTAssertEqual(settings.wanIndexes, [19, 20])
        XCTAssertEqual(settings.intervalSeconds, 120)
        XCTAssertNotNil(settings.target)
    }

    func testOfficeSettingsDefaultIntervalIsSixtySeconds() throws {
        XCTAssertEqual(try OfficeSnmpSettings.parse(env()).intervalSeconds, 60)
    }

    func testOfficeSettingsHostNameOrIPv6CountsAsNotSet() throws {
        XCTAssertNil(try OfficeSnmpSettings.parse(env(host: "router.example.com")).host)
        XCTAssertNil(try OfficeSnmpSettings.parse(env(host: "::1")).host)
    }

    func testOfficeSettingsMissingHostIsNotConfigured() throws {
        XCTAssertNil(try OfficeSnmpSettings.parse(env(host: nil)).target)
    }

    func testOfficeSettingsBadIndexesAreSkipped() throws {
        XCTAssertEqual(try OfficeSnmpSettings.parse(env(indexes: "x, 0, -1, 1.5, 7")).wanIndexes, [7])
        XCTAssertNil(try OfficeSnmpSettings.parse(env(indexes: "x,0")).target)
    }

    func testOfficeSettingsIndexesAreDeduplicatedAndCappedAtEight() throws {
        XCTAssertEqual(try OfficeSnmpSettings.parse(env(indexes: "3,3,4")).wanIndexes, [3, 4])
        let many = (1...10).map(String.init).joined(separator: ",")
        XCTAssertEqual(try OfficeSnmpSettings.parse(env(indexes: many)).wanIndexes.count, 8)
    }

    func testOfficeSettingsIntervalLimitsAreTenToSixHundred() throws {
        XCTAssertEqual(try OfficeSnmpSettings.parse(env(interval: "10")).intervalSeconds, 10)
        XCTAssertEqual(try OfficeSnmpSettings.parse(env(interval: "600")).intervalSeconds, 600)
        XCTAssertThrowsError(try OfficeSnmpSettings.parse(env(interval: "9")))
        XCTAssertThrowsError(try OfficeSnmpSettings.parse(env(interval: "601")))
        XCTAssertThrowsError(try OfficeSnmpSettings.parse(env(interval: "soon")))
    }

    func testOfficeSettingsDescriptionNeverShowsTheCommunity() throws {
        let settings = try OfficeSnmpSettings.parse(env())
        XCTAssertFalse(settings.description.contains(secret))
        XCTAssertTrue(settings.description.contains("community: set"))
    }

    func testOfficeSettingsRefusalMessageNeverEchoesTheInput() {
        XCTAssertThrowsError(try OfficeSnmpSettings.parse(env(interval: secret))) { error in
            XCTAssertFalse(String(describing: error).contains(secret))
        }
    }
}
