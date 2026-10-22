# Daily Report — {{DATE}}

**{{PROJECT}}**  ·  `{{BRANCH}}`

**🎯 TL;DR** — one sentence: the day's verdict (the single most important result, and whether the plan is on track).

---

<!-- Writing guide (the worker prompt in SKILL.md is the authority; this is the shape):
     ・Coarse-to-fine, like descending a ladder: big picture → recap → results → in progress →
       what to discuss → next action. A reader who stops after any section still has the
       most important things above it. Never open with a detail.
     ・Main body = everything above "## 📎 Appendix": at most 700 tokens by `wc -w`, counted
       without the 📹 / ![] media lines (they never count and are never dropped). The per-section
       and per-line budgets are in SKILL.md's "Word budget" (the single source of truth). The
       appendix holds the bookkeeping (run roster, hypotheses, decisions, carry-over) and is
       collapsed in Notion.
     ・Results: ≤ 5 claims. Each claim = one line with the takeaway (not a category name),
       a leading [confirmed]/[preliminary]/[refuted-prior] tag, then ≤ 3 evidence sub-bullets
       (run · condition · number, ≤ 15 words each), then its video / figure line.
     ・Want to discuss: ≤ 3 questions, most important first, each with the materials (what was
       tried, what the data says, candidate answers) so the discussion can start immediately.
     ・Next action: 2–3 options, each with pros and cons, then ONE proposal with its reason —
       phrased as a proposal to the advisor, not a to-do list.
     ・Plain language. Name runs by what they are (agent, mode, task, condition), never by
       internal ids or bare tags. Numbers live in evidence sub-bullets and the roster only.
     ・No Research / Engineering split. Engineering work goes to the appendix unless it is
       the day's result. -->

## 🗺️ Big picture

- **Problem → key idea**: this project tries to solve <problem> with <key idea>.
- **What "it works" looks like**: <the result that would show the idea is effective — the simplest solved case>.
- **Why this way** (optional): <why the obvious alternative is not enough>.

## 🔁 Since last time

- Last report (<date>) ended with: <one line>.
- Planned then: <one line> → what happened: <done / partial / dropped, one line>.

## ✅ Results

- [confirmed | preliminary | refuted-prior] <claim: the takeaway in one phrase>
  - <evidence: run · condition · number>
  - <evidence>
  📹 [<what to conclude from the video>](<absolute video path>)
  ![<what to conclude from the figure>](<absolute image path>)

## 🔄 In progress

- <idea being tested> — plan: <how it will be validated> — so far: <quick result, or "no data yet">

## 🙋 Want to discuss

- **<question, one line>**
  - tried: <what was tried>
  - data: <what the data says>
  - candidates: <candidate answers / options>

## ⏭️ Next action

- **Option 1 — <name>**: <what> — pros: <…> — cons: <…>
- **Option 2 — <name>**: <what> — pros: <…> — cons: <…>
- **Proposal**: start with option <k> because <reason>; option <j> if <condition>.

## 📎 Appendix

### 📌 Runs

- <run label> — <agent · mode · task · condition> · seed `<n>` · commit `<sha>` · out `<path>` · <outcome>

### 🛠️ Engineering changes

- <what changed and why> (one bullet per theme)

### 🧠 Hypotheses — Active

| hypothesis | thread | status | evidence |
|---|---|---|---|
| hypothesis | #thread-tag | open / supported / refuted | run/finding (YYYY-MM-DD last touched) |

### 🧠 Hypotheses — Archived

| hypothesis | thread | status | evidence |
|---|---|---|---|
| resolved hypothesis | #thread-tag | supported / refuted | run/finding (YYYY-MM-DD last touched) |

### 🧭 Decisions

| decision | alternatives | rationale |
|---|---|---|
|  |  |  |

### 🔄 Carry-over

- [x] prior Next item — done (where closed)
- [~] prior Next item — partial (what remains)
- [ ] prior Next item — carried (carry × N — reason)
