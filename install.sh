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
#   7. Restow every package (`stow -R -t ~ <pkg>`) — surviving partial conflicts per package
#   8. Install tpm (if missing)
#
# Failures in any step are logged but do NOT abort the rest of the script.
# Existing symlinks are left untouched (treated as already-installed).

set -u

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
TS="$(date +%Y%m%d-%H%M%S)"

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
    stow tmux=3.4 git curl jq bc xclip nvim nodejs
    stylua black isort clang-format python=3.11
    pueue ripgrep pre-commit
  )
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
  for d in "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share" "$HOME/.claude"; do
    if [ -L "$d" ]; then
      warn "$d is a symlink; leaving as-is (you may want to inspect)"
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
  # bash
  backup_if_real "$HOME/.bashrc"
  backup_if_real "$HOME/.inputrc"
  # tmux
  backup_if_real "$HOME/.tmux.conf"
  # nvim
  backup_if_real "$HOME/.config/nvim"
  # pueue
  backup_if_real "$HOME/.config/pueue"
  # claude (file-level under ~/.claude/)
  for f in CLAUDE.md settings.json statusline.js; do
    backup_if_real "$HOME/.claude/$f"
  done
  for d in commands skills hooks; do
    backup_if_real "$HOME/.claude/$d"
  done
}

#------------------------------------------------------------------------------
# 7. stow each package independently
#------------------------------------------------------------------------------
run_stow() {
  if ! have stow; then
    warn "stow not installed; cannot symlink (install pixi tools first)"
    return
  fi
  log "Stowing packages from $DOTFILES_DIR"
  if ! cd "$DOTFILES_DIR"; then
    err "cd $DOTFILES_DIR failed"
    return
  fi
  shopt -s nullglob
  local had_any=0
  for pkg_dir in */; do
    local pkg="${pkg_dir%/}"
    # Skip non-package directories
    case "$pkg" in
      .archive|.git|.submodules) continue ;;
    esac
    [ -d "$pkg" ] || continue
    had_any=1
    # -R: restow (rebuild symlinks for this package, idempotent)
    if stow -R -t "$HOME" "$pkg" 2>/tmp/stow-${pkg}.err; then
      ok "stow $pkg"
    else
      warn "stow $pkg had conflicts; see /tmp/stow-${pkg}.err and resolve manually"
    fi
  done
  shopt -u nullglob
  [ $had_any -eq 0 ] && warn "no stow packages found in $DOTFILES_DIR"
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
  log "Dotfiles installer (idempotent)"
  log "DOTFILES_DIR=$DOTFILES_DIR"
  if [ ! -d "$DOTFILES_DIR" ]; then
    err "$DOTFILES_DIR not found. Clone with:"
    err "  git clone --recursive git@github.com:tatsukamijo/dotfiles.git $DOTFILES_DIR"
    exit 1
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
  echo "  Next steps:"
  echo "    - Open a new shell (or 'source ~/.bashrc') to pick up PATH changes"
  echo "    - Launch nvim once to install plugins via lazy.nvim + Mason"
  echo "    - In tmux, press prefix+I (Ctrl-p I) to install tpm plugins"
  echo "    - Set machine-local secrets in ~/.bashrc.local (ANTHROPIC_API_KEY etc.)"
}

main "$@"
