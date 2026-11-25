import SwiftUI

struct Country: Codable, Identifiable {
    var code: String
    var name: String
    var id: String { code }
    var flag: String {
        let subdivisions = ["GB-ENG": "gbeng", "GB-SCT": "gbsct", "GB-WLS": "gbwls"]
        if let name = subdivisions[code] { return String(String.UnicodeScalarView([UnicodeScalar(0x1f3f4)!] + name.unicodeScalars.compactMap { UnicodeScalar(0xe0000 + $0.value) } + [UnicodeScalar(0xe007f)!])) }
        if code == "GB-NIR" { return "🇬🇧" }
        guard code.count == 2 else { return "🌍" }
        return String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
    }
}
struct CountryAssignment: Decodable {
    var kind: String
    var record_id: String
    var country_code: String
}
struct CountryRecord: Identifiable {
    let kind: String
    let record: Record
    var id: String { kind + ":" + record.id }
}
struct CountriesView: View {
    @EnvironmentObject private var store: FishStore
    @State private var assignments: [CountryAssignment] = []
    @State private var loaded = false
    @State private var error = ""
    @State private var selecting: CountryRecord?
    @State private var search = ""
    var countries: [Country] {
        guard let url = Bundle.main.url(forResource: "fishing-countries", withExtension: "json"), let data = try? Data(contentsOf: url), let countries = try? JSONDecoder().decode([Country].self, from: data) else { return [] }
        return countries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func chosen(_ kind: String, _ id: String) -> String? { assignments.first { $0.kind == kind && $0.record_id == id }?.country_code }
    func effectiveCountry(_ catchItem: Record) -> String? {
        chosen("catch", catchItem.id) ?? store.trips.first { $0.strings("catch_ids").contains(catchItem.id) }.flatMap { chosen("trip", $0.id) }
    }
    var body: some View {
        List {
            if !error.isEmpty { Section { Text(error).foregroundStyle(.orange); Button("Try again") { Task { await load() } } } }
            if loaded {
                Section("Countries fished") {
                    let used = Set(assignments.map(\.country_code))
                    let visited = countries.filter { used.contains($0.code) }
                    if visited.isEmpty { Text("Choose a country for a trip or catch to start your collection.").foregroundStyle(.secondary) }
                    ForEach(visited) { country in
                        let trips = store.trips.filter { chosen("trip", $0.id) == country.code }
                        let catches = store.catches.filter { effectiveCountry($0) == country.code }
                        NavigationLink { CountryDetail(country: country, trips: trips, catches: catches) } label: { VStack(alignment: .leading) { Text("\(country.flag)  \(country.name)"); Text("\(trips.count) trips · \(catches.count) catches · \(Set(catches.map { $0.string("species").lowercased() }.filter { !$0.isEmpty }).count) species").font(.caption).foregroundStyle(.secondary) } }
                    }
                }
                Section("Assign countries") {
                    ForEach(store.trips) { item in Button { selecting = CountryRecord(kind: "trip", record: item) } label: { recordLabel(item, kind: "trip") } }
                    ForEach(store.catches) { item in Button { selecting = CountryRecord(kind: "catch", record: item) } label: { recordLabel(item, kind: "catch") } }
                }
                Section { Text("A catch inherits its trip’s country unless assigned separately. Names: iso-codes, LGPL-2.1+.").font(.footnote).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Countries fished").task { await load() }
            .sheet(item: $selecting) { selection in NavigationStack {
                List {
                    if chosen(selection.kind, selection.record.id) != nil { Button("Clear country", role: .destructive) { Task { await assign(nil, to: selection) } } }
                    ForEach(countries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { country in
                        Button("\(country.flag)  \(country.name)") { Task { await assign(country.code, to: selection) } }
                    }
                }.searchable(text: $search).navigationTitle("Choose country").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selecting = nil } } }
            } }
    }
    func recordLabel(_ record: Record, kind: String) -> some View {
        let code = chosen(kind, record.id) ?? (kind == "catch" ? effectiveCountry(record) : nil)
        return VStack(alignment: .leading) { Text(kind == "catch" ? record.string("species") : (record.string("place").isEmpty ? "Fishing trip" : record.string("place"))); Text("\(kind.capitalized) · \(britishDate(record.string("date"))) · \(countries.first { $0.code == code }?.name ?? "No country chosen")").font(.caption).foregroundStyle(.secondary) }
    }
    func load() async {
        do {
            guard let base = store.connectedAddress else { throw URLError(.notConnectedToInternet) }
            assignments = try JSONDecoder().decode([CountryAssignment].self, from: await store.fetch("/api/fishing-countries", base: base))
            loaded = true; error = ""
        } catch { self.error = "Countries are unavailable. Check your connection and that the server supports countries." }
    }
    func assign(_ code: String?, to record: CountryRecord) async {
        do {
            let expected = chosen(record.kind, record.record.id)
            _ = try await store.postJSON(path: "/api/fishing-countries", body: ["kind":record.kind, "record_id":record.record.id, "country_code":code as Any? ?? NSNull(), "expected":expected as Any? ?? NSNull()])
            selecting = nil; search = ""; await load()
        } catch { selecting = nil; self.error = error.localizedDescription }
    }
}
struct CountryDetail: View {
    let country: Country
    let trips: [Record]
    let catches: [Record]
    var body: some View {
        List {
            Section("Species") { ForEach(Array(Set(catches.map { $0.string("species") }.filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0) } }
            Section("Catches") { ForEach(catches) { item in NavigationLink { CatchDetail(item: item) } label: { CatchRow(item: item) } } }
            Section("Trips") { ForEach(trips) { item in NavigationLink { TripDetail(item: item) } label: { Text(item.string("place").isEmpty ? "Fishing trip" : item.string("place")) } } }
        }.navigationTitle("\(country.flag) \(country.name)")
    }
}
