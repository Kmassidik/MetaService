import Foundation
import MSCore

/// The optional `hardware` of a helper's facts: what the machine is made of (the computer's make and model, each kind of CPU core, the drives), for the panel's spec rows.
/// Every part is optional, as a helper leaves out what it cannot read. The texts come from the machine, so they are cleaned like `cpu_model` (see CpuModelText):
/// a core type or a drive whose name cleans to nothing is dropped, and a report with nothing left in it is no report.
/// Kept as given: an absent part is left out of the JSON, not sent as null.
public struct HardwareReport: Equatable, Codable {
    /// One kind of CPU core. A chip with big and small cores has two.
    public struct CoreType: Equatable, Codable {
        public let name: String
        /// Physical cores of this kind over all sockets, threads not counted.
        public let cores: Int
        /// The highest clock these cores run at; nil when the helper does not say.
        public let maxMhz: Int?

        public init(name: String, cores: Int, maxMhz: Int? = nil) {
            self.name = name
            self.cores = cores
            self.maxMhz = maxMhz
        }

        static let keys: Set<String> = ["name", "cores", "max_mhz"]

        /// Nil when the name cleans to nothing.
        static func parse(_ object: StrictObject) throws -> CoreType? {
            let name = CpuModelText.clean(try object.string("name", maxLength: CpuModelText.maxIncoming))
            let cores = try object.int("cores", range: 1...100_000)
            let maxMhz = object.has("max_mhz") ? try object.int("max_mhz", range: 1...20_000) : nil
            return name.map { CoreType(name: $0, cores: cores, maxMhz: maxMhz) }
        }
    }

    /// One physical drive.
    public struct Disk: Equatable, Codable {
        public let model: String
        /// Decimal GB (10^9 bytes), as drives are sold.
        public let sizeGb: Int
        /// `nvme`, `ssd` or `hdd`.
        public let kind: String

        public init(model: String, sizeGb: Int, kind: String) {
            self.model = model
            self.sizeGb = sizeGb
            self.kind = kind
        }

        static let keys: Set<String> = ["model", "size_gb", "kind"]
        static let kinds: Set<String> = ["nvme", "ssd", "hdd"]

        /// Nil when the model cleans to nothing.
        static func parse(_ object: StrictObject) throws -> Disk? {
            let model = CpuModelText.clean(try object.string("model", maxLength: CpuModelText.maxIncoming))
            let sizeGb = try object.int("size_gb", range: 1...100_000_000)
            let kind = try object.choice("kind", among: kinds)
            return model.map { Disk(model: $0, sizeGb: sizeGb, kind: kind) }
        }
    }

    /// The make and model of the computer, for example NVIDIA DGX Spark.
    public let system: String?
    public let coreTypes: [CoreType]?
    /// Biggest first, as the helper lists them.
    public let disks: [Disk]?

    public init(system: String? = nil, coreTypes: [CoreType]? = nil, disks: [Disk]? = nil) {
        self.system = system
        self.coreTypes = coreTypes
        self.disks = disks
    }

    static let keys: Set<String> = ["system", "core_types", "disks"]
    static let maxItems = 8

    /// A helper that does not say it (or says null) gives nil, and so does one whose every text cleans to nothing.
    static func optional(_ object: StrictObject, _ key: String) throws -> HardwareReport? {
        guard object.has(key) else { return nil }
        let report = try HardwareReport(try object.object(key, allowed: keys))
        return report.system == nil && report.coreTypes == nil && report.disks == nil ? nil : report
    }

    init(_ object: StrictObject) throws {
        system = try CpuModelText.optional(object, "system")
        coreTypes = try Self.list(object, "core_types", allowed: CoreType.keys, CoreType.parse)
        disks = try Self.list(object, "disks", allowed: Disk.keys, Disk.parse)
    }

    /// One to eight items, as the contract says. A list whose every item was dropped is left out, never sent empty.
    private static func list<Item>(_ object: StrictObject, _ key: String, allowed: Set<String>, _ parse: (StrictObject) throws -> Item?) throws -> [Item]? {
        guard object.has(key) else { return nil }
        let items = try object.objects(key, allowed: allowed, maxCount: maxItems)
        guard !items.isEmpty else { throw InputError("facts/hardware/\(key) must not be empty") }
        let kept = try items.compactMap(parse)
        return kept.isEmpty ? nil : kept
    }
}
