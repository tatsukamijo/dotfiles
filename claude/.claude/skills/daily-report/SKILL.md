---
name: daily-report
description: Generate a readable research daily report for the current project, shaped like a good progress report to an advisor (big picture → recap of last time → results with evidence and videos → in progress → what to discuss → next action as options with a proposal; bookkeeping in a collapsed appendix). Runs almost entirely in a background agent — the foreground only resolves paths and the Notion target, then a background worker reads today's session transcripts + git activity, drafts the report to <project>/.claude/daily-reports/YYYY-MM-DD.md, and (if configured) syncs it as a dated child page placed at the TOP of a Notion parent page, with result videos and figures attached under the results they support. Use when the user says "今日の日報書いて", "daily report", "今日のまとめ", or asks to summarize today's work in this project.
---

# Daily Report

One readable research daily report for the current project. The whole job
runs in a **single background agent**: `/daily-report` resolves a few paths in
the foreground, fires the worker, and returns immediately. You are notified when
the report is saved locally and synced to Notion.

The report is written the way a good progress report is given to an advisor:
it descends the abstraction ladder (big picture first, details last), states
done / in progress / to do, isolates at most three things to discuss with the
materials for each, and ends with the next action as options plus one proposal.
Bookkeeping (run roster, hypotheses, decisions, carry-over) lives in a collapsed
appendix. **Main body at most 700 words. No journey narrative.**

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

If the project's reports live somewhere other than `ROOT` (an earlier report
dir exists elsewhere, or `ROOT` is `$HOME` because the session was started
outside the project), use the directory that already holds
`.claude/daily-reports/` as ROOT.

**REPOS** — the git roots the project's code lives in, resolved here because
the worker cannot see the conversation: `git -C "$ROOT" rev-parse
--show-toplevel` if it succeeds, plus the root of every repository this
session edited code in (you know where the day's code went; the worker only
sees transcripts). Pass them space-separated, or `none`. BRANCH is the
branch of each (`repo:branch` when there are several). If the session runs past midnight at the end
of a workday, date the report to the workday and tell the worker to digest both
dates (see the DATE RANGE NOTE slot in the worker prompt).

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
  BRANCH        = <<current git branch; "repo:branch" per repo when there are several>>
  REPOS         = <<git roots holding the project's code, space-separated; "none" if there is no repo>>
  DATE          = <<DATE>>            (local date, YYYY-MM-DD)
  OUT           = <<OUT>>
  TRANSCRIPT_DIR = <<TRANSCRIPT_DIR>>  (dir holding this project's session *.jsonl)
  TEMPLATE      = <<skill dir>>/template.md
  UPLOAD_SCRIPT = <<skill dir>>/notion-upload-images.sh
  VIDEO_SCRIPT  = <<skill dir>>/notion-upload-videos.sh
  NOTION_PARENT = <<parent page URL/ID, or "DISABLED">>
  DATE RANGE NOTE = <<"none", or: "digest DATE and <next date> and treat them as one day">>

Who reads this: the project's advisor and the author, next morning, in two
minutes. The reader must be able to stop after any section and still hold the
most important things. Write for that reader, not for completeness.

1. Git signals — for each repo in REPOS, capture output. END is the day
   after DATE, or the day after the second date named in DATE RANGE NOTE.
   REPOS = "none" → skip and write "no git signals (no repository)" under
   Engineering changes. If the digest shows code going to a repo not in
   REPOS (a module path like `dexicl/...` with its directory), add it after
   `git -C <dir> rev-parse --show-toplevel` succeeds.
   - git log --since="DATE 00:00" --until="END 00:00" --pretty='%h %s' --no-merges
   - git status --short
   - n=$(git rev-list --count HEAD); k=$(( n > 5 ? 5 : n - 1 )); [ "$k" -ge 1 ] && git diff --stat HEAD~$k..HEAD
   - git diff --stat HEAD            (uncommitted work)

2. Session digest — extract today's conversation across ALL of this project's
   sessions with the self-contained command below (substitute TRANSCRIPT_DIR
   and DATE). It reads every *.jsonl in TRANSCRIPT_DIR, keeps entries dated
   DATE, de-dups by message uuid, and merges them in timestamp order — a day
   split over several Claude Code sessions becomes one chronological digest. It
   depends only on python3 — no bundled file. Run it EXACTLY, python lines
   flush to the left margin. Redirect the output to a file and read that file
   in chunks (a full day is large); if DATE RANGE NOTE names a second date, run
   it once per date and read both, first date first. Long entries are kept
   head and tail with a `...[truncated N chars]...` marker (4000 chars for
   assistant text, 1500 for user text); when an entry you need is cut
   mid-conclusion, re-run the command with a larger cap as a third argument
   (e.g. `20000`) and read that entry — never guess a truncated judgment or
   number:

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
        cap = int(sys.argv[3]) if len(sys.argv) > 3 else (4000 if t == "assistant" else 1500)
        if tx.startswith("This session is being continued"):   # compaction summary: the densest record of a day, never cut
            cap = 10 ** 9
        if len(tx) > cap:
            h = int(cap * 0.7)
            tx = tx[:h] + " ...[truncated %d chars]... " % (len(tx) - cap) + tx[-(cap - h):]
        rows.append((lo, t, tx))
    fh.close()
rows.sort(key=lambda r: r[0])
out = ["[%s %s]\n%s" % (lo.strftime("%H:%M"), t.upper(), tx) for lo, t, tx in rows]
print("\n\n".join(out) if out else "(no entries for %s)" % date)
PY

   - Scope: the report covers work on PROJECT only — ROOT, REPOS and their
     outputs. The transcript dir is shared by every session started from the
     same directory, so the digest can contain work on other repositories or
     tools: exclude it (at most one Engineering-changes line when it served
     this project). With a DATE RANGE NOTE, the second date counts only while
     the project's work continues: stop at the first gap of three hours or
     more, or at a switch to another project.
   - Distill the printed output into a working digest for yourself: results
     with their numbers, decisions, problems and their root causes, what the
     user asked for and pushed back on, what is left open. Corroborate every
     number you will print against the run's own result files when the digest
     names them (result*.json, logs); the transcript is the primary source, the
     files are the check. Precedence when sources disagree: the run's summary
     result file > its per-episode result files > step/call logs > the
     transcript; print the winning value, name the source only when sources
     disagree, and mark a differing transcript value "stale, from the
     session" in the roster. When two sources store different
     representations (cumulative vs per-episode counts), print one, say
     which, and never print a number that appears in neither. A number that
     exists only in the transcript is marked "from the session" in the
     roster. Anything the previous report does not cover is in scope for
     this report regardless of its date.
     Entries from different sessions are interleaved by wall-clock time —
     treat the day as one continuous record.
   - FALLBACK: if python3 is unavailable or the command errors out, skip the
     transcript entirely, draft from the git signals only, and add one line to
     the report (under In progress) noting "session digest unavailable this
     run — report based on git activity only".

3. Draft — read TEMPLATE, copy its section order and headings verbatim, fill
   it, write to OUT (mkdir -p the parent dir first; overwrite if it exists).
   The template's HTML comment is a guide: do not copy it into OUT.

   Previous report — find the most recent file in $ROOT/.claude/daily-reports/
   matching *.md whose date is strictly older than DATE (ignore today's own OUT
   on a re-run). Read it whole: its Big picture, its Next action, its Appendix
   (Hypotheses Active + Archived, Carry-over). Older reports may use a legacy
   layout (sections "Findings", "Yesterday's Next", "Reproducibility",
   top-level "Hypotheses" tables, Research/Engineering tracks): read the same
   information from wherever it sits — Next action from "Next", Carry-over
   from "Yesterday's Next", Hypotheses from any "Hypotheses" table. A section
   the previous report lacks (a legacy report has no Big picture; its
   "Objective" is not one) is treated as a first run for that section:
   derive it and mark it "(derived today — confirm)". None → first run:
   Since last time = "No previous report." and the carry-over / hypotheses
   sections start empty.

   Threads — read `$ROOT/.claude/daily-report-threads.txt` if it exists. One
   `#tag-name — short description` per line (blank lines and lines starting
   with `#` ignored). Use these tags in the Hypotheses `thread` column. If the
   day's work clearly belongs to a thread not in the file, append one line;
   never overwrite existing lines.

   Fill the sections in this order of thought (coarse to fine):

   a. 🗺️ Big picture — two or three one-line bullets, and nothing else:
      "Problem → key idea" (this project tries to solve <problem> with <key
      idea>), "What 'it works' looks like" (the result that would show the idea
      is effective: the simplest solved case, described qualitatively —
      "door opened, hot dog lifted"; thresholds live in the roster), and
      optionally "Why this way". Copy it from the previous report unless the
      day changed it; if changed, say so in one clause. No previous report →
      derive it from the digest and the project's own docs (README, CLAUDE.md,
      docs/) and end the first bullet with "(derived today — confirm)". This
      section is the top of the ladder: no run names, no numbers.

   b. 🔁 Since last time — at most three one-line bullets: where the previous
      report ended (its TL;DR or last result), what it planned (its Next action
      proposal), and what happened to that plan today (done / partial /
      dropped, in a few words). Pivot rule: when the day's work left the
      previous report's research line for another, say so here in one clause
      ("dropped; the day went to <new line>"), rewrite Big picture for the new
      line marked "(derived today — confirm)", and give the old line's carried
      items the reason `deprioritized for <new line>` (on a pivot this reason
      overrides any per-item reason). No previous report →
      the single line "No previous report."

   c. 🎯 TL;DR — write it LAST, but it sits on the header line: ONE sentence,
      at most 35 words, giving the day's verdict: the single most important
      result and whether the plan is on track. Not a list of everything.
      Quiet day → "**🎯 TL;DR** — quiet day; no runs or commits."

   d. ✅ Results — what was learned today, as at most FIVE claims, most
      important first. A claim is one line stating the takeaway (never a
      category name: "Retrieval opened the door every episode; without it only
      once", not "Retrieval results"), beginning with a confidence tag in plain
      brackets: [confirmed] (reproduced, ≥2 independent runs, or strong
      multi-metric evidence), [preliminary] (single run / not reproduced), or
      [refuted-prior] (overturns an earlier report's claim or hypothesis —
      takes precedence). Under it, at most THREE evidence sub-bullets (2-space
      indent), each ≤ 15 words naming run · condition · number; a comparison
      across conditions goes in one sub-bullet (`with 17 / 13 / 10 calls, without
      37 / 43 / 8`). A pre-registered pass/fail bar (set BEFORE the result was
      seen) is stated with the result and whether it cleared; never invent one.
      Name runs by what they are — agent, mode, task, condition — never by
      internal ids or bare tags ("Astra, tool-call mode, microwave-open with
      experience", not "astra_mwopen"). Engineering work is a Result only when
      it IS the day's finding (a bug that invalidated earlier numbers, a
      measured speedup); otherwise it belongs in the appendix.
      Videos and figures go directly under the claim they support (rules below).
      A hypothesis whose status flips today MUST have its claim here.

   e. 🔄 In progress — at most THREE bullets: an idea being tested or about to
      be, each on one line as `<idea> — plan: <how it will be validated> — so
      far: <quick result, or "no data yet">`. An idea without a plan to
      validate it is not listed. Nothing in progress → "None."

   f. 🙋 Want to discuss — at most THREE questions, most important first, each
      a bold one-line question followed by three sub-bullets: `tried:` (what
      was done), `data:` (what the numbers or videos say), `candidates:`
      (candidate answers or options). These are the things the author is
      stuck on or needs a decision on; a stale carried item (see Carry-over,
      carry × 3 or more) is raised here as "commit or drop?". Nothing to
      discuss → "None today."

   g. ⏭️ Next action — the most important section. TWO or THREE options for
      what to do by the next report, each one line: `**Option k — <name>**:
      <what> — pros: <…> — cons: <…>`, then ONE `**Proposal**:` line that
      picks an option with its reason and names the condition under which
      another option becomes better. It is a proposal to the advisor, not a
      to-do list; every `[~]` / `[ ]` carry-over item must be covered by one
      of the options or explicitly dropped in the proposal.

   h. 📎 Appendix — the bookkeeping, complete and terse:
      - 📌 Runs: ONE bullet per run, sweep, eval or diagnostic whose results
        first appear in this report (an overnight run analysed today belongs
        here, marked "ran <date>, analysed today"; a diagnostic is anything
        that produced a number the report cites — pass/fail plumbing checks
        are grouped in one bullet or go under Engineering changes) — the
        complete roster, including runs that produced no headline claim —
        `<run label> — <agent · mode · task · condition> · seed · commit · out
        <path> · <outcome in a few words>`; omit fields that do not apply. The
        run label is what the Results claims call that run. Fields identical
        across all runs (commit, harness version, output root) may be stated
        once in a lead line under the heading instead of per bullet. No runs
        → "None".
      - 🛠️ Engineering changes: one bullet per theme (≤ 7): what changed and
        why, in plain words; uncommitted work counts. None → "None".
      - 🧠 Hypotheses — Active / Archived: tables with columns hypothesis ·
        thread · status · evidence. status ∈ open / supported / refuted;
        evidence cites the run or claim and ENDS in `(YYYY-MM-DD)`, the date
        the status was last touched. Carry over every still-relevant row from
        the previous report's Active and Archived tables, update status + date
        where today bears on it, add rows raised today. A row raised today
        takes its status from the Results claim that backs it: a [confirmed]
        claim → `supported` (or `refuted` for a negative result), a
        [preliminary] claim → `open`, with the evidence cell opening with the
        direction so far ("negative so far: …" / "favourable so far: …"); a
        row may be raised and resolved in the same report. Archival: a row whose
        status is not `open`, whose date is ≥ 3 days older than DATE and which
        was not touched today moves to Archived ("touched" = new evidence or
        a status change recorded today; restating old numbers does not reset
        the date). Every status flip of a
        CARRIED row since the previous report must have a matching Results
        claim ([confirmed] for open→supported, [refuted-prior] for any flip to
        or from refuted); [refuted-prior] is reserved for rows or claims that
        existed in an earlier report. Check this before writing the tables. No active rows → "N/A"; no
        archived rows → omit the Archived heading and table.
        Pipe sanitization (critical): never put a vertical bar inside a table
        cell — rewrite `|err|` as `abs(err)`, `||x||` as `‖x‖`, `A | B` as
        `A / B`; `\|` is unsafe (it double-escapes on the way to Notion and
        breaks the row). Scan every cell before writing the file.
      - 🧭 Decisions: a table decision · alternatives · rationale; only real
        decisions — a path taken over a NAMED alternative. None → "N/A".
      - 🔄 Carry-over: one checklist line per item of the previous report's
        Next action (its options and proposal; legacy layout: its Next list):
        `[x]` done (where closed), `[~]` partial (a sub-step of the item was
        executed; say what remains), `[ ]` not touched (evidence that merely
        informs the item keeps `[ ]` and its counter, noted in parentheses).
        The item list is the deduplicated union of the previous
        report's Next action and its Carry-over, matched by content (a legacy
        report may list an item in both); the counter is read from the
        Carry-over entry. Carry-counting is a counter per item. First time
        `[ ]` (the item was in the previous Next action but not in its
        Carry-over): `- [ ] run the seed sweep — not started` (no counter;
        that is carry × 1). Already `[ ]` in the previous Carry-over:
        `- [ ] run the seed sweep (carry × 2 — deprioritized for the pivot)`
        where K+1 continues the previous `(carry × K)` and a bare previous
        entry counts as K = 1; reason is one of `blocked on <X>`,
        `deprioritized for <Y>`, `still-relevant, no progress`. All items at
        carry × 3 or more are raised together as ONE Want-to-discuss
        question, "commit or drop?", listing them. No previous report → "N/A".

   Word budget (measured with `wc -w`, so every whitespace-separated token
   counts: "—", "·", "0/3", "**Option", a heading word; think in tokens):
   - Main body = everything above `## 📎 Appendix`, counted WITHOUT media
     lines: delete every `📹 [...]` and `![...]` line, then `wc -w` the rest.
     Limit 700 tokens. Media lines never count and are never dropped to make
     the budget.
   - Per-section token budgets, which sum to 650 and leave 50 for the title,
     project line, rule and headings — write to these from the start, and
     to the per-line caps, which are what make the budgets reachable:
     TL;DR 35 · Big picture 55 (≤ 25 per bullet) · Since last time 40 (≤ 15
     per bullet) · Results 240 (claim line ≤ 20; evidence sub-bullet ≤ 14;
     two evidence sub-bullets per claim by default, a third only when it
     changes the conclusion) · In progress 45 (≤ 22 per item) · Want to
     discuss 115 (question ≤ 12; each sub-bullet ≤ 10; the "commit or drop?"
     list line is exempt) · Next action 120 (option line ≤ 30 with pros and
     cons ≤ 8 each; proposal ≤ 25). Every cap is measured exactly like the
     budget: `wc -w` on the whole line, dash, tag and scaffolding included —
     `- [preliminary] Retrieval opened the door every episode; without it only once`
     is 11 tokens.
   - The 700 total is the only hard stop. Section budgets are soft: a
     section within 10 % of its budget is fine when the total is under 700.
     Measure, then cut: after the draft, `wc -w` each section (media lines
     removed). While the TOTAL is over 700, take the section furthest over
     its budget, FIRST enforce its per-line caps (rewrite long lines), THEN
     its structural cuts: Results — drop third evidence sub-bullets, then the
     least important claim (keep ≥ 3); Want to discuss — merge the two least
     important questions; Next action — drop a third option; In progress —
     drop the least important item. Never cut a claim below one evidence
     line, never remove a media line, never cut structure a section's
     Proposal depends on. Re-measure the whole body once more before writing
     OUT.

   Hard limits:
   - Results ≤ 5 claims; ≤ 3 evidence sub-bullets per claim; In progress ≤ 3;
     Want to discuss ≤ 3; Next action = 2–3 options + 1 proposal.
   - The bold track labels `**🔬 Research**` / `**🛠️ Engineering**` of the old
     layout must not appear (the heading "🛠️ Engineering changes" is fine).
   - No internal ids in prose or captions. An internal id is a label that
     means something only inside the project's bookkeeping: run tags
     (astra_mwopen), clip ids (P1), config or job names, and labels coined
     during the session (rung names, "Option A"); describe what they are
     instead. A name is allowed in prose when the previous report's prose or
     an advisor-facing page already uses it (a model name like FT-A). Ids
     inside file paths are fine: the roster's `out <path>` and the paths of
     media lines keep them. The appendix keeps reproducibility facts —
     commits, Slurm job ids, node names, seeds, paths — and table cells
     carried verbatim from an earlier report are exempt (do not rewrite
     history); rows written today follow the rule.
   - Numbers appear only in evidence sub-bullets, In-progress `so far:`
     results, Want-to-discuss `data:` lines, the one headline number of the
     TL;DR, and the appendix. Not "numbers" for this rule: dates ("Last
     report (2026-10-18)"), option numbers, carry counters, and setup counts
     that describe a plan ("two more seed sets", "3 episodes"). Big picture
     has none at all.
   - Do not invent metrics, runs, blockers or targets.

   Figures — images MADE to illustrate a finding (a plot, a strip of frames, a
   before/after or side-by-side) that support a claim. Per-step observation
   dumps, camera snapshots and tool outputs are not figures. Source them from
   the digest (a plotting script that wrote a file, a path named in the
   conversation) and from the run output directories named in the roster,
   not from `git status` (figure dirs are usually gitignored). Resolve each to an ABSOLUTE path and confirm it exists;
   VIEW each image (read the file) to learn what it actually depicts and
   caption it from the image itself — never caption a figure as something it
   does not show. Cap at 4; figure lines never count toward the word budget
   and are never dropped to make it. Placement — on its own line directly
   below the claim's last evidence sub-bullet, as a Markdown image line:
     ![<CAPTION>](<absolute image path>)
   <CAPTION> states what to CONCLUDE from the figure with its key number, not
   what it depicts. No figures → skip.

   Videos — a result video is evidence like a figure, and a reader who reviews
   behaviour from videos must find them next to the result, not in a folder.
   Unit: the deliverable video of a run — the rollout or replay the author
   would show for it (rollout*.mp4, ego*.mp4, a side-by-side) — one line per
   output directory that holds one (a roster bullet covering several
   condition directories gets one line per directory), plus every .mp4 /
   .webm path named in the digest. Not deliverables: per-step or per-frame
   dumps, open-loop prediction clips, and the parts of a compilation (a
   compilation supersedes its parts; name the parts in the roster if useful).
   Every deliverable video gets a line; there is no cap, and video lines
   never count toward the word budget. Precedence: a video the author named,
   sent or asked for in the transcript is a deliverable whatever the
   structural rule says; with nested compilations, the level the author
   chose wins (everything below it is parts, everything above it is
   superseded). A compilation line replaces the lines of exactly the
   directories it draws from; every other directory keeps its line. A
   directory holding many per-seed rollouts gets ONE line pointing at the
   newest file with the aggregate outcome and the count ("6 seeds, 1
   success"); a probe with more than six condition directories gets one
   aggregated line with per-condition outcomes in the roster text. Media
   that belong to no run of this report (retrieved human clips, data
   visualisations, side-by-sides cut today from earlier runs) go under one
   fixed roster bullet, "Media cut today from earlier runs / data — <source>",
   with captions naming what they show. The caption's outcome comes from the
   run's result files or the transcript, never from viewing the video; when
   neither states one, write "outcome not assessed". Resolve the file per directory: prefer `rollout_small.mp4`,
   else `rollout.mp4`, else the newest *.mp4 up to three levels below the
   run's `out` directory (e.g. `k0_s1_*/`, `seed*/`); confirm it exists on
   disk and is under 100 MB; drop any that is not and say so in the roster.
   Placement — below the Results claim that cites that run, after its
   evidence sub-bullets and any figure, at most TWO video lines per claim
   (the two most informative; the rest go under the run's Runs bullet); a run
   no claim cites goes below its own Runs bullet in the appendix. Syntax (a
   link line with a leading camera emoji, so the sync step can recognise it;
   it renders as a clickable link locally):
     📹 [<CAPTION>](<absolute video path>)
   <CAPTION> says in plain words who ran (agent / model and mode), on what
   task and condition, and the outcome with its key number, e.g. "Astra,
   tool-call mode, microwave-open with retrieved experience: door opened in
   all 3 episodes (17 / 13 / 10 calls)". No videos → skip.

   Blank lines — leave a blank line before every heading and between the
   last line of a section and the next heading; a bold line that directly
   follows a bullet is merged into that bullet by Notion.

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
     at the MCP resource `notion://docs/enhanced-markdown-spec`. Use TAB
     characters for every indentation level in the Notion copy (Notion ignores
     space indentation: space-indented children fall out of their parent).
     Apply in order:
     a. Drop the leading "# Daily Report —" line — the page title carries the date.
     b. Remove every Markdown image line (trimmed text matching `![...](...)`)
        and every video line (trimmed text starting with `📹 [`): a local path
        is not a URL, so Notion renders a dead "Add an image" placeholder or a
        broken link. Figures and videos are re-added as real uploads in the
        steps below.
     c. Wrap the TL;DR line in a callout — indent the inner line one tab:
          <callout icon="🎯" color="gray_bg">
          	**TL;DR** — …
          </callout>
     d. Color the LEADING confidence tag of each Results claim, and ONLY the
        bracketed tag — never the claim text. Pure token substitution: wrap
        exactly the bracket token in a `<span color="...">` tag so the closing
        `</span>` sits immediately after the tag's closing `]`:
          `- [confirmed] <text>`     → `- <span color="green">[confirmed]</span> <text>`
          `- [refuted-prior] <text>` → `- <span color="orange">[refuted-prior]</span> <text>`
          `- [preliminary] <text>`   → `- <span color="gray">[preliminary]</span> <text>`
        The tag name is `span`. Notion does NOT recognise any other tag name
        for inline colour: NEVER write `<color ...>`, `<colour ...>`,
        `<font ...>`, `<text color=...>`, or `**[confirmed]**{color=green}` —
        those render as literal text. Do NOT extend the span past the `]` and
        do NOT put a block-level `{color=...}` on the bullet (both colour the
        whole line).
     e. Wrap the body of "## 🙋 Want to discuss" (everything under the heading
        up to the next heading) in `<callout icon="🙋" color="orange_bg"> …
        </callout>`, every wrapped line indented one extra tab (sub-bullets
        keep their relative nesting). The heading STAYS OUTSIDE the callout.
        "None today." → no callout. This and the TL;DR callout are the only
        callouts on the page; never wrap an individual Result in one. NEVER
        use GitHub admonition syntax (`> [!note]` etc.): Notion renders it as
        literal text in an "Empty quote" placeholder.
     f. Collapse the appendix: every `### …` heading under `## 📎 Appendix`
        becomes a toggle heading, `### 📌 Runs {toggle="true"}`, with every line
        under it indented one extra TAB so it nests inside the toggle (tables
        included). If the post-sync fetch shows `{toggle=` as literal text,
        replace each with the toggle block form instead:
          <details>
          <summary>📌 Runs</summary>
          	- run bullet ...
          </details>
        (children tab-indented). A subsection whose body is just "None" /
        "N/A" stays a plain heading.
     Pass the result as-is; the hosted Notion MCP converts it to blocks.
   - notion-search under NOTION_PARENT for a child page with that exact title:
     - EXISTS → notion-update-page on it, command "replace_content", new_str = body.
       Keep its page URL.
     - NONE → notion-create-pages with parent {"type":"page_id","page_id":NOTION_PARENT},
       properties {"title": <title>}, content = body. Keep the new page URL it returns.
   - Move to top — ALWAYS, in BOTH the EXISTS and NONE cases. notion-create-pages
     appends a new page at the BOTTOM of the parent, so without this step a new
     report silently lands last; doing it on the EXISTS path too self-heals an
     earlier run whose move failed. notion-fetch NOTION_PARENT, find the line
     `<page url="<child-url>">...</page>` for the child in its content, then run
     ONE notion-update-page on NOTION_PARENT with command "update_content" and
     two content_updates: (1) delete that exact <page> line where it is, (2)
     insert the same <page> line before the first block of the parent body.
     Moving the existing tag re-orders the child; it does not duplicate it.
     (The older path, "insert_content" with position {"type":"start"} and a
     <page> tag, is refused by the API since 2026-10 — do not use it.) Never
     remove a <page> tag without re-inserting it in the same call: a dropped
     <page> tag deletes that child page from the parent.
   - Verify the move — notion-fetch NOTION_PARENT and confirm the FIRST <page> in
     its content is the child you just synced. If it is not first, run the
     update_content move once more. If it is still not first after that retry,
     add "move-to-top failed" to the Return line. Do NOT skip this check — the
     move silently failing (new report stuck at the bottom) is a known bug.
   - Verify the body rendered cleanly — notion-fetch the CHILD page itself and
     scan its returned content for literal-text artefacts that mean a
     transform fell back to plain text instead of rendering as a Notion
     block. Reject any of these strings appearing in the fetched body:
       `<color`, `<colour`, `<font` — colour span used the wrong tag name (step d).
       `[!warning]`, `[!note]`, `[!caution]`, `Empty quote` — GitHub admonition
                      syntax leaked into the body (step e).
       `{color=`    — block-level colour attribute on a bullet (step d).
       `{toggle=`   — toggle heading rendered as literal text: children were not
                      tab-indented (step f); switch to the <details> form.
       `\\|`        — double-escaped pipe inside a table cell (the `\|` escape
                      got doubled). Fix at the source by rewriting the cell
                      without a vertical bar, NOT by re-escaping.
     If any appears, redo the transform on the body, replace_content again,
     and only return "synced" once the post-fetch scan is clean. Add
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
   - Videos upload — same mechanics for every `📹 [CAPTION](PATH)` line you
     stripped in step (b): the ANCHOR is the sub-bullet (or Runs bullet) on the
     line directly above it, 6-12 consecutive ASCII words copied verbatim. Then:
       source ~/.bashrc.local 2>/dev/null; bash VIDEO_SCRIPT '<child-page-id>' '<anchor>' '<PATH>' '<CAPTION>' ...
     Triples are (anchor, video, caption). The script uploads each video through
     Notion's file-upload API (files over 19 MB go through multi-part upload
     automatically) and nests a playable video block under the first block
     whose text contains the anchor; it prints "inserted ... (nested under ...)"
     on a hit and "anchor not found ... SKIPPED" on a miss, inserting nothing on
     a miss. Re-run only the missed ones with a corrected anchor. Never hand-
     place a video through the Notion MCP. NOTION_TOKEN unset → report "videos:
     NOTION_TOKEN not set"; any other failure → "videos: upload failed:
     <script stderr>"; never fail the run over videos. Skip when there are no
     videos.

5. Return ONE line: the saved OUT path + main-body token count + Notion status
   (synced / off / "MCP unavailable" / "failed: <reason>") + figures status
   (uploaded N / none in report / "N in report, not uploaded: Notion off" /
   "NOTION_TOKEN not set" / "upload failed: <reason>") + videos status (same
   vocabulary, plus "N anchor misses").
```

## Notes

- Local report: `<ROOT>/.claude/daily-reports/YYYY-MM-DD.md`. The skill does
  not commit it; gitignore or track it as you prefer.
- Shape: the report descends the abstraction ladder — big picture, recap of the
  last report, results with evidence, in progress, what to discuss, next action
  as options with one proposal — so a reader can stop anywhere and still have
  the most important things. The main body is capped at 700 words; everything
  else (run roster, engineering changes, hypotheses, decisions, carry-over) is
  an appendix, collapsed on the Notion page.
- Notion: `daily-report-notion.txt` (project-local) overrides `notion-page.txt`
  (global). Each report is a `<DATE> — <PROJECT>` child page; the newest is moved
  to the top of the parent so the parent reads newest-first.
- Re-running on the same day overwrites the local file and replaces the existing
  Notion child page — it refreshes, it does not duplicate. Replacing the page
  content drops previously attached figures and videos; the run re-attaches them.
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
- Videos: result videos (rollout mp4 of every run in the Runs roster) are
  written as `📹 [caption](path)` lines under the claim they support; step 4
  strips them from the Notion copy and re-adds each as a playable video block
  via notion-upload-videos.sh (same anchor contract as the image script; files
  over 19 MB use Notion's multi-part upload). Same NOTION_TOKEN requirement.
- Notion styling: the Notion copy is enriched in the sync step (step 4
  transforms c–f) — TL;DR callout, coloured confidence tags, an orange
  "Want to discuss" callout, collapsed appendix toggles. The local .md stays
  plain Markdown; the styling lives only on the Notion page.
- The session digest is sourced from on-disk transcripts (not live context),
  which is what lets the whole job run in the background. It reads every
  same-day session *.jsonl under TRANSCRIPT_DIR, up to dispatch time.
- Hypotheses are kept as two appendix tables — Active (current ledger) and
  Archived (resolved with status unchanged ≥3 days). The Archived table is
  built by the worker, not by hand; status flips re-promote a row to Active and
  must surface as a Results claim.
- Threads: `$ROOT/.claude/daily-report-threads.txt` is a one-line-per-thread
  registry the worker reads and may append to. Format
  `#thread-name — short description`. Threads classify the Hypotheses table.
- Reference for the shape: the lab's progress-report guide (進捗報告編) —
  state done / in progress / to do; for a discussion, prepare the premise, the
  desired outcome, the ideas with their validation plan, the 2–3 topics you are
  stuck on, and the next action as options with a recommended one; explain
  coarse-to-fine, opening with the big picture and a recap of last time.
