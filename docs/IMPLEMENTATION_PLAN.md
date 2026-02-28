# Skippy Implementation Plan (MVP)

This document breaks the MVP into concrete phases with checkpoints so progress is easy to track and review.

## Progress Tracking

Status legend:

- `[ ]` Not started
- `[-]` In progress
- `[x]` Done
- `[!]` Blocked

## MVP Summary (Locked Decisions)

- iOS target: `17+`
- Single Audiobookshelf server/account for MVP
- Login-only (existing Audiobookshelf account)
- Simple/native UI
- Streaming over Wi-Fi + cellular
- Ask cellular streaming preference on first launch
- Streaming + offline downloads + background playback

## Phase 0: Project Setup (Foundation)

Goal: Create a buildable iOS app skeleton with the right capabilities and architecture seams.

### Checkpoints

- [x] Create branch `codex/ios-init`
- [x] Create Xcode project (`Skippy`) with:
  - [x] iOS app target (SwiftUI)
  - [x] Unit test target
  - [x] UI test target
- [x] Set deployment target to iOS 17+
- [x] Configure bundle identifier and signing placeholders
- [x] Enable Background Modes capability:
  - [x] Audio, AirPlay, Picture in Picture
- [x] Add app icon placeholders / assets scaffold
- [x] Add project folder structure (see Architecture Skeleton below)
- [x] App launches to a placeholder root screen

### Exit Criteria

- App builds and runs on simulator
- App launches without runtime errors
- Git commit created for project skeleton

## Phase 1: Architecture Skeleton (No Real Networking Yet)

Goal: Create the core modules/services as compilable stubs so features can be built incrementally.

### Architecture Skeleton (Suggested)

- `Skippy/App/`
  - `SkippyApp.swift`
  - `AppState.swift`
  - `RootView.swift`
- `Skippy/Features/Auth/`
  - `LoginView.swift`
  - `LoginViewModel.swift`
- `Skippy/Features/Library/`
  - `LibraryView.swift`
  - `LibraryViewModel.swift`
- `Skippy/Features/BookDetail/`
  - `BookDetailView.swift`
  - `BookDetailViewModel.swift`
- `Skippy/Features/Player/`
  - `PlayerView.swift`
  - `PlayerViewModel.swift`
- `Skippy/Services/API/`
  - `APIClient.swift`
  - `AudiobookshelfAPI.swift`
- `Skippy/Services/Auth/`
  - `AuthStore.swift`
  - `KeychainStore.swift`
- `Skippy/Services/Playback/`
  - `PlayerService.swift`
  - `NowPlayingService.swift`
- `Skippy/Services/Downloads/`
  - `DownloadManager.swift`
- `Skippy/Services/Persistence/`
  - `PersistenceController.swift`
- `Skippy/Models/`
  - `UserSession.swift`
  - `Audiobook.swift`
  - `Chapter.swift`
  - `PlaybackProgress.swift`
  - `DownloadRecord.swift`
- `Skippy/Support/`
  - `Config.swift`
  - `Logger.swift`

### Checkpoints

- [x] Define app navigation flow (`unauthenticated -> library -> player/detail`)
- [x] Add dependency container / service wiring
- [x] Add model stubs and mock data
- [x] Add protocol-based interfaces for API, playback, downloads
- [x] Root view switches between login and library based on auth state
- [x] Project compiles with all stubs in place

### Exit Criteria

- Clear compile-time seams for networking/playback/downloads
- Can demo navigation with mock data only

## Phase 2: Authentication + Server Connection (First Vertical Slice)

Goal: Let user connect to an Audiobookshelf server and persist session.

### User-Facing Scope

- Enter server URL, username, password
- Login to remote Audiobookshelf server
- Handle errors clearly
- Save session securely

### Checkpoints

- [x] Implement login form (URL, username, password)
- [x] URL validation (basic format + scheme handling)
- [x] Add `APIClient` login request
- [x] Parse/store auth session/token
- [x] Persist credentials/session secrets in Keychain
- [x] Restore prior session on app launch
- [x] Show error states:
  - [x] Invalid URL
  - [x] Network unreachable
  - [x] Invalid credentials
  - [x] Server/API mismatch
- [x] Add logout flow (basic)

### Exit Criteria

- Successful login against a real Audiobookshelf server
- App reopens without requiring login again (if session valid)

## Phase 3: Discovery Surfaces (Home/Library/Series/Collections)

Goal: Build the core browsing experience to match Audiobookshelf navigation patterns and metadata richness.

### User-Facing Scope

- Top-level authenticated tabs/screens:
  - Home
  - Library (Books)
  - Series
  - Collections
- Search available from each screen
- Shelf-based browsing experience for audiobooks (horizontal rails with covers)
- Rich metadata shown in cards/detail previews (title, author, progress, series/collection context)

### API Notes (Confirmed from Audiobookshelf docs)

- Auth:
  - `POST /login` (token is typically in `user.token` in current server responses)
- Navigation/data:
  - `GET /api/libraries`
  - `GET /api/libraries/{id}/personalized`
  - `GET /api/libraries/{id}/items`
  - `GET /api/libraries/{id}/series`
  - `GET /api/libraries/{id}/collections`
  - `GET /api/libraries/{id}/search`
  - `GET /api/libraries/{id}/filterdata`
- Metadata/assets:
  - `GET /api/items/{id}`
  - `GET /api/items/{id}/cover`

### Checkpoints

- [x] Add baseline library fetch API call(s)
- [x] Map core list response into app models
- [x] Build initial list UI with pull-to-refresh and error/empty handling
- [x] Add authenticated tab shell for `Home | Library | Series | Collections`
- [x] Implement Home screen using `/personalized` sections as shelves
- [ ] Implement Library screen using `/items` with sort/filter support from `/filterdata`
- [x] Implement Series screen using `/series` endpoint + series artwork/title/count
- [x] Implement Collections screen using `/collections` endpoint + collection artwork/title
- [x] Implement search on each screen using `/search` and context-aware scopes
  - [x] Local search UX on Home, Library, Series, Collections
  - [x] Server-backed `/search` integration per surface
- [x] Create reusable `ShelfView` component:
  - [x] horizontal scroll
  - [x] cover image
  - [x] title/author/progress overlays
  - [x] tap-through to detail/player entry points
- [ ] Expand metadata mapping from `/items/{id}` for richer detail pages
- [ ] Add pagination strategy for large libraries (server-side page/limit)
- [ ] Add basic local image caching strategy for covers

### Exit Criteria

- User can browse Home, Library, Series, and Collections with search on each screen
- Shelf view is used for audiobook rails and is performant with real server data
- Metadata and covers render reliably from live Audiobookshelf responses

### Execution Milestones (Recommended)

Use short-lived branches from latest `main`, then merge sequentially:

1. `codex/phase-3a-tabs-navigation`
- Scope:
  - Add authenticated tab shell for `Home | Library | Series | Collections`
  - Keep existing Library data loading working inside new shell
- Done when:
  - User can switch between all 4 screens
  - Existing login/logout flow still works

2. `codex/phase-3b-home-shelves`
- Scope:
  - Implement Home screen using `/api/libraries/{id}/personalized`
  - Add reusable `ShelfView` for horizontal rails
- Done when:
  - [x] Personalized shelves render with covers/titles
  - [x] Tapping a shelf item opens detail

3. `codex/phase-3c-library-upgrade`
- Scope:
  - Upgrade Library screen to use `/api/libraries/{id}/items` + `/filterdata`
  - Add sort/filter controls and better empty/error states
- Done when:
  - Library supports server-driven sorting/filter metadata
  - Large lists remain responsive

4. `codex/phase-3d-series-collections`
- Scope:
  - Implement Series (`/series`) and Collections (`/collections`) screens
  - Reuse `ShelfView`/grid components for visual consistency
- Done when:
  - [x] Series and Collections screens load real data
  - [x] Navigation into contained books works

5. `codex/phase-3e-search-all-surfaces`
- Scope:
  - Add search to Home/Library/Series/Collections using `/search`
  - Make search context-aware by active screen/scope
- Done when:
  - [x] Search works on every screen
  - [x] Results are relevant to current browsing context

6. `codex/phase-3f-metadata-polish`
- Scope:
  - Expand detail metadata via `/api/items/{id}`
  - Harden cover/image handling and caching strategy
  - Add pagination for large libraries
- Done when:
  - Detail screens show richer metadata reliably
  - Scrolling and image loading perform well on realistic datasets

## Phase 4: Book Detail + Streaming Playback

Goal: Start listening from the app with reliable streaming playback.

### User-Facing Scope

- Book details and chapter list
- Inline player controls directly in the detail surface (no forced navigation to a separate player screen when pressing Play)
- Player layout should not depend on showing the left cover image (cover can be optional/hidden without breaking control layout)
- Standard transport controls:
  - Play/Pause (single toggle button)
  - Seek back `15s`
  - Seek forward `15s`
  - Previous/Next chapter when available
- Scrubbing behavior like a standard audiobook player:
  - User can drag backward/forward freely
  - During scrubbing, show target time preview (iOS interaction; hover-equivalent)
- Always-visible progress metrics:
  - Percent complete
  - Elapsed time
  - Remaining time
- Keep right-side utility controls focused to:
  - Playback speed
  - Sleep timer
  - Bookmark actions
- Audible playback on device (no silent playback bug)

### Checkpoints

- [x] Book detail API/data loading
- [x] Chapter/track list UI
- [ ] Replace large Play CTA with inline transport controls in detail layout
- [ ] Make control strip resilient when artwork is omitted (no empty left-image slot assumptions)
- [ ] Remove non-essential right-side controls; keep speed/timer/bookmark
- [ ] Implement `PlayerService` using `AVPlayer`/`AVFoundation`
- [ ] Start stream playback from beginning
- [x] Resume playback from saved position
- [ ] Playback speed controls (`1x`, `1.25x`, `1.5x`, `2x`)
- [ ] Seek back/forward controls are exactly `15s`
- [ ] Previous/next chapter controls (enabled only when chapter exists)
- [ ] Scrubber with time-preview while dragging
- [ ] Display elapsed, remaining, and percentage completion in player UI
- [ ] Basic buffering/loading state UI
- [ ] Handle network playback failure + retry
- [ ] Fix no-audio output path:
  - [ ] Validate stream URL/source
  - [ ] Validate `AVAudioSession` category/activation
  - [ ] Validate device route and mute-state handling
- [x] Sleep timer controls
- [x] Bookmark controls (local + server sync)

### Exit Criteria

- User can stream a book end-to-end in foreground with audible output and standard controls
- User does not need to navigate to a separate page just to access core playback controls

## Phase 5: Background Playback + Lock Screen Controls

Goal: Playback continues when screen locks/backgrounds and integrates with iOS media controls.

### User-Facing Scope

- Continue playback with phone locked
- Control playback from lock screen / Control Center / headphones
- Show now playing metadata/artwork
- Playback must continue when iPhone screen is closed/locked (background audio is required, not optional)

### Checkpoints

- [ ] Configure `AVAudioSession` for playback
- [ ] Confirm Background Modes capability works in build
- [ ] Verify lock-screen continuity on physical iPhone:
  - [ ] Start playback, lock device, confirm audio continues
  - [ ] Unlock device, confirm state remains in sync
- [ ] Add `NowPlayingService` with metadata updates
- [ ] Integrate `MPNowPlayingInfoCenter`
- [ ] Integrate `MPRemoteCommandCenter`
- [ ] Support play/pause/seek remote commands
- [ ] Handle audio interruptions (calls/Siri/alarms)
- [ ] Handle route changes (Bluetooth/headphones disconnect)

### Exit Criteria

- Locking the phone does not stop audiobook playback
- System media controls control the app reliably
- Verified on real device (not simulator-only)

## Phase 6: Offline Downloads (Core MVP)

Goal: Download audiobooks locally and play them without network connectivity.

### User-Facing Scope

- Download audiobook
- View download state/progress
- Play offline
- Delete download

### Checkpoints

- [ ] Define download storage layout (per book)
- [ ] Implement `DownloadManager` state machine:
  - [ ] queued
  - [ ] downloading
  - [ ] paused
  - [ ] completed
  - [ ] failed
- [ ] Implement authenticated download requests
- [ ] Persist download records across app restarts
- [ ] Mark books as offline-ready
- [ ] Prefer local media when available
- [ ] Delete local download + cleanup metadata
- [ ] UI for download actions/status
- [ ] Airplane mode validation flow

### Exit Criteria

- User can download at least one book and play fully offline

## Phase 7: Playback Progress Persistence + Sync

Goal: Preserve progress locally and sync to Audiobookshelf when possible.

### User-Facing Scope

- Resume where user left off
- Progress survives app restarts
- Syncs to server when online
- If app-local progress and server progress differ materially, user is asked which source to continue with

### Checkpoints

- [x] Persist local progress updates while playing
- [ ] Persist a dedicated app-local playback timeline resilient to server-side resets/bugs
- [ ] Throttle/debounce progress writes to avoid excessive I/O
- [x] Restore progress on app relaunch
- [x] Implement progress sync API call(s)
- [ ] Queue failed sync attempts for retry
- [x] Timestamp-based conflict handling (most recent wins)
- [ ] Replace silent "most recent wins" for large conflicts with explicit user choice dialog:
  - [ ] "Continue with App Time"
  - [ ] "Continue with Server Time"
  - [ ] Show both positions and last-updated timestamps in dialog
- [ ] Define meaningful conflict threshold (seconds/percent) before prompting user
- [ ] Track and surface sync-event failures with actionable UI copy
- [x] Visual confirmation (subtle progress indicators)

### Exit Criteria

- Progress resumes correctly after app restart and syncs after reconnecting
- User can reliably recover from server-reset progress using app-local timeline

## Phase 8: Settings + Onboarding Preferences (MVP Polish)

Goal: Capture user preferences and expose basic controls needed for daily use.

### User-Facing Scope

- First-launch preference prompt for cellular streaming
- Settings screen for server/session and playback/network options

### Checkpoints

- [ ] First-launch prompt for cellular streaming preference
- [ ] Persist preference locally
- [ ] Settings screen scaffold
- [ ] Toggle for cellular streaming on/off
- [ ] Logout button
- [ ] Server info / current connection display
- [ ] Optional: skip interval setting (15s/30s)

### Exit Criteria

- User can control cellular streaming behavior after onboarding

## Phase 9: Testing, Stability, and Release Readiness (MVP)

Goal: Reduce regressions and validate critical flows.

### Test Priorities

- Auth success/failure
- Library load/error
- Playback start/seek/resume
- Background playback
- Download + offline playback
- Progress persistence/sync retry

### Checkpoints

- [ ] Unit tests for parsing/models/view models
- [ ] Unit tests for auth/session handling
- [ ] Unit tests for progress conflict logic
- [ ] UI smoke tests for login -> library flow
- [ ] Manual test checklist created
- [ ] Test on:
  - [ ] Simulator
  - [ ] Physical iPhone (strongly recommended for audio/background behavior)
- [ ] Crash/error logging strategy (local logs minimum)
- [ ] Beta readiness checklist (TestFlight prep)

### Exit Criteria

- Critical flows pass manual checklist on device
- No blocker bugs for MVP use case

## Suggested Git Checkpoint Commits

These are recommended commit boundaries to keep progress easy to review:

- [ ] `chore: create iOS app project skeleton`
- [ ] `feat: add app architecture and service stubs`
- [ ] `feat: implement Audiobookshelf login and session persistence`
- [ ] `feat: load and display audiobook library`
- [ ] `feat: add streaming playback controls`
- [ ] `feat: enable background playback and lock screen controls`
- [ ] `feat: add offline downloads`
- [ ] `feat: persist and sync playback progress`
- [ ] `feat: add settings and first-launch cellular preference`
- [ ] `test: add MVP smoke tests and manual checklist`

## Risks / Blockers Tracker

Use this section to log issues as they appear.

### Current Known Risks

- Xcode simulator/runtime install may delay initial project generation/testing
- Audiobookshelf API details may require adjustments after first integration
- Background downloads may be constrained by auth/token behavior
- Current public Audiobookshelf API docs are explicitly marked as out-of-date; endpoint behavior must be validated against running server responses
- Playback currently can fail silently if audio session/route/stream setup is incomplete

### Active Blockers

- [ ] Investigate no-audio playback on device
- [ ] Investigate sync-event errors and conflict UX for local-vs-server progress

## Current Next Step

- Wait for Xcode simulator/runtime install to finish
- Create branch `codex/ios-init`
- Generate Xcode project and Phase 0/1 skeleton
