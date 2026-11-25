import SwiftUI
import MapKit

struct DiscoveryView: View {
    @EnvironmentObject private var store: FishStore
    @State private var surveys: [Record] = []
    @State private var observations: [Record] = []
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 53, longitude: -2), span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4))
    @State private var mode = "Surveys"
    @State private var message = ""
    var visible: [Record] {
        let records = mode == "Surveys" ? surveys : observations
        return Array(records.lazy.filter { item in
            guard let lat = item.number("lat"), let lon = item.number("lon") else { return false }
            return abs(lat - region.center.latitude) < region.span.latitudeDelta / 2 && abs(lon - region.center.longitude) < region.span.longitudeDelta / 2
        }.prefix(500))
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Layer", selection: $mode) { Text("Surveys").tag("Surveys"); Text("Observations").tag("Observations") }.pickerStyle(.segmented).padding()
            if mode == "Observations" { Button("Search this area") { Task { await search() } }.padding(.bottom) }
            Map(coordinateRegion: $region, annotationItems: visible) { item in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.number("lat") ?? 0, longitude: item.number("lon") ?? 0)) {
                    NavigationLink { DiscoveryDetail(item: item, survey: mode == "Surveys") } label: { Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(mode == "Surveys" ? .orange : .green) }.accessibilityLabel(item.string("name"))
                }
            }
            Text(message.isEmpty ? (mode == "Surveys" ? "Historic Environment Agency surveys, up to 500 in this area. Records do not imply fishing access." : "Community observations from iNaturalist, not stocking records.") : message).font(.footnote).foregroundStyle(.secondary).padding(8)
        }.navigationTitle("Fish nearby").task { await loadSurveys() }
    }
    func loadSurveys() async {
        guard surveys.isEmpty, let base = store.connectedAddress else { return }
        do {
            let data = try await store.fetch("/surveys.json", base: base)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
            surveys = rows.enumerated().map { index, value in var copy = value; copy["id"] = "survey-\(index)"; return Record(copy) }
        } catch { message = "Could not load surveys. Check your connection." }
    }
    func search() async {
        guard region.span.latitudeDelta <= 4 && region.span.longitudeDelta <= 4 else { message = "Zoom in to search a smaller area."; return }
        var components = URLComponents(string: "https://api.inaturalist.org/v1/observations")!
        let values = ["taxon_id":"47178", "swlat":String(region.center.latitude-region.span.latitudeDelta/2), "swlng":String(region.center.longitude-region.span.longitudeDelta/2), "nelat":String(region.center.latitude+region.span.latitudeDelta/2), "nelng":String(region.center.longitude+region.span.longitudeDelta/2), "geoprivacy":"open", "per_page":"100", "order_by":"observed_on", "order":"desc"]
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        do {
            guard let url = components.url else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = result["results"] as? [[String: Any]] else { throw URLError(.badServerResponse) }
            observations = rows.compactMap { value in
                guard let geo = value["geojson"] as? [String: Any], let points = geo["coordinates"] as? [Double], points.count >= 2 else { return nil }
                var copy = value; copy["lat"] = points[1]; copy["lon"] = points[0]; let taxon = value["taxon"] as? [String: Any] ?? [:]; copy["name"] = taxon["preferred_common_name"] ?? taxon["name"] ?? "Fish"; return Record(copy)
            }
            message = "Showing \(observations.count) observations."
        } catch { message = "Could not load observations. Check your connection." }
    }
}
struct DiscoveryDetail: View {
    let item: Record
    let survey: Bool
    var body: some View {
        List {
            if survey {
                LabeledContent("Water", value: item.string("water")); LabeledContent("Latest survey", value: item.string("latest"))
                if let species = item.values["species"] as? [String: Any] { Section("Recorded fish") { ForEach(species.keys.sorted(), id: \.self) { name in LabeledContent(name, value: String(describing: species[name] ?? "")) } } }
                Text("Environment Agency freshwater survey snapshot. Historic records do not imply fishing access.").font(.footnote).foregroundStyle(.secondary)
            } else {
                LabeledContent("Observed", value: item.string("observed_on")); Text(item.string("place_guess"))
                if let url = URL(string: "https://www.inaturalist.org/observations/" + item.id) { Link("Open iNaturalist observation", destination: url) }
                Text("A community observation, not a stocking event or proof of fishing access.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle(item.string("name").isEmpty ? "Fish record" : item.string("name"))
    }
}
