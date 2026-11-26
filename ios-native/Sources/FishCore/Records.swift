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

/// Encode the existing Fish On multipart contract with a stable boundary.
public func multipartBody(fields: [String: String], photo: Data?, boundary: String) -> Data {
    var body = Data()
    func append(_ text: String) { body.append(Data(text.utf8)) }
    for key in fields.keys.sorted() {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(fields[key] ?? "")\r\n")
    }
    if let photo {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"fish.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
        body.append(photo)
        append("\r\n")
    }
    append("--\(boundary)--\r\n")
    return body
}

/// Convert an explicitly labelled catch weight to grams, rejecting ambiguous input.
public func weightInGrams(_ value: String) -> Double? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    func matches(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
    }
    if let parts = matches(#"^(\d+(?:\.\d+)?)\s*(kg|kilograms?|g|grams?|oz|ounces?)$"#), let number = Double(parts[1]), number > 0, number.isFinite {
        if parts[2] == "kg" || parts[2].hasPrefix("kilogram") { return number * 1000 }
        if parts[2] == "oz" || parts[2].hasPrefix("ounce") { return number * 28.349523125 }
        return number
    }
    if let parts = matches(#"^(\d+(?:\.\d+)?)\s*(?:lb|lbs|pounds?)(?:\s*(\d+(?:\.\d+)?)\s*(?:oz|ounces?))?$"#), let pounds = Double(parts[1]), let ounces = Double(parts[2].isEmpty ? "0" : parts[2]), pounds.isFinite, ounces.isFinite, ounces < 16, pounds * 16 + ounces > 0 {
        return pounds * 453.59237 + ounces * 28.349523125
    }
    return nil
}

/// Return British English month names independently of the device's calendar locale.
public func britishMonthNames() -> [String] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_GB")
    formatter.calendar = Calendar(identifier: .gregorian)
    return formatter.monthSymbols
}

/// Select a stable snapshot of records within map bounds.
public func recordsInArea(_ records: [Record], latitude: Double, longitude: Double, latitudeSpan: Double, longitudeSpan: Double, limit: Int) -> [Record] {
    guard latitudeSpan > 0, longitudeSpan > 0, limit > 0 else { return [] }
    return Array(records.lazy.filter { item in
        guard let lat = item.number("lat"), let lon = item.number("lon") else { return false }
        return abs(lat - latitude) < latitudeSpan / 2 && abs(lon - longitude) < longitudeSpan / 2
    }.prefix(limit))
}
