import Foundation
import Observation

@MainActor
protocol DownloadManaging: AnyObject {
    var records: [String: DownloadRecord] { get }
    var downloadedBooks: [String: DownloadedBookRecord] { get }
    var fullyDownloadedBookIDs: Set<String> { get }

    func enqueue(_ audiobook: Audiobook, details: AudiobookDetails)
    func pause(audiobookID: String)
    func resume(audiobookID: String)
    func deleteDownload(audiobookID: String)
    func record(for audiobookID: String) -> DownloadRecord?
    func isDownloaded(audiobookID: String) -> Bool
    func localTracks(for audiobookID: String) -> [AudiobookTrack]
    func localDetails(for audiobookID: String) -> AudiobookDetails?
    func downloadedLibrary() -> [Audiobook]
}

@MainActor
@Observable
final class DownloadManager: DownloadManaging {
    private struct PersistedState: Codable {
        var records: [String: DownloadRecord]
        var books: [String: DownloadedBookRecord]
    }

    private struct ActiveTaskContext {
        let audiobookID: String
        let trackID: String
    }

    private final class SessionDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
        weak var owner: DownloadManager?

        nonisolated func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            Task { @MainActor [weak owner] in
                owner?.handleProgress(
                    taskIdentifier: downloadTask.taskIdentifier,
                    totalBytesWritten: totalBytesWritten,
                    totalBytesExpectedToWrite: totalBytesExpectedToWrite
                )
            }
        }

        nonisolated func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            // Preserve CFNetwork temp file immediately. It may be removed before
            // the async hop to MainActor runs.
            let preservedURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("skippy-download-\(UUID().uuidString).tmp")
            do {
                try FileManager.default.moveItem(at: location, to: preservedURL)
            } catch {
                do {
                    try FileManager.default.copyItem(at: location, to: preservedURL)
                } catch {
                    Task { @MainActor [weak owner] in
                        owner?.debugLog(
                            "failed to preserve temp file task=\(downloadTask.taskIdentifier) temp=\(location.path) error=\(error.localizedDescription)"
                        )
                        owner?.handleTaskCompletionError(taskIdentifier: downloadTask.taskIdentifier, error: error)
                    }
                    return
                }
            }

            Task { @MainActor [weak owner] in
                owner?.handleDownloadFinished(
                    taskIdentifier: downloadTask.taskIdentifier,
                    temporaryLocation: preservedURL
                )
            }
        }

        nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else {
                return
            }
            Task { @MainActor [weak owner] in
                owner?.handleTaskCompletionError(taskIdentifier: task.taskIdentifier, error: error)
            }
        }
    }

    var records: [String: DownloadRecord] = [:]
    var downloadedBooks: [String: DownloadedBookRecord] = [:]

    var fullyDownloadedBookIDs: Set<String> {
        Set(downloadedBooks.values.filter { isBookFullyDownloaded($0) }.map(\.bookID))
    }

    private let fileManager: FileManager
    private let stateFileURL: URL
    private let mediaRootURL: URL
    private let delegate: SessionDelegate
    private let session: URLSession
    private var activeTasks: [Int: ActiveTaskContext] = [:]

    private func debugLog(_ message: String) {}

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let supportFolder = appSupport.appending(path: "Skippy", directoryHint: .isDirectory)
        let mediaRoot = supportFolder.appending(path: "OfflineMedia", directoryHint: .isDirectory)
        stateFileURL = supportFolder.appending(path: "downloads-state-v1.json")
        mediaRootURL = mediaRoot

        delegate = SessionDelegate()
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

        delegate.owner = self
        createDirectoryIfMissing(supportFolder)
        createDirectoryIfMissing(mediaRoot)
        loadState()
    }

    deinit {
        session.invalidateAndCancel()
    }

    func enqueue(_ audiobook: Audiobook, details: AudiobookDetails) {
        debugLog("enqueue requested book=\(audiobook.id) title=\(audiobook.title)")
        let availableTracks = details.tracks.compactMap { track -> (AudiobookTrack, URL)? in
            guard let url = track.streamURL else {
                return nil
            }
            return (track, url)
        }
        debugLog("resolved tracks count=\(availableTracks.count) for book=\(audiobook.id)")
        guard !availableTracks.isEmpty else {
            debugLog("enqueue failed no downloadable tracks for book=\(audiobook.id)")
            records[audiobook.id] = DownloadRecord(
                audiobookID: audiobook.id,
                state: .failed,
                progress: 0,
                downloadedBytes: 0,
                totalBytes: nil,
                errorMessage: "No downloadable tracks available."
            )
            persistState()
            return
        }

        let existing = downloadedBooks[audiobook.id]
        let bookFolder = mediaRootURL.appending(path: audiobook.id, directoryHint: .isDirectory)
        createDirectoryIfMissing(bookFolder)

        var mergedTracks: [DownloadedTrackRecord] = []
        for (index, pair) in availableTracks.enumerated() {
            let track = pair.0
            let remoteURL = pair.1
            let remoteExtension = remoteURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleExtension = URL(fileURLWithPath: track.title).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            let extensionPart: String
            if !remoteExtension.isEmpty {
                extensionPart = remoteExtension
            } else if !titleExtension.isEmpty {
                extensionPart = titleExtension
            } else {
                extensionPart = "m4b"
            }
            let fileURL = bookFolder.appending(path: "\(index)-\(track.id).\(extensionPart)")
            if let prior = existing?.tracks.first(where: { $0.trackID == track.id }) {
                var preserved = prior
                if !(prior.status == .completed && fileManager.fileExists(atPath: prior.localFilePath)) {
                    preserved.localFilePath = fileURL.path
                }
                preserved.remoteURL = remoteURL
                mergedTracks.append(preserved)
            } else {
                mergedTracks.append(
                    DownloadedTrackRecord(
                        trackID: track.id,
                        title: track.title,
                        startOffset: track.startOffset,
                        duration: track.duration,
                        remoteURL: remoteURL,
                        localFilePath: fileURL.path,
                        bytesDownloaded: 0,
                        totalBytes: nil,
                        status: .pending,
                        resumeData: nil,
                        errorMessage: nil
                    )
                )
            }
        }

        downloadedBooks[audiobook.id] = DownloadedBookRecord(
            bookID: audiobook.id,
            title: audiobook.title,
            author: audiobook.author,
            coverURL: audiobook.coverURL,
            chapters: details.chapters.isEmpty ? audiobook.chapters : details.chapters,
            tracks: mergedTracks,
            downloadedAt: existing?.downloadedAt
        )

        records[audiobook.id] = records[audiobook.id] ?? DownloadRecord(
            audiobookID: audiobook.id,
            state: .queued,
            progress: 0,
            downloadedBytes: 0,
            totalBytes: nil,
            errorMessage: nil
        )
        recalculateRecord(for: audiobook.id)
        startNextTrackIfPossible(for: audiobook.id)
        persistState()
        debugLog("enqueue completed setup for book=\(audiobook.id)")
    }

    func pause(audiobookID: String) {
        debugLog("pause requested book=\(audiobookID)")
        guard let taskPair = activeTasks.first(where: { $0.value.audiobookID == audiobookID }) else {
            debugLog("pause ignored no active task for book=\(audiobookID)")
            return
        }
        let taskID = taskPair.key
        let context = taskPair.value
        guard let task = session.getAllTasksSync().first(where: { $0.taskIdentifier == taskID }) as? URLSessionDownloadTask else {
            return
        }

        task.cancel { [weak self] resumeData in
            Task { @MainActor in
                guard let self, var book = self.downloadedBooks[context.audiobookID] else {
                    return
                }
                if let index = book.tracks.firstIndex(where: { $0.trackID == context.trackID }) {
                    book.tracks[index].status = .paused
                    book.tracks[index].resumeData = resumeData
                    self.downloadedBooks[context.audiobookID] = book
                }
                self.activeTasks.removeValue(forKey: taskID)
                self.recalculateRecord(for: context.audiobookID, forcedState: .paused)
                self.persistState()
                self.debugLog("pause completed book=\(context.audiobookID) track=\(context.trackID)")
            }
        }
    }

    func resume(audiobookID: String) {
        debugLog("resume requested book=\(audiobookID)")
        guard downloadedBooks[audiobookID] != nil else {
            debugLog("resume ignored no downloaded record for book=\(audiobookID)")
            return
        }
        startNextTrackIfPossible(for: audiobookID)
        persistState()
    }

    func deleteDownload(audiobookID: String) {
        debugLog("delete requested book=\(audiobookID)")
        if let taskPair = activeTasks.first(where: { $0.value.audiobookID == audiobookID }),
           let task = session.getAllTasksSync().first(where: { $0.taskIdentifier == taskPair.key })
        {
            task.cancel()
            activeTasks.removeValue(forKey: taskPair.key)
        }

        let bookFolder = mediaRootURL.appending(path: audiobookID, directoryHint: .isDirectory)
        try? fileManager.removeItem(at: bookFolder)

        downloadedBooks.removeValue(forKey: audiobookID)
        records.removeValue(forKey: audiobookID)
        persistState()
        debugLog("delete finished book=\(audiobookID)")
    }

    func record(for audiobookID: String) -> DownloadRecord? {
        records[audiobookID]
    }

    func isDownloaded(audiobookID: String) -> Bool {
        guard let book = downloadedBooks[audiobookID] else {
            return false
        }
        return isBookFullyDownloaded(book)
    }

    func localTracks(for audiobookID: String) -> [AudiobookTrack] {
        guard let book = downloadedBooks[audiobookID], isBookFullyDownloaded(book) else {
            return []
        }
        return book.tracks
            .filter { $0.status == .completed && fileManager.fileExists(atPath: $0.localFilePath) }
            .sorted { $0.startOffset < $1.startOffset }
            .map { track in
                AudiobookTrack(
                    id: track.trackID,
                    title: track.title,
                    startOffset: track.startOffset,
                    duration: track.duration,
                    streamURL: track.localFileURL
                )
            }
    }

    func localDetails(for audiobookID: String) -> AudiobookDetails? {
        guard let book = downloadedBooks[audiobookID], isBookFullyDownloaded(book) else {
            return nil
        }
        let tracks = localTracks(for: audiobookID)
        let size = book.tracks.reduce(Int64(0)) { partial, track in
            partial + track.bytesDownloaded
        }
        return AudiobookDetails(
            subtitle: nil,
            narrators: [],
            publishedYear: nil,
            publisher: nil,
            genres: [],
            description: "Downloaded for offline playback.",
            duration: tracks.compactMap(\.duration).reduce(0, +),
            sizeBytes: size > 0 ? size : nil,
            chapters: book.chapters,
            tracks: tracks,
            userProgress: nil,
            bookmarks: []
        )
    }

    func downloadedLibrary() -> [Audiobook] {
        downloadedBooks.values
            .filter { isBookFullyDownloaded($0) }
            .map { book in
                Audiobook(
                    id: book.bookID,
                    title: book.title,
                    author: book.author,
                    progress: 0,
                    coverURL: book.coverURL,
                    chapters: book.chapters
                )
            }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private func startNextTrackIfPossible(for audiobookID: String) {
        debugLog("startNextTrackIfPossible book=\(audiobookID)")
        if activeTasks.values.contains(where: { $0.audiobookID == audiobookID }) {
            debugLog("start skipped active task already running for book=\(audiobookID)")
            return
        }
        guard var book = downloadedBooks[audiobookID] else {
            debugLog("start skipped no local book record for book=\(audiobookID)")
            return
        }
        if isBookFullyDownloaded(book) {
            book.downloadedAt = book.downloadedAt ?? Date()
            downloadedBooks[audiobookID] = book
            recalculateRecord(for: audiobookID, forcedState: .completed)
            persistState()
            debugLog("book already fully downloaded book=\(audiobookID)")
            return
        }

        guard let index = book.tracks.firstIndex(where: { track in
            switch track.status {
            case .pending, .paused, .failed, .downloading:
                return track.status != .completed
            case .completed:
                return false
            }
        }) else {
            recalculateRecord(for: audiobookID, forcedState: .completed)
            persistState()
            debugLog("no pending track found, marking complete book=\(audiobookID)")
            return
        }

        let track = book.tracks[index]
        let task: URLSessionDownloadTask
        if let resumeData = track.resumeData {
            debugLog("starting track from resumeData book=\(audiobookID) track=\(track.trackID)")
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: track.remoteURL)
            request.timeoutInterval = 120
            debugLog("starting fresh track download book=\(audiobookID) track=\(track.trackID) url=\(track.remoteURL.absoluteString)")
            task = session.downloadTask(with: request)
        }

        book.tracks[index].status = .downloading
        book.tracks[index].errorMessage = nil
        downloadedBooks[audiobookID] = book
        activeTasks[task.taskIdentifier] = ActiveTaskContext(audiobookID: audiobookID, trackID: track.trackID)
        recalculateRecord(for: audiobookID, forcedState: .downloading)
        task.resume()
        persistState()
        debugLog("task resumed id=\(task.taskIdentifier) book=\(audiobookID) track=\(track.trackID)")
    }

    private func handleProgress(taskIdentifier: Int, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let context = activeTasks[taskIdentifier],
              var book = downloadedBooks[context.audiobookID],
              let index = book.tracks.firstIndex(where: { $0.trackID == context.trackID })
        else {
            return
        }

        book.tracks[index].bytesDownloaded = max(totalBytesWritten, 0)
        book.tracks[index].totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        book.tracks[index].status = .downloading
        downloadedBooks[context.audiobookID] = book
        recalculateRecord(for: context.audiobookID, forcedState: .downloading)
        debugLog(
            "progress task=\(taskIdentifier) book=\(context.audiobookID) track=\(context.trackID) bytes=\(totalBytesWritten)/\(totalBytesExpectedToWrite)"
        )
    }

    private func handleDownloadFinished(taskIdentifier: Int, temporaryLocation: URL) {
        guard let context = activeTasks[taskIdentifier],
              var book = downloadedBooks[context.audiobookID],
              let index = book.tracks.firstIndex(where: { $0.trackID == context.trackID })
        else {
            return
        }

        let destinationURL = book.tracks[index].localFileURL
        createDirectoryIfMissing(destinationURL.deletingLastPathComponent())
        try? fileManager.removeItem(at: destinationURL)
        debugLog(
            "download finished task=\(taskIdentifier) book=\(context.audiobookID) track=\(context.trackID) temp=\(temporaryLocation.path) dest=\(destinationURL.path)"
        )
        do {
            try fileManager.moveItem(at: temporaryLocation, to: destinationURL)
            let attrs = try? fileManager.attributesOfItem(atPath: destinationURL.path)
            if let size = attrs?[.size] as? Int64 {
                book.tracks[index].bytesDownloaded = size
                book.tracks[index].totalBytes = max(book.tracks[index].totalBytes ?? 0, size)
            }
            book.tracks[index].status = .completed
            book.tracks[index].resumeData = nil
            book.tracks[index].errorMessage = nil
            downloadedBooks[context.audiobookID] = book
            activeTasks.removeValue(forKey: taskIdentifier)
            recalculateRecord(for: context.audiobookID)
            startNextTrackIfPossible(for: context.audiobookID)
            debugLog("track move success book=\(context.audiobookID) track=\(context.trackID)")
        } catch {
            book.tracks[index].status = .failed
            book.tracks[index].errorMessage = error.localizedDescription
            downloadedBooks[context.audiobookID] = book
            activeTasks.removeValue(forKey: taskIdentifier)
            recalculateRecord(for: context.audiobookID, forcedState: .failed, errorMessage: error.localizedDescription)
            debugLog("track move failed book=\(context.audiobookID) track=\(context.trackID) error=\(error.localizedDescription)")
        }
        persistState()
    }

    private func handleTaskCompletionError(taskIdentifier: Int, error: Error) {
        guard let context = activeTasks[taskIdentifier],
              var book = downloadedBooks[context.audiobookID],
              let index = book.tracks.firstIndex(where: { $0.trackID == context.trackID })
        else {
            return
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            debugLog("task cancelled task=\(taskIdentifier) book=\(context.audiobookID) track=\(context.trackID)")
            return
        }

        book.tracks[index].status = .failed
        book.tracks[index].errorMessage = error.localizedDescription
        downloadedBooks[context.audiobookID] = book
        activeTasks.removeValue(forKey: taskIdentifier)
        recalculateRecord(for: context.audiobookID, forcedState: .failed, errorMessage: error.localizedDescription)
        persistState()
        debugLog("task failed task=\(taskIdentifier) book=\(context.audiobookID) track=\(context.trackID) error=\(error.localizedDescription)")
    }

    private func recalculateRecord(
        for audiobookID: String,
        forcedState: DownloadRecord.State? = nil,
        errorMessage: String? = nil
    ) {
        guard let book = downloadedBooks[audiobookID] else {
            return
        }

        let downloadedBytes = book.tracks.reduce(Int64(0)) { $0 + max($1.bytesDownloaded, 0) }
        let totalCandidates = book.tracks.compactMap(\.totalBytes)
        let totalBytes = totalCandidates.count == book.tracks.count ? totalCandidates.reduce(Int64(0), +) : nil

        let progress: Double
        if let totalBytes, totalBytes > 0 {
            progress = min(max(Double(downloadedBytes) / Double(totalBytes), 0), 1)
        } else {
            let completedCount = book.tracks.filter { $0.status == .completed }.count
            progress = book.tracks.isEmpty ? 0 : Double(completedCount) / Double(book.tracks.count)
        }

        let state = forcedState ?? derivedState(for: book)
        records[audiobookID] = DownloadRecord(
            audiobookID: audiobookID,
            state: state,
            progress: progress,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            errorMessage: errorMessage
        )
    }

    private func derivedState(for book: DownloadedBookRecord) -> DownloadRecord.State {
        if isBookFullyDownloaded(book) {
            return .completed
        }
        if book.tracks.contains(where: { $0.status == .completed && !fileManager.fileExists(atPath: $0.localFilePath) }) {
            return .failed
        }
        if book.tracks.contains(where: { $0.status == .downloading }) {
            return .downloading
        }
        if book.tracks.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if book.tracks.contains(where: { $0.status == .paused }) {
            return .paused
        }
        return .queued
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let stored = try? JSONDecoder().decode(PersistedState.self, from: data)
        else {
            debugLog("no persisted download state found")
            return
        }
        records = stored.records
        downloadedBooks = stored.books
        migrateLegacyAudioExtensionsIfNeeded()
        reconcileMissingCompletedFiles()
        // Ignore stale active states on relaunch; user can resume explicitly.
        for key in records.keys where records[key]?.state == .downloading {
            records[key]?.state = .paused
        }
        persistState()
        debugLog("loaded persisted state books=\(downloadedBooks.count) records=\(records.count)")
    }

    private func persistState() {
        let payload = PersistedState(records: records, books: downloadedBooks)
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }
        try? data.write(to: stateFileURL, options: [.atomic])
    }

    private func createDirectoryIfMissing(_ url: URL) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func migrateLegacyAudioExtensionsIfNeeded() {
        for (bookID, var book) in downloadedBooks {
            var changed = false
            for index in book.tracks.indices {
                let oldURL = URL(fileURLWithPath: book.tracks[index].localFilePath)
                if oldURL.pathExtension.lowercased() != "audio" {
                    continue
                }
                guard fileManager.fileExists(atPath: oldURL.path) else {
                    continue
                }
                let newURL = oldURL.deletingPathExtension().appendingPathExtension("m4b")
                do {
                    if fileManager.fileExists(atPath: newURL.path) {
                        try fileManager.removeItem(at: newURL)
                    }
                    try fileManager.moveItem(at: oldURL, to: newURL)
                    book.tracks[index].localFilePath = newURL.path
                    changed = true
                    debugLog("migrated legacy extension book=\(bookID) track=\(book.tracks[index].trackID) path=\(newURL.path)")
                } catch {
                    debugLog("failed legacy extension migration book=\(bookID) track=\(book.tracks[index].trackID) error=\(error.localizedDescription)")
                }
            }
            if changed {
                downloadedBooks[bookID] = book
                recalculateRecord(for: bookID)
            }
        }
    }

    private func reconcileMissingCompletedFiles() {
        for (bookID, var book) in downloadedBooks {
            var changed = false
            for index in book.tracks.indices {
                if book.tracks[index].status == .completed,
                   !fileManager.fileExists(atPath: book.tracks[index].localFilePath)
                {
                    book.tracks[index].status = .failed
                    book.tracks[index].errorMessage = "Local file missing."
                    changed = true
                }
            }
            if changed {
                downloadedBooks[bookID] = book
                recalculateRecord(for: bookID)
            }
        }
    }

    private func isBookFullyDownloaded(_ book: DownloadedBookRecord) -> Bool {
        !book.tracks.isEmpty && book.tracks.allSatisfy {
            $0.status == .completed && fileManager.fileExists(atPath: $0.localFilePath)
        }
    }
}

private extension URLSession {
    func getAllTasksSync() -> [URLSessionTask] {
        let semaphore = DispatchSemaphore(value: 0)
        var tasks: [URLSessionTask] = []
        getAllTasks {
            tasks = $0
            semaphore.signal()
        }
        semaphore.wait()
        return tasks
    }
}
