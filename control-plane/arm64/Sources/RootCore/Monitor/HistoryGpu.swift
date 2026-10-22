import Foundation

/// One GPU's numbers inside a history point. `index` is the GPU's place in the reading's `gpus` list, so a line keeps its name when another GPU has a gap.
/// A number the helper did not give is left out of the point (a gap), never 0.
public struct HistoryGpu: Codable, Equatable, Sendable {
    public var index: Int
    public var utilizationPercent: Double?
    public var memoryUsedBytes: Int?
    public var temperatureCelsius: Double?
    public var powerWatts: Double?

    public init(index: Int, utilizationPercent: Double? = nil, memoryUsedBytes: Int? = nil, temperatureCelsius: Double? = nil, powerWatts: Double? = nil) {
        self.index = index
        self.utilizationPercent = utilizationPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.temperatureCelsius = temperatureCelsius
        self.powerWatts = powerWatts
    }

    private enum CodingKeys: String, CodingKey { case index, utilizationPercent, memoryUsedBytes, temperatureCelsius, powerWatts }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(index, forKey: .index)
        try box.encodeIfPresent(utilizationPercent, forKey: .utilizationPercent)
        try box.encodeIfPresent(memoryUsedBytes, forKey: .memoryUsedBytes)
        try box.encodeIfPresent(temperatureCelsius, forKey: .temperatureCelsius)
        try box.encodeIfPresent(powerWatts, forKey: .powerWatts)
    }

    var hasNumbers: Bool { utilizationPercent != nil || memoryUsedBytes != nil || temperatureCelsius != nil || powerWatts != nil }
}

extension HistoryPoint {
    /// The series of a reading's GPUs. A GPU with no number at all adds nothing; no GPU with a number: no `gpus` key.
    static func gpuSeries(_ gpus: [MachineStats.Gpu]?) -> [HistoryGpu]? {
        let series = (gpus ?? []).enumerated()
            .map { HistoryGpu(index: $0.offset, utilizationPercent: $0.element.utilizationPercent, memoryUsedBytes: $0.element.memoryUsedBytes,
                              temperatureCelsius: $0.element.temperatureCelsius, powerWatts: $0.element.powerWatts) }
            .filter(\.hasNumbers)
        return series.isEmpty ? nil : series
    }
}
