import Foundation

/// Reads the wall-side electrical telemetry an Apple Silicon desktop reports through ioreg
/// (an AppleSmartBattery-compatible SMC node carries `PowerTelemetryData` even without a battery).
/// A number the node does not give is nil, never 0.
enum DarwinWall {
    private static let toolPath = "/usr/sbin/ioreg"
    /// Targeted query: only the services that carry a PowerTelemetryData dictionary, instead of the huge full dump.
    private static let sampleArguments = ["-r", "-k", "PowerTelemetryData", "-d", "1"]
    private static let commandTimeoutSeconds: TimeInterval = 2
    private static let maxOutputBytes = 256 * 1024
    private static let milliVoltsPerVolt = 1000.0
    private static let centiAmpsPerAmp = 100.0
    private static let centiwattsPerWatt = 100.0

    /// Unit math, settled empirically on live machines (mac-mini, mac-studio, mac-studio-2): the three fields are
    /// milli / centi / centi units. Proof on each sample, V×I ≈ W: mac-mini 12.583 V × 2.75 A = 34.60 W ≈
    /// SystemPowerIn 3467 × 0.01 W; mac-studio 12.086 × 5.66 = 68.41 W ≈ 6843 × 0.01; mac-studio-2 12.052 × 4.82
    /// = 58.09 W ≈ 5809 × 0.01. So: voltage ÷ 1000 (mV), current ÷ 100 (hundreds of mA), power ÷ 100 (cW).
    struct Reading: Equatable {
        let voltage, current, watts: Double?
        static let unknown = Reading(voltage: nil, current: nil, watts: nil)
    }

    static func read() -> Reading { reading(sampleText: sample() ?? "") }

    /// The parsing, kept pure so tests can feed real ioreg text.
    static func reading(sampleText: String) -> Reading {
        var voltage, current, watts: Int?
        for line in sampleText.split(separator: "\n") {
            voltage = voltage ?? integer("SystemVoltageIn", in: line)
            current = current ?? integer("SystemCurrentIn", in: line)
            watts = watts ?? integer("SystemPowerIn", in: line)
        }
        // 0 V is impossible on a powered Mac: the node reports zeros before its first real update, so treat all-zero as unknown.
        guard let volts = voltage, volts > 0 else { return .unknown }
        return Reading(voltage: rounded(Double(volts) / milliVoltsPerVolt, 1),
                       current: current.map { rounded(Double($0) / centiAmpsPerAmp, 2) },
                       watts: watts.map { rounded(Double($0) / centiwattsPerWatt, 1) })
    }

    /// The number after `"Name"=` on one line, when it is a plain integer.
    private static func integer(_ name: String, in line: some StringProtocol) -> Int? {
        guard let marker = line.firstRange(of: "\"\(name)\"=") else { return nil }
        let digits = line[marker.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    private static func rounded(_ number: Double, _ decimals: Int) -> Double {
        let factor = pow(10, Double(decimals))
        return (number * factor).rounded() / factor
    }

    /// Runs ioreg without a shell. Nil on any failure: it cannot start, it runs past the time limit, or it exits non-zero.
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
