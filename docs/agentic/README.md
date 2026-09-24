# Agentic Workflow Docs

This folder defines the project workflow for role-based implementation with Codex.

## Purpose

Use these docs to make each task traceable and repeatable across six roles:
Researcher, Planner, Implementer, Reviewer, Bug Fixer, and Validator.

## Task Naming

Create task folders under `docs/agentic/tasks/` using:
`YYYY-MM-DD-<slug>`

Example:
`2026-03-01-auth-refresh`

## Minimal Lifecycle

1. Create task folder.
2. Write `research.md`.
3. Write `plan.md`.
4. Implement and record `implementation-notes.md`.
5. Perform review and record `review.md`.
6. Validate and record `validation.md`.

## Quick Start

1. Copy all files from `docs/agentic/templates/` into a new task folder.
2. Fill required sections in `research.md` and `plan.md` first.
3. Implement only what is in scope in `plan.md`.
4. Record findings in `review.md` and resolve required fixes.
5. Run `./scripts/precommit.sh` before commit and `./scripts/prepush.sh` before push.
6. Record validation command results in `validation.md`.

## References

- Workflow: `docs/agentic/workflow.md`
- Templates: `docs/agentic/templates/`
- Example task: `docs/agentic/tasks/_example-task/`
