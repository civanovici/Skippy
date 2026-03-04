# Plan (Planner)

## Phase Metadata

- Task ID: `2026-03-03-offline-downloads`
- Phase: Planner
- Owner Agent: Planner
- Status: `approved`
- Approval: `approved`
- Approved By: `User`
- Approval Date (YYYY-MM-DD): `2026-03-03`

## Phase Gate

- Prerequisite: Researcher phase `Approval: approved`.
- Gate rule: Do not start Implementer phase until this phase is `Approval: approved`.

## Inputs From Research

- Research artifact path: `/Users/lupucristian/work/skippy/docs/agentic/tasks/2026-03-03-offline-downloads/research.md`
- Key finding 1: Current app has no offline repository layer and no real download persistence/lifecycle implementation.
- Key finding 2: Server supports both item ZIP downloads and resumable per-track file URLs; per-track route is better for pause/resume.
- Key unresolved question: None (resolved by user on 2026-03-03).

## Goal

- Primary goal: Deliver a v1 offline experience where downloaded audiobooks remain browseable and playable when server/device is offline.
- User impact: Users can reliably listen and navigate downloaded content without network connectivity and understand current connectivity/download status.

## Success Criteria

- Criterion 1: App shows an offline indicator when connectivity/server reachability is lost.
- Criterion 2: Home, Library, Collections, and Series support “Downloaded only” toggle; when offline, data is local-downloaded only.
- Criterion 3: Book detail supports `Download`, `Pause`, `Resume`, and `Delete download`, with visible progress/state.
- Criterion 4: Player can start/continue playback from local files for downloaded books when offline.
- Criterion 5: Item-level UI shows whether book is available offline.
- Criterion 6: Search is disabled while offline in v1.

## Scope

- In scope item 1: Offline state service (reachability + server health interpretation) and app-wide indicator binding.
- In scope item 2: Persistent download catalog + file storage metadata for downloaded audiobooks/tracks.
- In scope item 3: Download engine for per-track transfer with pause/resume/cancel/delete.
- In scope item 4: Local-data fallback repositories for Home/Library/Collections/Series + downloaded-only filtering.
- In scope item 5: Book detail download controls and playback local-track fallback.
- Out of scope item 1: Full offline mirror of entire remote library and non-downloaded items.
- Out of scope item 2: E2E/UI automation in this iteration.

## Options Considered

- Option A: Item ZIP downloads (`/api/items/{id}/download`) as primary offline artifact.
  - Tradeoffs: Simple single request per item, but ZIP extraction and per-track mapping add complexity; live probe suggests weak range semantics for fine pause/resume.
- Option B: HLS/session download from play endpoint (`POST /api/items/{id}/play`).
  - Tradeoffs: Aligned with streaming path, but session-oriented and less deterministic for durable offline caching.
- Option C: Per-track file downloads (`/api/items/{id}/file/{trackId}`) + local catalog (recommended).
  - Tradeoffs: More task orchestration across tracks, but best control for progress, pause/resume, retries, and deterministic local playback.

## Recommended Approach

- Approach summary: Implement Option C with a local `DownloadedCatalog` store, a `ConnectivityStore`, and repository-level fallback so all top-level tabs can render downloaded-only datasets when offline/unreachable.
- Why this option: It directly meets your requirements with the best pause/resume practicality and avoids high-risk ZIP pipeline complexity in v1.
- Product decisions confirmed (2026-03-03):
  - Offline mode is automatic only (no manual force-offline control).
  - Only fully downloaded books are marked offline-available/playable.
  - Downloaded-only filtering is auto-enabled while offline.
  - Delete download removes local media files only.
  - Search is disabled in offline mode for v1.

## Recommended V1 Data Model

1. `OfflineAvailability`
   - `bookID: String`
   - `isFullyDownloaded: Bool`
   - `downloadState: DownloadRecord.State`
   - `progress: Double`
2. `DownloadedBookRecord`
   - `bookID: String`
   - `title: String`
   - `author: String`
   - `coverURL: URL?`
   - `chapters: [Chapter]`
   - `tracks: [DownloadedTrackRecord]`
   - `downloadedAt: Date?`
3. `DownloadedTrackRecord`
   - `trackID: String`
   - `title: String`
   - `startOffset: TimeInterval`
   - `duration: TimeInterval?`
   - `remoteURL: URL`
   - `localFileURL: URL`
   - `bytesDownloaded: Int64`
   - `totalBytes: Int64?`
   - `status: TrackDownloadStatus`
4. `ConnectivityState`
   - `isNetworkReachable: Bool`
   - `isServerReachable: Bool`
   - `isOfflineEffective: Bool` (derived)
5. `TabDownloadFilter`
   - Runtime per-tab boolean `showDownloadedOnly`, automatically forced `true` when offline.

## Implementation Steps

1. Introduce offline core services.
   - Add `ConnectivityStore` (path monitor + debounced server reachability ping).
   - Add `OfflineCatalogStore` persistence (JSON first; migrate later if needed).
2. Replace placeholder download manager.
   - Implement `URLSession` background/foreground download tasks per track.
   - Support enqueue, pause, resume, cancel, delete, and progress callbacks.
   - Persist task/book/track state and recover on app restart.
3. Extend models and playback.
   - Extend track source model to carry local file URL.
   - Update `PlayerService` / `PlayerViewModel` to prefer local tracks when available/offline.
4. Add repository fallback for list tabs.
   - Add local query paths for Home/Library/Series/Collections (downloaded subset projections).
   - If `isOfflineEffective == true`, load local-only datasets.
   - Auto-enable downloaded-only view when offline (no manual v1 toggle persistence).
5. Add UI indicators and toggles.
   - Add offline badge/banner in each top-level page toolbar.
   - Add downloaded-only toggle in Home/Library/Series/Collections and auto-enable it when offline.
   - Add offline/download badge to `BookCardView`.
6. Update book detail actions.
   - Add `Download/Pause/Resume/Delete` controls with progress text.
   - Reflect per-item availability and storage use in detail metadata.
   - `Delete` removes local files only (does not clear progress/bookmarks).
7. Add tests (unit + integration-level where possible without E2E).
   - Download manager state transitions.
   - Local fallback logic in view models.
   - Playback source selection precedence.
   - Offline indicator and toggle filtering behavior.

## Files To Change

- `/Users/lupucristian/work/skippy/Skippy/Skippy/Services/Downloads/DownloadManager.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Models/DownloadRecord.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Services/Playback/PlayerService.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Player/PlayerViewModel.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/BookDetail/BookDetailView.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/BookDetail/BookDetailViewModel.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Home/HomeView.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Home/HomeViewModel.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Library/LibraryView.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Library/LibraryViewModel.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Series/SeriesView.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Series/SeriesViewModel.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Collections/CollectionsView.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Collections/CollectionsViewModel.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Support/BookCardView.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/App/AuthenticatedTabView.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/App/DependencyContainer.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Services/Persistence/PersistenceController.swift` (or new offline persistence service files)
- `/Users/lupucristian/work/skippy/Skippy/SkippyTests/` (new/updated unit tests)

## Test Plan

- Unit test coverage:
  - Download state machine transitions (`queued -> downloading -> paused -> downloading -> completed/failed`).
  - Offline eligibility is true only when all required tracks are fully downloaded.
  - Offline catalog persistence encode/decode and restart recovery.
  - View model auto-switches to downloaded-only datasets while offline.
  - Playback source selection local vs remote.
  - Search disabled while offline.
- Integration/UI test coverage:
  - No E2E in this iteration (per request).
- Manual verification:
  - Online download flow with pause/resume/delete.
  - Airplane mode playback of downloaded book.
  - Server-unreachable fallback loads local datasets and shows offline indicator.
  - Toggle behavior per tab with and without online connectivity.

## Risks And Mitigations

- Risk 1: Background/resume behavior can be brittle across app lifecycle events.
  - Mitigation: Persist track-level checkpoints and reconcile task states on app launch.
- Risk 2: Partial downloads may be surfaced incorrectly as fully offline.
  - Mitigation: Mark `isFullyDownloaded` only after all required tracks reach `completed` and file existence checks pass.
- Risk 3: Downloaded subset may produce sparse Home/Series/Collections offline views.
  - Mitigation: Show clear empty-state copy: “No downloaded items in this section.”

## Rollback Plan

- Rollback trigger: Regressions in playback startup or severe download failures post-merge.
- Rollback steps: Feature-flag/disable offline fallback first; if needed, revert to prior remote-only behavior while keeping non-invasive model additions.

## Phase Summary

- Summary: Plan defines a bounded v1 offline architecture centered on per-track downloads, persisted downloaded catalog, and app-wide offline-aware data fallback.
- Recommendation: `proceed`
- Awaiting user approval to implement: `no`
