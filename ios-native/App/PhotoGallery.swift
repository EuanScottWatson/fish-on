import SwiftUI

struct PhotoGallery: View {
    @EnvironmentObject private var store: FishStore
    @Environment(\.dismiss) private var dismiss
    @State var selectedID: String
    var items: [Record] { store.catches.filter { !$0.string("photo").isEmpty } }
    var body: some View {
        NavigationStack {
            TabView(selection: $selectedID) {
                ForEach(items) { item in
                    VStack {
                        if let url = store.photoURL(item.string("photo")) {
                            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                        }
                        Text("\(item.string("species")) · \(britishDate(item.string("date")))").font(.footnote).padding()
                    }.tag(item.id)
                }
            }.tabViewStyle(.page(indexDisplayMode: .automatic)).background(.black)
                .navigationTitle("Photographs").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
