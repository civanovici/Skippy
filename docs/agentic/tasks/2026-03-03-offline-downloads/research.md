# Research (Researcher)

## Phase Metadata

- Task ID: `2026-03-03-offline-downloads`
- Phase: Researcher
- Owner Agent: Researcher
- Status: `approved`
- Approval: `approved`
- Approved By: `User`
- Approval Date (YYYY-MM-DD): `2026-03-03`

## Phase Gate

- Gate rule: Do not start Planner phase until this phase is `Approval: approved`.

## Task Profile

- Complexity: `complex`
- Requires live API verification: `yes`
- Requires online docs check: `yes`
- Requires E2E in this iteration: `no`

## Task Summary

- Feature summary: Add end-to-end offline listening support for downloaded audiobooks, including offline indicator, downloaded-item indicators, downloaded-only toggles across Home/Library/Collections/Series, and download/pause/resume/delete actions on book details.
- User-visible outcome: When server is unreachable or device is offline, the app still allows playback and browsing of downloaded audiobooks, with clear UI indicators and filtering.
- Explicit non-goals: E2E automation for this iteration; storing credentials in repository files.

## Research Questions

- Question 1: What network/data flows does the app currently use, and what is missing for offline behavior?
- Question 2: What Audiobookshelf endpoints support downloadable media and play session URLs?
- Question 3: What does the running server actually return for these endpoints?
- Question 4: How do mature audio apps handle offline indicators, downloaded-only filtering, and download lifecycle UX?

## Sources Checked

| Type (`code | docs | live-server`) | Location / URL | Why it matters | Checked at |
| --- | --- | --- | --- |
| code | `/Users/lupucristian/work/skippy/Skippy/Skippy/Services/API/AudiobookshelfAPI.swift` | Defines current API usage and mapping (including track `contentUrl` to stream URL). | 2026-03-03T19:38:00Z |
| code | `/Users/lupucristian/work/skippy/Skippy/Skippy/Services/Downloads/DownloadManager.swift` | Confirms download implementation depth today. | 2026-03-03T19:38:00Z |
| code | `/Users/lupucristian/work/skippy/Skippy/Skippy/Services/Playback/PlayerService.swift` | Confirms playback currently resolves remote track URLs only. | 2026-03-03T19:38:00Z |
| code | `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Home/HomeViewModel.swift` | Confirms Home data comes from server fetch path with no offline fallback. | 2026-03-03T19:40:00Z |
| code | `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Library/LibraryViewModel.swift` | Confirms Library fetch/search are server-first only. | 2026-03-03T19:40:00Z |
| code | `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Collections/CollectionsViewModel.swift` | Confirms Collections fetch/search are server-first only. | 2026-03-03T19:40:00Z |
| code | `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/Series/SeriesViewModel.swift` | Confirms Series fetch/search are server-first only. | 2026-03-03T19:40:00Z |
| docs | https://api.audiobookshelf.org/ | Official API reference for item, play, file, and download endpoints. | 2026-03-03T19:34:00Z |
| docs | https://www.audiobookshelf.org/faq/app/ | Official guidance on offline support differences by client/app. | 2026-03-03T19:45:00Z |
| docs | https://help.libbyapp.com/en-us/6007.htm | Libby guidance: downloaded content remains available offline. | 2026-03-03T19:44:00Z |
| docs | https://help.libbyapp.com/en-us/6060.htm | Libby guidance: actions and settings for downloaded titles. | 2026-03-03T19:44:00Z |
| docs | https://support.spotify.com/us/article/listen-offline/ | Spotify guidance: explicit offline mode that only plays downloaded content. | 2026-03-03T19:44:00Z |
| docs | https://support.pocketcasts.com/knowledge-base/playback-effects/ | Pocket Casts guidance: “play downloaded only” and streaming controls. | 2026-03-03T19:44:00Z |
| live-server | `<LOCAL_ABS_SERVER>` read-only probes (`GET`/`HEAD` + one `POST /play` shape check) | Verifies actual endpoint behavior and payload shape on current server version. | 2026-03-03T19:52:00Z |

## Evidence Log

| Step | Command / Request | Key output (status/fields) | Interpretation |
| --- | --- | --- | --- |
| 1 | Code scan (`rg`, `nl -ba`) for offline/download/network logic | `DownloadManager` only stores in-memory queued records; no transfer/persistence. | Downloading is not implemented yet beyond placeholder state. |
| 2 | `rg` for connectivity monitors (`NWPathMonitor`, reachability, background download APIs) | No connectivity monitor and no background download task usage found. | Offline mode cannot be inferred/app-managed today. |
| 3 | `POST /login` on `<LOCAL_ABS_SERVER>` | HTTP 200; token present. | Server reachable and authenticated for verification. |
| 4 | `GET /api/libraries`, `GET /api/libraries/{id}/items` | HTTP 200; book library and item IDs returned. | Current listing endpoints in app are healthy. |
| 5 | `GET /api/items/{itemId}?expanded=1` | HTTP 200; `media.tracks[0].contentUrl` present (`/api/items/{id}/file/{trackId}`). | Item details include direct file URL path needed for offline downloads. |
| 6 | `HEAD /api/items/{id}/file/{trackId}` + range `GET` | HTTP 200 + `Accept-Ranges: bytes`; range request returns HTTP 206. | Track file endpoint supports resumable/partial transfer semantics. |
| 7 | `HEAD /api/items/{id}/download` | HTTP 200; `Content-Type: application/zip`, attachment filename. | Item-level download endpoint exists but returns ZIP package. |
| 8 | range `GET /api/items/{id}/download` | HTTP 200 (not 206), large transfer began before timeout budget. | ZIP endpoint appears less suitable for precise pause/resume than track file endpoint. |
| 9 | `GET /api/libraries/{id}/personalized`, `/series`, `/collections` | HTTP 200 with expected result arrays. | All major menu tabs rely on online endpoints today. |
| 10 | `POST /api/items/{id}/play` (payload-shape check) | HTTP 200; `audioTracks[0].contentUrl` is HLS (`/hls/.../output.m3u8`). | Play endpoint is session/HLS oriented; better for streaming than durable offline assets. |

## API Capability Matrix

| Endpoint / Data source | In code today | In docs | Verified on server | Notes |
| --- | --- | --- | --- | --- |
| `GET /api/libraries` | `yes` | `yes` | `yes` | Used to discover target library IDs. |
| `GET /api/libraries/{id}/items` | `yes` | `yes` | `yes` | Used for Library and grouped fallback resolution. |
| `GET /api/libraries/{id}/personalized` | `yes` | `yes` | `yes` | Used by Home tab. |
| `GET /api/libraries/{id}/series` | `yes` | `yes` | `yes` | Used by Series tab. |
| `GET /api/libraries/{id}/collections` | `yes` | `yes` | `yes` | Used by Collections tab. |
| `GET /api/items/{id}?expanded=1` | `yes` | `yes` | `yes` | Returns chapter/track metadata including `contentUrl`. |
| `POST /api/items/{id}/play` | `no` | `yes` | `yes` | Returns HLS play-session payload; not used by app today. |
| `GET /api/items/{id}/file/{trackId}` | `no` (indirect URL only) | `yes` | `yes` | Best candidate for resumable per-track offline downloads. |
| `GET /api/items/{id}/download` | `no` | `yes` | `yes` | Returns ZIP attachment; adds unzip/storage management complexity. |
| Local offline index/store | `no` | `n/a` | `n/a` | Must be introduced for offline menus/toggles/indicators. |

## Findings

- Finding 1: Current app architecture is entirely online-first for Home/Library/Series/Collections and detail fetches; offline behavior is currently “error state + retry”.
- Finding 2: Playback currently depends on remote `streamURL` tracks and has no local-file fallback path.
- Finding 3: The existing `DownloadManager` is a stub (in-memory queue state only), so pause/resume/delete and persistence are unimplemented.
- Finding 4: Audiobookshelf exposes two plausible download paths: item ZIP (`/download`) and per-track file (`/file/{trackId}`). Live evidence shows per-track route supports byte ranges (HTTP 206) and is a better fit for resumable downloads.
- Finding 5: Mature apps converge on explicit UX: visible offline mode indicator plus a “downloaded only” playback/browse mode (Libby, Spotify, Pocket Casts patterns).
- Finding 6: Audiobookshelf’s own FAQ distinguishes offline behavior across clients, reinforcing that native-client download management is the app’s responsibility.

## Candidate Data Models (Optional)

- Option A: `MinimalOverlayModel` (download status only in-memory + remote lists filtered opportunistically).
  - Pros: Very small implementation effort.
  - Cons: Fails hard requirement that menus work offline; state lost on app restart; weak pause/resume guarantees.
- Option B: `FullMirrorModel` (local mirror of full remote libraries/shelves + downloaded files).
  - Pros: Rich offline browsing and search parity with online mode.
  - Cons: Highest complexity, sync conflict surface, and storage footprint for v1.
- Option C: `DownloadedCatalogModel` (recommended): persist only downloaded items + local tracks/chapters + per-tab downloaded-only filters; online tabs still use server when reachable.
  - Pros: Meets offline availability requirements with bounded scope; cleanly supports offline indicators and filters; lower sync complexity.
  - Cons: Offline catalogs are subset-only (downloaded items), not full-library mirror.

## Constraints And Risks

- Constraint 1: Do not persist credentials/tokens in repository artifacts.
- Constraint 2: User requested to ignore E2E in this iteration.
- Constraint 3: Menus must switch to local downloaded datasets when offline/unreachable.
- Risk 1: Large media files can cause long-running transfer and app lifecycle edge cases.
- Risk 2: Partial/failed downloads can create false “available offline” indicators unless completion criteria are strict.
- Risk 3: Playlist/shelf composition offline can drift from online if only downloaded subset is persisted.

## Open Questions For User

- Resolved on 2026-03-03:
  - Offline mode trigger: automatic only when internet/server is unavailable (no manual force toggle in v1).
  - Offline availability: only fully downloaded books are considered offline-available.
  - Downloaded-only filtering: auto-enabled when offline; not a persisted manual preference for v1.
  - Delete action: delete local media files only; keep progress/bookmarks data.
  - Search behavior: disable search while offline in v1.

## Recommendation

- Recommended approach: Implement Option C (`DownloadedCatalogModel`) using per-track file downloads (`/api/items/{id}/file/{trackId}`), a persistent local download catalog, and an app-wide offline state service that drives indicators + automatic local-data fallback.
- Why: This is the smallest model that still satisfies your required offline behavior across browsing and playback, while preserving robust pause/resume feasibility through ranged track downloads.

## Phase Summary

- Summary: Research completed across current code, official docs, live server evidence, and market patterns. Endpoint and architecture evidence is sufficient to proceed with implementation planning.
- Confidence level (`high | medium | low`): `high`
- Go/No-Go for planning: `go`
