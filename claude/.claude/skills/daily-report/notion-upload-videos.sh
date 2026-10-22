#!/usr/bin/env bash
# Upload local videos (mp4 / webm / mov) to Notion and nest each as a video
# block under the report line it belongs to — same contract as
# notion-upload-images.sh (anchor = verbatim plain-text substring of the
# target line; "" or "END" = page end; an anchor that matches nothing SKIPS
# the video, nothing inserted). Files over 19 MB go through Notion's
# multi-part upload (10 MB parts).
#
# Usage:
#   notion-upload-videos.sh <page_id> <anchor> <video> <caption> [<anchor> <video> <caption> ...]
#
# Needs NOTION_TOKEN (internal-integration token with access to the page),
# curl, jq and split.
set -uo pipefail

NOTION_VERSION="2026-03-11"
API="https://api.notion.com/v1"
PART_BYTES=$((10 * 1024 * 1024))
SINGLE_MAX=$((19 * 1000 * 1000))
die() { echo "notion-upload-videos: $*" >&2; exit 1; }

[ -n "${NOTION_TOKEN:-}" ] || die "NOTION_TOKEN not set"
[ "$#" -ge 4 ] || die "usage: notion-upload-videos.sh <page_id> <anchor> <video> <caption> ..."
page_id="$1"; shift
[ $(( $# % 3 )) -eq 0 ] || die "args after page_id must be (anchor video caption) triples"

auth=(-H "Authorization: Bearer $NOTION_TOKEN" -H "Notion-Version: $NOTION_VERSION")

mime_of() {
  case "${1,,}" in
    *.mp4) echo video/mp4 ;; *.webm) echo video/webm ;; *.mov) echo video/quicktime ;; *) echo "" ;;
  esac
}

index_file=""; tmpdir=""
cleanup() { [ -n "$index_file" ] && rm -f "$index_file"; [ -n "$tmpdir" ] && rm -rf "$tmpdir"; }
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

anchor_id() {
  jq -rs --arg a "$1" \
    '($a | gsub("`"; "")) as $a
     | [.[] | select(.text | contains($a))][0].id // empty' "$index_file"
}

# upload $1 -> echo file_upload id (empty + non-zero on failure)
upload() {
  local vid="$1" name mime size created uid sent nparts i part done_
  name="$(basename "$vid")"; mime="$(mime_of "$name")"
  [ -f "$vid" ]  || { echo "notion-upload-videos: skip (not found): $vid" >&2; return 1; }
  [ -n "$mime" ] || { echo "notion-upload-videos: skip (unsupported type): $vid" >&2; return 1; }
  size="$(stat -c %s "$vid")"
  if [ "$size" -le "$SINGLE_MAX" ]; then
    created="$(curl -sS "${auth[@]}" -H "Content-Type: application/json" -X POST "$API/file_uploads" \
      -d "$(jq -n --arg f "$name" --arg c "$mime" '{filename:$f,content_type:$c}')")"
    uid="$(jq -r '.id // empty' <<<"$created")"
    [ -n "$uid" ] || { echo "notion-upload-videos: create failed for $name: $(jq -rc '.message//.' <<<"$created")" >&2; return 1; }
    sent="$(curl -sS "${auth[@]}" -X POST "$API/file_uploads/$uid/send" -F "file=@\"$vid\";type=$mime")"
    [ "$(jq -r '.status // empty' <<<"$sent")" = "uploaded" ] || \
      { echo "notion-upload-videos: send failed for $name: $(jq -rc '.message//.' <<<"$sent")" >&2; return 1; }
    printf '%s' "$uid"; return 0
  fi
  # multi-part: 10 MB parts (Notion: 5-20 MB per part except the last)
  nparts=$(( (size + PART_BYTES - 1) / PART_BYTES ))
  tmpdir="${tmpdir:-$(mktemp -d)}"
  rm -f "$tmpdir"/part_*
  split -b "$PART_BYTES" -d -a 3 "$vid" "$tmpdir/part_" || { echo "notion-upload-videos: split failed for $name" >&2; return 1; }
  created="$(curl -sS "${auth[@]}" -H "Content-Type: application/json" -X POST "$API/file_uploads" \
    -d "$(jq -n --arg f "$name" --arg c "$mime" --argjson n "$nparts" '{mode:"multi_part",number_of_parts:$n,filename:$f,content_type:$c}')")"
  uid="$(jq -r '.id // empty' <<<"$created")"
  [ -n "$uid" ] || { echo "notion-upload-videos: multi-part create failed for $name: $(jq -rc '.message//.' <<<"$created")" >&2; return 1; }
  i=0
  for part in "$tmpdir"/part_*; do
    i=$((i + 1))
    sent="$(curl -sS "${auth[@]}" -X POST "$API/file_uploads/$uid/send" -F "file=@\"$part\";type=$mime" -F "part_number=$i")"
    [ "$(jq -r '.object // empty' <<<"$sent")" = "error" ] && \
      { echo "notion-upload-videos: part $i/$nparts failed for $name: $(jq -rc '.message//.' <<<"$sent")" >&2; return 1; }
    echo "notion-upload-videos: $name part $i/$nparts sent" >&2
  done
  done_="$(curl -sS "${auth[@]}" -H "Content-Type: application/json" -X POST "$API/file_uploads/$uid/complete" -d '{}')"
  [ "$(jq -r '.status // empty' <<<"$done_")" = "uploaded" ] || \
    { echo "notion-upload-videos: complete failed for $name: $(jq -rc '.message//.' <<<"$done_")" >&2; return 1; }
  printf '%s' "$uid"
}

fetch_blocks
ok=0; bad=0

while [ "$#" -ge 3 ]; do
  anchor="$1"; vid="$2"; caption="$3"; shift 3
  name="$(basename "$vid")"
  [ -n "$caption" ] || caption="$name"

  parent="$page_id"; where="page end"
  if [ -n "$anchor" ] && [ "$anchor" != "END" ]; then
    aid="$(anchor_id "$anchor")"
    if [ -n "$aid" ]; then
      parent="$aid"; where="nested under $aid"
    else
      echo "notion-upload-videos: anchor not found ('$anchor') for $name — SKIPPED, nothing inserted (fix the anchor and re-run)" >&2
      bad=$((bad + 1)); continue
    fi
  fi

  uid="$(upload "$vid")" || { bad=$((bad + 1)); continue; }

  block="$(jq -n --arg id "$uid" --arg cap "$caption" \
    '{type:"video",video:{type:"file_upload",file_upload:{id:$id},caption:[{type:"text",text:{content:$cap}}]}}')"
  resp="$(curl -sS "${auth[@]}" -H "Content-Type: application/json" \
    -X PATCH "$API/blocks/$parent/children" -d "$(jq -n --argjson b "$block" '{children:[$b]}')")"
  if [ "$(jq -r '.object // empty' <<<"$resp")" = "error" ]; then
    echo "notion-upload-videos: insert failed for $name: $(jq -rc '.message//.' <<<"$resp")" >&2
    bad=$((bad + 1)); continue
  fi
  ok=$((ok + 1))
  echo "notion-upload-videos: inserted $name ($where)"
done

echo "notion-upload-videos: done ($ok inserted, $bad skipped/failed)"
[ "$bad" -eq 0 ]
