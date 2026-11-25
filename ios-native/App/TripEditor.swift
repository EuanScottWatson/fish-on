import SwiftUI
import PhotosUI
import UIKit

struct TripEditor: View {
    @EnvironmentObject private var store: FishStore
    @Environment(\.dismiss) private var dismiss
    @State var item: Record?
    @State private var id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    @State private var date = Date()
    @State private var endDate = Date()
    @State private var hasEndDate = false
    @State private var place = ""
    @State private var startTime = ""
    @State private var endTime = ""
    @State private var method = ""
    @State private var bait = ""
    @State private var targetSpecies = ""
    @State private var weather = ""
    @State private var notes = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var catchIDs: Set<String> = []
    @State private var map = false
    @StateObject private var location = CurrentLocation()
    @State private var busy = false
    @State private var error = ""
    private let dateFormat: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    var body: some View {
        Form {
            Section("Trip") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("End date", isOn: $hasEndDate)
                if hasEndDate { DatePicker("End date", selection: $endDate, displayedComponents: .date) }
                TextField("Place", text: $place)
                TextField("Start time (HH:MM)", text: $startTime)
                TextField("End time (HH:MM)", text: $endTime)
                TextField("Method", text: $method)
                TextField("Bait / lures", text: $bait)
                TextField("Target species", text: $targetSpecies)
                TextField("Weather", text: $weather)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            Section("Location") {
                Button("Use my current location") { location.request() }
                if let error = location.error { Text(error).foregroundStyle(.orange) }
                Button("Choose on map") { map = true }
                TextField("Latitude", text: $latitude).keyboardType(.numbersAndPunctuation)
                TextField("Longitude", text: $longitude).keyboardType(.numbersAndPunctuation)
            }
            Section("Catches on this trip") {
                if store.catches.isEmpty { Text("No saved catches yet.").foregroundStyle(.secondary) }
                ForEach(store.catches) { record in
                    let unavailable = store.trips.contains { $0.id != id && $0.strings("catch_ids").contains(record.id) }
                    Button { if catchIDs.contains(record.id) { catchIDs.remove(record.id) } else { catchIDs.insert(record.id) } } label: {
                        HStack { Image(systemName: catchIDs.contains(record.id) ? "checkmark.circle.fill" : "circle"); Text(record.string("species")); Spacer(); if unavailable { Text("Another trip").font(.caption) } }
                    }.disabled(unavailable)
                }
            }
            Section { Button(busy ? "Saving…" : "Save trip") { Task { await save() } }.disabled(busy); if !error.isEmpty { Text(error).foregroundStyle(.orange) }; Text("A connection is needed to save trips.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle(item == nil ? "Log a trip" : "Edit trip")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $map) { NavigationStack { LocationPicker(latitude: $latitude, longitude: $longitude) } }
            .onChange(of: location.coordinate?.latitude) { _ in if let point = location.coordinate { latitude = String(format: "%.6f", point.latitude); longitude = String(format: "%.6f", point.longitude) } }
            .onAppear { load() }
    }
    func load() {
        guard let item else { return }
        id = item.id; date = dateFormat.date(from: item.string("date")) ?? Date()
        if let value = dateFormat.date(from: item.string("end_date")) { endDate = value; hasEndDate = true }
        place = item.string("place"); startTime = item.string("start_time"); endTime = item.string("end_time")
        method = item.string("method"); bait = item.string("bait"); targetSpecies = item.string("target_species")
        weather = item.string("weather"); notes = item.string("notes"); latitude = item.string("latitude"); longitude = item.string("longitude")
        catchIDs = Set(item.strings("catch_ids"))
    }
    func save() async {
        guard latitude.isEmpty == longitude.isEmpty else { error = "Enter both coordinates or neither."; return }
        if !latitude.isEmpty && (Double(latitude).map { abs($0) <= 90 } != true || Double(longitude).map { abs($0) <= 180 } != true) { error = "Enter valid coordinates."; return }
        let values: [String: Any] = ["id":id,"date":dateFormat.string(from: date),"end_date":hasEndDate ? dateFormat.string(from: endDate) : "", "place":place,"start_time":startTime,"end_time":endTime,"timezone":item?.string("timezone") ?? "", "latitude":Double(latitude) as Any? ?? NSNull(),"longitude":Double(longitude) as Any? ?? NSNull(),"method":method,"bait":bait,"target_species":targetSpecies,"weather":weather,"notes":notes,"catch_ids":Array(catchIDs)]
        busy = true; defer { busy = false }
        do { _ = try await store.postJSON(path: "/api/trips", body: values); await store.refresh(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

extension FishStore {
    func postJSON(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let base = connectedAddress, let url = URL(string: base + path) else { throw URLError(.notConnectedToInternet) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else { throw FishError.message(object["error"] as? String ?? "The server returned HTTP \(http.statusCode).") }
        return object
    }
}

struct TripPhotoPicker: View {
    @EnvironmentObject private var store: FishStore
    let trip: Record
    @State private var photo: PhotosPickerItem?
    @State private var message = ""
    @State private var busy = false
    @State private var pending: (id: String, data: Data)?
    @State private var deleting: String?
    var photos: [[String: String]] { trip.values["photos"] as? [[String: String]] ?? [] }
    var body: some View {
        Section("Trip photos") {
            ForEach(photos, id: \.self) { photo in
                if let base = store.connectedAddress, let path = photo["url"], let url = URL(string: base + path) { AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }; if let id = photo["id"] { Button("Remove photo", role: .destructive) { deleting = id } } }
            }
            PhotosPicker(selection: $photo, matching: .images) { Text(busy ? "Uploading…" : "Add a trip photo") }.disabled(busy)
            if pending != nil { Button("Retry photo upload") { Task { await upload() } }.disabled(busy) }
            if !message.isEmpty { Text(message).foregroundStyle(.orange) }
        }.confirmationDialog("Remove this trip photo?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Remove photo", role: .destructive) { if let id = deleting { Task { do { try await store.delete(path: "/api/trips/\(trip.id)/photos/\(id)"); await store.refresh() } catch { message = error.localizedDescription }; deleting = nil } } } }.onChange(of: photo) { item in
            guard let item else { return }
            Task {
                busy = true; defer { busy = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.normalisedJPEG() else { throw FishError.message("Could not read the photo.") }
                    pending = (UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), jpeg)
                    busy = false
                    await upload()
                    busy = true
                } catch { message = error.localizedDescription }
            }
        }
    }
    func upload() async {
        guard !busy, let pending else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await store.sendMultipart(path: "/api/trips/\(trip.id)/photos", fields: ["photo_id": pending.id], photo: pending.data)
            self.pending = nil; await store.refresh(); message = "Photo uploaded."
        } catch { message = "Photo not uploaded: \(error.localizedDescription). You can retry." }
    }

}
