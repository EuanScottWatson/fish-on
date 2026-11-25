import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var store: FishStore
    var speciesCounts: [(String, Int)] { counts(store.catches.map { $0.string("species") }) }
    var placeCounts: [(String, Int)] { counts(store.catches.map { $0.string("place") }) }
    var body: some View {
        List {
            Section("Your fishing") {
                LabeledContent("Catches", value: "\(store.catches.count)")
                LabeledContent("Species recorded", value: "\(speciesCounts.count)")
                LabeledContent("Trips recorded", value: "\(store.trips.count)")
                LabeledContent("Trips with linked catches", value: "\(store.trips.filter { !$0.strings("catch_ids").isEmpty }.count)")
                LabeledContent("Catches this year", value: "\(store.catches.filter { $0.string("date").hasPrefix(String(Calendar.current.component(.year, from: Date())) + "-") }.count)")
            }
            Section("Most caught") { ForEach(speciesCounts.prefix(10), id: \.0) { name, count in LabeledContent(name, value: "\(count)") } }
            Section("Fishing places") { ForEach(placeCounts.prefix(10), id: \.0) { name, count in LabeledContent(name, value: "\(count)") } }
            Section("Catches by year") { ForEach(counts(store.catches.compactMap { value in let date = value.string("date"); return date.count >= 10 ? String(date.prefix(4)) : nil }), id: \.0) { year, count in LabeledContent(year, value: "\(count)") } }
            Section { Text("Counts reflect saved records only. Trips are counted whether or not a catch was linked.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Statistics")
    }
    func counts(_ names: [String]) -> [(String, Int)] {
        var items: [String: (String, Int)] = [:]
        for name in names {
            let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty { continue }
            let key = label.lowercased(); let previous = items[key] ?? (label, 0); items[key] = (previous.0, previous.1 + 1)
        }
        return items.values.sorted { $0.1 == $1.1 ? $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending : $0.1 > $1.1 }
    }
}
