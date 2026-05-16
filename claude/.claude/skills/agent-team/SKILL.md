---
name: agent-team
description: Run non-trivial implementation work as a two-phase agent team — investigator-planner produces PLAN.md and task decomposition, then per-task implementers + reviewer + smoke-tester spawn in parallel under auto mode and coordinate via SendMessage. Use whenever the user asks to "implement X", "build X", "add feature Y", "refactor X", "migrate X to Y", "リファクタして", "移行して", "agent team で進めて", "マルチエージェントで実装", "並列で実装", or "実装進めて". Size floor — only use when the task touches ≥3 files OR has ≥2 distinct phases (plan + execute). For one- or two-file edits, just do it inline.
---

# Agent team implementation

The user's standard workflow for non-trivial implementation. **Two phases, one team, no bare Agent calls.**

## Hard rules (these are the failure modes — must hold every time)

1. **Every `Agent` call MUST carry `team_name`.** A bare `Agent({...})` without `team_name` is wrong — those agents can't coordinate via SendMessage. If you notice a bare Agent call mid-spawn, abort that tool block and respawn inside the team.
2. **All agents — planner AND executors — run with `mode: "auto"`.** If `mode: "auto"` is rejected by the tool, STOP and ask the user — do not silently fall back to default mode.
3. **All executors spawn in one assistant turn's tool-use block.** Multiple `Agent` calls inside the same message. Splitting across turns loses parallelism and breaks the reviewer's streaming behavior.
4. **Default flow is Phase 1 → Phase 2 in the same turn, no user gate.** The two-phase split exists for division of labor and context isolation (the planner doesn't pollute the implementers' context, and one planner can fan out to N parallel implementers), NOT for human approval. After the planner returns, immediately spawn the executors in the next tool block of the same turn. **Only stop for user approval if the user explicitly asked for plan review** ("先にプラン見せて", "show me the plan first", etc.) — otherwise drive straight through.

## Phase 1 — plan

Pick a short slug for the team (e.g. `auth-rewrite`, `yubi-phase4`). Then:

1. `TeamCreate({ name: "<slug>" })`
2. Spawn the planner. Use the **Planner prompt template** below verbatim, substituting `<slug>` and `<request>`. Note `subagent_type: "general-purpose"` (NOT `"Plan"` — the Plan subagent type lacks Write/Edit and cannot create PLAN.md cleanly):
   ```
   Agent({
     team_name: "<slug>",
     name: "investigator-planner",
     subagent_type: "general-purpose",
     mode: "auto",
     description: "Investigate and decompose <task>",
     prompt: <Planner prompt template, filled in>
   })
   ```

### Planner prompt template

```
You are investigator-planner on team <slug>.

User request (verbatim): <request>

Deliverable:
1. Investigate the codebase (Read, Grep, Glob).
2. **External research (only if needed)**: if the task involves
   unfamiliar libraries, new APIs, RFCs, framework conventions, or
   protocol details that aren't already in the codebase, do targeted
   WebSearch + WebFetch. Cap at ~5 sources total. Distill, don't enumerate.
   Skip entirely for purely internal refactors.
3. **If external research happened**, write
   ~/.claude/teams/<slug>/references.md:
   - One section per source. Each section:
     - `## <topic>` heading
     - Source URL on the first line
     - 2-5 line distilled takeaway (the part the implementer needs —
       not the article's full argument)
     - "Used by: Task <N>, Task <M>"
   - Omit the file entirely if no external research was needed.
4. Write ~/.claude/teams/<slug>/PLAN.md with these sections:
   - Contract: what we ship, what we explicitly do NOT.
   - Locked decisions: APIs, file paths, naming, conventions to follow.
   - Tasks: numbered. For each task — owner role name (task-specific like
     `script-dev`, `launch-bringup`, NOT generic `implementer-1`), files
     touched (exact paths), the change in 2-4 lines, validation command.
     If a task depends on references.md, add a line:
     `References: references.md → <section heading(s)>`.
5. TaskCreate one entry per task. Task N description must match Task N in PLAN.md.
6. Return: team slug, task count, list of role names, whether
   references.md was created, open questions (if any).

Do NOT implement. Do NOT spawn other agents. Read-only investigation
(WebSearch/WebFetch + Read/Grep/Glob + the file writes for PLAN.md
and references.md).
```

After the planner returns:
- **By default, proceed directly to Phase 2 in the same turn** (next tool block). The phase split is for context isolation and parallelism, not gating.
- Briefly note the team slug and task count in user-facing text so the user can intercept if something looks wrong, but do NOT wait for confirmation.
- **Exception**: if the user explicitly asked for plan review ("先にプラン見せて", "show the plan first"), surface the planner summary and end the turn. Amendments → `SendMessage({ to: "investigator-planner", summary: "<one-line>", message: "<amendments>" })`. Do not start a new planner agent.

## Phase 2 — execute (parallel, auto mode)

Once the user approves the plan, spawn **all executors in one message** (one tool block, multiple Agent calls), each with `team_name: "<slug>"` and `mode: "auto"`:

| Role | Count | `subagent_type` | Notes |
|---|---|---|---|
| Per-task implementer (named from PLAN.md, e.g. `script-dev`) | one per task | `general-purpose` | Needs Edit + Bash |
| `reviewer` | 1 | `general-purpose` | Read-only by prompt; needs Bash for `git diff` |
| `smoke-tester` | 1 | `general-purpose` | Needs Bash for build/test commands |

### Streaming reviewer — what it means

The reviewer keeps its task open and reacts to SendMessage from each implementer as they finish. **Not a flag** — it is enforced by the prompt: the reviewer does NOT call `TaskUpdate completed` until it has reviewed every implementer's diff via SendMessage. See the role-specific tail below.

### Common executor prompt skeleton

Append the role-specific tail (below) verbatim after this skeleton. Substitute `<role>` with the role name and `N` with the task ID assigned to that role in PLAN.md.

```
You are `<role>` on team <slug>.

1. Read ~/.claude/teams/<slug>/PLAN.md (the locked contract). If your task's
   plan entry has a `References: references.md → ...` line, also read those
   sections of ~/.claude/teams/<slug>/references.md.
2. TaskList → you own Task N. TaskGet N. TaskUpdate in_progress.
3. Do the scoped work for Task N.
4. Run the validation command from the plan. TaskUpdate completed.

Constraints:
- Edit ONLY <files listed in the plan for this task>.
- DO NOT touch other files. DO NOT commit. DO NOT push.
- Cross-cutting issue → SendMessage to team-lead (or the affected role).
  Do NOT silently expand scope.
```

### Role-specific tails

**reviewer** — replaces step 4 of the skeleton:
```
4. Streaming behavior: keep this task IN PROGRESS until every implementer
   has reported done. As each implementer sends you their diff (or you
   notice their task moved to completed), `git diff <their files>`,
   cross-check vs PLAN.md, SendMessage findings back to that role +
   team-lead. Do NOT edit files. Mark your own task completed only after
   the last implementer's review pass.
```

**smoke-tester** — replaces step 4 of the skeleton:
```
4. After all implementers report Task completed (poll TaskList until
   all impl tasks are done), run the full validation chain from PLAN.md
   (build / py_compile / launch / tests). Report pass/fail per check.
   Do NOT fix failures — SendMessage the responsible role.
```

## After completion

Before deleting the team, shut down members cleanly:

1. For each non-lead member: `SendMessage({ to: "<name>", summary: "shutdown", message: { type: "shutdown_request" } })`. Wait for shutdown_response from each.
2. `TeamDelete({ name: "<slug>" })`. (Fails if members are still active — that's why step 1 exists.)

If follow-up work is expected, skip both and leave the team. PLAN.md stays in `~/.claude/teams/<slug>/` either way — useful input for `/daily-report`.

## Additional anti-patterns (not already in hard rules)

| Slip | Why wrong |
|---|---|
| Planner with `subagent_type: "Plan"` | Plan agent lacks Write/Edit; cannot create PLAN.md cleanly. Use `general-purpose`. |
| Stopping for user approval between Phase 1 and Phase 2 by default | The phase split is for context isolation / parallelism, not gating. Drive through unless the user asked for review. |
| One-shot Agent that "plans and implements" | Same — no gate. |
| Generic role names (`implementer-1`, `worker-a`) | Use task-specific (`script-dev`, `launch-bringup`) — easier to SendMessage, easier to read in logs. |
| Re-spawning the planner for amendments | Use SendMessage to the existing one — preserves context. |
| `TaskUpdate completed` on reviewer before all impl reviews done | Defeats streaming review — implementer drift goes uncaught. |
| `TeamDelete` without shutting members down first | Fails; teammates orphan. |
