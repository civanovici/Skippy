import SwiftUI

struct StatsView: View {
    @State var viewModel: StatsViewModel

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter
    }()

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            listeningSummarySection
            recentSessionsSection
            topItemsSection
            dailyTotalsSection
            librarySection
        }
        .navigationTitle("Stats")
        .overlay {
            if viewModel.isLoading {
                ProgressView("Loading stats…")
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var listeningSummarySection: some View {
        Section("Listening Summary") {
            if let stats = viewModel.userStats {
                LabeledContent("Total Listening", value: durationText(stats.totalTimeSeconds))
                LabeledContent("Today", value: durationText(stats.todayTimeSeconds))
                LabeledContent("Tracked Days", value: "\(stats.dailyTotals.count)")
                LabeledContent("Tracked Items", value: "\(stats.topItems.count)")
            } else {
                Text("No listening activity available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var recentSessionsSection: some View {
        Section("Recent Sessions") {
            if let stats = viewModel.userStats, !stats.recentSessions.isEmpty {
                ForEach(Array(stats.recentSessions.prefix(5))) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.itemTitle ?? "Unknown Item")
                                .font(.subheadline.weight(.medium))
                            if let author = session.itemAuthor?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !author.isEmpty
                            {
                                Text(author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(durationText(session.seconds))
                                .font(.caption.weight(.semibold))
                            if let date = session.updatedAt ?? session.startedAt {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("No recent sessions.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var topItemsSection: some View {
        Section("Top Items") {
            if let stats = viewModel.userStats, !stats.topItems.isEmpty {
                ForEach(Array(stats.topItems.prefix(5))) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                            if let author = item.author?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !author.isEmpty
                            {
                                Text(author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(durationText(item.seconds))
                            .font(.caption.weight(.semibold))
                    }
                }
            } else {
                Text("No item activity.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var dailyTotalsSection: some View {
        Section("Daily Activity") {
            if let stats = viewModel.userStats, !stats.dailyTotals.isEmpty {
                ForEach(Array(stats.dailyTotals.prefix(14))) { day in
                    HStack {
                        Text(day.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(durationText(day.seconds))
                            .font(.caption.weight(.semibold))
                    }
                }
            } else {
                Text("No daily totals yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        Section("Library Analytics") {
            if let library = viewModel.libraryStats {
                LabeledContent("Library", value: library.libraryName)
                LabeledContent("Total Items", value: "\(library.totalItems)")
                LabeledContent("Total Duration", value: durationText(library.totalDurationSeconds))
                LabeledContent("Total Size", value: Self.sizeFormatter.string(fromByteCount: library.totalSizeBytes))
                LabeledContent("Authors", value: "\(library.totalAuthors)")
                LabeledContent("Genres", value: "\(library.totalGenres)")
                LabeledContent("Audio Tracks", value: "\(library.numAudioTracks)")

                if !library.longestItems.isEmpty {
                    Text("Longest Items")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(library.longestItems.prefix(3))) { item in
                        HStack {
                            Text(item.title)
                                .lineLimit(1)
                            Spacer()
                            Text(durationText(item.durationSeconds ?? 0))
                                .font(.caption.weight(.semibold))
                        }
                    }
                }

                if !library.largestItems.isEmpty {
                    Text("Largest Items")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(Array(library.largestItems.prefix(3))) { item in
                        HStack {
                            Text(item.title)
                                .lineLimit(1)
                            Spacer()
                            Text(Self.sizeFormatter.string(fromByteCount: item.sizeBytes ?? 0))
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            } else {
                Text("No library analytics available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let safe = max(seconds, 0)
        return Self.durationFormatter.string(from: safe) ?? "0m"
    }
}

#Preview {
    NavigationStack {
        StatsView(
            viewModel: StatsViewModel(
                apiClient: APIClient(audiobookshelf: MockAudiobookshelfAPI()),
                authStore: AuthStore.previewAuthenticated,
                logger: Logger()
            )
        )
    }
}
