#!/usr/bin/env bash
# git 'clean' filter for claude/.claude/settings.json.
#
# Claude Code rewrites the top-level `model` key of ~/.claude/settings.json every
# time you switch models via `/model` (it "saves it as your default"). That file
# is a symlink into this repo, so each switch would otherwise show up as a tracked
# diff. This filter strips just the `model` key on the way into git, so model
# switches never churn the repo while every other settings edit is tracked as
# normal.
#
# Wiring: `.gitattributes` maps the file to `filter=claudemodel`; install.sh runs
#   git config filter.claudemodel.clean <path-to-this-script>
# per clone (git config lives in .git/config, which is not itself tracked).
#
# jq normalizes formatting on both sides of every comparison, so formatting-only
# differences (e.g. Claude's writer vs jq's output) never register as a diff — only
# real content changes to non-model keys do. If jq is missing we pass the content
# through unmodified rather than break git operations on the file.
set -uo pipefail

if jq_bin=$(command -v jq 2>/dev/null); then
  :
elif [ -x "$HOME/.pixi/bin/jq" ]; then
  jq_bin="$HOME/.pixi/bin/jq"
else
  exec cat
fi

exec "$jq_bin" --indent 2 'del(.model)'
