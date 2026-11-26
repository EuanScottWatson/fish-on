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
            Section("Personal bests") {
                let bests = personalBests()
                if bests.isEmpty { Text("Add a weight with units to a catch to see personal bests.").foregroundStyle(.secondary) }
                ForEach(bests) { item in NavigationLink { CatchDetail(item: item) } label: { LabeledContent(item.string("species"), value: item.string("weight")) } }
            }
            Section("Most caught") { ForEach(speciesCounts.prefix(10), id: \.0) { name, count in LabeledContent(name, value: "\(count)") } }
            Section("Fishing places") { ForEach(placeCounts.prefix(10), id: \.0) { name, count in LabeledContent(name, value: "\(count)") } }
            Section("Catches by month") { ForEach(monthCounts(), id: \.0) { month, count in LabeledContent(month, value: "\(count)") } }
            Section("Catches by year") { ForEach(counts(store.catches.compactMap { value in let date = value.string("date"); return date.count >= 10 ? String(date.prefix(4)) : nil }), id: \.0) { year, count in LabeledContent(year, value: "\(count)") } }
            Section { Text("Counts reflect saved records only. Trips are counted whether or not a catch was linked.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Statistics")
    }
    func monthCounts() -> [(String, Int)] {
        let symbols = britishMonthNames()
        return symbols.enumerated().map { index, label in
            let month = String(format: "-%02d-", index + 1)
            return (label, store.catches.filter { $0.string("date").count == 10 && $0.string("date").contains(month) }.count)
        }
    }
    func personalBests() -> [Record] {
        var best: [String: (Double, Record)] = [:]
        for item in store.catches {
            let name = item.string("species").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let grams = weightInGrams(item.string("weight")) else { continue }
            let key = name.lowercased()
            if grams > (best[key]?.0 ?? 0) { best[key] = (grams, item) }
        }
        return best.values.map { $0.1 }.sorted { $0.string("species").localizedCaseInsensitiveCompare($1.string("species")) == .orderedAscending }
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
