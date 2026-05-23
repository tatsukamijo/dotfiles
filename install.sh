#!/usr/bin/env bash
# Idempotent dotfiles installer. Safe to re-run from any partial state.
#
# What it does (each step is a no-op if already satisfied):
#   1. Install pixi (if missing)
#   2. pixi global install <tools> (idempotent per tool)
#   3. Install Claude Code (if `claude` not on PATH)
#   4. git submodule update --init --recursive
#   5. Pre-create top-level dirs so stow folds at file-level (~/.claude, ~/.config, ~/.local)
#   6. Backup any pre-existing real files/dirs that would conflict with stow
#      (timestamped .bak.<TS>; never overwrites prior backups)
#   7. Restow the OS-appropriate packages (common + per-OS), surviving partial conflicts
#   8. Install tpm (if missing)
#
# Run `./install.sh --uninstall` (or `-u`) to `stow -D` the same OS-appropriate
# set of packages. Other steps (pixi tools, tpm, ...) are left in place.
#
# Failures in any step are logged but do NOT abort the rest of the script.
# Existing symlinks are left untouched (treated as already-installed).
#
# Single-branch / cross-platform: this repo holds macOS and Linux configs side
# by side. The OS is detected here and only the relevant stow packages are
# linked — bash vs zsh, and the macOS-only tools (skhd/yabai/hammerspoon), must
# never land on the wrong OS.

set -u

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
TS="$(date +%Y%m%d-%H%M%S)"

# OS detection — drives stow package and pixi tool selection below.
case "$(uname -s)" in
  Darwin) OS_KIND=macos ;;
  Linux)  OS_KIND=linux ;;
  *)      OS_KIND=unknown ;;
esac

# Stow packages: shared set + an OS-specific set. Deliberately NOT every dir.
COMMON_PKGS=(claude nvim tmux)
case "$OS_KIND" in
  macos) OS_PKGS=(zsh skhd yabai hammerspoon starship borders) ;;
  linux) OS_PKGS=(bash pueue clipimg) ;;
  *)     OS_PKGS=() ;;
esac
STOW_PKGS=("${COMMON_PKGS[@]}" "${OS_PKGS[@]}")

log()  { printf '\033[34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[ok]\033[0m %s\n' "$*"; }
skip() { printf '\033[90m[skip]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[warn]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m[err]\033[0m %s\n' "$*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

#------------------------------------------------------------------------------
# 1. pixi
#------------------------------------------------------------------------------
ensure_pixi() {
  if have pixi; then
    skip "pixi already installed ($(pixi --version 2>/dev/null))"
  else
    log "Installing pixi"
    if curl -fsSL https://pixi.sh/install.sh | bash; then
      ok "pixi installed"
    else
      warn "pixi install failed"
    fi
  fi
  # Make pixi reachable for the rest of this run regardless of shell init state
  export PATH="$HOME/.pixi/bin:$PATH"
}

#------------------------------------------------------------------------------
# 2. pixi global tools (per-tool, individually idempotent)
#------------------------------------------------------------------------------
ensure_pixi_tools() {
  if ! have pixi; then
    warn "pixi not on PATH; skipping global tools"
    return
  fi
  local tools=(
    stow tmux=3.4 git curl jq bc nvim nodejs
    stylua black isort clang-format python=3.11
    ripgrep pre-commit
  )
  # Linux-only extras (xclip: X11 clipboard; pueue: task queue used on Linux).
  if [ "$OS_KIND" = linux ]; then
    tools+=(xclip pueue)
  fi
  log "Installing pixi global tools (idempotent per tool)"
  for t in "${tools[@]}"; do
    if pixi global install "$t" >/dev/null 2>&1; then
      ok "$t"
    else
      warn "pixi global install $t failed (continuing)"
    fi
  done
}

#------------------------------------------------------------------------------
# 3. Claude Code
#------------------------------------------------------------------------------
ensure_claude_code() {
  if have claude; then
    skip "claude code already installed"
    return
  fi
  log "Installing Claude Code"
  if curl -fsSL https://claude.ai/install.sh | bash; then
    ok "claude code installed"
  else
    warn "claude code install failed"
  fi
}

#------------------------------------------------------------------------------
# 4. git submodules
#------------------------------------------------------------------------------
ensure_submodules() {
  if [ ! -d "$DOTFILES_DIR/.git" ]; then
    warn "$DOTFILES_DIR is not a git repo; skipping submodule update"
    return
  fi
  log "Updating git submodules"
  if git -C "$DOTFILES_DIR" submodule update --init --recursive; then
    ok "submodules up to date"
  else
    warn "submodule update failed"
  fi
}

#------------------------------------------------------------------------------
# 5. Pre-create dirs that must NOT become a single stow symlink
#    (we want stow to fold at file-level inside them, not at the dir level)
#------------------------------------------------------------------------------
ensure_real_dirs() {
  # Order matters: parents before children. ~/.local MUST exist as a real dir
  # before stow runs, otherwise stow folds it into a single symlink to
  # whichever package owns .local/, swallowing all future writes from claude,
  # nvim, etc. into the dotfiles repo.
  for d in "$HOME/.config" "$HOME/.local" "$HOME/.local/bin" "$HOME/.local/share" "$HOME/.local/state" "$HOME/.claude"; do
    if [ -L "$d" ]; then
      warn "$d is a symlink (likely stow-folded); leaving as-is — inspect and replace with a real dir before re-stowing"
    else
      mkdir -p "$d"
    fi
  done
}

#------------------------------------------------------------------------------
# 6. Backup conflicting real files/dirs (skip existing symlinks)
#------------------------------------------------------------------------------
backup_if_real() {
  local p="$1"
  if [ -L "$p" ]; then
    return 0   # already a symlink (presumably from a prior stow run); leave it
  fi
  if [ -e "$p" ]; then
    local bak="${p}.bak.${TS}"
    if mv "$p" "$bak"; then
      ok "backup: $p -> $bak"
    else
      warn "backup failed for $p"
    fi
  fi
}

backup_existing_targets() {
  log "Backing up pre-existing real files (symlinks left alone)"
  # Common: tmux
  backup_if_real "$HOME/.tmux.conf"
  # Common: nvim
  backup_if_real "$HOME/.config/nvim"
  # Common: claude (file-level under ~/.claude/)
  for f in CLAUDE.md settings.json statusline.js; do
    backup_if_real "$HOME/.claude/$f"
  done
  for d in commands skills hooks; do
    backup_if_real "$HOME/.claude/$d"
  done
  # OS-specific targets
  if [ "$OS_KIND" = linux ]; then
    backup_if_real "$HOME/.bashrc"
    backup_if_real "$HOME/.inputrc"
    backup_if_real "$HOME/.config/pueue"
    backup_if_real "$HOME/.local/bin/clipimg-recv"
  elif [ "$OS_KIND" = macos ]; then
    backup_if_real "$HOME/.zshrc"
    backup_if_real "$HOME/.config/skhd"
    backup_if_real "$HOME/.config/yabai"
    backup_if_real "$HOME/.config/borders"
    backup_if_real "$HOME/.config/starship.toml"
    backup_if_real "$HOME/.hammerspoon"
  fi
}

#------------------------------------------------------------------------------
# 7. stow each package independently
#------------------------------------------------------------------------------
run_stow() {
  if ! have stow; then
    warn "stow not installed; cannot symlink (install pixi tools first)"
    return
  fi
  log "Stowing $OS_KIND packages: ${STOW_PKGS[*]}"
  if ! cd "$DOTFILES_DIR"; then
    err "cd $DOTFILES_DIR failed"
    return
  fi
  for pkg in "${STOW_PKGS[@]}"; do
    if [ ! -d "$pkg" ]; then
      warn "package '$pkg' not found in $DOTFILES_DIR; skipping"
      continue
    fi
    # -R: restow (rebuild symlinks for this package, idempotent)
    if stow -R -t "$HOME" "$pkg" 2>/tmp/stow-${pkg}.err; then
      ok "stow $pkg"
    else
      warn "stow $pkg had conflicts; see /tmp/stow-${pkg}.err and resolve manually"
    fi
  done
}

#------------------------------------------------------------------------------
# uninstall: `stow -D` each package
#------------------------------------------------------------------------------
run_unstow() {
  if ! have stow; then
    warn "stow not installed; nothing to remove"
    return
  fi
  log "Un-stowing $OS_KIND packages: ${STOW_PKGS[*]}"
  if ! cd "$DOTFILES_DIR"; then
    err "cd $DOTFILES_DIR failed"
    return
  fi
  for pkg in "${STOW_PKGS[@]}"; do
    [ -d "$pkg" ] || continue
    if stow -D -t "$HOME" "$pkg" 2>/tmp/unstow-${pkg}.err; then
      ok "unstow $pkg"
    else
      warn "unstow $pkg had issues; see /tmp/unstow-${pkg}.err"
    fi
  done
}

#------------------------------------------------------------------------------
# 8. tpm (tmux plugin manager)
#------------------------------------------------------------------------------
ensure_tpm() {
  if [ -d "$HOME/.tmux/plugins/tpm" ]; then
    skip "tpm already installed"
    return
  fi
  log "Installing tmux plugin manager (tpm)"
  if git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" >/dev/null 2>&1; then
    ok "tpm installed"
  else
    warn "tpm clone failed"
  fi
}

#------------------------------------------------------------------------------
# main
#------------------------------------------------------------------------------
main() {
  local action=install
  case "${1:-}" in
    ""|install)        ;;
    --uninstall|-u)    action=uninstall ;;
    *) err "unknown arg: $1 (use --uninstall to remove symlinks)"; exit 2 ;;
  esac

  log "Dotfiles installer (idempotent)"
  log "DOTFILES_DIR=$DOTFILES_DIR"
  if [ ! -d "$DOTFILES_DIR" ]; then
    err "$DOTFILES_DIR not found. Clone with:"
    err "  git clone --recursive git@github.com:tatsukamijo/dotfiles.git $DOTFILES_DIR"
    exit 1
  fi

  if [ "$action" = uninstall ]; then
    run_unstow
    log "Done."
    return 0
  fi

  ensure_pixi
  ensure_pixi_tools
  ensure_claude_code
  ensure_submodules
  ensure_real_dirs
  backup_existing_targets
  run_stow
  ensure_tpm

  log "Done."
  local rc=".bashrc"
  [ "$OS_KIND" = macos ] && rc=".zshrc"
  echo "  Next steps:"
  echo "    - Open a new shell (or 'source ~/$rc') to pick up PATH changes"
  echo "    - Launch nvim once to install plugins via lazy.nvim + Mason"
  echo "    - In tmux, press prefix+I (Ctrl-p I) to install tpm plugins"
  echo "    - Set machine-local secrets in ~/$rc.local (ANTHROPIC_API_KEY etc.)"
}

main "$@"
