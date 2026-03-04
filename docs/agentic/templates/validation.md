# Validation (Validator)

## Phase Metadata

- Task ID:
- Phase: Validator
- Owner Agent: Validator
- Status: `draft | completed`
- Review approval confirmed: `yes | no`

## Phase Gate

- Prerequisite: Reviewer phase `Approval: approved`.
- Gate rule: Do not mark task complete until validation verdict is recorded.

## Environment

- Date:
- Branch:
- Target:
- Build configuration:

## Gate Check Summary

- Research approval: `approved | missing`
- Plan approval: `approved | missing`
- Review approval: `approved | missing`

## Required Project Checks

### Precommit Result

- Command: `./scripts/precommit.sh`
- Result: `pass | fail | not-run`
- Summary:

### Prepush Result

- Command: `./scripts/prepush.sh`
- Result: `pass | fail | not-run`
- Summary:

## Feature-Specific Checks

- Command:
  - Result:
  - Evidence:
- Command:
  - Result:
  - Evidence:

## Known Limitations / Environment Issues

- Issue 1:
- Issue 2:

## Final Validation Verdict

- Verdict: `pass | fail | pass-with-caveats`
- Notes:

## Phase Summary

- Summary:
- Ready to hand off: `yes | no`
