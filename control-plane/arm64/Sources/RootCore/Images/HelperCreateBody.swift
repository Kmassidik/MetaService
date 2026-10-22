import Foundation

/// The body of the create command the parent sends to a helper. Only values the parent derived reach it: the image name is the machine's own saved default, never something the
/// browser typed (the request has no such field), and `bundle` is a catalog id the parent has checked.
public enum HelperCreateBody {
    public static func make(commandId: String, request: CreateWorkloadOperatorRequest, machineDefaultImage: String?, catalog: [ImageEntry] = ImageCatalog.entries) -> [String: Any] {
        var body: [String: Any] = ["command_id": commandId, "name": request.name, "kind": request.kind, "cpu": request.cpu, "ram_mb": request.ramMb, "disk_gb": request.diskGb, "gpu_mode": request.gpuMode]
        body["image"] = machineDefaultImage
        body["bundle"] = ImageCatalog.helperBundle(for: request.bundle, in: catalog)
        return body
    }
}
