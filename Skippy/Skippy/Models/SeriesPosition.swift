import Foundation

/// A book's place in a series, e.g. "Expeditionary Force" #3.5.
struct SeriesPosition: Hashable, Codable {
    let id: String?
    let name: String
    let sequence: String?

    /// Numeric value of `sequence` used for ordering ("3.5" → 3.5, "1-2" → 1).
    var sortValue: Double? {
        guard let sequence else {
            return nil
        }
        return Double(sequence.prefix { $0.isNumber || $0 == "." })
    }

    /// Parses Audiobookshelf's flattened `seriesName`, e.g.
    /// "Galaxy's Edge #10, Galaxy's Edge: Order of the Centurion #1".
    static func parse(seriesName: String) -> [SeriesPosition] {
        seriesName
            .components(separatedBy: ", ")
            .compactMap { part in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }
                guard let marker = trimmed.range(of: " #", options: .backwards) else {
                    return SeriesPosition(id: nil, name: trimmed, sequence: nil)
                }
                let sequence = trimmed[marker.upperBound...].trimmingCharacters(in: .whitespaces)
                return SeriesPosition(
                    id: nil,
                    name: String(trimmed[..<marker.lowerBound]),
                    sequence: sequence.isEmpty ? nil : sequence
                )
            }
    }
}

extension Audiobook {
    /// The book's position in `seriesName` when it belongs to it, otherwise its first series.
    func seriesPosition(in seriesName: String?) -> SeriesPosition? {
        if let seriesName,
           let match = series.first(where: { $0.name.caseInsensitiveCompare(seriesName) == .orderedSame }) {
            return match
        }
        return series.first
    }
}

extension Array where Element == Audiobook {
    /// The series most of these books belong to; used to number a mixed collection.
    var dominantSeriesName: String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for book in self {
            var seen = Set<String>()
            for name in book.series.map(\.name) where seen.insert(name).inserted {
                if counts[name] == nil {
                    order.append(name)
                }
                counts[name, default: 0] += 1
            }
        }
        return order.max { counts[$0, default: 0] < counts[$1, default: 0] }
    }

    /// Orders books by their number in `seriesName` (or their first series when nil);
    /// books without a number in it follow, by title.
    func sortedBySeries(_ seriesName: String?) -> [Audiobook] {
        func sortValue(_ book: Audiobook) -> Double? {
            guard let seriesName else {
                return book.series.first?.sortValue
            }
            return book.series
                .first { $0.name.caseInsensitiveCompare(seriesName) == .orderedSame }?
                .sortValue
        }
        return sorted { lhs, rhs in
            let left = sortValue(lhs)
            let right = sortValue(rhs)
            switch (left, right) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }
}
