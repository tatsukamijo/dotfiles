---
name: daily-report
description: Generate a terse research-style daily report for the current project. Runs almost entirely in a background agent — the foreground only resolves paths and the Notion target, then a background worker reads today's session transcripts + git activity, drafts the report to <project>/.claude/daily-reports/YYYY-MM-DD.md, and (if configured) syncs it as a dated child page placed at the TOP of a Notion parent page. Use when the user says "今日の日報書いて", "daily report", "今日のまとめ", or asks to summarize today's work in this project.
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
SESSION_TX=$(find "$HOME/.claude/projects" -maxdepth 2 -name "${CLAUDE_CODE_SESSION_ID}.jsonl" 2>/dev/null | head -1)
TRANSCRIPT_DIR=$([ -n "$SESSION_TX" ] && dirname "$SESSION_TX" || echo "$HOME/.claude/projects/$(echo "$ROOT" | sed 's/[/.]/-/g')")
```
`CLAUDE_CODE_SESSION_ID` names the current session's transcript
(`<session-id>.jsonl`). Every Claude Code session for this project writes its
own `*.jsonl` into the SAME directory, so `TRANSCRIPT_DIR` — the parent of that
file — is the project's whole transcript dir, and the worker digests EVERY
same-day session in it, not just the one that ran `/daily-report`. If the
current session's file is not found, fall back to the conventional mangled
project dir (`$HOME/.claude/projects/` + `ROOT` with every `/` and `.` turned
to `-`). The worker handles a missing or empty dir by using git signals only.

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
  TRANSCRIPT_DIR = <<TRANSCRIPT_DIR>>  (dir holding this project's session *.jsonl)
  TEMPLATE      = <<skill dir>>/template.md
  UPLOAD_SCRIPT = <<skill dir>>/notion-upload-images.sh
  NOTION_PARENT = <<parent page URL/ID, or "DISABLED">>

1. Git signals — run in ROOT, capture output:
   - git log --since=midnight --pretty='%h %s' --no-merges
   - git status --short
   - git diff --stat HEAD~5..HEAD   (or HEAD if fewer than 5 commits)

2. Session digest — extract today's conversation across ALL of this project's
   sessions with the self-contained command below (substitute TRANSCRIPT_DIR
   and DATE). It reads every *.jsonl in TRANSCRIPT_DIR, keeps entries dated
   DATE, de-dups by message uuid, and merges them in timestamp order — a day
   split over several Claude Code sessions becomes one chronological digest. It
   depends only on python3 — no bundled file. Run it EXACTLY, python lines
   flush to the left margin:

python3 - "TRANSCRIPT_DIR" "DATE" <<'PY'
import sys, json, glob, os
from datetime import datetime
tdir, date = sys.argv[1], sys.argv[2]
seen, rows = set(), []
for path in sorted(glob.glob(os.path.join(tdir, "*.jsonl"))):
    try:
        if datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d") < date:
            continue
        fh = open(path)
    except OSError:
        continue
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
        uid = d.get("uuid")
        if uid in seen:
            continue
        if uid:
            seen.add(uid)
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
        rows.append((lo, t, tx))
    fh.close()
rows.sort(key=lambda r: r[0])
out = ["[%s %s]\n%s" % (lo.strftime("%H:%M"), t.upper(), tx) for lo, t, tx in rows]
print("\n\n".join(out) if out else "(no entries for %s)" % date)
PY

   - Distill the printed output into the session digest — terse and factual:
     tasks tackled, decisions made, problems diagnosed and their root causes,
     things learned, what is left open. No narrative. Entries from different
     sessions are interleaved by wall-clock time — treat the day as one
     continuous record. THIS IS THE PRIMARY SOURCE for the report.
   - FALLBACK: if python3 is unavailable or the command errors out, skip the
     transcript entirely, draft from the git signals only, and add one line to
     the report (under Findings or Next) noting "session digest unavailable
     this run — report based on git activity only".

3. Draft — read TEMPLATE, copy its structure verbatim, fill it, write to OUT
   (mkdir -p the parent dir first; overwrite if it exists):
   - Previous report — find the most recent file in $ROOT/.claude/daily-reports/
     matching *.md whose date is strictly older than DATE (ignore today's own
     OUT file on a re-run). If one exists, read its `## ⏭️ Next` section, its
     `## 🔄 Yesterday's Next` checklist, its `## 🧠 Hypotheses — Active` table,
     and its `## 🧠 Hypotheses — Archived` table (older reports may still use
     the legacy single `## 🧠 Hypotheses` heading — treat that as Active). This
     single read feeds the Yesterday's Next reconciliation, the carry-counting,
     and the Hypotheses carry-over below. None → first run, skip them all (their
     sections become `N/A`).
   - Threads — read `$ROOT/.claude/daily-report-threads.txt` if it exists. One
     `#tag-name — short description` per line (blank lines and lines starting
     with `#` ignored). Each tag names a research thread the project sustains
     across days. The worker uses these tags as the `thread` column in
     Hypotheses, and MAY suffix Findings / Issues / Next top-level bullets with
     a single matching tag for longitudinal scanning. Missing or empty file →
     no enforcement, but if today's work clearly clusters into 2-4 distinct
     threads, propose tags and append them to the file (one per line, never
     overwrite existing lines). A hypothesis raised today whose thread is not
     yet in the file → either reuse the closest existing tag or append a new
     line; never leave a contradiction between table cells and the file.
   - Replace {{DATE}}, {{PROJECT}}, {{BRANCH}}.
   - Build sections from the session digest; git signals only corroborate. Do
     NOT omit real work just because it never reached a commit.
   - Five sections carry a 🔬 Research track and a 🛠️ Engineering track — Objective,
     Progress, Findings, Issues / Blockers, Next — marked by the
     **🔬 Research** / **🛠️ Engineering** bold labels; keep both labels and classify
     each item. The other four sections (Hypotheses, Decisions, Yesterday's Next,
     Reproducibility) are single tables / checklists / lists — no R/E split, no
     track labels. Research = hypotheses, experiment design, results and
     their interpretation, scientific conclusions, methodology calls. Engineering
     = code, infrastructure, tooling, configs, pipeline plumbing, build/deploy,
     bug fixes. An item with both facets is split — research facet under Research,
     engineering facet under Engineering, no whole-item duplication.
   - Formatting — each track is a TWO-LEVEL bullet list, never a paragraph and
     never a flat wall of bullets. The **🔬 Research** / **🛠️ Engineering** label
     sits alone on its line. Under it, each top-level `-` bullet STATES THE
     TOPIC'S CONCLUSION — the takeaway in one terse phrase, NOT a bare category
     label. The supporting facts hang off it as 2-space-indented sub-bullets:
       **🔬 Research**
       - ph2 dynamics-MLP fine-tune gives no measurable gain over plain-BC ph1
         - tie on every metric — success rate, duration, fidelity
         - dyn-loss + reg + smoothness gave no benefit on this forgiving task
       - Sub-linear speedup is arm-tracking-limited, not PV-capped
         - speedup sub-linear — 2.36x at 150 Hz vs ideal 3x
         - realized peak only ~38% of the PV cap
     Write the conclusion, not the category: "Sub-linear speedup is
     arm-tracking-limited, not PV-capped", never "Speedup bottleneck". One
     sub-bullet = one fact, <= ~15 words. A topic whose conclusion needs no
     elaboration is one top-level bullet with no sub-bullet. Never put content
     on the label line (no `**🔬 Research** — ...`).
     Thread tag (optional) — every top-level conclusion bullet in Findings /
     Issues / Blockers / Next MAY end with a single `#thread-name` suffix
     matching the project's threads file (see Threads above). Sub-bullets do
     NOT carry tags. Confidence tag stays leading, thread stays trailing:
       `- [confirmed] Hybrid beats either single-distribution model. #excite-data`
     Skip the suffix when no thread tag clearly applies; do not invent one
     per bullet.
   - Numbers belong in Findings sub-bullets, not buried in prose. Every
     quantitative result — a metric, an ablation point, a sweep setting — is a
     terse sub-bullet under the conclusion it supports, naming the run and the
     condition; the top-level bullet is the conclusion, the sub-bullets are its
     evidence. A comparison across conditions goes under ONE conclusion: inline
     in a sub-bullet when short (`real 0.098 / shuffled 0.107 / no-dt 0.112`),
     one sub-bullet per condition when not.
   - Pre-registered targets — if a run had a pass/fail bar fixed BEFORE its
     result was seen (success-rate floor, val-loss ceiling, p-value, speedup
     goal), its supporting sub-bullet states the result AND whether it cleared
     that bar — e.g. "dyn_rmse stayed flat over 2000 steps — target was a drop
     → fail". Never invent a bar that was not actually pre-registered; a run
     with no prior bar simply reports its result.
   - Findings confidence markers — every Findings top-level (conclusion) bullet,
     both tracks, BEGINS with a plain-bracket tag (no backticks), right after
     the `- ` (e.g. `- [refuted-prior] The v6 model does use dt.`): `[confirmed]`
     (reproduced, ≥2 independent runs, or strong multi-metric evidence),
     `[preliminary]` (n=1 / single observation / not yet reproduced), or
     `[refuted-prior]` (overturns a conclusion or hypothesis from an earlier
     report). Precedence: if it overturns a past claim use `[refuted-prior]`,
     else pick `[confirmed]` / `[preliminary]` by evidence strength. Sub-bullets
     are never tagged.
   - Hypotheses ledger — split into TWO tables, BOTH with columns
     hypothesis · thread · status · evidence:
       `## 🧠 Hypotheses — Active`
       `## 🧠 Hypotheses — Archived`
     `status` ∈ `open` / `supported` / `refuted`; `thread` is one of the
     project's thread tags (see Threads above) or blank if unclassified;
     `evidence` cites the run / finding and ENDS in `(YYYY-MM-DD)` — the date
     status was last touched (initial entry, status flip, or fresh supporting
     evidence). The trailing date acts as last-updated.
     Carry over every still-relevant row from the previous report's Active AND
     Archived tables (legacy single `## 🧠 Hypotheses` heading also counts as
     Active), update status + date where today's work bears on it, and add
     rows for hypotheses raised today.
     Archival rule — at write time, any row whose status is NOT `open` AND
     whose evidence date is ≥3 days older than DATE AND was not touched today
     moves to the Archived table. Archived rows stay one read away but no
     longer clutter the active scan. Do NOT re-promote an archived row unless
     today's work flips its status — in which case it reappears in Active with
     today's date and the corresponding Finding (see flip-coupling below).
     Flip-coupling — every status flip between consecutive reports (in either
     direction: `open`→`supported`, `open`→`refuted`, `supported`→`refuted`,
     `refuted`→`supported`, `archived`→back-to-active via re-flip) MUST surface
     as a Findings conclusion bullet citing the run that caused it:
       · `open`→`supported`         → `[confirmed]` Finding
       · `open`→`refuted`           → `[refuted-prior]` Finding
       · `supported`→`refuted`      → `[refuted-prior]` Finding
       · `refuted`→`supported`      → `[refuted-prior]` Finding (the earlier
                                       refutation is itself being overturned)
       · `supported`→`supported`    → no flip, no required Finding (status
                                       unchanged; only update the date if new
                                       evidence was added)
     Before emitting the ledger, diff today's status vector against the
     previous report's and assert every diff row has a matching Findings
     bullet — if any flip is missing, draft the Finding first then return to
     the ledger.
     Empty cases — no active hypotheses → Active table = `N/A`; no archived
     hypotheses → omit the Archived heading and table entirely.
     Pipe sanitization (CRITICAL) — math notation with vertical bars is the
     #1 row-breaking offender (e.g. `|err|`, `|∂Δq/∂a|`, `||x||_F`,
     absolute-value bars, OR-bars `X | Y`). The escape `\|` is not a safe
     bet: the Markdown→Notion conversion has been observed to double-escape
     it to `\\|`, which Notion then re-parses as `\\` followed by an
     unescaped `|`, breaking the row. This has corrupted 3 of the last 4
     reports.
     Strict rule inside TABLE CELLS only (Hypotheses + Decisions; prose
     outside tables is unaffected): rewrite vertical-bar notation in prose
     or with Unicode norm bars, do NOT rely on `\|`:
       `|err|`         → `abs(err)` / `err magnitude` / Unicode `‖err‖` if
                          you really mean the norm
       `|∂Δq/∂a|`     → `Frobenius norm of ∂Δq/∂a` / `‖∂Δq/∂a‖`
       `||x||_F`      → `‖x‖_F`
       `X | Y`         → `X / Y` or `X or Y`
     After drafting both tables, scan every cell between column-separator
     pipes; any remaining un-escaped `|` is a bug, rewrite the cell.
   - Decisions — the `## 🧭 Decisions` table (columns decision · alternatives ·
     rationale). Log only real decisions: a path taken over a *named*
     alternative. Routine actions are not decisions. None → `N/A`.
   - Yesterday's Next — reconcile the previous report's `## ⏭️ Next` (from the
     previous-report read) into the `## 🔄 Yesterday's Next` checklist, one line
     per prior Next item: `[x]` done (note where it closed), `[~]` partial (note
     what remains), `[ ]` carried over. Every `[~]` / `[ ]` item must also appear
     in today's `## ⏭️ Next` so nothing is silently dropped.
     Carry-counting — for every `[ ]` (still pending) item, look up the SAME
     item in the previous report's `## 🔄 Yesterday's Next` (the checklist, not
     the Next section). If that entry already carries a `(carry × K)`
     annotation, today is `(carry × K+1 — <reason>)`. If it was a bare `[ ]`
     yesterday with no annotation, today is `(carry × 2 — <reason>)`. If the
     item was `[x]` or `[~]` or did not exist in yesterday's checklist, the
     counter starts fresh — no annotation required today (it is `carry × 1`).
     `<reason>` is mandatory and is one short clause from:
       `blocked on <X>` — depends on an external/upstream event named X.
       `deprioritized for <Y>` — explicitly traded against Y, which IS being
         worked on.
       `still-relevant, no progress` — neither blocked nor traded, just not
         touched. Honest signal that this item is drifting.
     Stale escalation — any `[ ]` item whose carry count reaches K+1 ≥ 3 MUST
     also be written into today's `## 🚧 Issues / Blockers` (under the matching
     track) as a top-level bullet, so a long-stale Next item can no longer
     silently roll forward. The bullet text restates the item plus its
     `(carry × N — <reason>)` annotation; if the reason is
     `still-relevant, no progress`, flag it as `(carry × N — drifting, decide
     to commit or drop)` to force the human to take a stance next session.
     No previous report → `N/A`.
   - Reproducibility roster — the `## 📌 Reproducibility` section collects one
     compact bullet per run, sweep, eval or diagnostic executed today. It is the
     COMPLETE run roster: a run that produced numbers but no headline Finding is
     still recorded here, never silently dropped.
       - <run label> — commit `<sha>` · ckpt `<path>` · seed `<n>` · ds `<version>` · pueue `<id>`
     `<run label>` is the name that run is referred to by in Findings. Omit any
     field that does not apply. No runs → `None`.
   - TL;DR — write it LAST, after every section is drafted: a one-line abstract
     (may wrap to two, never longer) distilled from Findings — the single most
     important result plus the current state — on the `**TL;DR** — …` header
     line. Quiet day → `**TL;DR** — quiet day; no runs or commits.`
   - Terse: Findings = conclusions with their evidence numbers, not a commit
     recap. Next = <= 3 topics per track. Hypotheses / Decisions empty → `N/A`;
     Yesterday's Next with no prior report → `N/A`; Reproducibility with no runs
     → `None`. Empty subsections → "None" / "N/A", never pad. Do not invent
     metrics, runs, or blockers.
   - Figures — collect the day's analysis images (*.png / *.jpg / *.jpeg) that
     illustrate a result. Source them from the SESSION DIGEST — figures the
     day's work generated or saved (a plotting script that wrote a file, a path
     named in the conversation). Do NOT rely on `git status`: analysis figure
     dirs (e.g. `figures/`) are routinely gitignored, so an untracked-files
     scan misses them. Resolve each to an ABSOLUTE path and confirm the file
     exists on disk before using it; drop any that do not. VIEW each image
     (read the file — it is viewable) to learn what it actually depicts: place
     it under the finding it depicts and caption it from the image itself,
     never from the finding's text alone — never caption a figure as something
     it does not show. Cap at 6. Each figure goes next to the result it
     supports — like a figure in a paper,
     never a figures section and never an end-of-page dump.
     Placement — on its own line, directly below the Findings / Progress
     SUB-BULLET it illustrates, write a Markdown image line:
       ![<CAPTION>](<absolute image path>)
     <CAPTION> states what to CONCLUDE from the figure, not what it depicts —
     the takeaway with the key number. Not "DTW distance, ph1 vs ph2 across
     frequencies" but "DTW: no ph1/ph2 trajectory difference at any frequency
     (p >= 0.08)". The image path MUST be absolute. These lines render in a
     local Markdown viewer; step 4 strips them from the Notion copy and re-adds
     each as a proper nested upload. If there are no figures, skip this.

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
   - Child page content = the report body, transformed for Notion. The body
     itself (the local .md) stays plain Markdown — these transforms apply ONLY
     to the copy sent to Notion. It is Notion-flavored Markdown; full syntax is
     at the MCP resource `notion://docs/enhanced-markdown-spec`. Apply in order:
     a. Drop the leading "# Daily Report —" line — the page title carries the date.
     b. Remove every Markdown image line (trimmed text matching `![...](...)`):
        a local path is not a URL, so Notion renders a dead "Add an image"
        placeholder. Figures are re-added as real uploads in the step below.
     c. Wrap the TL;DR line in a callout — indent the inner line one tab:
          <callout icon="🎯" color="gray_bg">
            **TL;DR** — …
          </callout>
        This is the ONLY callout used to highlight a result — never wrap an
        individual Finding in a callout.
     d. Color the LEADING confidence tag of each Findings conclusion bullet, and
        ONLY the bracketed tag — never the bullet text. Pure token substitution:
        wrap exactly the bracket token in a `<span color="...">` tag so the
        closing `</span>` sits immediately after the tag's closing `]`,
        leaving the rest of the line outside the span:
          `- [confirmed] <text>`     → `- <span color="green">[confirmed]</span> <text>`
          `- [refuted-prior] <text>` → `- <span color="orange">[refuted-prior]</span> <text>`
          `- [preliminary] <text>`   → `- <span color="gray">[preliminary]</span> <text>`
        The tag name is `span`. Notion does NOT recognise any other tag
        name for inline colour. NEVER write `<color color="...">`,
        `<colour ...>`, `<font color="...">`, `<text color="...">`, or
        wrap in markdown emphasis like `**[confirmed]**{color=green}` —
        Notion will render those as literal text instead of colouring the
        tag, and the page will show the angle-bracket syntax directly
        instead of a coloured pill. The ONLY accepted opening tag is
        `<span color="green">` / `<span color="orange">` / `<span color="gray">`
        (or any other valid Notion colour name — see
        notion://docs/enhanced-markdown-spec).
        Do NOT extend the span past the `]`; do NOT put a block-level
        `{color=...}` attribute on the bullet — either of those colors the whole
        line. Leave the same word alone where it recurs mid-sentence.
     e. If Reproducibility has run bullets, make it collapsible: its heading
        becomes `## 📌 Reproducibility {toggle="true"}` and every bullet under it
        is indented one extra tab so it nests in the toggle. Just "None" → leave
        the heading plain.
     f. If the Issues / Blockers section has real content (not "None"), wrap its
        whole body — the **🔬 Research** / **🛠️ Engineering** labels and their
        bullets — in `<callout icon="🚧" color="red_bg"> … </callout>`, every
        wrapped line indented one extra tab (sub-bullets keep their relative
        nesting). Empty section → no callout. The Issues / Blockers heading
        STAYS OUTSIDE the callout (same pattern as TL;DR).

        Worked example. Given the local markdown:
          ## 🚧 Issues / Blockers

          **🔬 Research**
          - excite_v2 halted at 31/48 tasks
            - mount wobbles at 100 Hz
          **🛠️ Engineering**
          - meshcat blank page not diagnosed

        The transformed Notion body is:
          ## 🚧 Issues / Blockers

          <callout icon="🚧" color="red_bg">
            **🔬 Research**
            - excite_v2 halted at 31/48 tasks
              - mount wobbles at 100 Hz
            **🛠️ Engineering**
            - meshcat blank page not diagnosed
          </callout>

        NEVER use GitHub admonition syntax (`> [!warning]`, `> [!note]`,
        `> [!caution]`, etc.) — Notion renders those as literal text
        inside a blockquote, and the body shows up as "Empty quote"
        placeholder blocks. The ONLY callout syntax Notion accepts is
        the `<callout>` XML tag shown in step (c) and (f).
     Pass the result as-is; the hosted Notion MCP converts it to blocks.
   - notion-search under NOTION_PARENT for a child page with that exact title:
     - EXISTS → notion-update-page on it, command "replace_content", new_str = body.
       Keep its page URL.
     - NONE → notion-create-pages with parent {"type":"page_id","page_id":NOTION_PARENT},
       properties {"title": <title>}, content = body. Keep the new page URL it returns.
   - Move to top — ALWAYS, in BOTH the EXISTS and NONE cases. notion-create-pages
     appends a new page at the BOTTOM of the parent, so without this step a new
     report silently lands last; doing it on the EXISTS path too self-heals an
     earlier run whose move failed. Run notion-update-page on NOTION_PARENT,
     command "insert_content", position {"type":"start"}, content
     '<page url="<child-url>"><title></page>'. Inserting a <page> block with an
     EXISTING child URL MOVES that child to the start — it does not duplicate.
   - Verify the move — notion-fetch NOTION_PARENT and confirm the FIRST <page> in
     its content is the child you just synced. If it is not first, run the
     insert_content move once more. If it is still not first after that retry,
     add "move-to-top failed" to the Return line. Do NOT skip this check — the
     move silently failing (new report stuck at the bottom) is a known bug.
   - Verify the body rendered cleanly — notion-fetch the CHILD page itself and
     scan its returned content for literal-text artefacts that mean a
     transform fell back to plain text instead of rendering as a Notion
     block. Reject any of these strings appearing in the fetched body —
     each one is the smoking gun of a specific past bug:
       `<color`     — colour span used the wrong tag name (step d). Must be `<span color="...">`.
       `<colour`    — same.
       `<font`      — same.
       `[!warning]` — GitHub admonition syntax leaked into the body (step f). Must be `<callout icon="🚧" color="red_bg"> ... </callout>`.
       `[!note]`    — same.
       `[!caution]` — same.
       `Empty quote` — symptom of GitHub admonition being parsed as blockquote.
       `{color=`    — block-level colour attribute on a bullet (step d).
       `\\|`        — double-escaped pipe inside a Hypotheses/Decisions cell
                      (the `\|` escape got doubled during conversion). Means
                      one or more rows split into phantom columns. Fix at the
                      source by rewriting `|...|` notation as prose / Unicode
                      `‖...‖` per the table-cell rule, NOT by re-escaping.
     If any of these strings appears, the transform produced bad text:
     redo the transform on the body, replace_content again, and only
     return "synced" once the post-fetch scan is clean. Add
     "render-verify retried Nx" to the Return line if you had to retry.
   - On "object not found" / permission error: stop, report that NOTION_PARENT is
     not shared with the connector. Do not retry blindly.
   - Figures upload — after the page text is synced and you have the child page
     id, re-add each Markdown image line you stripped above, next to the bullet
     it sat under (the MCP cannot upload binaries — this uses the Notion REST
     API). For each stripped `![CAPTION](PATH)` line, the ANCHOR is the
     sub-bullet on the line directly above it: copy 6-12 consecutive words from
     that sub-bullet verbatim, ASCII only — skip any word carrying a backtick or
     a non-ASCII symbol (` τ Δ ∂ ⊙ → ² ≈ ×) so the anchor survives the
     Markdown→Notion conversion. Then:
       source ~/.bashrc.local 2>/dev/null; bash UPLOAD_SCRIPT '<child-page-id>' '<anchor>' '<PATH>' '<CAPTION>' ...
     Args after the page id are (anchor, image, caption) triples, one per figure
     — quote each, they contain spaces. The script uploads each image and nests
     it as an image block UNDER the first block whose text contains the anchor;
     it prints "nested under ..." on a hit. On an anchor miss it SKIPS that
     figure — inserts NOTHING, no page-end dump — and prints "anchor not found
     ... SKIPPED". A miss means the anchor was wrong: re-run the script for ONLY
     the missed figures with a corrected anchor (a cleaner ASCII phrase from the
     same sub-bullet); since the miss inserted nothing, the re-run leaves no
     stray or duplicate. Never hand-place a missed figure through the Notion MCP
     — that is what leaves `attachment:` text artifacts on the page. If a figure
     still misses after a corrected anchor, leave it out and say so in the
     Return line ("figures: N anchor misses"). NOTION_TOKEN (a Notion
     internal-integration token) must be in the environment. If it is unset the
     script prints "NOTION_TOKEN not set" — then report "figures: NOTION_TOKEN
     not set". On any other non-zero exit report "figures: upload failed:
     <script stderr>"; never fail the run over figures. Skip when there are no
     figures.

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
- Figures: the worker writes each figure as a Markdown image line in the body
  (which renders in a local viewer); step 4 strips those lines from the Notion
  copy — a local path would otherwise become a dead "Add an image" placeholder —
  and re-adds each as a child image block via the REST API
  (notion-upload-images.sh, since the MCP cannot upload binaries), nested under
  the bullet it supports so the figure sits indented beneath its discussion, no
  end-of-page dump. It needs NOTION_TOKEN — a Notion internal-integration
  token — exported in ~/.bashrc.local. Without it the report syncs as text
  only; figures are skipped.
- Notion styling: the Notion copy is enriched in the sync step (step 4 transforms
  c–f) — TL;DR as a callout, colored Findings confidence tags, a collapsible
  Reproducibility toggle, a red Issues / Blockers callout. The local .md stays
  plain Markdown; the styling lives only on the Notion page.
- The session digest is sourced from on-disk transcripts (not live context),
  which is what lets the whole job run in the background. It reads every
  same-day session *.jsonl under TRANSCRIPT_DIR, up to dispatch time.
- Hypotheses are kept as two tables — Active (current ledger, scanned daily)
  and Archived (resolved with status unchanged ≥3 days, kept one read away).
  The Archived table is built by the worker, not by hand; status flips
  re-promote a row to Active automatically.
- Threads: `$ROOT/.claude/daily-report-threads.txt` is a one-line-per-thread
  registry the worker reads and may append to. Format
  `#thread-name — short description`. Threads are how multi-day research
  arcs become scannable longitudinally — Hypotheses carry a `thread` column,
  and Findings / Issues / Next bullets may end with the same `#tag` suffix.
