import Foundation
import RootCore
import RootStore

/// Keeps the GPU memory promised to containers: a booking is made when a create is accepted, follows the create to its VM, and is freed when the create fails or the VM is deleted.
/// A stopped VM keeps its booking. The rules themselves are in `GpuBooking` (RootCore); the store makes check and write one step.
final class GpuLimitService: @unchecked Sendable {
    private let bookings: GpuBookingStore
    private let clock: Clock

    init(bookings: GpuBookingStore, clock: Clock) {
        self.bookings = bookings
        self.clock = clock
    }

    /// What the placement needs to know about a machine's card.
    func room(of machine: MachineSummary) -> GpuRoom {
        GpuRoom(announcesLimit: machine.capabilities?.gpuMemoryLimit == true, totalGb: GpuBooking.totalGb(gpu: machine.gpu),
                bookedGb: (try? bookings.bookedGb(machine: machine.id)) ?? 0)
    }

    /// Books the limit of an accepted create under the create command's id. Without a limit this does nothing. Throws `GpuBookingRefusal` when it does not fit.
    func book(machine: MachineSummary, command: String, request: CreateWorkloadOperatorRequest) throws {
        guard let gb = request.gpuMemoryGb else { return }
        try bookings.book(machine: machine.id, key: command, gb: gb, room: room(of: machine), now: clock.now)
    }

    /// A command has finished. A create that failed frees its booking; one that succeeded hands it to the VM it made. A delete frees the VM's.
    func settle(_ command: CommandRow, succeeded: Bool, workload: String?) {
        switch (command.type, succeeded) {
        case ("create", false): free(machine: command.machine, key: command.id)
        case ("create", true): hand(over: command, to: workload)
        case ("delete", true): freeDeletedVM(command)
        default: break
        }
    }

    private func freeDeletedVM(_ command: CommandRow) {
        guard let workload = command.workloadId else { return }
        free(machine: command.machine, key: workload)
    }

    /// A create that never got as far as being sent (or could not be written) gives its booking back.
    func free(machine: String, key: String) {
        try? bookings.release(machine: machine, key: key)
    }

    private func hand(over command: CommandRow, to workload: String?) {
        guard let workload else { return free(machine: command.machine, key: command.id) }
        try? bookings.move(machine: command.machine, from: command.id, to: workload)
    }
}
