---
name: pueue-monitor
description: Set up event-driven pueue monitoring (Monitor tool + jq state poller) so background pueue jobs notify Claude only on state transitions. Use when the user runs long pueue chains (training, conversion, copy) and wants Claude to react only on failure/completion without burning tokens on idle polling. Also covers the two pueue+Claude foot-guns we hit (argv tokenization when wrapping commands in `bash -c` / `bash -lc`, and the `Done.result` JSON shape).
---

# pueue monitor skill

Monitor pueue state transitions event-driven so Claude wakes up only when something happens (job fails, completes, transitions).
The monitor is a 30-second `pueue status --json | jq` poller that runs in a Monitor task; only changes are emitted to stdout, so each Claude wake corresponds to a real state change.

## When to use

The user has long-running pueue chains (training, dataset conversion, large copies) and wants Claude to:
- React on failure/completion, not on every poll
- Not burn tokens checking "still Running" repeatedly

## Foot-gun 1 — argv tokenization (the `bash -c` trap)

The single most-repeated foot-gun: wrapping a `pueue add` command with
`bash -lc '<multi-arg>'` or `bash -c '<multi-arg>'`. The outer shell
strips the quotes **before** pueue ever sees them, so the "single
string" of shell code becomes a bunch of separate argv entries. pueue
joins them back with spaces and runs `sh -c '<joined>'`, but `bash -c`
(or `-lc`) inside that re-joined string only takes the first post-`-c`
token as the script — the rest become positional arguments. The actual
command never runs.

We've hit this repeatedly: `pueue add -- bash -lc pixi run …`,
`pueue add -- bash -c "cp -r SRC/. DST/ && echo done"`, etc. Each time
the job exits in ~0 s with cryptic output (rsync help, `cp: missing
file operand`, pixi help banner).

### The two valid patterns — never combine them

**(a) Direct command, no shell features needed** — use `pueue add --`:

```bash
pueue add -- cp -r /src/. /dst/
pueue add --after 0 --working-directory /repo -- pixi run train_phase1
```

pueue stores `cp -r /src/. /dst/` and runs it via `sh -c <stored>`. No
`bash` wrapper. Works for any plain `prog arg1 arg2 …`.

**(b) Need shell features (`&&`, pipes, redirects, env subst, `cd`)** —
use the single-string form (no `--`):

```bash
pueue add 'cp -r /src/. /dst/ && echo done'
pueue add --after 0 'cd /repo && pixi run pipeline | tee /tmp/log'
```

pueue stores the literal string and runs it via `sh -c '<string>'`. The
shell features are interpreted at execution time, not by the calling
shell.

### What never works

```bash
pueue add -- bash -c "cmd && other"      # outer quotes stripped → broken
pueue add -- bash -lc "pixi run …"       # same
```

If you genuinely need a multi-line bash script with login-shell
sourcing, write the script to a file and `pueue add -- bash
/abs/path/script.sh`. Don't inline it.

If wandb / env vars are needed: prefer file-based credentials
(`~/.netrc` is read by file, no env needed). Avoid `bash -lc` wrappers
unless absolutely necessary.

### Verification

After submitting, check the stored command:

```bash
pueue status --json | jq '.tasks["<id>"].command'
```

If you see your shell features rendered as bare tokens
(`"bash -c cp -r /src/. /dst/ && echo done"` with no quoting around the
script), you have hit this trap — remove the task and resubmit in form
(a) or (b).

## Foot-gun 2 — `Done.result` JSON shape varies

`pueue status --json` returns `.tasks[id].status` as a single-key object whose key is the state (`Queued`, `Running`, `Stashed`, `Paused`, `Done`).

For `Done`, the inner `.status.Done.result` is:
- a **string** for simple terminal states: `"Success"`, `"DependencyFailed"`, `"Killed"`
- an **object** for failures with exit code: `{"Failed": 1}`

A jq filter that does `(.status.Done.result | keys[0])` works on the object but throws on the strings → silently swallowed by `2>/dev/null` and the monitor never emits. Use `.status.Done.result` directly (it stringifies both cleanly).

## Standard monitor command

Save and adapt this. Set the watched-id list to match your queued chain.

```bash
prev=""
while true; do
  cur=$(pueue status --json 2>/dev/null | jq -r '
    [.tasks["0"], .tasks["1"], .tasks["2"], .tasks["3"], .tasks["4"]]
    | to_entries
    | map(
        (.key | tostring) as $id
        | if .value == null then "\($id)=?"
          else
            (.value.status | keys[0]) as $k
            | if $k == "Done" then "\($id)=Done:\(.value.status.Done.result)"
              else "\($id)=\($k)" end
          end
      )
    | join(",")
  ' 2>/dev/null)
  if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then
    echo "[$(date '+%H:%M:%S')] $cur"
    prev="$cur"
  fi
  sleep 30
done
```

Wire it via the `Monitor` tool with `persistent: true`, `timeout_ms: 3600000`, and a description like `"pueue id 0-4 state transitions (<pipeline name>)"`. Each emitted line is one notification.

## End-to-end recipe

Given a chain with deps `0 → 1 → 2 → 3`:

1. **Queue** with either form (a) `pueue add -- prog args` or (b)
   `pueue add 'shell command'` (use (b) only when you actually need
   `&&`, pipes, or env subst). Never mix with `bash -c` wrappers — see
   Foot-gun 1.
   ```bash
   pueue add -- rsync -a /src/ /dst/                                           # id 0 (form a)
   pueue add --after 0 --working-directory /repo -- pixi run convert           # id 1 (form a)
   pueue add --after 1 --working-directory /repo -- pixi run train_phase1      # id 2 (form a)
   pueue add --after 2 --working-directory /repo -- pixi run train_phase2      # id 3 (form a)
   # If a step needs shell features:
   # pueue add --after 3 'cd /repo && pixi run eval | tee /tmp/eval.log'       # id 4 (form b)
   ```
2. **Start the monitor** with the matching id list (see template above).
3. **Wait** — events arrive via `<task-notification>` only on state changes. Initial baseline emits once.
4. **On Failure / Killed / DependencyFailed**: read the log with `pueue log <id> --lines N`, identify root cause, fix, then `pueue restart --in-place <id> [<dependents>]` (preserves IDs and deps; resets failed/killed tasks to Queued).
5. **On full success**: stop the monitor with `TaskStop <task_id>`.

## Useful pueue verbs

| op | command |
|---|---|
| Queue with deps | `pueue add --after N --working-directory PATH 'CMD'` |
| Inspect failure | `pueue log <id> --lines 80` |
| Stored command shape | `pueue status --json \| jq '.tasks["N"].command'` |
| Reset failed/killed in place | `pueue restart --in-place <id> [<dep_ids>...]` |
| Kill a runaway run | `pueue kill <id>` (then `pueue restart --in-place <id>` if you want to retry) |
| Remove tasks (clears history) | `pueue remove <id...>` |

## Cost notes

- Inside the monitor: `pueue status --json | jq` runs every 30 s on the host — zero token cost.
- Each emitted stdout line = 1 wake = 1 small (often cached) round-trip to Claude.
- Persistent monitor with no transitions ≈ free.
- Rule of thumb: for an N-step chain that mostly runs cleanly, expect ~2N wakes (Running entry + Done emit per stage), each cheap.
