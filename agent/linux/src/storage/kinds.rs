//! What a folder is, and whether its space can be had back: the colour and the hatch of a tile on the panel's Storage tab.
//! The rules are disktree's (github.com/tobi/disktree, crates/disktree-core/src/classify.rs, MIT), kept close to the original
//! so the panel reads like disktree. Added here: `Vms`, for the folders a machine's VMs and containers live in.
use super::walk::{Entry, EntryType, Marks};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Kind {
    Code,
    AgentScratch,
    Toolchain,
    Synced,
    Git,
    Media,
    Documents,
    Cache,
    Vms,
    #[default]
    Other,
}

impl Kind {
    /// The word in the contract.
    pub const fn word(self) -> &'static str {
        match self {
            Self::Code => "code",
            Self::AgentScratch => "agent",
            Self::Toolchain => "toolchain",
            Self::Synced => "synced",
            Self::Git => "git",
            Self::Media => "media",
            Self::Documents => "documents",
            Self::Cache => "cache",
            Self::Vms => "vms",
            Self::Other => "other",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reclaim {
    Regenerable,
    SyncHistory,
    PackageStore,
    BuildOutput,
    Reinstallable,
    SandboxLayers,
    Snapshots,
    Trash,
    Temporary,
}

impl Reclaim {
    /// The word in the contract.
    pub const fn word(self) -> &'static str {
        match self {
            Self::Regenerable => "regenerable",
            Self::SyncHistory => "sync_history",
            Self::PackageStore => "package_store",
            Self::BuildOutput => "build_output",
            Self::Reinstallable => "reinstallable",
            Self::SandboxLayers => "sandbox_layers",
            Self::Snapshots => "snapshots",
            Self::Trash => "trash",
            Self::Temporary => "temporary",
        }
    }
}

/// The kind a folder name says on its own, if any.
pub fn kind_of_name(name: &str) -> Option<Kind> {
    let lower = name.to_ascii_lowercase();
    if lower.starts_with("onedrive - ") || lower.starts_with("dropbox (") {
        return Some(Kind::Synced);
    }
    let kind = match lower.as_str() {
        "src" | "code" | "projects" | "repos" | "dev" | "work" | "workspace" | "workspaces" | "github.com" | "gitlab.com" | "sites" | "development" => Kind::Code,
        ".codex" | ".claude" | ".herdr" | ".pi" | ".cursor" | ".aider" | ".gemini" | ".continue" | ".windsurf" | ".microsandbox" | ".omp" | ".agents" | ".openai" | "tries"
        | "worktrees" | "experiments" | "scratch" | "playground" => Kind::AgentScratch,
        ".cargo" | ".rustup" | ".local" | ".npm" | ".pnpm-store" | "pnpm" | ".bun" | ".deno" | "go" | ".gradle" | ".m2" | ".platformio" | "mise" | ".mise" | ".pyenv" | ".nvm"
        | ".gem" | "gem" | ".rbenv" | ".espressif" | ".arduino15" | ".config" | ".vscode" | ".zig" | ".rye" | ".conda" | "anaconda3" | "miniconda3" | ".opam" | ".ghcup"
        | ".stack" | ".julia" | ".dotnet" | ".android" | ".sdkman" | ".volta" | ".yarn" | ".java" | ".nuget" | "xcode" | "coresimulator" => Kind::Toolchain,
        "sync" | "dropbox" | "nextcloud" | "google drive" | "onedrive" | "pclouddrive" | "mega" | ".stversions" | "mobile documents" | "cloudstorage" | "iclouddrive" => Kind::Synced,
        ".git" => Kind::Git,
        "pictures" | "photos" | "music" | "videos" | "movies" | "steam" | "models" | ".ollama" | ".lmstudio" | "games" | "wineprefix" => Kind::Media,
        "documents" | "desktop" | "downloads" | "books" | "notes" | "obsidian" | "public" | "templates" => Kind::Documents,
        ".cache" | "cache" | "caches" | ".ccache" | ".sccache" | "_cacache" | "__pycache__" | "node_modules" | "trash" | ".trash" | "tmp" | ".tmp" | "deriveddata"
        | "ios devicesupport" | "watchos devicesupport" | "temp" | "npm-cache" | "v3-cache" => Kind::Cache,
        // Not in disktree: where VM disks, container images and their volumes are kept on a Linux machine.
        "incus" | "lxd" | "docker" | "containerd" | "libvirt" | "containers" | "machines" | "firecracker" => Kind::Vms,
        _ => return None,
    };
    Some(kind)
}

/// Whether a folder's space can be had back, from its name, the kind of the folder holding it, and what sits beside it.
pub fn reclaim_of(name: &str, parent: Kind, beside: Marks) -> Option<Reclaim> {
    let lower = name.to_ascii_lowercase();
    let reclaim = match lower.as_str() {
        ".cache" | "cache" | "caches" | ".ccache" | ".sccache" | "_cacache" | "npm-cache" | "v3-cache" | "ios devicesupport" | "watchos devicesupport" => Reclaim::Regenerable,
        ".stversions" => Reclaim::SyncHistory,
        ".pnpm-store" | "pnpm" => Reclaim::PackageStore,
        "__pycache__" | ".pytest_cache" | ".mypy_cache" | ".ruff_cache" | ".next" | ".turbo" | ".parcel-cache" | "deriveddata" => Reclaim::BuildOutput,
        "logs" if beside.contains(Marks::APPLICATION_SUPPORT) => Reclaim::Temporary,
        // Too common a name to trust alone: only a build folder beside its manifest.
        "target" if beside.contains(Marks::CARGO_TOML) => Reclaim::BuildOutput,
        "node_modules" if beside.contains(Marks::PACKAGE_JSON) => Reclaim::Reinstallable,
        "layers" if parent == Kind::AgentScratch => Reclaim::SandboxLayers,
        "snapshots" if parent == Kind::AgentScratch => Reclaim::Snapshots,
        "trash" | ".trash" => Reclaim::Trash,
        "tmp" | ".tmp" | "temp" => Reclaim::Temporary,
        _ => return None,
    };
    Some(reclaim)
}

/// A git object store by its shape, whatever it is called: a bare repository or a `.git` folder has `objects`, `refs` and `HEAD`.
fn is_git_store(entry: &Entry) -> bool {
    entry.kind_of == EntryType::Dir && entry.marks.contains(Marks::GIT_STORE)
}

fn named_kind(entry: &Entry) -> Option<Kind> {
    if entry.kind_of != EntryType::Dir {
        return None;
    }
    kind_of_name(&entry.name).or_else(|| is_git_store(entry).then_some(Kind::Git))
}

/// Gives every entry below `root` a kind and a reclaim reason. Top-down: a folder's own name wins, otherwise it takes its parent's.
/// A top-level folder with an unknown name takes the kind of its largest recognisable child (`/home` is mostly code, so it is code).
pub fn classify(root: &mut Entry) {
    root.kind = Kind::Other;
    root.reclaim = None;
    let beside = root.marks;
    for child in &mut root.children {
        let kind = named_kind(child).or_else(|| dominant_child_kind(child)).unwrap_or(Kind::Other);
        let reclaim = if child.kind_of == EntryType::Dir { reclaim_of(&child.name, Kind::Other, beside) } else { None };
        classify_below(child, kind, reclaim);
    }
}

fn classify_below(entry: &mut Entry, kind: Kind, reclaim: Option<Reclaim>) {
    entry.kind = kind;
    entry.reclaim = reclaim;
    let beside = entry.marks;
    for child in &mut entry.children {
        let child_kind = named_kind(child).unwrap_or(kind);
        let child_reclaim = reclaim.or_else(|| if child.kind_of == EntryType::Dir { reclaim_of(&child.name, kind, beside) } else { None });
        classify_below(child, child_kind, child_reclaim);
    }
}

/// The kind of an unknown folder from what fills it: the first recognisable name down the largest folders, a few levels deep.
fn dominant_child_kind(entry: &Entry) -> Option<Kind> {
    let mut entry = entry;
    for _ in 0..3 {
        if let Some(kind) = entry.children.iter().find_map(named_kind) {
            return Some(kind);
        }
        entry = entry.children.iter().find(|child| child.kind_of == EntryType::Dir)?;
    }
    None
}
