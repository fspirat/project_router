import Foundation

/// Any JSON value. Used for tolerant decoding: every model is built from a
/// `JSONValue`, so a field that is sometimes a string, a number or `null`
/// never breaks decoding of the whole document.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
            return
        }
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let i = try? c.decode(Int.self) {
            self = .int(i)
            return
        }
        if let d = try? c.decode(Double.self) {
            self = .double(d)
            return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
            return
        }
        if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
            return
        }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:
            try c.encodeNil()
        case .bool(let b):
            try c.encode(b)
        case .int(let i):
            try c.encode(i)
        case .double(let d):
            try c.encode(d)
        case .string(let s):
            try c.encode(s)
        case .array(let a):
            try c.encode(a)
        case .object(let o):
            try c.encode(o)
        }
    }

    // MARK: - Parsing helpers

    /// Parses JSON bytes. Throws if the data is not JSON.
    public static func parse(_ data: Data) throws -> JSONValue {
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Parses a JSON string. Throws if the text is not JSON.
    public static func parse(_ text: String) throws -> JSONValue {
        return try parse(Data(text.utf8))
    }

    /// Re-encodes this value and decodes it as `T`.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Accessors

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self {
            return o[key]
        }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, index >= 0, index < a.count {
            return a[index]
        }
        return nil
    }

    public var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    public var isObject: Bool {
        if case .object = self {
            return true
        }
        return false
    }

    /// Lenient integer: ints, doubles (rounded half away from zero) and numeric strings.
    public var intValue: Int? {
        switch self {
        case .int(let i):
            return i
        case .double(let d):
            return JSONValue.roundedInt(d)
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = Int(t) {
                return i
            }
            if let d = Double(t) {
                return JSONValue.roundedInt(d)
            }
            return nil
        default:
            return nil
        }
    }

    /// Lenient double: numbers and numeric strings.
    public var doubleValue: Double? {
        switch self {
        case .int(let i):
            return Double(i)
        case .double(let d):
            return d
        case .string(let s):
            return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    /// Lenient string: strings, and numbers converted to text. `nil` for null, bool, array, object.
    public var stringValue: String? {
        switch self {
        case .string(let s):
            return s
        case .int(let i):
            return String(i)
        case .double(let d):
            return String(d)
        default:
            return nil
        }
    }

    /// Lenient bool: `true`/`false`, numbers (non-zero = true) and the strings "true"/"false"/"1"/"0".
    public var boolValue: Bool? {
        switch self {
        case .bool(let b):
            return b
        case .int(let i):
            return i != 0
        case .double(let d):
            return d != 0
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t == "true" || t == "1" {
                return true
            }
            if t == "false" || t == "0" || t.isEmpty {
                return false
            }
            return nil
        default:
            return nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self {
            return a
        }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self {
            return o
        }
        return nil
    }

    static func roundedInt(_ d: Double) -> Int? {
        guard d.isFinite else {
            return nil
        }
        return Int(exactly: d.rounded(.toNearestOrAwayFromZero))
    }

    // MARK: - Internal keyed helpers used by the models

    func num(_ key: String) -> Int? {
        return self[key]?.intValue
    }

    func str(_ key: String) -> String? {
        return self[key]?.stringValue
    }

    func flag(_ key: String) -> Bool? {
        return self[key]?.boolValue
    }

    /// The array under `key`, or `[]`.
    func list(_ key: String) -> [JSONValue] {
        return self[key]?.arrayValue ?? []
    }

    /// The object elements of the array under `key` (non-objects are skipped).
    func objects(_ key: String) -> [JSONValue] {
        return list(key).filter { $0.isObject }
    }

    /// The value under `key` only when it is an object.
    func obj(_ key: String) -> JSONValue? {
        if let v = self[key], v.isObject {
            return v
        }
        return nil
    }

    /// The string elements of the array under `key` (other elements are skipped).
    func strings(_ key: String) -> [String] {
        var out: [String] = []
        for v in list(key) {
            if case .string(let s) = v {
                out.append(s)
            }
        }
        return out
    }

    /// Decodes a JSON value from `decoder` and requires it to be an object.
    static func decodeObject(from decoder: Decoder) throws -> JSONValue {
        let v = try JSONValue(from: decoder)
        guard v.isObject else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a JSON object")
            )
        }
        return v
    }

    static func shapeError(_ decoder: Decoder, _ what: String) -> DecodingError {
        return DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unexpected shape: \(what)")
        )
    }
}
