import XCTest
import RootCore

final class MachineStateTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_800_000_000)

    func testMissingAndPreStartHeartbeatsArePendingWithinTheObservationWindow() {
        let heartbeats: [Date?] = [nil, started.addingTimeInterval(-60)]
        for lastSeen in heartbeats {
            let state = MachineStates.derive(lastSeen: lastSeen, now: started, workloadStates: [])
            XCTAssertEqual(state, .offline)
            XCTAssertTrue(MachineStates.statePending(lastSeen: lastSeen, now: started, observingSince: started, state: state))
        }
    }

    func testARecentPreStartHeartbeatKeepsItsExistingOnlineStateWithoutPending() {
        let lastSeen = started.addingTimeInterval(-1)
        let state = MachineStates.derive(lastSeen: lastSeen, now: started, workloadStates: [])
        XCTAssertEqual(state, .online)
        XCTAssertFalse(MachineStates.statePending(lastSeen: lastSeen, now: started, observingSince: started, state: state))
    }

    func testACurrentHeartbeatIsOnlineAndNotPending() {
        let lastSeen = started.addingTimeInterval(1)
        let state = MachineStates.derive(lastSeen: lastSeen, now: started.addingTimeInterval(2), workloadStates: [])
        XCTAssertEqual(state, .online)
        XCTAssertFalse(MachineStates.statePending(lastSeen: lastSeen, now: started.addingTimeInterval(2), observingSince: started, state: state))
    }

    func testTheDeadlineConfirmsOffline() {
        let deadline = started.addingTimeInterval(Double(MachineStates.observationSeconds))
        let state = MachineStates.derive(lastSeen: nil, now: deadline, workloadStates: [])
        XCTAssertEqual(state, .offline)
        XCTAssertFalse(MachineStates.statePending(lastSeen: nil, now: deadline, observingSince: started, state: state))
    }

    func testACurrentHeartbeatThatLaterGoesStaleIsOfflineNotPending() {
        let lastSeen = started.addingTimeInterval(1)
        let now = started.addingTimeInterval(Double(MachineStates.observationSeconds + 2))
        let state = MachineStates.derive(lastSeen: lastSeen, now: now, workloadStates: [])
        XCTAssertEqual(state, .offline)
        XCTAssertFalse(MachineStates.statePending(lastSeen: lastSeen, now: now, observingSince: started, state: state))
    }
}
