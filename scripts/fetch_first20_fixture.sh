#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${ROOT_DIR}/Skippy/SkippyTests/Fixtures/audiobookshelf_first20.json"

: "${ABS_SERVER:?ABS_SERVER is required, e.g. http://192.168.0.122:13378}"
: "${ABS_USERNAME:?ABS_USERNAME is required}"
: "${ABS_PASSWORD:?ABS_PASSWORD is required}"

mkdir -p "$(dirname "${OUT_FILE}")"

TOKEN="$(curl -sS \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"${ABS_USERNAME}\",\"password\":\"${ABS_PASSWORD}\"}" \
  "${ABS_SERVER}/login" | jq -r '.user.token // .user.accessToken // .token')"

LIBRARY_ID="$(curl -sS "${ABS_SERVER}/api/libraries?token=${TOKEN}" | jq -r '.libraries[] | select((.mediaType // "book") == "book") | .id' | head -n 1)"

if [[ -z "${LIBRARY_ID}" ]]; then
  echo "No audiobook library found."
  exit 1
fi

ITEMS_JSON="$(curl -sS "${ABS_SERVER}/api/libraries/${LIBRARY_ID}/items?minified=1&limit=20&page=0&token=${TOKEN}")"
TMP_ITEMS="$(mktemp /tmp/skippy-items-XXXXXX.ndjson)"

echo "${ITEMS_JSON}" | jq -c '.results[]' | while read -r item; do
  id="$(echo "${item}" | jq -r '.id')"
  title="$(echo "${item}" | jq -r '.media.metadata.title // .media.title // "Untitled"')"
  author="$(echo "${item}" | jq -r '.media.metadata.authorName // "Unknown Author"')"
  cover_path="$(echo "${item}" | jq -r '.media.coverPath // empty')"
  progress="$(echo "${item}" | jq -r '.progress // .mediaProgress.progress // .userMediaProgress.progress // 0')"

  tmp_cover="$(mktemp /tmp/skippy-cover-XXXXXX.jpg)"
  code="$(curl -sS -m 20 -o "${tmp_cover}" -w "%{http_code}" "${ABS_SERVER}/api/items/${id}/cover?token=${TOKEN}")"

  if [[ "${code}" == "200" ]]; then
    cover_width="$(sips -g pixelWidth "${tmp_cover}" 2>/dev/null | awk '/pixelWidth:/{print $2}')"
    cover_height="$(sips -g pixelHeight "${tmp_cover}" 2>/dev/null | awk '/pixelHeight:/{print $2}')"
  else
    cover_width="null"
    cover_height="null"
  fi

  rm -f "${tmp_cover}"

  jq -n \
    --arg id "${id}" \
    --arg title "${title}" \
    --arg author "${author}" \
    --arg coverPath "${cover_path}" \
    --arg coverURL "/api/items/${id}/cover" \
    --argjson progress "${progress}" \
    --argjson coverWidth "${cover_width:-null}" \
    --argjson coverHeight "${cover_height:-null}" \
    '{
      id:$id,
      title:$title,
      author:$author,
      coverPath:($coverPath | if . == "" then null else . end),
      coverURL:$coverURL,
      progress:$progress,
      coverWidth:$coverWidth,
      coverHeight:$coverHeight
    }' >> "${TMP_ITEMS}"
done

jq -s \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg server "${ABS_SERVER}" \
  --arg libraryId "${LIBRARY_ID}" \
  '{generatedAt:$generatedAt,server:$server,libraryId:$libraryId,items:.}' \
  "${TMP_ITEMS}" > "${OUT_FILE}"

rm -f "${TMP_ITEMS}"
echo "Wrote ${OUT_FILE}"
