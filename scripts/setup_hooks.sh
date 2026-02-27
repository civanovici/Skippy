#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

mkdir -p .githooks
chmod +x .githooks/pre-commit .githooks/pre-push scripts/precommit.sh scripts/prepush.sh
git config core.hooksPath .githooks

echo "Git hooks enabled via core.hooksPath=.githooks"
