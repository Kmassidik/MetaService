import Foundation

/// What `GET /v1/images` answers: which ready-made images this machine has prepared. The stock image needs no preparing, so it is always ready.
/// OpenClaw and Hermes are not prepared images: they are installed inside the VM after it starts (`PUT /v1/workloads/{id}/app`), so they are always ready too.
public enum PreparedImages {
    /// What the person reads next to an app that is installed after the VM starts.
    public static let appCaption = "Installs after the VM starts, about 2 minutes"

    public static let list = Data(("""
    {"images":[{"id":"blank","ready":true,"built_at":null},\
    {"id":"openclaw","ready":true,"built_at":null,"caption":"\(appCaption)"},\
    {"id":"hermes","ready":true,"built_at":null,"caption":"\(appCaption)"}]}
    """).utf8)
}
