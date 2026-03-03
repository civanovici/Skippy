# Research (Researcher)

## Phase Metadata

- Task ID: `2026-03-01-user-stats-section`
- Phase: Researcher
- Owner Agent: Researcher
- Status: `approved`
- Approval: `approved`
- Approved By: `Codex (research completed with code+docs+live evidence)`
- Approval Date (YYYY-MM-DD): `2026-03-01`

## Phase Gate

- Gate rule: Do not start Planner phase until this phase is `Approval: approved`.

## Task Profile

- Complexity: `medium`
- Requires live API verification: `yes`
- Requires online docs check: `yes`
- Requires E2E in this iteration: `no`

## Task Summary

- Feature summary: Add a Stats section under User menu to show user listening activity plus library analytics.
- User-visible outcome: User can open User -> Stats and view personal listening metrics/history and library-level totals from Audiobookshelf.
- Explicit non-goals: E2E coverage in this iteration; credential storage in repo.

## Research Questions

- Question 1: What API endpoints is the app using today, and where are gaps for user activity stats?
- Question 2: What does official Audiobookshelf API documentation expose for listening/library stats?
- Question 3: Which stats endpoints are available and usable on the running server for this user role?

## Sources Checked

| Type (`code | docs | live-server`) | Location / URL | Why it matters | Checked at |
| --- | --- | --- | --- |
| code | `/Users/lupucristian/work/skippy/Skippy/Skippy/Services/API/AudiobookshelfAPI.swift` | Definitive map of current network surface in app. | 2026-03-01T08:20:52Z |
| code | `/Users/lupucristian/work/skippy/Skippy/Skippy/Features/User/UserView.swift` | Confirms current User menu has no Stats section. | 2026-03-01T08:20:52Z |
| docs | https://api.audiobookshelf.org/#get-your-listening-stats | Official doc for `/api/me/listening-stats`. | 2026-03-01T08:11:00Z |
| docs | https://api.audiobookshelf.org/#get-a-user-s-listening-stats | Official doc for `/api/users/{id}/listening-stats`. | 2026-03-01T08:11:00Z |
| docs | https://api.audiobookshelf.org/#get-library-stats | Official doc for `/api/libraries/{id}/stats`. | 2026-03-01T08:11:00Z |
| live-server | `<LOCAL_ABS_SERVER>` read-only probes | Verifies actual endpoint availability and response shape on running server. | 2026-03-01T08:18:00Z |

## Evidence Log

| Step | Command / Request | Key output (status/fields) | Interpretation |
| --- | --- | --- | --- |
| 1 | Code scan (`rg`, `nl -ba`) of API + feature call sites | API methods in use: login, libraries/items/search, item details, progress, bookmarks. No stats fetch method. | Stats is not implemented yet in client API surface. |
| 2 | Docs check on api.audiobookshelf.org stats sections | Docs list `/api/me/listening-stats`, `/api/users/{id}/listening-stats`, `/api/libraries/{id}/stats`. | Official docs support both user-level and library-level stats. |
| 3 | `POST /login` | HTTP 200; token present (`tokenLen: 196`), user id returned. | Auth works for evidence collection. |
| 4 | `GET /api/libraries` | HTTP 200; one audiobook library object (`type: object`, `count: 1`). | Library-scoped endpoints can be tested. |
| 5 | `GET /api/libraries/{id}/personalized` and `/search` | HTTP 200 with expected array/object payloads. | Confirms existing app-used endpoints currently healthy. |
| 6 | `GET /api/items/{itemId}?expanded=1` | HTTP 200 with item detail object. | Existing detail endpoint is healthy. |
| 7 | `GET /api/me/progress/{itemId}` | HTTP 404 (`Not Found`). | Per-item progress may be missing for some items/users; client must tolerate nil/404 (already does). |
| 8 | `GET /api/me/listening-stats?days=7` | HTTP 200; keys: `dayOfWeek, days, items, recentSessions, today, totalTime`. | Server supports direct user stats endpoint suitable for User->Stats UI. |
| 9 | `GET /api/users/{id}/listening-stats?month=2026-02` | HTTP 200 with same top-level keys. | User-specific stats endpoint also works with explicit user id. |
| 10 | `GET /api/libraries/{id}/stats` | HTTP 200; keys include `totalDuration, totalItems, totalSize, largestItems, longestItems`. | Library analytics endpoint is available as optional enhancement. |
| 11 | `GET /api/me` and `GET /api/users/{id}` | `/api/me`: HTTP 200 user object; `/api/users/{id}`: HTTP 403 for this user. | Current account likely non-admin; avoid relying on general user admin endpoints. |
| 12 | `GET /api/me/listening-stats?days=30` detail probe | `totalTime=0`, `today=0`, `days={}`, `items={}`, `recentSessions=[]`. | Endpoint can return empty-state shapes; UI model must handle empty maps/arrays cleanly. |

## API Capability Matrix

| Endpoint / Data source | In code today | In docs | Verified on server | Notes |
| --- | --- | --- | --- | --- |
| `POST /login` | `yes` | `yes` | `yes` | Used in `AudiobookshelfHTTPAPI.login`. |
| `GET /api/libraries` | `yes` | `yes` | `yes` | Used for audiobook library discovery. |
| `GET /api/libraries/{id}/items` | `yes` | `yes` | `yes` | Used for library listing and grouped fallbacks. |
| `GET /api/libraries/{id}/personalized` | `yes` | `yes` | `yes` | Used for Home shelves. |
| `GET /api/libraries/{id}/search` | `yes` | `yes` | `yes` | Used across Home/Library/Series/Collections search. |
| `GET /api/items/{id}?expanded=1` | `yes` | `yes` | `yes` | Used for details/player context. |
| `GET/PATCH /api/me/progress/{id}` | `yes` | `yes` | `yes` (GET may 404 by item) | Client already treats decode/mismatch as nil fallback. |
| `POST/DELETE /api/me/item/{id}/bookmark` | `yes` | `yes` | `untested` | Not probed to preserve read-only live evidence. |
| `GET /api/me/listening-stats` | `no` | `yes` | `yes` | Best fit for user activity in User menu. |
| `GET /api/users/{id}/listening-stats` | `no` | `yes` | `yes` | Works, but `/api/me/*` avoids extra user-id coupling. |
| `GET /api/libraries/{id}/stats` | `no` | `yes` | `yes` | Useful optional library stats, not strictly user activity. |

## Findings

- Finding 1: Current app networking has no stats methods; User menu currently contains only Account + Logout.
- Finding 2: Official docs expose user listening stats endpoints and library stats endpoint.
- Finding 3: Running server supports both user stats and library stats; user stats currently return empty-state payloads (`days`/`items` object maps) for this account.
- Finding 4: `/api/users/{id}` is forbidden for this user, so user-level data should rely on `/api/me/*` rather than admin-like user endpoints.
- Finding 5: User selected Plan C on `2026-03-01` (hybrid personal + library stats).

## Candidate Data Models (Optional)

- Option A: Summary-only model from `/api/me/listening-stats` (`totalTime`, `today`, counts).
  - Pros: Smallest payload/UI complexity; fastest to ship.
  - Cons: Low utility if user wants trends/top titles/session context.
- Option B: Full user activity model from `/api/me/listening-stats` including trend map (`days`), top items (`items`), and session list (`recentSessions`).
  - Pros: Rich activity page without additional endpoints.
  - Cons: Requires robust decoding for polymorphic/empty map shapes.
- Option C: Hybrid user+library model (`/api/me/listening-stats` + `/api/libraries/{id}/stats`) [selected].
  - Pros: Adds catalog-level insights (library size/duration) beyond personal behavior.
  - Cons: Blends two concepts (personal activity vs library analytics), higher UI complexity for v1.

## Constraints And Risks

- Constraint 1: Must not store server credentials inside repo.
- Constraint 2: User asked to ignore E2E in this iteration.
- Risk 1: Official API docs can lag server behavior; runtime response shape should be treated as source of truth.
- Risk 2: Empty-state stats payloads (object maps + zero values) can cause brittle decoding/UI if not modeled defensively.

## Open Questions For User

- Question 1: Preferred default time window for listening trends (e.g., 7d, 30d, current month)?

## Recommendation

- Recommended approach: Implement Plan C v1: combine `/api/me/listening-stats` for personal activity and `/api/libraries/{id}/stats` for library analytics, using defensive models for zero/empty payloads.
- Why: User explicitly selected Plan C, both endpoints are verified on the running server, and this delivers broader value in one Stats surface.

## Phase Summary

- Summary: Research complete with evidence from local code, official docs, and live server probes; endpoint readiness is confirmed for the selected hybrid (Plan C) v1.
- Confidence level (`high | medium | low`): `high`
- Go/No-Go for planning: `go`
