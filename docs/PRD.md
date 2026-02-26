# Product Requirements Document (PRD)

## Product Name

Skippy

## Problem Statement

Users who host Audiobookshelf want a native iOS experience for listening to audiobooks from their own server, including private access (for example over Tailscale), offline downloads, and reliable background playback when the phone is locked.

## Product Vision

Deliver a fast, minimal, reliable iOS audiobook player focused on self-hosted Audiobookshelf users.

## Goals (MVP)

- Allow a user to connect to a specified Audiobookshelf server URL
- Authenticate with username/password
- Browse and select audiobooks from the user library
- Stream audiobook playback
- Download audiobook content to device storage for offline playback
- Continue playback with phone locked / app backgrounded
- Persist playback position and restore resume state

## Success Criteria (MVP)

- User can sign in and browse their audiobook library within 60 seconds on first launch (assuming valid server credentials)
- Playback continues when screen locks and responds to system media controls
- User can download at least one book and play it fully offline (airplane mode test)
- App restores last position after app restart for streamed and downloaded books

## Target Users

- Self-hosters running Audiobookshelf
- Users accessing Audiobookshelf over LAN/VPN/Tailscale
- Listeners who want offline audiobook playback on iPhone

## Core User Stories

- As a user, I want to enter my Audiobookshelf URL and login credentials so I can access my library.
- As a user, I want to stream a book immediately so I can start listening without downloading.
- As a user, I want to download a book locally so I can listen offline.
- As a user, I want playback to continue when my phone is locked so I can listen hands-free.
- As a user, I want the app to remember where I stopped so I can resume later.

## Assumptions

- Audiobookshelf exposes a stable API for login, library browsing, metadata retrieval, and playback/progress sync.
- Audio assets are delivered as files/streams compatible with `AVPlayer` or similar iOS playback APIs.
- iOS networking can reach Tailscale/private endpoints as long as connectivity is already configured on the device.

## Scope

### In Scope (MVP)

- Single server configuration (one active server/account)
- Username/password authentication
- Library list and book detail views
- Playback controls:
  - Play/pause
  - Seek forward/back
  - Scrub within track/chapter
  - Next/previous chapter (if metadata available)
- Background playback and lock screen controls
- Local downloads for audiobooks
- Download management (start/pause/cancel/delete) at basic level
- Playback progress persistence (local first, server sync when online)

### Out of Scope (MVP)

- CarPlay
- Apple Watch app
- Multi-account/server support
- Admin management of Audiobookshelf server
- Podcasts/music support (unless trivially exposed and intentionally included)
- Social features, ratings, reviews

## Functional Requirements

### 1. Server Connection & Authentication

- App must allow user to input:
  - Server URL (HTTP/HTTPS)
  - Username
  - Password
- App must validate URL format before attempting login.
- App must display clear error states for:
  - Invalid URL
  - Network unreachable
  - Authentication failure
  - Server/API incompatible
- App should persist session securely (token/cookie) and avoid repeated login when possible.
- Credentials/session secrets must be stored in Keychain.

### 2. Library Browsing

- App must fetch and display audiobook library items available to the user.
- App must show at minimum:
  - Title
  - Author (if available)
  - Cover art (if available)
  - Progress indicator (if available)
- App should support pull-to-refresh.
- App should support basic search/filter in MVP only if low effort; otherwise defer.

### 3. Book Details

- App must show:
  - Cover
  - Title
  - Author/narrator (if available)
  - Duration
  - Chapters/tracks list (if available)
  - Download status
  - Resume position
- App must allow starting playback from:
  - Beginning
  - Resume position
  - Selected chapter/track (if supported by API/data)

### 4. Streaming Playback

- App must support streaming playback over Wi-Fi/cellular (subject to iOS permissions/settings).
- App must provide playback controls:
  - Play/pause
  - Seek +/- X seconds (configurable default, e.g. 15s/30s)
  - Playback speed (at least 1.0x, 1.25x, 1.5x, 2.0x)
- App must display current position and remaining/elapsed time.
- App should recover gracefully from transient network errors and allow retry/resume.

### 5. Offline Downloads

- App must allow user to download an audiobook for offline playback.
- App must show download progress and state (`queued`, `downloading`, `paused`, `completed`, `failed`).
- App must allow deletion of downloaded content to free storage.
- App must verify local file availability before marking item as offline-ready.
- App should support background download continuation when feasible within iOS constraints.

### 6. Background Playback & System Integration

- Playback must continue when:
  - Screen is locked
  - App is backgrounded
- App must integrate with:
  - Lock Screen media controls
  - Control Center media controls
  - Headphone remote play/pause events
- App must display now playing metadata (title/chapter/artwork when available).
- App should handle audio interruptions (phone calls, Siri, alarms) and resume appropriately.

### 7. Progress Tracking & Sync

- App must persist playback position locally for each book.
- App should sync progress to Audiobookshelf when online/authenticated.
- If sync fails, app should queue retry and preserve local progress.
- Conflict handling (device vs server progress) can be simplified in MVP:
  - Prefer most recent timestamped progress record.

## Non-Functional Requirements

### Performance

- Initial library screen should become interactive within 2 seconds after cached data is available.
- Playback actions (play/pause/seek) should respond within 200ms under normal conditions.

### Reliability

- App should not lose local progress when app is terminated unexpectedly.
- Downloads should remain valid across app restarts.

### Security

- Store secrets in Keychain
- Do not log credentials
- Use HTTPS by default; if HTTP is allowed, surface a warning (especially outside local/private networks)

### Privacy

- No analytics required for MVP (optional opt-in later)
- No third-party tracking SDKs

## UX Requirements (MVP)

- Fast path from launch to playback in minimal taps
- Clear distinction between streaming and downloaded items
- Obvious offline state indicators
- Large playback controls suitable for one-handed use
- Preserve state when returning to app from background

## Technical Notes (Implementation Direction)

- `AVAudioSession` category configured for background playback
- Background Modes capability enabled: Audio, AirPlay, and Picture in Picture (Audio playback use-case)
- `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` for system media controls
- `URLSession` background configuration for downloads (subject to file/auth constraints)
- Local persistence for:
  - Session/account metadata
  - Library cache
  - Download records
  - Playback progress

## Risks & Mitigations

- Audiobookshelf API changes or undocumented behavior
  - Mitigation: isolate API layer and version assumptions
- Download/auth edge cases (signed URLs, expiring tokens)
  - Mitigation: design resumable/retry download workflow with refreshable auth
- iOS background limitations
  - Mitigation: prioritize reliable foreground download + background playback first
- Private network/Tailscale DNS issues on device
  - Mitigation: show actionable connectivity diagnostics (host unreachable, TLS error, DNS failure)

## Milestones (Proposed)

### Milestone 1: Skeleton + Auth

- Xcode project setup
- Server URL/login UI
- API client
- Session persistence

### Milestone 2: Library + Player

- Library browse UI
- Book detail UI
- Streaming playback
- Background audio and lock screen controls

### Milestone 3: Offline

- Download manager
- Offline playback
- Progress sync/retry
- Error handling polish

## Open Product Decisions (Need Your Input)

1. Minimum iOS version target (suggestion: iOS 17 for faster development, iOS 16 for wider compatibility)
2. Single server/account only in MVP, or multi-server support from day one?
3. Should signup/account creation be out of scope (login-only)? (recommended: login-only)
4. Preferred UI style:
   - Simple native Apple Books-like
   - Dense list for power users
   - Artwork-first library
5. Should streaming over cellular be enabled by default, or opt-in?

## Appendix: Nice-to-Have Features (Future)

- Sleep timer
- Chapter bookmarks
- Smart rewind after pause
- Variable skip durations
- Siri Shortcuts / App Intents
- CarPlay
- Apple Watch companion/remote
