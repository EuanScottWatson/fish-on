import Foundation

/// A server record whose values can be inspected without changing the original data.
public struct Record: Identifiable {
    public let values: [String: Any]
    public var id: String { string("id") }
    public init(_ values: [String: Any]) { self.values = values }
    public func string(_ key: String) -> String {
        guard let value = values[key], !(value is NSNull) else { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }
    public func number(_ key: String) -> Double? {
        guard let value = values[key], !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
    public func flag(_ key: String) -> Bool {
        if let value = values[key] as? Bool { return value }
        return number(key) != nil && number(key) != 0
    }
    public func strings(_ key: String) -> [String] { values[key] as? [String] ?? [] }
}

/// Decode an API list and reject malformed responses rather than showing an empty list.
public func decodeRecords(_ data: Data) throws -> [Record] {
    guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw CocoaError(.coderReadCorrupt)
    }
    return rows.map(Record.init)
}

/// Format an ISO calendar date without changing its day through time zone conversion.
public func britishDate(_ value: String) -> String {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
          parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return value.isEmpty ? "Date not recorded" : value }
    return "\(parts[2])/\(parts[1])/\(parts[0])"
}
