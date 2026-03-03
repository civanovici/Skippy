# Plan (Planner)

## Phase Metadata

- Task ID: `2026-03-01-user-stats-section`
- Phase: Planner
- Owner Agent: Planner
- Status: `approved`
- Approval: `approved`
- Approved By: `User`
- Approval Date (YYYY-MM-DD): `2026-03-01`

## Phase Gate

- Prerequisite: Researcher phase `Approval: approved`.
- Gate rule: Do not start Implementer phase until this phase is `Approval: approved`.

## Inputs From Research

- Research artifact path: `/Users/lupucristian/work/skippy/docs/agentic/tasks/2026-03-01-user-stats-section/research.md`
- Key finding 1: Server supports both `GET /api/me/listening-stats` and `GET /api/libraries/{id}/stats`.
- Key finding 2: Current app has no stats API methods and User menu has no Stats entry.
- Key unresolved question: None; user selected Option C on `2026-03-01`.

## Goal

- Primary goal: Add User -> Stats screen showing personal activity and library analytics with reliable empty-state handling.
- User impact: Gives visibility into both listening behavior and library scale directly from User menu.

## Success Criteria

- Criterion 1: User menu contains a `Stats` row navigating to a stats screen.
- Criterion 2: Screen loads data from `/api/me/listening-stats` and `/api/libraries/{id}/stats` and renders distinct personal and library sections.
- Criterion 3: Empty payloads render without crashes or decode errors (e.g., `totalTime=0`, empty maps/lists).

## Scope

- In scope item 1: New client API methods/models for `/api/me/listening-stats` and `/api/libraries/{id}/stats`.
- In scope item 2: New Stats UI under User menu (read-only) with personal + library sections.
- Out of scope item 1: E2E/UI automation for this iteration.
- Out of scope item 2: Admin/user-management stats views or cross-user comparisons.

## Options Considered

- Option A: Summary-only stats (total + today).
  - Tradeoffs: Simplest/fastest, but low insight depth.
- Option B: Activity stats v1 from `/api/me/listening-stats` (totals + days + recent sessions + top items).
  - Tradeoffs: Higher value and still one endpoint, with moderate decoding complexity.
- Option C: Activity + library analytics (`/api/libraries/{id}/stats`) [selected].
  - Tradeoffs: Richest but mixes personal and library concepts; more UI surface and design decisions.

## Recommended Approach

- Approach summary: Implement Option C as v1, combining `/api/me/listening-stats` and `/api/libraries/{id}/stats` with defensive decoding and clear sectioning in UI.
- Why this option: Explicitly chosen by user and fully supported by verified server endpoints.

## Recommended V1 Data Model

1. `UserListeningStats`
   - `totalTimeSeconds: TimeInterval`
   - `todayTimeSeconds: TimeInterval`
   - `dayOfWeekHeatmap: [Int: TimeInterval]` (normalized from API map)
   - `dailyTotals: [DailyListeningPoint]`
   - `topItems: [ListeningItemStat]`
   - `recentSessions: [ListeningSession]`
2. `DailyListeningPoint`
   - `date: Date`
   - `seconds: TimeInterval`
3. `ListeningItemStat`
   - `itemID: String`
   - `title: String`
   - `seconds: TimeInterval`
   - `percentOfTotal: Double?`
4. `ListeningSession`
   - `startedAt: Date?`
   - `endedAt: Date?`
   - `seconds: TimeInterval`
   - `itemID: String?`
   - `itemTitle: String?`
5. `LibraryStatsSnapshot`
   - `libraryID: String`
   - `libraryName: String`
   - `totalItems: Int`
   - `totalDurationSeconds: TimeInterval`
   - `totalSizeBytes: Int64`
   - `totalAuthors: Int`
   - `totalGenres: Int`
   - `largestItems: [LibraryItemStat]`
   - `longestItems: [LibraryItemStat]`
6. `LibraryItemStat`
   - `itemID: String`
   - `title: String`
   - `sizeBytes: Int64?`
   - `durationSeconds: TimeInterval?`

## Implementation Steps

1. Add API contracts + HTTP implementations for `fetchMyListeningStats(session:)` and `fetchLibraryStats(session:libraryID:)` in `AudiobookshelfAPI`.
2. Add decoding models and normalization logic for both endpoints, including empty payload handling.
3. Update `StatsViewModel` to load both datasets and map them into separate UI sections.
4. Add `StatsView` and wire navigation entry under `UserView`.
5. Add unit tests for decoding + empty-state mapping + view model loading/error states across both data sources.

## Files To Change

- `/Users/lupucristian/work/skippy/Skippy/Skippy/Services/API/AudiobookshelfAPI.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/User/UserView.swift`
- `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/User/` (new `StatsView.swift`, `StatsViewModel.swift`)
- `/Users/lupucristian/work/skippy/Skippy/SkippyTests/` (new/updated unit tests)

## Test Plan

- Unit test coverage: decode `listening-stats` and `library-stats` payload variants (empty/populated) and view-model state transitions.
- Integration/UI test coverage: deferred (explicitly out of scope this iteration).
- Manual verification: login with real server user; open User -> Stats; verify personal and library sections including empty states.

## Risks And Mitigations

- Risk 1: API payload variability between ABS versions.
  - Mitigation: flexible decoder, permissive optionals, and normalization with sane defaults.
- Risk 2: Combined screen complexity can reduce readability.
  - Mitigation: keep separate sections and cap top-N library lists in v1.

## Rollback Plan

- Rollback trigger: decode/runtime regressions in User view or API errors increasing after rollout.
- Rollback steps: disable library subsection first; if needed, remove Stats entry and endpoint call path.

## Phase Summary

- Summary: Plan C approved; v1 will ship hybrid personal + library stats with defensive decoding and clear sectioned UI.
- Recommendation: `proceed`
- Awaiting user approval to implement: `no`
