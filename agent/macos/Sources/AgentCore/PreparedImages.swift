import Foundation

/// What `GET /v1/images` answers: which ready-made images this machine has prepared. Only the stock image exists so far, and it needs no preparing, so the answer is always the same.
public enum PreparedImages {
    public static let stockOnly = Data(#"{"images":[{"id":"blank","ready":true,"built_at":null}]}"#.utf8)
}
