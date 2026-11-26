import SwiftUI
import MapKit

struct DiscoveryView: View {
    @EnvironmentObject private var store: FishStore
    @State private var surveys: [Record] = []
    @State private var surveyResults: [Record] = []
    @State private var observations: [Record] = []
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 53, longitude: -2), span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4))
    @State private var mode = "Surveys"
    @State private var message = "Press Search this area to find records."
    @State private var searching = false
    @State private var requestID = UUID()
    var visible: [Record] { mode == "Surveys" ? surveyResults : observations }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Layer", selection: $mode) { Text("Surveys").tag("Surveys"); Text("Observations").tag("Observations") }.pickerStyle(.segmented).padding()
            Button(searching ? "Searching…" : "Search this area") { Task { await searchArea() } }.disabled(searching).padding(.bottom)
            Map(coordinateRegion: $region, annotationItems: visible) { item in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.number("lat") ?? 0, longitude: item.number("lon") ?? 0)) {
                    NavigationLink { DiscoveryDetail(item: item, survey: mode == "Surveys") } label: { Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(mode == "Surveys" ? .orange : .green) }.accessibilityLabel(item.string("name"))
                }
            }
            Text(message).font(.footnote).foregroundStyle(.secondary).padding(8)
        }.navigationTitle("Fish nearby")
            .onChange(of: mode) { _ in requestID = UUID(); searching = false; message = "Press Search this area to find records." }
    }
    func searchArea() async {
        let area = region
        let searchMode = mode
        let id = UUID()
        requestID = id
        guard area.span.latitudeDelta <= 4 && area.span.longitudeDelta <= 4 else { message = "Zoom in to search a smaller area."; return }
        searching = true
        message = "Searching this area…"
        defer { if requestID == id { searching = false } }
        do {
            if searchMode == "Surveys" {
                if surveys.isEmpty {
                    guard let base = store.connectedAddress else { throw URLError(.notConnectedToInternet) }
                    let data = try await store.fetch("/surveys.json", base: base)
                    guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
                    surveys = rows.enumerated().map { index, value in var copy = value; copy["id"] = "survey-\(index)"; return Record(copy) }
                }
                guard requestID == id else { return }
                surveyResults = recordsInArea(surveys, latitude: area.center.latitude, longitude: area.center.longitude, latitudeSpan: area.span.latitudeDelta, longitudeSpan: area.span.longitudeDelta, limit: 500)
                message = "Showing \(surveyResults.count) surveys in the searched area. Historic records do not imply fishing access. © Environment Agency."
            } else {
                let results = try await findObservations(in: area)
                guard requestID == id else { return }
                observations = results
                message = "Showing \(observations.count) observations in the searched area. Community records do not imply fishing access."
            }
        } catch {
            guard requestID == id else { return }
            message = "Could not load \(searchMode.lowercased()). Check your connection and try again."
        }
    }
    func findObservations(in area: MKCoordinateRegion) async throws -> [Record] {
        var components = URLComponents(string: "https://api.inaturalist.org/v1/observations")!
        let values = ["taxon_id":"47178", "swlat":String(area.center.latitude-area.span.latitudeDelta/2), "swlng":String(area.center.longitude-area.span.longitudeDelta/2), "nelat":String(area.center.latitude+area.span.latitudeDelta/2), "nelng":String(area.center.longitude+area.span.longitudeDelta/2), "geoprivacy":"open", "per_page":"100", "order_by":"observed_on", "order":"desc"]
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = result["results"] as? [[String: Any]] else { throw URLError(.badServerResponse) }
        return rows.compactMap { value in
            guard let geo = value["geojson"] as? [String: Any], let points = geo["coordinates"] as? [Double], points.count >= 2 else { return nil }
            var copy = value; copy["lat"] = points[1]; copy["lon"] = points[0]; let taxon = value["taxon"] as? [String: Any] ?? [:]; copy["name"] = taxon["preferred_common_name"] ?? taxon["name"] ?? "Fish"; return Record(copy)
        }
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
