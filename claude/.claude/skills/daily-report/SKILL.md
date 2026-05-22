---
name: daily-report
description: Generate a terse research-style daily report for the current project. Runs almost entirely in a background agent — the foreground only resolves paths and the Notion target, then a background worker reads today's session transcript + git activity, drafts the report to <project>/.claude/daily-reports/YYYY-MM-DD.md, and (if configured) syncs it as a dated child page placed at the TOP of a Notion parent page. Use when the user says "今日の日報書いて", "daily report", "今日のまとめ", or asks to summarize today's work in this project.
---

# Daily Report

One terse research-style daily report for the current project. The whole job
runs in a **single background agent**: `/daily-report` resolves a few paths in
the foreground, fires the worker, and returns immediately. You are notified when
the report is saved locally and synced to Notion.

The report is terse — bullets, tables, conclusions. **No journey narrative.**

## Step 1 — resolve in the foreground (fast)

A background agent cannot read your live conversation and cannot ask you
questions, so the foreground does just two things: resolve paths, and settle the
Notion target.

**Paths:**
```sh
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DATE=$(date +%Y-%m-%d)
OUT="$ROOT/.claude/daily-reports/$DATE.md"
TRANSCRIPT=$(find "$HOME/.claude/projects" -maxdepth 2 -name "${CLAUDE_CODE_SESSION_ID}.jsonl" 2>/dev/null | head -1)
```
`CLAUDE_CODE_SESSION_ID` is set by Claude Code and the transcript file is named
`<session-id>.jsonl`, so this `find` resolves it exactly. If `TRANSCRIPT` is
empty, fall back to the newest `*.jsonl` in that project dir; if still none,
pass `TRANSCRIPT=none` (the worker then uses git only).

**Notion target** — resolve now, because the worker cannot ask:
- First hit wins: project-local `$ROOT/.claude/daily-report-notion.txt`, then the
  global `notion-page.txt` in this skill's directory.
- Value = first line that is not blank and not starting with `#`. `DISABLED` →
  Notion off. A real URL/ID → that is the parent page. `NOT_CONFIGURED` or a
  missing file → fall through to the next source.
- If neither file decides it, **ask the user once**: "Notion parent page URL for
  this project? (paste a URL, or say `skip`)". A URL → strip any `?...` query and
  write it to `$ROOT/.claude/daily-report-notion.txt`. `skip` → write `DISABLED`
  there so the project is never asked again.
- The result is a single value: a parent page URL/ID, or the literal `DISABLED`.

## Step 2 — dispatch the background worker

One `Agent` call with `run_in_background: true` and `subagent_type: "general-purpose"`.
Fill every `<<...>>` slot in the **Background worker prompt** below and send it.

If the user passed extra context (e.g. "include the eval numbers"), append it
verbatim to the worker prompt — do not summarize it away.

## Step 3 — return immediately

Tell the user the report is generating in the background and they will be
notified on completion. Do not wait, do not poll.

## Background worker prompt

```
You are the daily-report worker. Work autonomously — nobody can answer questions.

Inputs:
  ROOT          = <<ROOT>>
  PROJECT       = <<basename of ROOT>>
  BRANCH        = <<current git branch>>
  DATE          = <<DATE>>            (local date, YYYY-MM-DD)
  OUT           = <<OUT>>
  TRANSCRIPT    = <<TRANSCRIPT path, or "none">>
  TEMPLATE      = <<skill dir>>/template.md
  UPLOAD_SCRIPT = <<skill dir>>/notion-upload-images.sh
  NOTION_PARENT = <<parent page URL/ID, or "DISABLED">>

1. Git signals — run in ROOT, capture output:
   - git log --since=midnight --pretty='%h %s' --no-merges
   - git status --short
   - git diff --stat HEAD~5..HEAD   (or HEAD if fewer than 5 commits)

2. Session digest — if TRANSCRIPT is not "none", extract today's conversation
   with the self-contained command below (substitute TRANSCRIPT and DATE). It
   depends only on python3 — no bundled file. Run it EXACTLY, python lines flush
   to the left margin:

python3 - "TRANSCRIPT" "DATE" <<'PY'
import sys, json
from datetime import datetime
path, date = sys.argv[1], sys.argv[2]
out = []
try:
    fh = open(path)
except OSError as e:
    sys.exit("transcript open failed: %s" % e)
for line in fh:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue
    try:
        lo = datetime.fromisoformat((d.get("timestamp") or "").replace("Z", "+00:00")).astimezone()
    except ValueError:
        continue
    if lo.strftime("%Y-%m-%d") != date:
        continue
    t = d.get("type")
    if t not in ("user", "assistant"):
        continue
    c = (d.get("message") or {}).get("content")
    if isinstance(c, str):
        xs = [c]
    elif isinstance(c, list):
        xs = [b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text"]
    else:
        xs = []
    tx = "\n".join(x for x in xs if x).strip()
    if not tx:
        continue
    if t == "user" and tx.lstrip().startswith("<"):
        continue
    if len(tx) > 1500:
        tx = tx[:1500] + " ...[truncated]"
    out.append("[%s %s]\n%s" % (lo.strftime("%H:%M"), t.upper(), tx))
print("\n\n".join(out) if out else "(no entries for %s)" % date)
PY

   - Distill the printed output into the session digest — terse and factual:
     tasks tackled, decisions made, problems diagnosed and their root causes,
     things learned, what is left open. No narrative. THIS IS THE PRIMARY
     SOURCE for the report.
   - FALLBACK: if python3 is unavailable or the command errors out, skip the
     transcript entirely, draft from the git signals only, and add one line to
     the report (under Findings or Next) noting "session digest unavailable
     this run — report based on git activity only".

3. Draft — read TEMPLATE, copy its structure verbatim, fill it, write to OUT
   (mkdir -p the parent dir first; overwrite if it exists):
   - Replace {{DATE}}, {{PROJECT}}, {{BRANCH}}.
   - Build sections from the session digest; git signals only corroborate. Do
     NOT omit real work just because it never reached a commit.
   - Every section carries a 🔬 Research track and a 🛠️ Engineering track, marked
     by the **🔬 Research** / **🛠️ Engineering** bold labels — keep both labels and
     classify each item. Research = hypotheses, experiment design, results and
     their interpretation, scientific conclusions, methodology calls. Engineering
     = code, infrastructure, tooling, configs, pipeline plumbing, build/deploy,
     bug fixes. An item with both facets is split — research facet under Research,
     engineering facet under Engineering, no whole-item duplication.
   - Formatting — each track is a BULLET LIST, never a paragraph. The
     **🔬 Research** / **🛠️ Engineering** label sits alone on its line; content
     follows as `-` bullets on the next lines. Never write `**🔬 Research** — ...`
     (label and text on one line). One bullet = one fact, <= ~15 words; four
     facts is four bullets, not one run-on bullet.
   - Numbers belong in tables, not prose. Any quantitative result or comparison
     across conditions (a metric at several settings, an ablation, a sweep) goes
     into the Experiments table as rows — never as numbers buried in a sentence.
     Findings then state the conclusion and may point at the table.
   - Terse: Experiments = "N/A" unless a run / eval / sweep clearly happened.
     Findings = conclusions, not a commit recap. Next = <= 3 bullets per track.
     Empty subsections → "None" / "N/A", never pad. Do not invent metrics,
     experiments, or blockers.
   - Figures — also collect today's analysis images: *.png / *.jpg / *.jpeg
     files shown as new ("??") or modified ("M") in git status that illustrate
     a result (usually under a figures/ dir). Cap at 6. Under "## 📊 Figures"
     list each as `- <path relative to ROOT> — <one-line caption>`; if none,
     that section is "None". The image files are uploaded to Notion in step 4.

4. Notion sync — skip entirely if NOTION_PARENT is "DISABLED". Otherwise:
   - Select the connector. Multiple Notion MCP connectors may be present (tool
     names like mcp__claude_ai_Notion__*, mcp__notion__*, mcp__notion-personal__*),
     each authorized for a DIFFERENT workspace. Enumerate every tool matching
     mcp__*notion*__notion-fetch, call each on NOTION_PARENT, and pick the
     connector whose fetch succeeds — use that connector's prefix for ALL notion-*
     calls below. If no Notion connector exists at all, skip and report "Notion:
     MCP unavailable". If connectors exist but none can fetch NOTION_PARENT, skip
     and report "Notion: NOTION_PARENT unreachable (wrong workspace)".
   - Child page title = "<DATE> — <PROJECT>" (e.g. "2026-05-20 — franka").
   - Child page content = the report body MINUS its leading "# Daily Report —"
     line (the Notion page title already carries the date). Pass markdown as-is;
     the hosted Notion MCP converts it to blocks server-side.
   - notion-search under NOTION_PARENT for a child page with that exact title:
     - EXISTS → notion-update-page on it, command "replace_content", new_str = body.
     - NONE → notion-create-pages with parent {"type":"page_id","page_id":NOTION_PARENT},
       properties {"title": <title>}, content = body. Then place it at the TOP:
       notion-update-page on NOTION_PARENT with command "insert_content",
       position {"type":"start"}, content '<page url="<new-child-url>"><title></page>'.
       (Inserting a <page> block with an existing child URL MOVES that child;
       position start puts the newest report first. Verified mechanism.)
   - On "object not found" / permission error: stop, report that NOTION_PARENT is
     not shared with the connector. Do not retry blindly.
   - Figures upload — after the page text is synced and you have the child page
     id, upload the files listed in the report's "## 📊 Figures" section to that
     page (the MCP cannot upload binaries — this uses the Notion REST API):
       source ~/.bashrc.local 2>/dev/null; bash UPLOAD_SCRIPT <child-page-id> <abs fig path> ...
     Pass the child page id (UUID) and ABSOLUTE figure paths. The script needs
     NOTION_TOKEN (a Notion internal-integration token) in the environment. If
     NOTION_TOKEN is unset it prints "NOTION_TOKEN not set" — then report
     "figures: NOTION_TOKEN not set". On any other non-zero exit, report
     "figures: upload failed: <script stderr>"; never fail the run over figures.
     Skip silently when the Figures section is "None".

5. Return ONE line: the saved OUT path + Notion status
   (synced / off / "MCP unavailable" / "failed: <reason>") + figures status
   (uploaded N / none / "NOTION_TOKEN not set" / "upload failed: <reason>").
```

## Notes

- Local report: `<git root>/.claude/daily-reports/YYYY-MM-DD.md`. The skill does
  not commit it; gitignore or track it as you prefer.
- Notion: `daily-report-notion.txt` (project-local) overrides `notion-page.txt`
  (global). Each report is a `<DATE> — <PROJECT>` child page; the newest is moved
  to the top of the parent so the parent reads newest-first.
- Re-running on the same day overwrites the local file and replaces the existing
  Notion child page — it refreshes, it does not duplicate.
- Notion sync is best-effort: a failed sync never blocks the local report.
- Figures: the "## 📊 Figures" section lists today's analysis images. The image
  files are uploaded to the Notion page via the REST API (notion-upload-images.sh),
  which needs NOTION_TOKEN — a Notion internal-integration token — exported in
  ~/.bashrc.local. Without it, figures are listed in the report text but not
  uploaded to Notion.
- The session digest is sourced from the on-disk transcript (not live context),
  which is what lets the whole job run in the background. It captures the session
  up to dispatch time.
