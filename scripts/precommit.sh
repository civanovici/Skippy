#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PROJECT="${PROJECT:-Skippy/Skippy.xcodeproj}"
SCHEME="${SCHEME:-Skippy}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone SE (3rd generation)}"

echo "[precommit] Verifying repository state..."
if ! git diff --cached --quiet; then
  git diff --cached --check
fi

echo "[precommit] Building ${SCHEME}..."
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination "${DESTINATION}" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  >/tmp/skippy-precommit-build.log 2>&1 || {
    cat /tmp/skippy-precommit-build.log
    exit 1
  }

echo "[precommit] Running unit tests (SkippyTests)..."
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination "${DESTINATION}" \
  -only-testing:SkippyTests \
  test \
  CODE_SIGNING_ALLOWED=NO \
  >/tmp/skippy-precommit-test.log 2>&1 || {
    cat /tmp/skippy-precommit-test.log
    exit 1
  }

echo "[precommit] OK"
