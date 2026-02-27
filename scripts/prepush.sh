#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PROJECT="${PROJECT:-Skippy/Skippy.xcodeproj}"
SCHEME="${SCHEME:-Skippy}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone SE (3rd generation)}"

echo "[prepush] Running full local gate..."

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination "${DESTINATION}" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  >/tmp/skippy-prepush-build.log 2>&1 || {
    cat /tmp/skippy-prepush-build.log
    exit 1
  }

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination "${DESTINATION}" \
  test \
  CODE_SIGNING_ALLOWED=NO \
  >/tmp/skippy-prepush-test.log 2>&1 || {
    cat /tmp/skippy-prepush-test.log
    exit 1
  }

echo "[prepush] OK"
