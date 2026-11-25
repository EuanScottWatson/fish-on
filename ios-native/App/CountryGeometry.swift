import Foundation

func suggestCountry(latitude: Double?, longitude: Double?) -> String? {
    guard let lat = latitude, let lon = longitude, lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180,
          let url = Bundle.main.url(forResource: "country-boundaries", withExtension: "json"), let data = try? Data(contentsOf: url),
          let features = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
    for feature in features {
        guard let geometry = feature["geometry"] as? [String: Any], let type = geometry["type"] as? String else { continue }
        var polygons: [[[[Double]]]] = []
        if type == "Polygon", let polygon = geometry["coordinates"] as? [[[Double]]] { polygons = [polygon] }
        if type == "MultiPolygon", let multi = geometry["coordinates"] as? [[[[Double]]]] { polygons = multi }
        for polygon in polygons where !polygon.isEmpty {
            if inRing(lon, lat, polygon[0]) && !polygon.dropFirst().contains(where: { inRing(lon, lat, $0) }) { return feature["code"] as? String }
        }
    }
    return nil
}
private func inRing(_ x: Double, _ y: Double, _ ring: [[Double]]) -> Bool {
    guard ring.count > 2 else { return false }
    var inside = false
    var previous = ring.count - 1
    for index in ring.indices {
        let point = ring[index], prior = ring[previous]
        if point.count >= 2 && prior.count >= 2 && (point[1] > y) != (prior[1] > y) && x < (prior[0] - point[0]) * (y - point[1]) / (prior[1] - point[1]) + point[0] { inside.toggle() }
        previous = index
    }
    return inside
}
