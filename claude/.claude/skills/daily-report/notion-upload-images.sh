#!/usr/bin/env bash
# Upload local images to Notion and nest each as an image block under the
# report line it illustrates — like a figure under its discussion in a paper,
# not a dump at the end of the page.
#
# Usage:
#   notion-upload-images.sh <page_id> <anchor> <image> <caption> [<anchor> <image> <caption> ...]
#
#   <anchor>  : a short verbatim PLAIN-TEXT substring of the report line the
#               figure belongs under (no markdown markers, unique on the page).
#               "" or "END" => append at the end of the page.
#   <image>   : path to a .png / .jpg / .jpeg / .gif / .webp file.
#   <caption> : one-line figure caption ("" => use the filename).
#
# Needs NOTION_TOKEN (a Notion internal-integration token with access to the
# page), curl and jq. The Notion MCP cannot upload binaries — this hits the
# REST API directly.
set -uo pipefail

NOTION_VERSION="2026-03-11"
API="https://api.notion.com/v1"
die() { echo "notion-upload: $*" >&2; exit 1; }

[ -n "${NOTION_TOKEN:-}" ] || die "NOTION_TOKEN not set"
[ "$#" -ge 4 ] || die "usage: notion-upload-images.sh <page_id> <anchor> <image> <caption> ..."
page_id="$1"; shift
[ $(( $# % 3 )) -eq 0 ] || die "args after page_id must be (anchor image caption) triples"

auth=(-H "Authorization: Bearer $NOTION_TOKEN" -H "Notion-Version: $NOTION_VERSION")

mime_of() {
  case "${1,,}" in
    *.png) echo image/png ;; *.jpg|*.jpeg) echo image/jpeg ;;
    *.gif) echo image/gif ;; *.webp) echo image/webp ;; *) echo "" ;;
  esac
}

# Build a compact {id,text} index of every block on the page, descending into
# nested blocks (topic bullets -> sub-bullets) so anchors can match at any
# depth. The index is NDJSON in a temp file: accumulating the full block JSON
# in a shell variable and passing it back to jq via --argjson overflows
# ARG_MAX on a large page, which silently breaks every anchor lookup.
index_file=""
cleanup() { [ -n "$index_file" ] && rm -f "$index_file"; }
trap cleanup EXIT

fetch_blocks() {
  index_file="$(mktemp)"
  _fetch_children "$page_id"
}
_fetch_children() {
  local parent="$1" cursor="" body url cid
  while :; do
    url="$API/blocks/$parent/children?page_size=100"
    [ -n "$cursor" ] && url="$url&start_cursor=$cursor"
    body="$(curl -sS "${auth[@]}" "$url")"
    [ "$(jq -r '.object // empty' <<<"$body")" = "error" ] && \
      die "list blocks failed: $(jq -rc '.message // .' <<<"$body")"
    jq -c '.results[] | {id, text: ((.[.type].rich_text // []) | map(.plain_text) | join(""))}' \
      <<<"$body" >> "$index_file"
    for cid in $(jq -r '.results[] | select(.has_children == true and .type != "table") | .id' <<<"$body"); do
      _fetch_children "$cid"
    done
    [ "$(jq -r '.has_more' <<<"$body")" = "true" ] || break
    cursor="$(jq -r '.next_cursor' <<<"$body")"
  done
}

# id of the first block whose plain text contains $1 (empty if none).
# Backticks are dropped from the anchor: a caller may copy a phrase spanning an
# inline-code span, but Notion's stored plain text never carries them.
anchor_id() {
  jq -rs --arg a "$1" \
    '($a | gsub("`"; "")) as $a
     | [.[] | select(.text | contains($a))][0].id // empty' "$index_file"
}

# upload $1 -> echo file_upload id (empty + non-zero on failure).
upload() {
  local img="$1" name mime created uid sent
  name="$(basename "$img")"; mime="$(mime_of "$name")"
  [ -f "$img" ]  || { echo "notion-upload: skip (not found): $img" >&2; return 1; }
  [ -n "$mime" ] || { echo "notion-upload: skip (unsupported type): $img" >&2; return 1; }
  created="$(curl -sS "${auth[@]}" -H "Content-Type: application/json" -X POST "$API/file_uploads" \
    -d "$(jq -n --arg f "$name" --arg c "$mime" '{filename:$f,content_type:$c}')")"
  uid="$(jq -r '.id // empty' <<<"$created")"
  [ -n "$uid" ] || { echo "notion-upload: create failed for $name: $(jq -rc '.message//.' <<<"$created")" >&2; return 1; }
  sent="$(curl -sS "${auth[@]}" -X POST "$API/file_uploads/$uid/send" -F "file=@\"$img\";type=$mime")"
  [ "$(jq -r '.status // empty' <<<"$sent")" = "uploaded" ] || \
    { echo "notion-upload: send failed for $name: $(jq -rc '.message//.' <<<"$sent")" >&2; return 1; }
  printf '%s' "$uid"
}

fetch_blocks
ok=0; bad=0

while [ "$#" -ge 3 ]; do
  anchor="$1"; img="$2"; caption="$3"; shift 3
  name="$(basename "$img")"
  [ -n "$caption" ] || caption="$name"

  uid="$(upload "$img")" || { bad=$((bad + 1)); continue; }

  # Parent of the image block. Default = the page (image lands at page end).
  # With an anchor, parent = the matched block, so the image NESTS under that
  # bullet (renders indented beneath it, like a figure under its discussion).
  parent="$page_id"; where="page end"
  if [ -n "$anchor" ] && [ "$anchor" != "END" ]; then
    aid="$(anchor_id "$anchor")"
    if [ -n "$aid" ]; then
      parent="$aid"; where="nested under $aid"
    else
      echo "notion-upload: anchor not found ('$anchor') for $name — appending at page end" >&2
    fi
  fi

  block="$(jq -n --arg id "$uid" --arg cap "$caption" \
    '{type:"image",image:{type:"file_upload",file_upload:{id:$id},caption:[{type:"text",text:{content:$cap}}]}}')"
  resp="$(curl -sS "${auth[@]}" -H "Content-Type: application/json" \
    -X PATCH "$API/blocks/$parent/children" -d "$(jq -n --argjson b "$block" '{children:[$b]}')")"
  if [ "$(jq -r '.object // empty' <<<"$resp")" = "error" ]; then
    echo "notion-upload: insert failed for $name: $(jq -rc '.message//.' <<<"$resp")" >&2
    bad=$((bad + 1)); continue
  fi
  ok=$((ok + 1))
  echo "notion-upload: inserted $name ($where)"
done

echo "notion-upload: done ($ok inserted, $bad skipped/failed)"
[ "$bad" -eq 0 ]
