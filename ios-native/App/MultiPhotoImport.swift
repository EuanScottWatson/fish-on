import SwiftUI
import PhotosUI
import UIKit

struct MultiPhotoImport: View {
    @EnvironmentObject private var store: FishStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var message = "Choose photos to save them as drafts for later review."
    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $selected, maxSelectionCount: 0, matching: .images) { Label("Choose photos", systemImage: "photo.on.rectangle") }.disabled(busy)
                Text(message).font(.footnote)
            }
        }.navigationTitle("Add photos")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
            .onChange(of: selected) { values in if !values.isEmpty { Task { await save(values) } } }
    }
    func save(_ values: [PhotosPickerItem]) async {
        busy = true; defer { busy = false }
        var count = 0
        for item in values {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.normalisedJPEG() else { throw FishError.message("Could not read the photo.") }
                let metadata = PhotoMetadata(data: data)
                var draft = CatchDraft()
                draft.date = metadata.date ?? ""
                if let lat = metadata.latitude, let lon = metadata.longitude { draft.lat = String(lat); draft.lon = String(lon) }
                draft.photoFile = try DraftStorage.storePhoto(jpeg, id: draft.id)
                try store.saveDraft(draft)
                count += 1
            } catch { message = "Saved \(count) photos. Could not save the next photo: \(error.localizedDescription)"; return }
        }
        message = "Saved \(count) photos on this phone. Open Catches to review and identify them."
        selected = []
    }
}
