import Foundation

public enum VmOriginKind: String, Equatable {
    case panel, mcp
}

/// Who asks for a VM, as known when the parent accepts the create. The panel has one login, so a panel create names the operator and no person;
/// an MCP create names the person, the token (by its prefix, never its text), what the client called itself at `initialize`, and where the call came from.
public struct VmOriginInput: Equatable {
    public static let maxTextCharacters = 64
    public let kind: VmOriginKind
    public let actor: String
    public let personId: String?
    public let personName: String?
    public let tokenId: String?
    public let tokenPrefix: String?
    public let clientName: String?
    public let clientVersion: String?
    public let sourceIp: String?
    public let requestId: String?

    public init(kind: VmOriginKind, actor: String, personId: String? = nil, personName: String? = nil, tokenId: String? = nil, tokenPrefix: String? = nil,
                clientName: String? = nil, clientVersion: String? = nil, sourceIp: String? = nil, requestId: String? = nil) {
        self.kind = kind
        self.actor = actor
        self.personId = personId
        self.personName = personName
        self.tokenId = tokenId
        self.tokenPrefix = tokenPrefix
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.sourceIp = sourceIp
        self.requestId = requestId
    }

    public static func panel(operatorName: String, sourceIp: String?) -> VmOriginInput {
        VmOriginInput(kind: .panel, actor: operatorName, sourceIp: sourceIp)
    }

    /// Text a client chose for itself, made safe to keep and to show: no control characters, at most 64 characters, nil when nothing is left.
    public static func cleanClientText(_ text: String?) -> String? {
        guard let text else { return nil }
        let printable = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init)).trimmingCharacters(in: .whitespaces)
        return printable.isEmpty ? nil : String(printable.prefix(maxTextCharacters))
    }

    // MARK: kept with the create command until the VM has an id

    static let paramKeys = ["origin_kind", "origin_actor", "origin_person_id", "origin_person", "origin_token_id", "origin_token_prefix",
                            "origin_client_name", "origin_client_version", "origin_ip", "origin_request"]

    /// The command's parameters that carry this: the VM's id is not known until the machine has made it, and the record is written then.
    public var params: [String: String] {
        let pairs: [(String, String?)] = [("origin_kind", kind.rawValue), ("origin_actor", actor), ("origin_person_id", personId), ("origin_person", personName),
                                          ("origin_token_id", tokenId), ("origin_token_prefix", tokenPrefix), ("origin_client_name", clientName),
                                          ("origin_client_version", clientVersion), ("origin_ip", sourceIp), ("origin_request", requestId)]
        return pairs.reduce(into: [:]) { if let value = $1.1 { $0[$1.0] = value } }
    }

    public init?(params: [String: String]) {
        guard let kind = params["origin_kind"].flatMap(VmOriginKind.init(rawValue:)), let actor = params["origin_actor"] else { return nil }
        self.init(kind: kind, actor: actor, personId: params["origin_person_id"], personName: params["origin_person"], tokenId: params["origin_token_id"],
                  tokenPrefix: params["origin_token_prefix"], clientName: params["origin_client_name"], clientVersion: params["origin_client_version"],
                  sourceIp: params["origin_ip"], requestId: params["origin_request"])
    }
}

/// One VM's creator record as stored. Everything but the two `deleted` fields is sealed; those two are written once, when the parent deletes the VM.
public struct VmOriginRecord: Equatable {
    public let machineId: String
    public let workloadId: String
    public let input: VmOriginInput
    /// Nil for a record made afterwards for a VM that existed before this feature: nobody knows when it was made.
    public let createdAt: Int?
    /// True for such a record. It is part of the seal, so it cannot be dropped to make an old VM look new.
    public let backfilled: Bool
    public let deletedAt: Int?
    public let deletedBy: String?
    public let seal: String

    public init(machineId: String, workloadId: String, input: VmOriginInput, createdAt: Int?, backfilled: Bool = false, deletedAt: Int? = nil, deletedBy: String? = nil, seal: String) {
        self.backfilled = backfilled
        self.machineId = machineId
        self.workloadId = workloadId
        self.input = input
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.deletedBy = deletedBy
        self.seal = seal
    }

    /// The fields in a fixed order, each with its length in front, so no value can run into the next one.
    var canonical: String {
        let fields: [String?] = [machineId, workloadId, input.kind.rawValue, input.actor, input.personId, input.personName, input.tokenId, input.tokenPrefix,
                                 input.clientName, input.clientVersion, input.sourceIp, input.requestId, createdAt.map(String.init), backfilled ? "backfilled" : nil]
        return fields.map { $0.map { "\($0.utf8.count):\($0)" } ?? "-" }.joined(separator: "|")
    }
}

/// The seal that keeps a creator record honest: an HMAC the parent alone can make, over the record's canonical text.
/// The key comes from the parent's secret store and is never a token.
public enum VmOriginSeal {
    public static let purpose = "vm-origin"
    public static let sealCharacters = 16
    public static let fingerprintCharacters = 8

    /// `sign` is the parent's keyed HMAC (hex), `SecretBox.signature(_:purpose:)`.
    public static func seal(machineId: String, workloadId: String, input: VmOriginInput, createdAt: Int?, backfilled: Bool, sign: (String) -> String) -> String {
        let record = VmOriginRecord(machineId: machineId, workloadId: workloadId, input: input, createdAt: createdAt, backfilled: backfilled, seal: "")
        return String(sign(record.canonical).prefix(sealCharacters))
    }

    /// The short form people see and compare.
    public static func fingerprint(of seal: String) -> String { String(seal.prefix(fingerprintCharacters)) }

    /// True when the stored seal is what the parent would make for the stored fields now.
    public static func isIntact(_ record: VmOriginRecord, sign: (String) -> String) -> Bool {
        let expected = seal(machineId: record.machineId, workloadId: record.workloadId, input: record.input, createdAt: record.createdAt, backfilled: record.backfilled, sign: sign)
        return Tokens.constantTimeEqual(expected, record.seal)
    }
}

/// The short form on every VM in a machine's answer, so a list needs no second call.
public struct VmCreatedBy: Equatable, Encodable {
    public let kind: String
    public let label: String
    public let fingerprint: String?
    public let intact: Bool

    /// A VM the parent did not create, or made before this record existed.
    public static let unknown = VmCreatedBy(kind: "unknown", label: "unknown origin", fingerprint: nil, intact: true)

    enum CodingKeys: String, CodingKey { case kind, label, fingerprint, intact }

    /// The fingerprint is sent as null when there is none, so the shape never changes.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(kind, forKey: .kind)
        try box.encode(label, forKey: .label)
        try box.encode(fingerprint, forKey: .fingerprint)
        try box.encode(intact, forKey: .intact)
    }

    public init(kind: String, label: String, fingerprint: String?, intact: Bool) {
        self.kind = kind
        self.label = label
        self.fingerprint = fingerprint
        self.intact = intact
    }

    public init(_ record: VmOriginRecord, intact: Bool) {
        self.init(kind: record.input.kind.rawValue, label: Self.label(of: record), fingerprint: VmOriginSeal.fingerprint(of: record.seal), intact: intact)
    }

    public static let backfilledLabel = "admin (recorded afterwards)"

    /// "Ayu (MCP)" for a person's token, "panel (kurnia)" for the operator, and a plain note for a VM that was recorded afterwards.
    public static func label(of record: VmOriginRecord) -> String {
        record.backfilled ? backfilledLabel : label(of: record.input)
    }

    static func label(of input: VmOriginInput) -> String {
        switch input.kind {
        case .mcp: return "\(input.personName ?? input.actor) (MCP)"
        case .panel: return "panel (\(input.actor))"
        }
    }

    /// "claude-code 2.0.1", or nil when the client said nothing.
    public static func clientText(_ input: VmOriginInput) -> String? {
        guard let name = input.clientName else { return nil }
        return [name, input.clientVersion].compactMap { $0 }.joined(separator: " ")
    }
}
