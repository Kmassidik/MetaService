import Darwin
import Foundation
import AgentCore

struct DarwinStorageScanner: Sendable {
    static let tilesPerLevel: UInt64 = 4_000
    static let minimumFloor: UInt64 = 1_024 * 1_024

    let root: String
    let counters: StorageCounters

    func scan() throws -> StorageMap {
        let started = ProcessInfo.processInfo.systemUptime
        let before = try DarwinStorageVolumes.disk(at: root)
        let volumes = try DarwinStorageVolumes.mounted()
        let plan = DarwinStorageMountPlan(root: root, volumes: volumes)
        let floor = Swift.max(before.usedBytes / Self.tilesPerLevel, Self.minimumFloor)
        let walker = DarwinStorageWalker(root: root, allowedDevices: plan.allowedDevices, skip: plan.skip, counters: counters)
        let walked = try walker.walk(floor: floor)
        StorageClassifier.classify(walked.root)
        StorageTree.fit(walked.root)
        let after: StorageDisk
        do {
            after = try DarwinStorageVolumes.disk(at: root)
        } catch {
            // The earlier exact reading is still valid if the volume disappeared during the walk (Linux parity).
            after = before
        }
        let seconds = ((ProcessInfo.processInfo.systemUptime - started) * 10).rounded() / 10
        return StorageMap(root: String(root.prefix(4096)), finishedAt: Self.timestamp(Date()), seconds: Swift.max(seconds, 0),
                          entries: walked.entries, unreadable: walked.unreadable, disk: after, nodes: StorageTree.flatten(walked.root))
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

enum DarwinStorageExecution {
    /// Background QoS lowers this worker thread's CPU and I/O priority without nicing the whole helper process.
    static func start(scanner: DarwinStorageScanner, completion: @escaping StorageState.Completion) {
        DispatchQueue.global(qos: .background).async {
            // A refused priority hint must not prevent the read-only map (same rule as the Linux scanner).
            _ = pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0)
            do {
                completion(.success(try scanner.scan()))
            } catch let failure as StorageScanFailure {
                completion(.failure(failure))
            } catch {
                completion(.failure(StorageScanFailure(String(describing: error))))
            }
        }
    }
}
