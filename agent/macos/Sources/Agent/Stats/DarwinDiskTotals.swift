import Foundation
import IOKit
import AgentCore

/// Bytes read and written since boot, added over the machine's storage devices. The numbers come from the IOKit registry (the same ones `iostat` shows): readable by any user, no root.
enum DarwinDiskTotals {
    private static let driverClass = "IOBlockStorageDriver"
    private static let statisticsKey = "Statistics"
    private static let readKey = "Bytes (Read)"
    private static let writeKey = "Bytes (Write)"

    /// nil when the system lists no storage driver or gives no numbers (then the page hides the card, it does not show 0).
    static func read() -> DiskTotals? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(driverClass), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var totals: DiskTotals?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            totals = added(totals, statistics(of: service))
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return totals
    }

    private static func added(_ total: DiskTotals?, _ one: DiskTotals?) -> DiskTotals? {
        guard let one else { return total }
        return DiskTotals(readBytes: (total?.readBytes ?? 0) &+ one.readBytes, writtenBytes: (total?.writtenBytes ?? 0) &+ one.writtenBytes)
    }

    private static func statistics(of service: io_registry_entry_t) -> DiskTotals? {
        guard let value = IORegistryEntryCreateCFProperty(service, statisticsKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let numbers = value as? [String: Any],
              let read = (numbers[readKey] as? NSNumber)?.uint64Value, let written = (numbers[writeKey] as? NSNumber)?.uint64Value else { return nil }
        return DiskTotals(readBytes: read, writtenBytes: written)
    }
}
