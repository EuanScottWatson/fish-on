import SwiftUI
import MapKit

struct LicensedPhoto {
    let url: URL
    let credit: String
    init?(_ raw: Any?) {
        guard let raw = raw as? [String: Any], let url = URL(string: raw["medium_url"] as? String ?? ""),
              let credit = raw["attribution"] as? String, !credit.isEmpty,
              let licence = (raw["license_code"] as? String)?.lowercased(),
              ["cc0", "cc-by", "cc-by-sa", "cc-by-nc", "cc-by-nc-sa", "cc-by-nd", "cc-by-nc-nd"].contains(licence) else { return nil }
        self.url = url; self.credit = credit
    }
}

extension FishStore {
    func loadGuideIndex() async {
        guard guideIndex.isEmpty, let base = connectedAddress else { return }
        do {
            let data = try await fetch("/guide-images.json", base: base)
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { throw URLError(.cannotParseResponse) }
            guideIndex = result
        } catch { guideIndexError = "Photo and popularity information is unavailable." }
    }
    func guidePhoto(_ item: Record) -> LicensedPhoto? { LicensedPhoto(guideIndex[item.string("name").lowercased()]?["default_photo"]) }
    func popularity(_ item: Record) -> Int { (guideIndex[item.string("name").lowercased()]?["observations_count"] as? Int) ?? 0 }
}

struct SpeciesRangeView: View {
    let name: String
    @State private var key: Int?
    @State private var status = "Loading global records…"
    var body: some View {
        VStack(alignment: .leading) {
            if let key { GBIFMap(key: key).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 8)) }
            Text(status).font(.footnote).foregroundStyle(.secondary)
        }.task {
            var components = URLComponents(string: "https://api.gbif.org/v1/species/match")!
            components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "strict", value: "true")]
            do {
                guard let url = components.url else { throw URLError(.badURL) }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], value["rank"] as? String == "SPECIES", value["matchType"] as? String != "NONE", let taxon = (value["speciesKey"] as? Int) ?? (value["usageKey"] as? Int) else { throw URLError(.cannotParseResponse) }
                key = taxon; status = "Shading shows recorded observations, not a complete or current range. Data: GBIF contributors."
            } catch { status = "Global records are unavailable for this fish right now." }
        }
    }
}
struct GBIFMap: UIViewRepresentable {
    let key: Int
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(); map.delegate = context.coordinator
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 25, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 120)), animated: false)
        let overlay = MKTileOverlay(urlTemplate: "https://api.gbif.org/v2/map/occurrence/density/{z}/{x}/{y}@1x.png?taxonKey=\(key)&bin=hex&hexPerTile=57&style=green-noborder.poly")
        overlay.canReplaceMapContent = false; overlay.maximumZ = 12; map.addOverlay(overlay, level: .aboveLabels)
        return map
    }
    func updateUIView(_ view: MKMapView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay { let renderer = MKTileOverlayRenderer(tileOverlay: tiles); renderer.alpha = 0.78; return renderer }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

func fishingTip(_ name: String) -> String? {
    guard let url = Bundle.main.url(forResource: "fishing-tips", withExtension: "json"), let data = try? Data(contentsOf: url), let tips = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
    return tips[name]
}
