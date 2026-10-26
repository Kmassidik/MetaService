import Foundation

/// disktree-compatible labels and reclaim reasons, plus VM/container folders.
public enum StorageClassifier {
    public static func classify(_ root: StorageEntry) {
        root.kind = .other
        root.reclaim = nil
        for child in root.children {
            let kind = namedKind(child) ?? dominantChildKind(child) ?? .other
            let reclaim = child.type == .dir ? reclaimOf(child.name, parent: .other, beside: root.marks) : nil
            classifyBelow(child, kind: kind, reclaim: reclaim)
        }
    }

    static func kindOfName(_ name: String) -> StorageKind? {
        let lower = name.lowercased()
        if lower.hasPrefix("onedrive - ") || lower.hasPrefix("dropbox (") { return .synced }
        switch lower {
        case "src", "code", "projects", "repos", "dev", "work", "workspace", "workspaces", "github.com", "gitlab.com", "sites", "development":
            return .code
        case ".codex", ".claude", ".herdr", ".pi", ".cursor", ".aider", ".gemini", ".continue", ".windsurf", ".microsandbox", ".omp", ".agents", ".openai",
             "tries", "worktrees", "experiments", "scratch", "playground":
            return .agent
        case ".cargo", ".rustup", ".local", ".npm", ".pnpm-store", "pnpm", ".bun", ".deno", "go", ".gradle", ".m2", ".platformio", "mise", ".mise", ".pyenv", ".nvm",
             ".gem", "gem", ".rbenv", ".espressif", ".arduino15", ".config", ".vscode", ".zig", ".rye", ".conda", "anaconda3", "miniconda3", ".opam", ".ghcup",
             ".stack", ".julia", ".dotnet", ".android", ".sdkman", ".volta", ".yarn", ".java", ".nuget", "xcode", "coresimulator":
            return .toolchain
        case "sync", "dropbox", "nextcloud", "google drive", "onedrive", "pclouddrive", "mega", ".stversions", "mobile documents", "cloudstorage", "iclouddrive":
            return .synced
        case ".git": return .git
        case "pictures", "photos", "music", "videos", "movies", "steam", "models", ".ollama", ".lmstudio", "games", "wineprefix":
            return .media
        case "documents", "desktop", "downloads", "books", "notes", "obsidian", "public", "templates":
            return .documents
        case ".cache", "cache", "caches", ".ccache", ".sccache", "_cacache", "__pycache__", "node_modules", "trash", ".trash", "tmp", ".tmp", "deriveddata",
             "ios devicesupport", "watchos devicesupport", "temp", "npm-cache", "v3-cache":
            return .cache
        case "incus", "lxd", "docker", "containerd", "libvirt", "containers", "machines", "firecracker":
            return .vms
        default: return nil
        }
    }

    static func reclaimOf(_ name: String, parent: StorageKind, beside: StorageMarks) -> StorageReclaim? {
        switch name.lowercased() {
        case ".cache", "cache", "caches", ".ccache", ".sccache", "_cacache", "npm-cache", "v3-cache", "ios devicesupport", "watchos devicesupport":
            return .regenerable
        case ".stversions": return .syncHistory
        case ".pnpm-store", "pnpm": return .packageStore
        case "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".next", ".turbo", ".parcel-cache", "deriveddata": return .buildOutput
        case "logs" where beside.contains(.applicationSupport): return .temporary
        case "target" where beside.contains(.cargo): return .buildOutput
        case "node_modules" where beside.contains(.package): return .reinstallable
        case "layers" where parent == .agent: return .sandboxLayers
        case "snapshots" where parent == .agent: return .snapshots
        case "trash", ".trash": return .trash
        case "tmp", ".tmp", "temp": return .temporary
        default: return nil
        }
    }

    private static func namedKind(_ entry: StorageEntry) -> StorageKind? {
        guard entry.type == .dir else { return nil }
        if let named = kindOfName(entry.name) { return named }
        return entry.marks.contains(.gitStore) ? .git : nil
    }

    private static func classifyBelow(_ entry: StorageEntry, kind: StorageKind, reclaim: StorageReclaim?) {
        entry.kind = kind
        entry.reclaim = reclaim
        for child in entry.children {
            let childKind = namedKind(child) ?? kind
            let own = child.type == .dir ? reclaimOf(child.name, parent: kind, beside: entry.marks) : nil
            classifyBelow(child, kind: childKind, reclaim: reclaim ?? own)
        }
    }

    private static func dominantChildKind(_ entry: StorageEntry) -> StorageKind? {
        var current = entry
        for _ in 0..<3 {
            for child in current.children {
                if let kind = namedKind(child) { return kind }
            }
            guard let next = current.children.first(where: { $0.type == .dir }) else { return nil }
            current = next
        }
        return nil
    }
}
