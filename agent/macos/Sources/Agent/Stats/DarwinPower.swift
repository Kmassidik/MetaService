import Foundation

/// Reads this Mac's power draw with powermetrics. Needs root; where the machine refuses it the answer is nil, never 0.
enum DarwinPower {
    private static let toolPath = "/usr/bin/powermetrics"
    private static let sampleArguments = ["-i", "200", "-n", "1", "--samplers", "cpu_power"]
    /// The one line of the sample that carries the machine total, in milliwatts.
    private static let combinedLinePrefix = "Combined Power (CPU + GPU + ANE):"
    private static let commandTimeoutSeconds: TimeInterval = 2
    private static let maxOutputBytes = 16 * 1024
    private static let milliwattsPerWatt = 1000.0

    static func read() -> Double? { watts(sampleText: sample() ?? "") }

    /// The arithmetic, kept pure so tests can feed real sample text.
    static func watts(sampleText: String) -> Double? {
        for line in sampleText.split(separator: "\n") {
            guard let marker = line.firstRange(of: combinedLinePrefix) else { continue }
            let digits = line[marker.upperBound...].drop { $0 == " " }.prefix { $0.isNumber || $0 == "." }
            guard let milliwatts = Double(digits) else { return nil }
            return (milliwatts / milliwattsPerWatt * 10).rounded() / 10
        }
        return nil
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
