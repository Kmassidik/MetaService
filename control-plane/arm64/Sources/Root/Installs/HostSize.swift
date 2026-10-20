import Darwin

/// What kind of computer the parent runs on.
enum HostSize {
    /// The CPU name the system reports, such as `arm64`.
    static func architecture() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) } }
    }
}
