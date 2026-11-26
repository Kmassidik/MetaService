import Foundation

/// Reads this Mac's power draw with powermetrics. Needs root; where the machine refuses it the answer is nil, never 0.
enum DarwinPower {
    private static let toolPath = "/usr/bin/sudo"
    private static let sampleArguments = ["-n", "/usr/bin/powermetrics", "-i", "200", "-n", "1", "--samplers", "cpu_power,gpu_power"]
    /// One line of the sample per source, in milliwatts. The cpu_power sampler prints all four; the gpu_power sampler
    /// repeats "GPU Power:", so only each label's first occurrence is read.
    private static let linePrefixes: [Key: String] = [.cpu: "CPU Power:", .gpu: "GPU Power:", .ane: "ANE Power:", .combined: "Combined Power (CPU + GPU + ANE):"]
    private static let commandTimeoutSeconds: TimeInterval = 2
    private static let maxOutputBytes = 16 * 1024
    private static let milliwattsPerWatt = 1000.0

    /// The machine's power draw in watts, per source. A part the system does not report is nil, never 0.
    struct Reading: Equatable {
        let combined, cpu, gpu, ane: Double?
        static let unknown = Reading(combined: nil, cpu: nil, gpu: nil, ane: nil)
    }

    private enum Key { case cpu, gpu, ane, combined }

    static func read() -> Reading { readings(sampleText: sample() ?? "") }

    /// The arithmetic, kept pure so tests can feed real sample text.
    static func readings(sampleText: String) -> Reading {
        var answer = [Key: Double?]()
        for line in sampleText.split(separator: "\n") {
            for (key, prefix) in linePrefixes where answer[key] == nil {
                let lowercased = line.lowercased()
                guard let marker = lowercased.firstRange(of: prefix.lowercased()) else { continue }
                let digits = lowercased[marker.upperBound...].drop { $0 == " " }.prefix { $0.isNumber || $0 == "." }
                answer[key] = Double(digits).map { ($0 / milliwattsPerWatt * 10).rounded() / 10 }
            }
        }
        return Reading(combined: answer[.combined] ?? nil, cpu: answer[.cpu] ?? nil, gpu: answer[.gpu] ?? nil, ane: answer[.ane] ?? nil)
    }

    /// Runs the sampler without a shell. Nil on any failure: it cannot start, it runs past the time limit, or it exits non-zero.
    private static func sample() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = sampleArguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        guard finished.wait(timeout: .now() + commandTimeoutSeconds) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readData(ofLength: maxOutputBytes)
        return String(decoding: data, as: UTF8.self)
    }
}
