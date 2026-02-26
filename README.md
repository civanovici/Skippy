# Skippy

Native iOS audiobook player for [Audiobookshelf](https://www.audiobookshelf.org/).

Skippy connects to a user-provided Audiobookshelf server URL (including private/Tailscale-hosted servers), authenticates with username/password, and supports:

- Streaming audiobooks
- Downloading audiobooks for offline playback
- Background playback (screen locked / app in background)
- Resume progress and basic playback controls

## Status

Project is in planning phase. This repository currently contains product docs and will be used to build the iOS app.

## MVP Goals

- Connect to a single Audiobookshelf server URL
- Sign in with username/password
- Browse user library of audiobooks
- View book details and chapters/tracks
- Stream playback
- Download a book for offline playback
- Background audio + lock screen controls
- Persist playback progress locally and sync back to server (if API supports it as expected)

## Non-Goals (Initial MVP)

- CarPlay
- Apple Watch app
- In-app server management for multiple servers/accounts
- Advanced admin features (server/library management)
- E-book/PDF reading

## Planned Tech Stack (Confirmed for MVP)

- iOS 17+ (Swift / SwiftUI)
- `AVFoundation` / `AVAudioSession` for playback
- `MediaPlayer` for lock screen metadata and remote controls
- `URLSession` for API + downloads
- Local persistence: `SwiftData` or `Core Data` (TBD)
- Keychain for credentials/session tokens

## Tailscale Compatibility

Skippy is intended to work with Audiobookshelf instances reachable over Tailscale, as long as:

- The iPhone can reach the Tailscale/private hostname or IP
- TLS/cert configuration on the server is valid for the URL used (or the user uses HTTP within a trusted private network)
- The Audiobookshelf API is accessible from the device

No special Tailscale integration is required in-app if the network path is already available on iOS.

## Repository Structure (Planned)

- `README.md` - project overview and setup notes
- `docs/PRD.md` - product requirements
- `Skippy/` - iOS app source (to be created)
- `SkippyTests/` - unit tests
- `SkippyUITests/` - UI tests

## Feature Suggestions (Post-MVP)

- Sleep timer
- Playback speed presets and EQ shortcuts
- Chapter bookmarks and notes
- Multiple server profiles (home server + remote server)
- Siri Shortcuts ("Resume audiobook")
- CarPlay support
- Apple Watch remote controls

## Open Questions

- Should MVP support multiple Audiobookshelf libraries/accounts, or exactly one account/server?
- Do you want local downloads per-book only, or also per-chapter/partial download support?
- Should the app cache streaming audio automatically (temporary cache) in addition to explicit downloads?
- Confirm exact minimum iOS version target (note: `iOS 26.3` looks like a typo or device build reference)

## Current Product Decisions (Confirmed)

- Single server/account for MVP
- Simple native UI (not artwork-first)
- Cellular streaming supported
- Ask about cellular streaming behavior on first launch (with a setting to change later)

## Next Steps

1. Finalize MVP scope in `docs/PRD.md`
2. Confirm minimum iOS version and design direction
3. Create Xcode project scaffolding
4. Implement API client and authentication
5. Implement playback engine + background audio
6. Add offline downloads and sync
