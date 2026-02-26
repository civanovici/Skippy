# Repository Guidelines

## Project Structure & Module Organization

This repository is currently in planning/setup phase.

- `README.md`: project overview, MVP scope, and planned tech stack
- `docs/PRD.md`: product requirements and feature decisions
- `docs/IMPLEMENTATION_PLAN.md`: implementation sequencing and milestones
- `assets/`: design assets, including SVG icon concepts and `AppIcon.appiconset`

Planned source layout (not created yet):

- `Skippy/`: iOS app source (Swift/SwiftUI)
- `SkippyTests/`: unit tests
- `SkippyUITests/`: UI/integration tests

## Build, Test, and Development Commands

There is no Xcode project checked in yet, so there are no active build/test commands today.

Once scaffolding exists, prefer standard Xcode CLI commands:

- `xcodebuild -scheme Skippy -destination 'platform=iOS Simulator,name=iPhone 16' build`
- `xcodebuild -scheme Skippy -destination 'platform=iOS Simulator,name=iPhone 16' test`

Use `git status` before commits to confirm only intended files changed.

## Coding Style & Naming Conventions

For upcoming Swift code:

- Follow Swift API Design Guidelines and Xcode default formatting (4-space indentation)
- Use `UpperCamelCase` for types (`PlaybackViewModel`)
- Use `lowerCamelCase` for functions/properties (`resumePosition`)
- Keep files focused by feature (`Auth`, `Library`, `Playback`, `Downloads`)

Assets and docs should use clear, descriptive names (example: `skippy-app-icon-variant-2.svg`).

## Testing Guidelines

Testing framework is expected to be `XCTest` (unit + UI tests) after project creation.

- Unit tests: `SkippyTests/`
- UI tests: `SkippyUITests/`
- Test names should describe behavior, e.g. `testLoginFailsWithInvalidCredentials()`

Include test coverage for playback state, API parsing, auth/session handling, and offline download behavior.

## Commit & Pull Request Guidelines

Current commit history uses short, scoped, imperative messages such as:

- `docs: refine MVP decisions and auth scope`
- `docs: add initial project README and PRD`

Continue using `<scope>: <summary>` (examples: `ui:`, `playback:`, `api:`, `docs:`).

PRs should include:

- concise summary of changes
- linked issue/task (if available)
- testing notes (`Not run`, or command/results)
- screenshots for UI/icon changes

## Security & Configuration Tips

Do not commit real server URLs, credentials, tokens, or private network details. Use placeholders in docs and sample configs.
