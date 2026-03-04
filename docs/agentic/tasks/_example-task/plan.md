# Plan

## Goal

- Add one guarded token-refresh retry path for `401` responses.

## Success Criteria

- A stale token triggers refresh exactly once.
- Request is retried once after successful refresh.
- App logs out only if refresh fails.

## In Scope

- Update auth/session service retry handling.
- Add unit tests for success and failure refresh flows.

## Out of Scope

- UI changes.
- Multi-account session support.

## Approach

- Add single-flight refresh guard.
- Retry original request one time after successful refresh.
- Surface explicit logout path on refresh failure.

## Files To Change

- `Skippy/Skippy/Services/SessionService.swift`
- `Skippy/SkippyTests/SessionServiceTests.swift`

## Test Plan

- Unit test: refresh success retries original request and succeeds.
- Unit test: refresh failure logs out and returns auth error.

## Acceptance Criteria

- New tests pass.
- Existing auth/session tests remain green.

## Rollback / Risk Notes

- Revert session retry block if regressions are found.
- Residual risk: race condition during concurrent requests.
