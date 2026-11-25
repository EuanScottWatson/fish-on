import SwiftUI
import MapKit

@main
struct FishOnApp: App {
    @StateObject private var store = FishStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).preferredColorScheme(.dark)
                .tint(Color(red: 0.79, green: 0.84, blue: 0.53))
                .environment(\.locale, Locale(identifier: "en_GB"))
                .task { store.loadDrafts(); store.loadCachedRecords(); await store.refresh(); await store.syncDrafts() }
                .onChange(of: scenePhase) { phase in if phase == .active { Task { await store.refresh(); await store.syncDrafts() } } }
        }
    }
}

@MainActor
final class FishStore: ObservableObject {
    @Published var catches: [Record] = []
    @Published var drafts: [CatchDraft] = []
    @Published var draftError: String?
    @Published var syncError: String?
    @Published var syncing = false
    @Published var trips: [Record] = []
    @Published var fish: [Record] = []
    @Published var guideIndex: [String: [String: Any]] = [:]
    @Published var guideIndexError: String?
    @Published var connectedAddress: String?
    @Published var error: String?
    @Published var guideError: String?
    @Published var loading = false
    @Published var customAddress = UserDefaults.standard.string(forKey: "server") ?? ""
    private let defaults = ["http://192.168.32.48:7782", "http://100.94.227.14:7782"]
    var addresses: [String] {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FISH_UI_TEST"] == "1" { return ["http://127.0.0.1:18782"] }
        #endif
        var result: [String] = []
        for address in [customAddress.trimmingCharacters(in: .whitespacesAndNewlines)] + defaults {
            let cleaned = address.hasSuffix("/") ? String(address.dropLast()) : address
            if !cleaned.isEmpty && !result.contains(cleaned) { result.append(cleaned) }
        }
        return result
    }
    func saveAddress() {
        UserDefaults.standard.set(customAddress, forKey: "server")
    }
    func fetch(_ path: String, base: String) async throws -> Data {
        guard let url = URL(string: base + path), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        error = nil
        for base in addresses {
            do {
                let health = try await fetch("/health", base: base)
                guard let body = try JSONSerialization.jsonObject(with: health) as? [String: Any], body["ok"] as? Bool == true else { throw URLError(.badServerResponse) }
                let catchData = try await fetch("/api/catches", base: base)
                let tripData = try await fetch("/api/trips", base: base)
                let loadedCatches = try decodeRecords(catchData)
                let loadedTrips = try decodeRecords(tripData)
                cacheRecords(catchData: catchData, tripData: tripData)
                catches = loadedCatches
                trips = loadedTrips
                connectedAddress = base
                return
            } catch { continue }
        }
        connectedAddress = nil
        error = "Can't reach Fish On. Check your home Wi-Fi or connect Tailscale, then try again."
    }
    func loadGuide() async {
        guard fish.isEmpty, let base = connectedAddress else { return }
        do { fish = try decodeRecords(await fetch("/fishbase.json", base: base)); guideError = nil }
        catch { guideError = "Could not load the fish guide. Try again when connected." }
    }
    func photoURL(_ filename: String) -> URL? {
        guard let base = connectedAddress, !filename.isEmpty,
              let escaped = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: base + "/photos/" + escaped)
    }
}

struct RootView: View {
    @EnvironmentObject private var store: FishStore
    @State private var settings = false
    @State private var logging = false
    var body: some View {
        TabView {
            NavigationStack { HomeView().toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Connection settings") } } }.tabItem { Label("Home", systemImage: "house") }
            NavigationStack { CatchesView() }.tabItem { Label("Catches", systemImage: "photo.stack") }
            NavigationStack { GuideView() }.tabItem { Label("Guide", systemImage: "book") }
            NavigationStack { TripsView() }.tabItem { Label("Trips", systemImage: "binoculars") }
            NavigationStack { CatchMapView() }.tabItem { Label("Map", systemImage: "map") }
        }
        .sheet(isPresented: $settings) { NavigationStack { ConnectionView() } }
        .sheet(isPresented: $logging) { NavigationStack { CatchEditor(draft: CatchDraft(), editingExisting: false) } }
        .environment(\.logCatch, { logging = true })
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: FishStore
    @Environment(\.logCatch) private var logCatch
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("FISH ON · NATIVE PREVIEW").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                Text("You should've seen the one that got away!").font(.largeTitle.bold())
                Text("Your fishing journal, close at hand.").foregroundStyle(.secondary)
                Button("Log a catch") { logCatch() }.buttonStyle(.borderedProminent)
                if let error = store.draftError ?? store.syncError { Text(error).foregroundStyle(.orange) }
                if let error = store.error { Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(.orange) }
                else if let address = store.connectedAddress { Label("Connected · \(address)", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary) }
                HStack(spacing: 28) {
                    VStack(alignment: .leading) { Text("\(store.catches.count)").font(.title.bold()); Text("Catches").foregroundStyle(.secondary) }
                    VStack(alignment: .leading) { Text("\(store.trips.count)").font(.title.bold()); Text("Trips").foregroundStyle(.secondary) }
                }.padding(.vertical)
                NavigationLink { StatisticsView() } label: { Label("Your statistics", systemImage: "chart.bar") }
                NavigationLink { CountriesView() } label: { Label("Countries fished", systemImage: "globe.europe.africa") }
                NavigationLink { DiscoveryView() } label: { Label("Fish nearby", systemImage: "map") }
                Text("Recent catches").font(.title2.bold())
                ForEach(Array(store.catches.prefix(4))) { item in NavigationLink { CatchDetail(item: item) } label: { CatchRow(item: item) }.buttonStyle(.plain) }

            }.padding()
        }.navigationTitle("Fish On").refreshable { await store.refresh() }
    }
}

struct CatchRow: View {
    @EnvironmentObject private var store: FishStore
    let item: Record
    var body: some View {
        HStack(spacing: 12) {
            if let url = store.photoURL(item.string("photo")) { AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.2) }.frame(width: 70, height: 70).clipped().cornerRadius(6) }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.string("species").isEmpty ? "Catch" : item.string("species")).font(.headline)
                Text([item.string("place"), britishDate(item.string("date"))].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(.vertical, 4)
    }
}

struct CatchesView: View {
    @EnvironmentObject private var store: FishStore
    @State private var search = ""
    @State private var editDraft: CatchDraft?
    @Environment(\.logCatch) private var logCatch
    var matches: [Record] { store.catches.filter { search.isEmpty || "\($0.string("species")) \($0.string("place"))".localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            if !store.drafts.isEmpty { Section("Saved on this phone") { ForEach(store.drafts) { draft in Button { editDraft = draft } label: { VStack(alignment: .leading) { Text(draft.species.isEmpty ? "Photo to identify" : draft.species); Text(draft.ready ? "Waiting to sync" : "Review and identify").font(.caption).foregroundStyle(.secondary) } } } } }
            Section("Your catches") { ForEach(matches) { item in NavigationLink { CatchDetail(item: item) } label: { CatchRow(item: item) } } }
        }
            .navigationTitle("Catches").searchable(text: $search).refreshable { await store.refresh(); await store.syncDrafts() }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Log catch") { logCatch() } } }
            .sheet(item: $editDraft) { draft in NavigationStack { CatchEditor(draft: draft, editingExisting: true) } }
    }
}

struct CatchDetail: View {
    @EnvironmentObject private var store: FishStore
    let item: Record
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            if let url = store.photoURL(item.string("photo")) { AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView().frame(maxWidth: .infinity, minHeight: 160) } }
            Text(item.string("scientific")).italic().foregroundStyle(.secondary)
            Text("\(item.string("place")) · \(britishDate(item.string("date")))")
            ForEach(["weight", "length", "tackle", "notes"], id: \.self) { key in
                if !item.string(key).isEmpty { VStack(alignment: .leading, spacing: 4) { Text(key == "tackle" ? "Bait / tackle" : key.capitalized).font(.caption.weight(.bold)).foregroundStyle(.secondary); Text(item.string(key)) } }
            }
            Button("Edit catch") { editing = true }.buttonStyle(.bordered)
            Button("Delete catch", role: .destructive) { confirmingDelete = true }
            if !error.isEmpty { Text(error).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding() }.navigationTitle(item.string("species")).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) { NavigationStack { CatchEditor(draft: CatchDraft(item), editingExisting: true) } }
            .confirmationDialog("Delete this catch and its photo?", isPresented: $confirmingDelete) { Button("Delete", role: .destructive) { Task { do { try await store.delete(path: "/api/catches/" + item.id); await store.refresh(); dismiss() } catch { self.error = error.localizedDescription } } } }
    }
}

struct GuideView: View {
    @EnvironmentObject private var store: FishStore
    @State private var search = ""
    @State private var ukOnly = true
    @State private var water = "All"
    @State private var sort = "Popular"
    var matches: [Record] {
        let filtered = store.fish.filter { item in
            let names = ([item.string("common"), item.string("name")] + item.strings("aliases")).joined(separator: " ")
            return (!ukOnly || item.flag("uk")) && (water == "All" || item.flag(water == "Fresh" ? "fresh" : water == "Marine" ? "salt" : "brack")) && (search.isEmpty || names.localizedCaseInsensitiveContains(search))
        }
        return Array(filtered.sorted { a, b in
            if sort == "Popular" && store.popularity(a) != store.popularity(b) { return store.popularity(a) > store.popularity(b) }
            if sort == "Length" && (a.number("length") ?? 0) != (b.number("length") ?? 0) { return (a.number("length") ?? 0) > (b.number("length") ?? 0) }
            return (sort == "Scientific" ? a.string("name") : a.string("common")).localizedCaseInsensitiveCompare(sort == "Scientific" ? b.string("name") : b.string("common")) == .orderedAscending
        }.prefix(150))
    }
    var body: some View {
        List {
            Toggle("Recorded in the UK", isOn: $ukOnly)
            Picker("Water", selection: $water) { ForEach(["All", "Fresh", "Marine", "Brackish"], id: \.self) { Text($0) } }
            Picker("Sort", selection: $sort) { ForEach(["Popular", "Name", "Scientific", "Length"], id: \.self) { Text($0) } }
            if sort == "Popular" { Text(store.guideIndexError ?? "Popularity uses worldwide iNaturalist observations.").font(.footnote).foregroundStyle(.secondary) }
            if store.fish.isEmpty { Text(store.guideError ?? "Loading fish guide…").foregroundStyle(.secondary) }
            ForEach(matches) { item in NavigationLink { FishDetail(item: item) } label: { HStack { if let photo = store.guidePhoto(item) { AsyncImage(url: photo.url) { image in image.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.2) }.frame(width: 60, height: 60).clipped() }; VStack(alignment: .leading) { Text(item.string("common").isEmpty ? item.string("name") : item.string("common")); Text(item.string("name")).font(.caption).italic().foregroundStyle(.secondary) } } } }
            if !matches.isEmpty { Text("Showing up to 150 results. Search to narrow the list.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Fish guide").searchable(text: $search).task { await store.loadGuide(); await store.loadGuideIndex() }.refreshable { await store.loadGuide() }
    }
}

struct FishDetail: View {
    @EnvironmentObject private var store: FishStore
    let item: Record
    var body: some View {
        List {
            Section { if let photo = store.guidePhoto(item) { AsyncImage(url: photo.url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }; Text(photo.credit).font(.caption).foregroundStyle(.secondary) }; Text(item.string("name")).italic(); if !item.string("biology").isEmpty { Text(item.string("biology")) } }
            if let tip = fishingTip(item.string("name")) { Section("Fishing") { Text(tip) } }
            Section("Where it has been recorded") { SpeciesRangeView(name: item.string("name")) }
            Section("Habitat") { Text([item.flag("fresh") ? "Freshwater" : "", item.flag("salt") ? "Marine" : "", item.flag("brack") ? "Brackish" : ""].filter { !$0.isEmpty }.joined(separator: ", ")) }
            if !item.strings("countries").isEmpty { Section("Recorded countries") { Text(item.strings("countries").joined(separator: ", ")) } }
            Section { Text("FishBase, Froese & Pauly (eds.), 06/2026, CC BY-NC 4.0. Records do not guarantee current presence.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle(item.string("common").isEmpty ? item.string("name") : item.string("common"))
    }
}

struct TripsView: View {
    @EnvironmentObject private var store: FishStore
    @State private var adding = false
    var body: some View {
        List(store.trips) { item in NavigationLink { TripDetail(item: item) } label: { VStack(alignment: .leading) { Text(item.string("place").isEmpty ? "Fishing trip" : item.string("place")); Text(britishDate(item.string("date"))).font(.subheadline).foregroundStyle(.secondary) } } }
            .navigationTitle("Trips").refreshable { await store.refresh() }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Log trip") { adding = true } } }
            .sheet(isPresented: $adding) { NavigationStack { TripEditor(item: nil) } }
    }
}
struct TripDetail: View {
    @EnvironmentObject private var store: FishStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var message = ""
    let item: Record
    var body: some View {
        List { ForEach(["date", "end_date", "start_time", "end_time", "method", "bait", "target_species", "weather", "notes"], id: \.self) { key in
            if !item.string(key).isEmpty { LabeledContent(key.replacingOccurrences(of: "_", with: " ").capitalized, value: key.contains("date") ? britishDate(item.string(key)) : item.string(key)) }
        }
            Section("Catches") { ForEach(store.catches.filter { item.strings("catch_ids").contains($0.id) }) { catchItem in NavigationLink { CatchDetail(item: catchItem) } label: { CatchRow(item: catchItem) } } }
            TripPhotoPicker(trip: item)
            Section { Button("Edit trip") { editing = true }; Button("Delete trip", role: .destructive) { deleting = true }; if !message.isEmpty { Text(message).foregroundStyle(.orange) } }
        }.navigationTitle(item.string("place").isEmpty ? "Fishing trip" : item.string("place"))
            .sheet(isPresented: $editing) { NavigationStack { TripEditor(item: item) } }
            .confirmationDialog("Delete this trip? Catches will be kept.", isPresented: $deleting) { Button("Delete trip", role: .destructive) { Task { do { try await store.delete(path: "/api/trips/" + item.id); await store.refresh(); dismiss() } catch { message = error.localizedDescription } } } }
    }
}
struct CatchMapView: View {
    @EnvironmentObject private var store: FishStore
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 53, longitude: -2), span: MKCoordinateSpan(latitudeDelta: 9, longitudeDelta: 8))
    var located: [Record] { store.catches.filter { $0.number("lat") != nil && $0.number("lon") != nil } }
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: located) { item in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.number("lat") ?? 0, longitude: item.number("lon") ?? 0)) {
                NavigationLink { CatchDetail(item: item) } label: { Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(.red) }.accessibilityLabel(item.string("species"))
            }
        }.navigationTitle("Catch map").navigationBarTitleDisplayMode(.inline)
    }
}
struct ConnectionView: View {
    @EnvironmentObject private var store: FishStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("Connection") {
                Text(store.connectedAddress.map { "Connected: \($0)" } ?? "Not connected")
                TextField("Optional server address", text: $store.customAddress).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Save and reconnect") { store.saveAddress(); Task { await store.refresh() } }.disabled(store.loading)
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }
            Section { Text("Fish On tries your custom address, then your home network and Tailscale addresses. Away from home, connect Tailscale first. HTTP is for your private network.") }
        }.navigationTitle("Connection").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

private struct LogCatchKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues { var logCatch: () -> Void { get { self[LogCatchKey.self] } set { self[LogCatchKey.self] = newValue } } }
