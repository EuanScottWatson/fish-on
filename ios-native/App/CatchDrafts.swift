import Foundation
import SwiftUI
import UIKit
import PhotosUI
import Photos
import ImageIO
import CoreLocation
import UniformTypeIdentifiers

struct CatchDraft: Codable, Identifiable {
    var id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    var species = ""
    var scientific = ""
    var date = ""
    var place = ""
    var lat = ""
    var lon = ""
    var weight = ""
    var length = ""
    var tackle = ""
    var notes = ""
    var photoFile: String?
    var ready = false
    var fields: [String: String] { ["id":id,"species":species,"scientific":scientific,"date":date,"place":place,"lat":lat,"lon":lon,"weight":weight,"length":length,"tackle":tackle,"notes":notes] }
    init() {}
    init(_ record: Record) {
        id = record.id
        species = record.string("species"); scientific = record.string("scientific"); date = record.string("date")
        place = record.string("place"); lat = record.string("lat"); lon = record.string("lon")
        weight = record.string("weight"); length = record.string("length"); tackle = record.string("tackle"); notes = record.string("notes")
    }
}

enum DraftStorage {
    static var directory: URL {
        get throws {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = base.appendingPathComponent("FishOnDrafts", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }
    static func read() throws -> [CatchDraft] {
        let file = try directory.appendingPathComponent("drafts.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([CatchDraft].self, from: Data(contentsOf: file))
    }
    static func write(_ drafts: [CatchDraft]) throws {
        try JSONEncoder().encode(drafts).write(to: directory.appendingPathComponent("drafts.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    static func storePhoto(_ data: Data, id: String) throws -> String {
        let name = "\(id)-\(UUID().uuidString).jpg"
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUnlessOpen])
        return name
    }
    static func photo(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
    static func removePhoto(_ name: String?) throws {
        guard let name, !name.contains("/") else { return }
        let url = try directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

struct PhotoMetadata {
    var date: String?
    var latitude: Double?
    var longitude: Double?
    init(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return }
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let rawDate = (exif[kCGImagePropertyExifDateTimeOriginal as String] as? String) ?? (tiff[kCGImagePropertyTIFFDateTime as String] as? String)
        if let rawDate, rawDate.count >= 10 {
            let start = String(rawDate.prefix(10)).replacingOccurrences(of: ":", with: "-")
            if start.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { date = start }
        }
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double, let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double {
            let signedLat = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased() == "S" ? -abs(lat) : abs(lat)
            let signedLon = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased() == "W" ? -abs(lon) : abs(lon)
            if abs(signedLat) <= 90 && abs(signedLon) <= 180 { latitude = signedLat; longitude = signedLon }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) else { parent.dismiss(); return }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                if status == .authorized || status == .limited { PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: image) }) { _, _ in } }
            }
            parent.onPhoto(data); parent.dismiss()
        }
    }
}

extension FishStore {
    func loadDrafts() {
        do { drafts = try DraftStorage.read(); draftError = nil }
        catch { draftError = "Could not read saved drafts. Saving is paused to protect them." }
    }
    func saveDraft(_ draft: CatchDraft) throws {
        guard draftError == nil else { throw URLError(.cannotWriteToFile) }
        var next = drafts.filter { $0.id != draft.id }; next.append(draft)
        try DraftStorage.write(next); drafts = next
    }
    func removeDraft(_ draft: CatchDraft) throws {
        let next = drafts.filter { $0.id != draft.id }
        try DraftStorage.write(next); drafts = next
        try DraftStorage.removePhoto(draft.photoFile)
    }
    func sendMultipart(path: String, fields: [String: String], photo: Data?, timeout: TimeInterval = 30) async throws -> [String: Any] {
        guard let base = connectedAddress, let url = URL(string: base + path) else { throw URLError(.notConnectedToInternet) }
        let boundary = "FishOn-\(UUID().uuidString)"
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        for key in fields.keys.sorted() {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(fields[key] ?? "")\r\n")
        }
        if let photo { append("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"fish.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"); body.append(photo); append("\r\n") }
        append("--\(boundary)--\r\n")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"; request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("similarity-v1", forHTTPHeaderField: "X-FishOn-Identify"); request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else { throw FishError.message((object["error"] as? String) ?? "The server returned HTTP \(http.statusCode).") }
        return object
    }
    func syncDrafts() async {
        guard !syncing, draftError == nil, connectedAddress != nil else { return }
        syncing = true; defer { syncing = false }
        for draft in drafts where draft.ready {
            do {
                let photo = try draft.photoFile.map { try DraftStorage.photo($0) }
                _ = try await sendMultipart(path: "/api/catches", fields: draft.fields, photo: photo)
                try removeDraft(draft)
            } catch { syncError = "Waiting to sync: \(error.localizedDescription)"; return }
        }
        syncError = nil
        await refresh()
    }
}

enum FishError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

extension FishStore {
    func delete(path: String) async throws {
        guard let base = connectedAddress, let url = URL(string: base + path) else { throw URLError(.notConnectedToInternet) }
        var request = URLRequest(url: url, timeoutInterval: 20); request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw FishError.message(object?["error"] as? String ?? "Could not delete the record.")
        }
    }
}
