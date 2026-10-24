import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore

/// The public API's JSON. It keeps the API's own camelCase (the types name their keys) and its own error shape, so it never
/// goes through the panel's snake_case encoder.
enum SandboxApiJson {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    static func response<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(data: try encoder.encode(value))))
    }

    /// JSON that is already in the API's shape (the helper's readings), so it goes out as it came and is never re-encoded
    /// through a type the parent would have to guess.
    static func raw(_ value: Any, status: HTTPResponse.Status = .ok) throws -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        let data = try JSONSerialization.data(withJSONObject: value)
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }

    /// `{ code, message, error_code }`, with the status repeated in the body.
    static func failure(_ failure: SandboxApiFailure) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        let data = (try? encoder.encode(SandboxApiErrorBody(failure))) ?? Data()
        return Response(status: .init(code: failure.status), headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }
}
