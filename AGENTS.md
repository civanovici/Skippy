# Repository Guidelines

## Project Structure & Module Organization

Core project layout:

- `Skippy/Skippy/`: iOS app source (Swift/SwiftUI)
- `Skippy/SkippyTests/`: unit tests
- `Skippy/SkippyUITests/`: UI tests
- `docs/`: product + implementation docs (`PRD.md`, `IMPLEMENTATION_PLAN.md`)
- `assets/`: icon/design sources and generated `AppIcon.appiconset`

## Build, Test, and Development Commands

Use project-local Xcode CLI commands:

- `xcodebuild -project Skippy/Skippy.xcodeproj -scheme Skippy -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' build`
- `xcodebuild -project Skippy/Skippy.xcodeproj -scheme Skippy -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' test`
- `./scripts/precommit.sh`: local build + unit-test gate before commit
- `./scripts/prepush.sh`: local build + full test gate before push

Before commit: `git status --short` and `git diff --cached`.

## Coding Style & Naming Conventions

- Follow Swift API Design Guidelines and Xcode default formatting (4-space indentation)
- Use `UpperCamelCase` for types (`PlaybackViewModel`)
- Use `lowerCamelCase` for functions/properties (`resumePosition`)
- Keep files grouped by module (`App`, `Features`, `Services`, `Models`, `Support`)

Use clear file names for assets/docs, e.g. `skippy-app-icon-variant-2.svg`.

## Testing Guidelines

Frameworks: `XCTest` + `XCUITest`.

- Unit tests: `SkippyTests/`
- UI tests: `SkippyUITests/`
- Name tests by behavior, e.g. `testLoginFailsWithInvalidCredentials()`

Prioritize coverage for auth/session handling, API parsing, playback state, and downloads.

## Agent Review Workflow

Codex must always run code review and tests before every commit and push, automatically, without asking the user.

- Review the pending/staged diff before each commit
- Resolve review findings (or explicitly document accepted risk) before committing
- Run `./scripts/precommit.sh` before each commit
- Run `./scripts/prepush.sh` before each push
- If tests cannot run, record the reason in commit/PR notes and call it out in the handoff
- Do not skip review/tests because the user forgot to ask

If no staged diff exists, do not commit.

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
