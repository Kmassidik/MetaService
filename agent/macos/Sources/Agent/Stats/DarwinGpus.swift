import Darwin
import Foundation
import IOKit
import AgentCore

/// The graphics chips in the IOKit registry (`IOAccelerator` entries, the numbers `ioreg` shows): readable by any user, no root.
/// Temperature, power and clock are not in the registry without root, so they are never reported.
enum DarwinGpus {
    private static let acceleratorClass = "IOAccelerator"
    private static let brandName = "machdep.cpu.brand_string"

    /// Empty when the registry lists no accelerator or none with statistics.
    static func read() -> [GpuReading] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(acceleratorClass), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        let brand = text(brandName)
        var readings: [GpuReading] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let reading = properties(of: service).flatMap({ AppleGpuRegistry.reading(from: $0, brand: brand) }) { readings.append(reading) }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return readings
    }

    private static func properties(of service: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS, let unmanaged else { return nil }
        return unmanaged.takeRetainedValue() as? [String: Any]
    }

    private static func text(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
