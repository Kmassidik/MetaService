import Foundation
import MSCore

/// What a Linux helper can offer for sandboxes, as `Facts.sandbox` in contract/openapi.yaml (see sandbox/README.md).
/// Only a helper whose `capabilities.sandbox` is true sends it; the Root drops it from a helper that says false.
public struct SandboxFacts: Equatable, Codable {
    /// The program that runs the sandboxes, with its version when it can tell. The version is never guessed.
    public struct Engine: Equatable, Codable {
        public let name: String
        public let version: String?

        static let names: Set<String> = ["firecracker"]
        static let keys: Set<String> = ["name", "version"]

        public init(name: String, version: String?) {
            self.name = name
            self.version = version
        }

        init(_ object: StrictObject) throws {
            name = try object.choice("name", among: Self.names)
            version = try ReportedVersion.optional(object, "version")
        }

        enum CodingKeys: String, CodingKey { case name, version }

        /// A missing version is sent as null, so the shape never changes.
        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(name, forKey: .name)
            try box.encode(version, forKey: .version)
        }
    }

    /// What the sandboxes hold: vCPU and memory of the running ones, disk of all of them (paused ones included).
    public struct Booking: Equatable, Codable {
        public let vcpu: Int
        public let ramMb: Int
        public let diskMb: Int

        public init(vcpu: Int, ramMb: Int, diskMb: Int) {
            self.vcpu = vcpu
            self.ramMb = ramMb
            self.diskMb = diskMb
        }

        static let keys: Set<String> = ["vcpu", "ram_mb", "disk_mb"]

        init(_ object: StrictObject) throws {
            vcpu = try object.int("vcpu", range: SandboxFacts.countRange)
            ramMb = try object.int("ram_mb", range: SandboxFacts.countRange)
            diskMb = try object.int("disk_mb", range: SandboxFacts.countRange)
        }
    }

    /// One template built on this machine, and whether a sandbox can be made from it.
    public struct Template: Equatable, Codable {
        public let id: String
        public let build: String
        public let ready: Bool

        public init(id: String, build: String, ready: Bool) {
            self.id = id
            self.build = build
            self.ready = ready
        }

        static let keys: Set<String> = ["id", "build", "ready"]
        static let idPattern = #/^[a-z0-9][a-z0-9-]{0,62}$/#
        static let buildPattern = #/^[a-z0-9]{1,32}$/#

        init(_ object: StrictObject) throws {
            id = try object.string("id", pattern: Self.idPattern, maxLength: 63, minLength: 1)
            build = try object.string("build", pattern: Self.buildPattern, maxLength: 32, minLength: 1)
            ready = try object.bool("ready")
        }
    }

    public let engine: Engine
    public let maxRunning: Int
    public let running: Int
    public let paused: Int
    public let maxVcpu: Int
    public let maxRamMb: Int
    public let maxDiskMb: Int
    public let booked: Booking
    public let templates: [Template]
    /// The number of the last sandbox event. When it moves, the Root reads the helper's sandbox events.
    public let changes: Int

    static let keys: Set<String> = ["engine", "max_running", "running", "paused", "max_vcpu", "max_ram_mb", "max_disk_mb", "booked", "templates", "changes"]
    static let maxTemplates = 64
    /// A count a helper reports: never negative, and capped so a broken helper cannot send anything wild.
    static let countRange = 0...100_000_000
    private static let maxVcpuRange = 1...100_000
    private static let maxRamRange = 256...100_000_000
    private static let maxDiskRange = 512...100_000_000

    public init(engine: Engine, maxRunning: Int, running: Int, paused: Int, maxVcpu: Int, maxRamMb: Int, maxDiskMb: Int,
                booked: Booking, templates: [Template], changes: Int) {
        self.engine = engine
        self.maxRunning = maxRunning
        self.running = running
        self.paused = paused
        self.maxVcpu = maxVcpu
        self.maxRamMb = maxRamMb
        self.maxDiskMb = maxDiskMb
        self.booked = booked
        self.templates = templates
        self.changes = changes
    }

    init(_ object: StrictObject) throws {
        engine = try Engine(object.object("engine", allowed: Engine.keys))
        maxRunning = try object.int("max_running", range: Self.countRange)
        running = try object.int("running", range: Self.countRange)
        paused = try object.int("paused", range: Self.countRange)
        maxVcpu = try object.int("max_vcpu", range: Self.maxVcpuRange)
        maxRamMb = try object.int("max_ram_mb", range: Self.maxRamRange)
        maxDiskMb = try object.int("max_disk_mb", range: Self.maxDiskRange)
        booked = try Booking(object.object("booked", allowed: Booking.keys))
        templates = try object.objects("templates", allowed: Template.keys, maxCount: Self.maxTemplates).map(Template.init)
        changes = try object.int("changes", range: Self.countRange)
    }
}
