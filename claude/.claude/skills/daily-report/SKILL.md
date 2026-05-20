---
name: daily-report
description: Generate a concise research-style daily report for the current project, written by a delegated agent. Output goes to `<project>/.claude/daily-reports/YYYY-MM-DD.md` using the bundled template, and (if configured) is also created as a dated child page under a Notion parent page via the Notion MCP. Use when the user says things like "今日の日報書いて", "daily report", "今日のまとめ", or asks for a summary of today's work in this project.
---

# Daily Report

Write a **research-style** daily report for today's work in the current project. A subagent does the actual drafting; the orchestrator only sets up paths and dispatches.

The report is **terse**: bullets, tables, conclusions. **No journey narrative** ("then I tried X, then Y…"). State what was done and what was learned.

## Steps

1. **Resolve paths.**
   ```sh
   ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
   DATE=$(date +%Y-%m-%d)
   OUT="$ROOT/.claude/daily-reports/$DATE.md"
   mkdir -p "$ROOT/.claude/daily-reports"
   ```
   If `$OUT` already exists, ask the user whether to **overwrite** or **append a new section** (with a `## Update HH:MM` header). Default to overwrite if they don't answer.

2. **Gather raw signals yourself** (cheap, keeps the subagent focused). Run the git commands in parallel and capture output:
   - `git log --since=midnight --pretty='%h %s' --no-merges` — today's commits
   - `git log --since='1 day ago' --pretty='%h %s' --no-merges` — fallback if today is empty
   - `git status --short`
   - `git diff --stat HEAD~5..HEAD` (or `HEAD` if fewer than 5 commits)
   - `git rev-parse --abbrev-ref HEAD`
   - Project name = basename of `$ROOT`
   - List of yesterday's report if present (`ls .claude/daily-reports/ | tail -3`) — for continuity

   Then compose the **session digest** — usually the richest signal, and you write it directly (no command):
   - From **your own conversation context for this session**, list — terse and factual — what was actually worked on: tasks tackled, decisions made, problems diagnosed and their root causes, things learned, what's left open.
   - git routinely undersells a day: uncommitted edits, design decisions, debugging dead-ends, and reasoning never reach a commit message. The session digest is what closes that gap.
   - If this session's context was compacted, work from the compaction summary — do not guess at lost detail.
   - No narrative ("then I…"). Just the facts, one line each.

3. **Delegate the drafting to a subagent.** Use the `Agent` tool with `subagent_type: general-purpose`. Pass the gathered signals **inline** in the prompt so the subagent doesn't re-run git commands. Tell it to:
   - Read the template at the absolute path of `template.md` next to this SKILL.md.
   - Write the filled report to `$OUT` (give the absolute path).
   - Replace `{{DATE}}`, `{{PROJECT}}`, `{{BRANCH}}` placeholders.
   - Fill each section using ONLY the signals provided + a brief look at the most-changed files if needed for context (cap at 3 file reads).
   - Keep it terse: bullets ≤ 1 line each, prefer tables for experiments, no preamble, no closing summary.
   - Drop sections that have no content by writing `None` or `N/A` rather than padding.
   - Do NOT invent experiments, metrics, or blockers that aren't in the signals or asked about.
   - Return only the saved path.

   Example prompt skeleton (fill in the `<<...>>` slots before sending):
   ```
   Draft today's research-style daily report and save it to <<OUT>>.

   Template (read first, copy structure verbatim, then fill):
     <<absolute path to template.md>>

   Project: <<PROJECT>>
   Branch:  <<BRANCH>>
   Date:    <<DATE>>

   Today's commits:
   <<git log output>>

   Working tree:
   <<git status output>>

   Recent diff stat:
   <<git diff --stat output>>

   Session digest — what was actually worked on today (PRIMARY source):
   <<session digest>>

   Yesterday's report (for continuity, optional): <<path or "none">>

   Rules:
   - Terse. Bullets ≤ 1 line. No journey narrative.
   - The session digest is the primary source; git signals corroborate it. Do NOT
     omit real work just because it never reached a commit.
   - Fill Experiments only if the signals clearly involve a run, eval, or sweep. Otherwise "N/A".
   - Findings = conclusions or hypothesis updates, not a recap of commits.
   - Next = at most 3 bullets, concrete.
   - Read at most 3 changed files if needed to disambiguate a commit or digest line.
   - Output only the saved path; do not echo the report back.
   ```

4. **Sync to Notion as a dated child page.** First resolve the **parent page** — check these sources in order, first decision wins:
   1. Project-local: `$ROOT/.claude/daily-report-notion.txt`
   2. Global: `notion-page.txt` next to this SKILL.md
   In each file the value is the first line that is not blank and not starting with `#`:
   - a real URL/ID → that is the parent page; proceed to sync.
   - `DISABLED` → Notion sync is intentionally off here; skip silently (no message needed).
   - `NOT_CONFIGURED`, or the file is missing → not set; fall through to the next source.
   If **neither file decides it** (both unset), **ask the user once**: "Notion parent page URL for this project? (paste a URL, or say `skip` to disable Notion sync for this project)".
   - URL given → strip any `?source=...` tracking query, write the clean URL to `$ROOT/.claude/daily-report-notion.txt`, then sync to it.
   - `skip` → write `DISABLED` to `$ROOT/.claude/daily-report-notion.txt` so this project is never asked again, and skip the sync.
   Once a parent page is resolved: confirm Notion MCP tools are available — tool names prefixed `mcp__claude_ai_Notion__` (the claude.ai-managed connector, normal case) or `mcp__notion__` (a manually-added server). If neither is present, tell the user to enable the Notion connector (claude.ai → Settings → Connectors, then `/mcp` to authenticate) and skip the sync this run.
   - **Child page title**: `<DATE> — <PROJECT>` (e.g. `2026-05-20 — dotfiles`). Date-led so pages sort chronologically; the project suffix avoids title collisions when several projects share one parent.
   - **Child page content**: the markdown body of `$OUT` **minus its leading `# Daily Report — DATE` line** — the Notion page title already carries the date and renders as the page heading, so do not duplicate it in the content. Pass the rest as-is; the hosted Notion MCP converts markdown to blocks server-side, do NOT pre-convert.
   - Check whether a child page with that exact title already exists under the parent (`notion-search` scoped to the parent via `page_url`):
     - **None** → create it: `notion-create-pages` with `parent: {"type":"page_id","page_id":<parent>}`, `properties: {"title":<title>}`, `content: <body>`.
     - **Exists** → reuse the overwrite/append decision from Step 1: overwrite → `notion-update-page` `command: "replace_content"`; append → `notion-update-page` `command: "insert_content"`, `position: {"type":"end"}`.
   - If a call fails with "object not found" (or similar permission error): the parent page is not accessible to the connector. Tell the user to re-run the Notion OAuth and grant access to the parent page. Do not retry blindly.

5. **Report** to the user (one line): the saved local path, plus Notion sync status (synced / off / failed-with-reason). Do not paste the report contents.

## Notes

- The local report is per-project (`<git root>/.claude/daily-reports/`). On Notion, the parent page is resolved per-project: `$ROOT/.claude/daily-report-notion.txt` (this project's own page) overrides the global `notion-page.txt` (shared aggregate). A project with no local file falls back to the global parent; reports there are still distinguished by the `— <PROJECT>` title suffix.
- If not in a git repo, fall back to `$(pwd)/.claude/daily-reports/` and tell the user.
- The user may pass extra context (e.g. "also include the perception eval results"). Forward it verbatim into the subagent prompt — don't summarize it away.
- Don't commit the report. The user can decide whether `.claude/daily-reports/` is gitignored or tracked.
- Notion sync is best-effort: a failed sync never blocks the local report. Report the failure and move on.
