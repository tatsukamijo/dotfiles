---
name: daily-report
description: Generate a concise research-style daily report for the current project, written by a delegated agent. Output goes to `<project>/.claude/daily-reports/YYYY-MM-DD.md` using the bundled template. Use when the user says things like "今日の日報書いて", "daily report", "今日のまとめ", or asks for a summary of today's work in this project.
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

2. **Gather raw signals yourself** (cheap, keeps the subagent focused). Run these in parallel and capture output:
   - `git log --since=midnight --pretty='%h %s' --no-merges` — today's commits
   - `git log --since='1 day ago' --pretty='%h %s' --no-merges` — fallback if today is empty
   - `git status --short`
   - `git diff --stat HEAD~5..HEAD` (or `HEAD` if fewer than 5 commits)
   - `git rev-parse --abbrev-ref HEAD`
   - Project name = basename of `$ROOT`
   - List of yesterday's report if present (`ls .claude/daily-reports/ | tail -3`) — for continuity

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

   Yesterday's report (for continuity, optional): <<path or "none">>

   Rules:
   - Terse. Bullets ≤ 1 line. No journey narrative.
   - Fill Experiments only if commits/diff clearly involve a run, eval, or sweep. Otherwise "N/A".
   - Findings = conclusions or hypothesis updates, not a recap of commits.
   - Next = at most 3 bullets, concrete.
   - Read at most 3 changed files if needed to disambiguate a commit message.
   - Output only the saved path; do not echo the report back.
   ```

4. **Report the path** to the user (one line). Do not paste the report contents.

## Notes

- The report is for the **current project**, not a global log. Path is always `<git root>/.claude/daily-reports/`.
- If not in a git repo, fall back to `$(pwd)/.claude/daily-reports/` and tell the user.
- The user may pass extra context (e.g. "also include the perception eval results"). Forward it verbatim into the subagent prompt — don't summarize it away.
- Don't commit the report. The user can decide whether `.claude/daily-reports/` is gitignored or tracked.
