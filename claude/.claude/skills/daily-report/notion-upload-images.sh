#!/usr/bin/env bash
# Upload local image files to Notion and append them as image blocks to a page.
# Usage: notion-upload-images.sh <page_id> <image> [image ...]
# Needs NOTION_TOKEN (a Notion internal-integration token) in the environment,
# plus curl and jq. The Notion MCP cannot upload binaries — this hits the REST
# API directly. The integration must have access to <page_id>.
set -uo pipefail

NOTION_VERSION="2026-03-11"
API="https://api.notion.com/v1"

die() { echo "notion-upload: $*" >&2; exit 1; }

[ -n "${NOTION_TOKEN:-}" ] || die "NOTION_TOKEN not set"
[ "$#" -ge 2 ] || die "usage: notion-upload-images.sh <page_id> <image> [image ...]"

page_id="$1"; shift

mime_of() {
  case "${1,,}" in
    *.png)        echo "image/png" ;;
    *.jpg|*.jpeg) echo "image/jpeg" ;;
    *.gif)        echo "image/gif" ;;
    *.webp)       echo "image/webp" ;;
    *)            echo "" ;;
  esac
}

blocks="[]"
ok=0
bad=0

for img in "$@"; do
  name="$(basename "$img")"
  if [ ! -f "$img" ]; then
    echo "notion-upload: skip (not found): $img" >&2; bad=$((bad + 1)); continue
  fi
  mime="$(mime_of "$name")"
  if [ -z "$mime" ]; then
    echo "notion-upload: skip (unsupported type): $img" >&2; bad=$((bad + 1)); continue
  fi

  created="$(curl -sS -X POST "$API/file_uploads" \
    -H "Authorization: Bearer $NOTION_TOKEN" \
    -H "Notion-Version: $NOTION_VERSION" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg f "$name" --arg c "$mime" '{filename: $f, content_type: $c}')")"
  upload_id="$(jq -r '.id // empty' <<<"$created")"
  if [ -z "$upload_id" ]; then
    echo "notion-upload: create failed for $name: $(jq -rc '.message // .' <<<"$created")" >&2
    bad=$((bad + 1)); continue
  fi

  sent="$(curl -sS -X POST "$API/file_uploads/$upload_id/send" \
    -H "Authorization: Bearer $NOTION_TOKEN" \
    -H "Notion-Version: $NOTION_VERSION" \
    -F "file=@\"$img\";type=$mime")"
  if [ "$(jq -r '.status // empty' <<<"$sent")" != "uploaded" ]; then
    echo "notion-upload: send failed for $name: $(jq -rc '.message // .' <<<"$sent")" >&2
    bad=$((bad + 1)); continue
  fi

  blocks="$(jq --arg id "$upload_id" --arg cap "$name" \
    '. + [{type: "image", image: {type: "file_upload", file_upload: {id: $id},
       caption: [{type: "text", text: {content: $cap}}]}}]' <<<"$blocks")"
  ok=$((ok + 1))
  echo "notion-upload: uploaded $name"
done

if [ "$(jq 'length' <<<"$blocks")" -gt 0 ]; then
  resp="$(curl -sS -X PATCH "$API/blocks/$page_id/children" \
    -H "Authorization: Bearer $NOTION_TOKEN" \
    -H "Notion-Version: $NOTION_VERSION" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --argjson c "$blocks" '{children: $c}')")"
  if [ "$(jq -r '.object // empty' <<<"$resp")" = "error" ]; then
    die "append blocks failed: $(jq -rc '.message // .' <<<"$resp")"
  fi
fi

echo "notion-upload: done ($ok uploaded, $bad skipped/failed)"
[ "$bad" -eq 0 ]
