# Agentic Workflow

This workflow is the canonical task execution order.

## Phase 1: Researcher

Output:
- `research.md`

Gate:
- Claims include source path/URL.
- Constraints are listed explicitly.
- Known risks are listed explicitly.

## Phase 2: Planner

Output:
- `plan.md`

Gate:
- Plan is decision complete.
- In-scope and out-of-scope are explicit.
- Acceptance criteria are testable.

## Phase 3: Implementer

Output:
- Code diff
- `implementation-notes.md`

Gate:
- Changes map directly to plan items.
- No opportunistic refactors.
- Deviations from plan are documented.

## Phase 4: Reviewer

Output:
- `review.md`

Gate:
- Findings are listed by severity.
- Findings include file references.
- Each finding is resolved or accepted as explicit risk.

## Phase 5: Bug Fixer

Output:
- Updates in `implementation-notes.md`
- Updates in `review.md`

Gate:
- Each bug has repro steps.
- Verification after fix is documented.

## Phase 6: Validator

Output:
- `validation.md`

Required commands:
- `./scripts/precommit.sh` before commit
- `./scripts/prepush.sh` before push

Gate:
- Pass/fail result is recorded per command.
- Timestamp and short summary are recorded.
- If checks are skipped, reason is documented.
