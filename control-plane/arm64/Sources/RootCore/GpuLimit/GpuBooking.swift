import Foundation

/// How much of a card's memory is promised to VMs. Pure: the numbers come in, the answer goes out.
/// A VM's limit stays booked while the VM is stopped, until the VM is deleted, so the limits can never add up to more than the card has.
public enum GpuBooking {
    public static let megabytesPerGb = 1024
    public static let allowedGb = 1...1024

    static let helperTooOldCode = "helper_too_old"
    static let helperTooOldMessage = "Update the helper on this machine first."
    static let unknownMemoryCode = "gpu_memory_unknown"
    static let unknownMemoryMessage = "This machine does not say how much memory its card has, so a limit cannot be booked."
    static let notAvailableCode = "gpu_memory_not_available"

    /// The first card's memory in whole GB (rounded down), or nil when the machine has no card or does not say. Only the first card counts for now.
    public static func totalGb(gpu: [GpuInfo]) -> Int? {
        guard let memoryMb = gpu.first?.memoryMb, memoryMb > 0 else { return nil }
        return memoryMb / megabytesPerGb
    }

    /// What the panel shows for a machine; nil when the card or its memory is unknown.
    public static func summary(total: Int?, booked: Int) -> GpuBookingSummary? {
        total.map { GpuBookingSummary(totalGb: $0, bookedGb: booked, freeGb: max(0, $0 - booked)) }
    }

    /// Why a new limit cannot be booked, or nil when it fits. Exactly full is allowed; one GB more is not.
    public static func refusal(_ room: GpuRoom, requestedGb: Int) -> GpuBookingRefusal? {
        guard room.announcesLimit else { return GpuBookingRefusal(code: helperTooOldCode, message: helperTooOldMessage, freeGb: nil) }
        guard let total = room.totalGb else { return GpuBookingRefusal(code: unknownMemoryCode, message: unknownMemoryMessage, freeGb: nil) }
        let free = max(0, total - room.bookedGb)
        guard requestedGb > free else { return nil }
        return GpuBookingRefusal(code: notAvailableCode, message: "Only \(free) GB of the card's \(total) GB is still free to book.", freeGb: free)
    }
}

/// What the Root knows about a machine's card when a limit is asked for.
public struct GpuRoom: Equatable {
    public let announcesLimit: Bool
    public let totalGb: Int?
    public let bookedGb: Int

    public init(announcesLimit: Bool, totalGb: Int?, bookedGb: Int) {
        self.announcesLimit = announcesLimit
        self.totalGb = totalGb
        self.bookedGb = bookedGb
    }
}

public struct GpuBookingSummary: Encodable, Equatable {
    public let totalGb: Int
    public let bookedGb: Int
    public let freeGb: Int
}

/// A limit that cannot be booked, with the plain reason. Becomes a 409; `freeGb` is in the body when the card's numbers are known.
public struct GpuBookingRefusal: Error, Equatable {
    public let code: String
    public let message: String
    public let freeGb: Int?
}
