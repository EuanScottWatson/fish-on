import SwiftUI
import PhotosUI
import MapKit
import UIKit

struct CatchEditor: View {
    @EnvironmentObject private var store: FishStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: CatchDraft
    @State private var picked: PhotosPickerItem?
    @State private var camera = false
    @State private var crop = false
    @State private var mapPicker = false
    @StateObject private var location = CurrentLocation()
    @State private var box: CGRect?
    @State private var photoData: Data?
    @State private var suggestions: [[String: Any]] = []
    @State private var scoreType = ""
    @State private var message = ""
    @State private var busy = false
    @State private var hasDate = false
    @State private var selectedDate = Date()
    let editingExisting: Bool
    private let dateFormat: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    var body: some View {
        Form {
            Section("Photograph") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { Button("Take a photo") { camera = true } }
                PhotosPicker(selection: $picked, matching: .images) { Label("Choose from Photos", systemImage: "photo") }
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 320)
                    Button("Draw or adjust fish box") { crop = true }
                    Button(busy ? "Identifying…" : "Identify fish") { Task { await identify() } }.disabled(busy)
                }
                if !message.isEmpty { Text(message).font(.footnote) }
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                    Button(suggestionLabel(suggestion)) {
                        draft.species = (suggestion["common"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (suggestion["scientific"] as? String ?? "")
                        draft.scientific = suggestion["scientific"] as? String ?? ""
                    }
                }
            }
            Section("Catch details") {
                TextField("Fish species", text: $draft.species)
                TextField("Scientific name", text: $draft.scientific)
                Toggle("Date recorded", isOn: $hasDate)
                if hasDate { DatePicker("Date caught", selection: $selectedDate, displayedComponents: .date) }
                TextField("Place", text: $draft.place)
                TextField("Weight", text: $draft.weight)
                TextField("Length", text: $draft.length)
                TextField("Bait / tackle", text: $draft.tackle)
                TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
            }
            Section("Location") {
                Button("Use my current location") { location.request() }
                if let error = location.error { Text(error).foregroundStyle(.orange) }
                Button("Choose on map") { mapPicker = true }
                TextField("Latitude", text: $draft.lat).keyboardType(.numbersAndPunctuation)
                TextField("Longitude", text: $draft.lon).keyboardType(.numbersAndPunctuation)
            }
            Section {
                Button("Save catch") { save() }.disabled(busy)
                Text("Catches are saved on this phone first. Named catches sync when the server is available; photographs without a species remain here for review.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(editingExisting ? "Edit catch" : "Log a catch")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onChange(of: location.coordinate?.latitude) { _ in if let point = location.coordinate { draft.lat = String(format: "%.6f", point.latitude); draft.lon = String(format: "%.6f", point.longitude) } }
        .onAppear {
            if let date = dateFormat.date(from: draft.date) { hasDate = true; selectedDate = date }
            if let name = draft.photoFile { do { photoData = try DraftStorage.photo(name) } catch { message = "Could not load the saved photo: \(error.localizedDescription)" } }
        }
        .onChange(of: picked) { item in
            guard let item else { return }
            Task { do { if let data = try await item.loadTransferable(type: Data.self) { applyPhoto(data) } else { message = "Could not read that photo." } } catch { message = "Could not read that photo: \(error.localizedDescription)" } }
        }
        .sheet(isPresented: $camera) { CameraPicker { data in applyPhoto(data) } }
        .sheet(isPresented: $crop) { if let photoData, let image = UIImage(data: photoData) { NavigationStack { CropView(image: image, box: $box) } } }
        .sheet(isPresented: $mapPicker) { NavigationStack { LocationPicker(latitude: $draft.lat, longitude: $draft.lon) } }
    }
    func applyPhoto(_ original: Data) {
        guard let image = UIImage(data: original), let converted = image.normalisedJPEG() else { message = "Could not open this image."; return }
        let metadata = PhotoMetadata(data: original)
        do {
            let previous = draft.photoFile
            draft.photoFile = try DraftStorage.storePhoto(converted, id: draft.id)
            photoData = converted; box = nil; suggestions = []
            if draft.date.isEmpty, let value = metadata.date, let date = dateFormat.date(from: value) { hasDate = true; selectedDate = date }
            if draft.lat.isEmpty && draft.lon.isEmpty, let lat = metadata.latitude, let lon = metadata.longitude { draft.lat = String(lat); draft.lon = String(lon) }
            // Existing draft images remain until the new draft is durably saved.
            if previous == nil { message = "Photo added. Identify it now or save and review later." }
            else { message = "Photo replaced in this editor." }
        } catch { message = "Could not save this photo on your phone: \(error.localizedDescription)" }
    }
    func save() {
        guard !draft.species.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.photoFile != nil else { message = "Add a photo or enter a species."; return }
        if draft.lat.isEmpty != draft.lon.isEmpty { message = "Enter both coordinates or neither."; return }
        if !draft.lat.isEmpty && (Double(draft.lat).map { abs($0) <= 90 } != true || Double(draft.lon).map { abs($0) <= 180 } != true) { message = "Enter valid coordinates."; return }
        draft.date = hasDate ? dateFormat.string(from: selectedDate) : ""
        draft.ready = !draft.species.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        do { try store.saveDraft(draft); dismiss(); Task { await store.syncDrafts() } }
        catch { message = "Could not save the catch on your phone: \(error.localizedDescription)" }
    }
    func suggestionLabel(_ item: [String: Any]) -> String {
        let name = (item["common"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (item["scientific"] as? String ?? "Fish")
        if scoreType == "similarity", let value = item["similarity"] as? Double { return "\(name) · match \(String(format: "%.2f", value))" }
        if let value = item["probability"] as? Double { return "\(name) · \(Int((value * 100).rounded()))%" }
        return name
    }
    func identify() async {
        guard let photoData else { return }
        busy = true; defer { busy = false }
        do {
            if box == nil {
                message = "Finding the fish…"
                let result = try await store.sendMultipart(path: "/api/detect", fields: [:], photo: photoData, timeout: 15)
                if let rect = result["box"] as? [String: Double], let x = rect["x"], let y = rect["y"], let w = rect["w"], let h = rect["h"], w > 0, h > 0 { box = CGRect(x: x, y: y, width: w, height: h) }
                else { message = "Draw a box around the fish, then identify it."; return }
            }
            guard let image = UIImage(data: photoData), let selected = box, let cropped = image.croppedJPEG(normalised: selected) else { message = "Could not crop the fish. Adjust the box and try again."; return }
            message = "Identifying your fish…"
            let result = try await store.sendMultipart(path: "/api/identify", fields: [:], photo: cropped, timeout: 110)
            suggestions = result["suggestions"] as? [[String: Any]] ?? []
            scoreType = result["score_type"] as? String ?? "probability"
            message = suggestions.isEmpty ? "No suggestions found. Adjust the box and try again." : (scoreType == "similarity" ? "Choose a suggestion. Match scores are not probabilities." : "Choose a suggestion after checking it.")
        } catch { message = "Identification unavailable: \(error.localizedDescription). You can save the photo and review it later." }
    }
}

extension UIImage {
    func normalisedJPEG() -> Data? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let ratio = min(1, 3000 / max(size.width, size.height))
        let size = CGSize(width: size.width * ratio, height: size.height * ratio)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
        return image.jpegData(compressionQuality: 0.88)
    }
    func croppedJPEG(normalised box: CGRect) -> Data? {
        guard let source = cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let rect = CGRect(x: box.minX * bounds.width, y: box.minY * bounds.height, width: box.width * bounds.width, height: box.height * bounds.height).intersection(bounds).integral
        guard !rect.isEmpty, let crop = source.cropping(to: rect) else { return nil }
        return UIImage(cgImage: crop).jpegData(compressionQuality: 0.9)
    }
}

struct CropView: View {
    let image: UIImage
    @Binding var box: CGRect?
    @Environment(\.dismiss) private var dismiss
    @State private var start: CGPoint?
    @State private var current: CGPoint?
    var body: some View {
        GeometryReader { geo in
            let ratio = image.size.width / image.size.height
            let width = min(geo.size.width, geo.size.height * ratio)
            let height = width / ratio
            VStack {
                Text("Drag from one corner of the fish to the other.").padding()
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image).resizable().frame(width: width, height: height)
                    if let rect = drawingBox(width: width, height: height) { Rectangle().stroke(.yellow, lineWidth: 3).frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY).allowsHitTesting(false) }
                }.frame(width: width, height: height).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in if start == nil { start = value.startLocation }; current = value.location }.onEnded { value in
                        if let rect = drawingBox(width: width, height: height), rect.width > 4, rect.height > 4 { box = CGRect(x: rect.minX / width, y: rect.minY / height, width: rect.width / width, height: rect.height / height); dismiss() }
                        start = nil; current = nil
                    })
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.navigationTitle("Select the fish").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
    func drawingBox(width: CGFloat, height: CGFloat) -> CGRect? {
        if let start, let current {
            let x1 = min(max(start.x, 0), width), x2 = min(max(current.x, 0), width)
            let y1 = min(max(start.y, 0), height), y2 = min(max(current.y, 0), height)
            return CGRect(x: min(x1,x2), y: min(y1,y2), width: abs(x1-x2), height: abs(y1-y2))
        }
        return box.map { CGRect(x: $0.minX * width, y: $0.minY * height, width: $0.width * width, height: $0.height * height) }
    }
}

struct LocationPicker: View {
    @Binding var latitude: String
    @Binding var longitude: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PinMap(latitude: $latitude, longitude: $longitude).ignoresSafeArea(edges: .bottom).navigationTitle("Choose location")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
struct PinMap: UIViewRepresentable {
    @Binding var latitude: String
    @Binding var longitude: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(); map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: Double(latitude) ?? 53, longitude: Double(longitude) ?? -2), span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)), animated: false)
        map.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations)
        if let lat = Double(latitude), let lon = Double(longitude), abs(lat) <= 90, abs(lon) <= 180 { let pin = MKPointAnnotation(); pin.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon); map.addAnnotation(pin) }
    }
    final class Coordinator: NSObject {
        let parent: PinMap
        init(_ parent: PinMap) { self.parent = parent }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            parent.latitude = String(format: "%.6f", point.latitude); parent.longitude = String(format: "%.6f", point.longitude)
        }
    }
}
