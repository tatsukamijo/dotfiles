#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit): run the project's pre-commit hooks
# against the file Claude just touched. Falls back to `pixi run -e lint`
# if no .pre-commit-config.yaml is present. Silent no-op otherwise.
set -u

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0
[ ! -f "$file" ] && exit 0

# Always respect the canonical pre-commit-config exclude (^\.pixi/|.snap)
case "$file" in
  */.pixi/*|*.snap) exit 0 ;;
esac

# Walk up to find .pre-commit-config.yaml (preferred) or pixi.toml (fallback)
dir=$(dirname "$file")
precommit_root=""
pixi_root=""
while [ "$dir" != "/" ] && [ "$dir" != "." ]; do
  [ -z "$precommit_root" ] && [ -f "$dir/.pre-commit-config.yaml" ] && precommit_root="$dir"
  [ -z "$pixi_root" ] && [ -f "$dir/pixi.toml" ] && pixi_root="$dir"
  [ -n "$precommit_root" ] && break
  dir=$(dirname "$dir")
done

# Path 1: .pre-commit-config.yaml + `pre-commit` available — universal
if [ -n "$precommit_root" ] && command -v pre-commit >/dev/null 2>&1; then
  (cd "$precommit_root" && pre-commit run --files "$file") >/dev/null 2>&1 || true
  exit 0
fi

# Path 2: pixi.toml with a `lint` env — fallback for non-pre-commit projects
if [ -n "$pixi_root" ] && \
   grep -qE '^\[feature\.lint(\.|])|^\[environments\.lint\]|"lint"\s*=|=\s*\[.*"lint"' "$pixi_root/pixi.toml" 2>/dev/null; then
  case "$file" in
    *.py|*.pyi)
      (cd "$pixi_root" && pixi run -e lint ruff check --fix --force-exclude "$file") >/dev/null 2>&1 || true
      (cd "$pixi_root" && pixi run -e lint ruff format --force-exclude "$file") >/dev/null 2>&1 || true
      ;;
  esac
  case "$file" in
    *.py|*.pyi|*.md|*.txt|*.toml|*.yaml|*.yml|*.json|*.sh|*.rst|*.c|*.cpp|*.h|*.hpp|*.lua|*.tex)
      (cd "$pixi_root" && pixi run -e lint typos --write-changes --force-exclude "$file") >/dev/null 2>&1 || true
      ;;
  esac
fi

exit 0
