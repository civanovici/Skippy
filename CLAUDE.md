# Skippy — Claude Context

Native iOS audiobook player for [Audiobookshelf](https://www.audiobookshelf.org/) self-hosted servers.

See `AGENTS.md` for coding conventions, commit style, and agentic workflow rules.

---

## Current Implementation State

### Done

- **Phase 0–2**: Xcode project, SwiftUI app skeleton, auth (login/logout/session via Keychain), API client
- **Phase 3**: Home shelves (`/personalized`), Library, Series, Collections, search on all surfaces, reusable `ShelfView`/`BookCardView` components
- **Phase 4**: Book detail screen with inline transport controls (play/pause, ±15s, prev/next chapter, scrubber with time preview, speed control, sleep timer, bookmarks), `PlayerService` using `AVPlayer`
- **Phase 5** (partial): Background audio capability enabled, `NowPlayingService` with `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`, audio interruption/route-change handling, `PersistenceController` integrated into views
- **Phase 7** (partial): Local progress persistence (throttled writes), restore on relaunch, server sync, conflict dialog ("Continue with App Time" / "Continue with Server Time"), local-only fallback when server sync fails
- **User/Stats screen**: Activity and library analytics tab (`StatsView` / `StatsViewModel`)

### In Progress / Blocked

- **Phase 5 blocker**: Lock-screen/background playback stops after device lock on physical iPhone (simulator is fine). Needs targeted logging of `AVAudioSession`, `AVPlayerItem`, and `NowPlayingInfoCenter` state at lock time.
- **Phase 6** (not started): Offline downloads — `DownloadManager` stub exists, `ConnectivityStore` wired into tab view models (latest commit), but download state machine and UI are not implemented yet.
- **Phase 3 remaining**: Library sort/filter via `/filterdata`, pagination for large libraries, local image caching for covers.
- **Phase 7 remaining**: Queue failed sync attempts for retry, show both positions + timestamps in conflict dialog.

### Not Started

- Phase 8: Settings screen, first-launch cellular streaming preference
- Phase 9: Unit tests beyond existing fixture-driven book card tests, UI smoke tests, TestFlight prep

---

## Architecture

```
Skippy/
  App/          SkippyApp, RootView, AppState, DependencyContainer, AuthenticatedTabView
  Features/     Auth, BookDetail, Collections, Home, Library, Player, Series, User
  Services/     API (APIClient, AudiobookshelfAPI)
                Auth (AuthStore, KeychainStore)
                Connectivity (ConnectivityStore)
                Downloads (DownloadManager)
                Persistence (PersistenceController)
                Playback (PlayerService, NowPlayingService)
  Models/       Audiobook, AudiobookDetails, Chapter, DownloadRecord, HomeShelf,
                PlaybackProgress, UserSession, UserStats, AudioBookmark
  Support/      BookCardView, BookCardImageLayout, ShelfView, Config, Logger, View+Searchable
```

MVVM throughout. `DependencyContainer` owns all service instances and injects them into view models.

---

## Key Audiobookshelf API Endpoints Used

| Purpose | Endpoint |
|---|---|
| Login | `POST /login` |
| Libraries | `GET /api/libraries` |
| Home shelves | `GET /api/libraries/{id}/personalized` |
| Library items | `GET /api/libraries/{id}/items` |
| Series | `GET /api/libraries/{id}/series` |
| Collections | `GET /api/libraries/{id}/collections` |
| Search | `GET /api/libraries/{id}/search` |
| Book detail | `GET /api/items/{id}` |
| Cover image | `GET /api/items/{id}/cover` |

---

## Active Branch

`codex/download-books` — wiring download/connectivity dependencies into tab view models as groundwork for Phase 6.

---

## Known Risks

- Background audio stops on physical iPhone after screen lock (Phase 5 blocker)
- Audiobookshelf public API docs are marked out-of-date; endpoint behavior must be validated against a live server
- Download auth/token behavior with `URLSession` background sessions is untested
