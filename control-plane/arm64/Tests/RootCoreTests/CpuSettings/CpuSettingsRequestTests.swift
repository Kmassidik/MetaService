import XCTest
@testable import RootCore

final class CpuSettingsRequestTests: XCTestCase {
    private func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    private func create(_ kind: String = "vm", _ change: (inout [String: Any]) -> Void = { _ in }) throws -> CreateWorkloadOperatorRequest {
        var body: [String: Any] = ["name": "demo", "kind": kind, "cpu": 4, "ram_mb": 2048, "disk_gb": 20]
        change(&body)
        return try CreateWorkloadOperatorRequest(body: data(body))
    }

    func testAVmReadsItsSocketsTypeAndFlags() throws {
        let request = try create { $0["cpu_sockets"] = 2; $0["cpu_type"] = "EPYC-Genoa"; $0["cpu_flags"] = ["nested-virt": "on", "aes": "off"] }
        XCTAssertEqual(request.cpuSockets, 2)
        XCTAssertEqual(request.cpuType, "EPYC-Genoa")
        XCTAssertEqual(request.cpuFlags, ["nested-virt": "on", "aes": "off"])
        XCTAssertNil(request.cpuLimitPercent)
        XCTAssertEqual(try create { $0["cpu"] = 64; $0["cpu_sockets"] = 8 }.cpuSockets, 8)
        XCTAssertEqual(try create { $0["cpu_type"] = "Skylake-Server-v4.1_x" }.cpuType, "Skylake-Server-v4.1_x")
        XCTAssertEqual(try create { $0["cpu_type"] = String(repeating: "a", count: 40) }.cpuType?.count, 40)
        XCTAssertEqual(try create { $0["cpu_flags"] = ["aes": "on"] }.cpuFlags, ["aes": "on"], "one flag is enough")
    }

    func testOneSocketAndTheHostTypeAreTheSameWishAsSayingNothing() throws {
        let defaults = try create { $0["cpu_sockets"] = 1; $0["cpu_type"] = "host" }
        XCTAssertNil(defaults.cpuSockets)
        XCTAssertNil(defaults.cpuType)
        XCTAssertEqual(defaults, try create())
        XCTAssertEqual(try create { $0["cpu_sockets"] = NSNull(); $0["cpu_type"] = NSNull(); $0["cpu_flags"] = NSNull() }, try create())
        XCTAssertNil(try create().cpuFlags, "no flags asked: the CPU type decides")
    }

    func testAContainerReadsALimitOfAtMostAllItsCores() throws {
        XCTAssertEqual(try create("container") { $0["cpu_limit_percent"] = 150 }.cpuLimitPercent, 150)
        XCTAssertEqual(try create("container") { $0["cpu_limit_percent"] = 10 }.cpuLimitPercent, 10)
        XCTAssertEqual(try create("container") { $0["cpu_limit_percent"] = 400 }.cpuLimitPercent, 400, "4 CPUs: 400 is all of them")
        XCTAssertEqual(try create("container") { $0["cpu"] = 64; $0["cpu_limit_percent"] = 6400 }.cpuLimitPercent, 6400)
        XCTAssertNil(try create("container").cpuLimitPercent, "no limit asks for no cap")
        XCTAssertNil(try create("container") { $0["cpu_limit_percent"] = NSNull() }.cpuLimitPercent)
        XCTAssertThrowsError(try create("container") { $0["cpu_limit_percent"] = 401 }) {
            XCTAssertEqual(($0 as? InputError)?.message, "cpu_limit_percent can be at most cpu x 100")
        }
    }

    func testValuesOutOfRangeOrOfTheWrongTypeAreRefused() {
        for bad: Any in [0, -1, 9, 2.5, "2", true] {
            XCTAssertThrowsError(try create { $0["cpu"] = 8; $0["cpu_sockets"] = bad }, "sockets \(bad)")
        }
        for bad: Any in ["", "-host", ".x", "EPYC Genoa", "EPYC/Genoa", "EPYC:Genoa", "épyc", String(repeating: "a", count: 41), 5, true, ["host"]] {
            XCTAssertThrowsError(try create { $0["cpu_type"] = bad }, "type \(bad)")
        }
        for bad: Any in [[String: Any](), ["md-clear": "on"], ["aes": "yes"], ["aes": "ON"], ["aes": true], ["aes": NSNull()], ["aes": "on", "pcid": "on"], "aes", ["aes"]] {
            XCTAssertThrowsError(try create { $0["cpu_flags"] = bad }, "flags \(bad)")
        }
        for bad: Any in [0, 9, -150, 6401, 150.5, "150", true] {
            XCTAssertThrowsError(try create("container") { $0["cpu"] = 64; $0["cpu_limit_percent"] = bad }, "limit \(bad)")
        }
        XCTAssertThrowsError(try create { $0["cpu_flags"] = [String: Any]() }) { XCTAssertEqual(($0 as? InputError)?.message, "cpu_flags must name at least one flag") }
        XCTAssertThrowsError(try create { $0["cpu_flags"] = ["md-clear": "on"] }) { XCTAssertEqual(($0 as? InputError)?.message, "unknown field cpu_flags/md-clear") }
    }

    func testAFieldOnTheWrongKindIsRefusedInPlainWords() {
        let vmOnly: [(String, Any)] = [("cpu_sockets", 2), ("cpu_type", "EPYC-Genoa"), ("cpu_flags", ["aes": "on"])]
        for (field, value) in vmOnly {
            XCTAssertThrowsError(try create("container") { $0[field] = value }) {
                XCTAssertEqual(($0 as? InputError)?.message, "\(field) can only be set when kind is vm")
            }
        }
        XCTAssertThrowsError(try create("container") { $0["cpu_sockets"] = 1 }, "the default is still a field on the wrong kind")
        XCTAssertThrowsError(try create("container") { $0["cpu_type"] = "host" })
        XCTAssertThrowsError(try create { $0["cpu_limit_percent"] = 150 }) {
            XCTAssertEqual(($0 as? InputError)?.message, "cpu_limit_percent can only be set when kind is container")
        }
    }

    func testTheCoresMustSplitEvenlyOverTheSockets() throws {
        XCTAssertEqual(try create { $0["cpu"] = 6; $0["cpu_sockets"] = 3 }.cpuSockets, 3)
        XCTAssertEqual(try create { $0["cpu"] = 8; $0["cpu_sockets"] = 8 }.cpuSockets, 8, "one core on each socket")
        for (cpu, sockets) in [(6, 4), (1, 2), (3, 2), (64, 7)] {
            XCTAssertThrowsError(try create { $0["cpu"] = cpu; $0["cpu_sockets"] = sockets }, "\(cpu) on \(sockets)") {
                XCTAssertEqual(($0 as? InputError)?.message, "cpu must be a multiple of cpu_sockets")
            }
        }
    }

    func testTheSettingsSurvivePlacingTheRequestOnAMachine() throws {
        func vm(on machine: String?) throws -> CreateWorkloadOperatorRequest {
            try create { $0["machine"] = machine; $0["cpu_sockets"] = 2; $0["cpu_type"] = "EPYC-Genoa"; $0["cpu_flags"] = ["nested-virt": "off"] }
        }
        XCTAssertEqual(try vm(on: nil).placed(on: "dgx"), try vm(on: "dgx"))
        XCTAssertEqual(try create("container") { $0["cpu_limit_percent"] = 150 }.placed(on: "dgx").cpuLimitPercent, 150)
    }

    func testTheHelperCreateBodyCarriesOnlyWhatDiffersFromBefore() throws {
        let vm = HelperCreateBody.make(commandId: "rc-1", request: try create { $0["cpu_sockets"] = 2; $0["cpu_type"] = "EPYC-Genoa"; $0["cpu_flags"] = ["nested-virt": "on", "aes": "off"] },
                                       machineDefaultImage: nil)
        XCTAssertEqual(vm["cpu_sockets"] as? Int, 2)
        XCTAssertEqual(vm["cpu_type"] as? String, "EPYC-Genoa")
        XCTAssertEqual(vm["cpu_flags"] as? [String: String], ["nested-virt": "on", "aes": "off"])
        XCTAssertNil(vm["cpu_limit_percent"])
        let sent = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: vm)) as? [String: Any])
        XCTAssertEqual(sent["cpu_flags"] as? [String: String], ["nested-virt": "on", "aes": "off"], "the flags go as the contract's object")
        let today: Set<String> = ["command_id", "name", "kind", "cpu", "ram_mb", "disk_gb", "gpu_mode"]
        let container = HelperCreateBody.make(commandId: "rc-1", request: try create("container") { $0["cpu_limit_percent"] = 150 }, machineDefaultImage: nil)
        XCTAssertEqual(container["cpu_limit_percent"] as? Int, 150)
        XCTAssertEqual(Set(container.keys), today.union(["cpu_limit_percent"]))
        let defaults = HelperCreateBody.make(commandId: "rc-1", request: try create { $0["cpu_sockets"] = 1; $0["cpu_type"] = "host" }, machineDefaultImage: nil)
        XCTAssertEqual(Set(defaults.keys), today, "one socket and the host CPU are what every VM got before")
    }

    func testTheAuditShowsTheFlagsByName() {
        XCTAssertEqual(CpuSettings.flagsText(["nested-virt": "on", "aes": "off"]), "aes off, nested-virt on")
        XCTAssertEqual(CpuSettings.flagsText(["aes": "on"]), "aes on")
    }

    // MARK: what the helper offers

    private func offer(_ capabilities: [String: Any] = [:]) throws -> Capabilities {
        var caps: [String: Any] = ["vm": true, "container": true, "gpu_in_vm": false, "gpu_in_container": false]
        caps.merge(capabilities) { $1 }
        let facts: [String: Any] = ["os": "linux", "arch": "x86_64", "cpu_cores": 16, "ram_total_mb": 65536, "disk_total_gb": 1000, "free_ram_mb": 60000, "free_disk_gb": 900,
                                    "gpu": [], "capabilities": caps]
        return try HeartbeatRequest(body: data(["facts": facts, "workloads": []])).facts.capabilities
    }

    func testTheHelperSaysWhichCpuSettingsItOffers() throws {
        let caps = try offer(["cpu_models": ["host", "EPYC-Genoa", "kvm64"], "cpu_topology": true, "cpu_flags": ["nested-virt", "aes"], "cpu_limit": true])
        XCTAssertEqual(caps.cpuModels, ["host", "EPYC-Genoa", "kvm64"])
        XCTAssertTrue(caps.cpuTopology)
        XCTAssertEqual(caps.cpuFlags, ["nested-virt", "aes"])
        XCTAssertTrue(caps.cpuLimit)
        XCTAssertEqual(try offer(["cpu_models": (0..<64).map { "model-\($0)" }]).cpuModels.count, 64, "64 models is the most")
        XCTAssertEqual(try offer(["cpu_flags": [String]()]).cpuFlags, [])
        XCTAssertFalse(try offer(["cpu_topology": false, "cpu_limit": false]).cpuTopology)
    }

    func testAHelperThatDoesNotSayOffersTheHostCpuOnOneSocketAndNothingElse() throws {
        for caps in [try offer(), try offer(["cpu_models": NSNull(), "cpu_topology": NSNull(), "cpu_flags": NSNull(), "cpu_limit": NSNull()])] {
            XCTAssertEqual(caps.cpuModels, ["host"])
            XCTAssertFalse(caps.cpuTopology)
            XCTAssertEqual(caps.cpuFlags, [])
            XCTAssertFalse(caps.cpuLimit)
        }
    }

    func testBrokenOffersAreRefused() {
        let bad: [[String: Any]] = [
            ["cpu_models": "host"], ["cpu_models": [5]], ["cpu_models": ["EPYC Genoa"]], ["cpu_models": ["-host"]], ["cpu_models": [String(repeating: "a", count: 41)]],
            ["cpu_models": (0..<65).map { "model-\($0)" }], ["cpu_models": ["host", "EPYC-Genoa", "host"]],
            ["cpu_topology": "yes"], ["cpu_topology": 1], ["cpu_limit": "true"], ["cpu_limit": 0],
            ["cpu_flags": ["md-clear"]], ["cpu_flags": ["AES"]], ["cpu_flags": ["aes", "aes"]], ["cpu_flags": (0..<9).map { _ in "aes" }], ["cpu_flags": "aes"], ["cpu_flags": [true]],
            ["cpu_flags": ["aes": true]], ["cpu_sockets": true],
        ]
        for item in bad { XCTAssertThrowsError(try offer(item), "\(item)") }
        XCTAssertThrowsError(try offer(["cpu_flags": ["md-clear"]])) { XCTAssertEqual(($0 as? InputError)?.message, "facts/capabilities/cpu_flags may only list nested-virt and aes") }
        XCTAssertThrowsError(try offer(["cpu_models": ["host", "host"]])) { XCTAssertEqual(($0 as? InputError)?.message, "facts/capabilities/cpu_models must be different from each other") }
    }

    private let offered = Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false, cpuModels: ["host", "EPYC-Genoa"], cpuTopology: true, cpuFlags: ["aes"], cpuLimit: true)

    func testSavedCapabilitiesFromBeforeTheCpuSettingsStillRead() throws {
        let old = Data(#"{"vm":true,"container":true,"gpuInVm":false,"gpuInContainer":true,"gpuMemoryLimit":true}"#.utf8)
        let caps = try JSONDecoder().decode(Capabilities.self, from: old)
        XCTAssertTrue(caps.gpuMemoryLimit)
        XCTAssertEqual(caps.cpuModels, ["host"])
        XCTAssertFalse(caps.cpuTopology)
        XCTAssertEqual(caps.cpuFlags, [])
        XCTAssertFalse(caps.cpuLimit)
        XCTAssertEqual(try JSONDecoder().decode(Capabilities.self, from: JSONEncoder().encode(offered)), offered, "what is saved reads back the same")
    }

    func testThePanelGetsTheOfferUnderTheContractsNames() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoder.encode(offered)) as? [String: Any])
        XCTAssertEqual(json["cpu_models"] as? [String], ["host", "EPYC-Genoa"])
        XCTAssertEqual(json["cpu_topology"] as? Bool, true)
        XCTAssertEqual(json["cpu_flags"] as? [String], ["aes"])
        XCTAssertEqual(json["cpu_limit"] as? Bool, true)
    }

    func testSwitchingTheGpuOffKeepsTheCpuOffer() throws {
        let all = Capabilities(vm: true, container: true, gpuInVm: true, gpuInContainer: true, gpuMemoryLimit: true, cpuModels: ["host", "EPYC-Genoa"], cpuTopology: true,
                               cpuFlags: ["nested-virt"], cpuLimit: true)
        XCTAssertEqual(MachineSettings(allowGpu: false).limiting(all),
                       Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false, gpuMemoryLimit: true, cpuModels: ["host", "EPYC-Genoa"], cpuTopology: true,
                                    cpuFlags: ["nested-virt"], cpuLimit: true))
    }

    // MARK: placement

    private let oldHelper = Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false)
    private let everything = Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false, cpuModels: ["host", "EPYC-Genoa", "kvm64"], cpuTopology: true,
                                          cpuFlags: ["nested-virt", "aes"], cpuLimit: true)

    private func machine(_ id: String, _ caps: Capabilities, ram: Int = 8192) -> PlacementMachine {
        PlacementMachine(id: id, online: true, capabilities: caps, freeRamMb: ram, freeDiskGb: 500)
    }

    private func wish(_ kind: String = "vm", sockets: Int? = nil, type: String? = nil, flags: [String: String]? = nil, limit: Int? = nil, only: String? = nil,
                      ram: Int = 1024) -> PlacementWish {
        PlacementWish(kind: kind, gpuMode: "none", ramMb: ram, diskGb: 10, onlyMachine: only, cpuSockets: sockets, cpuType: type, cpuFlags: flags, cpuLimitPercent: limit)
    }

    func testAPlacementSkipsMachinesThatCannotGiveTheCpuSettings() throws {
        let pool = [machine("big", oldHelper, ram: 99999), machine("small", everything, ram: 4096)]
        for asked in [wish(sockets: 2), wish(type: "EPYC-Genoa"), wish(flags: ["nested-virt": "off"]), wish("container", limit: 150)] {
            XCTAssertEqual(try Placement.choose(pool, asked), "small", "\(asked)")
        }
        XCTAssertEqual(try Placement.choose(pool, wish()), "big", "nothing asked: the offer is not looked at")
        XCTAssertEqual(try Placement.choose(pool, wish(sockets: 1, type: "host")), "big", "one socket and the host CPU are what every machine gives")
    }

    func testWhenNoMachineCanGiveASettingTheRefusalSaysWhatIsMissingAndWhatToDo() {
        let cases: [(PlacementWish, String)] = [
            (wish(sockets: 2), "This machine cannot give a VM more than one socket. Update its helper, or pick 1 socket."),
            (wish(type: "EPYC-Genoa"), "This machine cannot set the CPU type EPYC-Genoa. Update its helper, or pick host."),
            (wish(flags: ["nested-virt": "on"]), "This machine cannot switch the nested-virt flag. Update its helper, or leave the flag on Default."),
            (wish("container", limit: 150), "This machine cannot cap a container's CPU time. Update its helper, or leave the CPU limit empty."),
        ]
        for (asked, message) in cases {
            XCTAssertThrowsError(try Placement.choose([machine("old", oldHelper)], asked)) {
                XCTAssertEqual($0 as? PlacementRefusal, PlacementRefusal(code: "missing_capability", message: message, resource: "capability", needed: 1, free: 0))
            }
        }
    }

    func testAModelOrFlagTheMachineDoesNotListIsRefusedEvenWhenItOffersOthers() {
        let amd = machine("amd", Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false, cpuModels: ["host", "EPYC-Genoa"], cpuTopology: true, cpuFlags: ["aes"]))
        XCTAssertNoThrow(try Placement.choose([amd], wish(sockets: 4, type: "EPYC-Genoa", flags: ["aes": "on"])))
        XCTAssertThrowsError(try Placement.choose([amd], wish(type: "Skylake-Server"))) {
            XCTAssertEqual(($0 as? PlacementRefusal)?.message, "This machine cannot set the CPU type Skylake-Server. Update its helper, or pick host.")
        }
        XCTAssertThrowsError(try Placement.choose([amd], wish(flags: ["aes": "on", "nested-virt": "off"]))) {
            XCTAssertEqual(($0 as? PlacementRefusal)?.message, "This machine cannot switch the nested-virt flag. Update its helper, or leave the flag on Default.")
        }
        XCTAssertThrowsError(try Placement.choose([amd], wish(type: "epyc-genoa")), "a model is matched exactly as the helper names it")
    }

    func testWhenNoMachineCanTheFirstMachinesReasonByNameIsTheAnswer() {
        let noSockets = machine("b", Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false, cpuModels: ["host", "EPYC-Genoa"]))
        let noModel = machine("a", Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false, cpuTopology: true))
        XCTAssertThrowsError(try Placement.choose([noSockets, noModel], wish(sockets: 2, type: "EPYC-Genoa"))) {
            XCTAssertEqual(($0 as? PlacementRefusal)?.message, "This machine cannot set the CPU type EPYC-Genoa. Update its helper, or pick host.")
        }
        XCTAssertEqual(try Placement.choose([noSockets, noModel, machine("c", everything, ram: 1024)], wish(sockets: 2, type: "EPYC-Genoa")), "c")
        XCTAssertThrowsError(try Placement.choose([noSockets, noModel, machine("c", everything)], wish(sockets: 2, only: "b"))) {
            XCTAssertEqual(($0 as? PlacementRefusal)?.code, "missing_capability", "a named machine is the only one asked")
        }
    }

    func testAShortageCountsOnlyTheMachinesThatOfferTheCpuSettings() {
        let pool = [machine("big", oldHelper, ram: 99999), machine("small", everything, ram: 2048)]
        XCTAssertThrowsError(try Placement.choose(pool, wish(sockets: 2, ram: 4096))) {
            XCTAssertEqual($0 as? PlacementRefusal, PlacementRefusal(code: "not_enough_room", message: "not enough RAM", resource: "ram_mb", needed: 4096, free: 2048))
        }
    }

    func testAMissingKindIsStillTheAnswerBeforeTheCpuSettings() {
        let mac = machine("mac", Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false))
        XCTAssertThrowsError(try Placement.choose([mac], wish("container", limit: 150))) {
            XCTAssertEqual(($0 as? PlacementRefusal)?.message, "no machine can run a container")
        }
    }
}
