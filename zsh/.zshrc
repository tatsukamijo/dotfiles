# ============================================================================
# Zsh Configuration
# ============================================================================

# ----------------------------------------------------------------------------
# History Configuration
# ----------------------------------------------------------------------------
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=20000
setopt HIST_IGNORE_ALL_DUPS  # Remove older duplicate entries
setopt HIST_REDUCE_BLANKS    # Remove superfluous blanks
setopt SHARE_HISTORY         # Share history between sessions
setopt APPEND_HISTORY        # Append to history file

# ----------------------------------------------------------------------------
# Key Bindings
# ----------------------------------------------------------------------------

# History search with arrow keys (search based on what's already typed)
autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search    # Up arrow
bindkey "^[[B" down-line-or-beginning-search  # Down arrow

# Word navigation with Alt+Arrow keys
bindkey "^[[1;3C" forward-word     # Alt+Right
bindkey "^[[1;3D" backward-word    # Alt+Left
bindkey "^[^[[C" forward-word      # Alt+Right (alternative)
bindkey "^[^[[D" backward-word     # Alt+Left (alternative)

# ----------------------------------------------------------------------------
# Tmux Integration
# ----------------------------------------------------------------------------
function precmd() {
  if [ ! -z $TMUX ]; then
    tmux refresh-client -S
  fi
}

# ----------------------------------------------------------------------------
# SSH Agent Forwarding Fix (for tmux)
# ----------------------------------------------------------------------------
if [ -n "$SSH_AUTH_SOCK" ] && [ "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]; then
    ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
fi
export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"

# ----------------------------------------------------------------------------
# Nested Neovim Protection
# ----------------------------------------------------------------------------
# Open files in parent nvim from :terminal
# - nvim FILE       → open in a new vertical split (like neo-tree 's')
# - nvim -e FILE    → reuse an existing editor window
#                     (skips :terminal and Claude Code panes); else new vsplit
if [[ -n "$NVIM" ]]; then
  nvim() {
    local mode='split'
    if [[ "$1" == "-e" || "$1" == "--edit" ]]; then
      mode='edit'
      shift
    fi
    if [[ $# -eq 0 ]]; then
      return 0
    fi
    local f abs
    for f in "$@"; do
      case "$f" in
        /*) abs="$f" ;;
        *)  abs="$PWD/$f" ;;
      esac
      command nvim --server "$NVIM" --remote-send \
        "<Cmd>lua _G.OpenFromTerm([==[${abs}]==], [==[${mode}]==])<CR>" 2>/dev/null
    done
  }
fi

# ----------------------------------------------------------------------------
# PATH Configuration
# ----------------------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:/usr/local/go/bin"
export PATH="/usr/local/bin:$PATH"
export PATH="/Users/tatsuya/.pixi/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"

# ----------------------------------------------------------------------------
# Prompt
# ----------------------------------------------------------------------------
eval "$(starship init zsh)"

# ----------------------------------------------------------------------------
# Zsh Completions
# ----------------------------------------------------------------------------
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
FPATH=/opt/homebrew/share/zsh-completions:$FPATH
FPATH=/opt/homebrew/share/zsh/site-functions:$FPATH

autoload -Uz compinit
compinit

# Pixi completion
eval "$(pixi completion --shell zsh)"

# ----------------------------------------------------------------------------
# Claude Code
# ----------------------------------------------------------------------------
# Claude Code: enable experimental Agent Teams feature
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# ----------------------------------------------------------------------------
# Local Configuration
# ----------------------------------------------------------------------------
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# ============================================================================
# Custom Functions
# ============================================================================

# ----------------------------------------------------------------------------
# Utility Functions
# ----------------------------------------------------------------------------

# Create directory and cd into it
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Extract archives automatically (creates directory based on archive name)
extract() {
  if [ -z "$1" ]; then
    echo "Usage: extract <archive-file>"
    return 1
  fi

  # Get archive basename without extension
  local archive="$1"
  local dirname="${archive%.*}"

  # For double extensions like .tar.gz, remove both
  case "$archive" in
    *.tar.gz|*.tar.bz2|*.tar.xz)
      dirname="${archive%.tar.*}"
      ;;
  esac

  # Create target directory and extract into it
  mkdir -p "$dirname"

  case $1 in
    *.tar.gz|*.tgz)  tar xzf "$archive" -C "$dirname" ;;
    *.tar.bz2|*.tbz) tar xjf "$archive" -C "$dirname" ;;
    *.tar.xz)        tar xJf "$archive" -C "$dirname" ;;
    *.tar)           tar xf "$archive" -C "$dirname" ;;
    *.zip)           unzip -q "$archive" -d "$dirname" ;;
    *.gz)            gunzip -c "$archive" > "$dirname/${archive%.gz}" ;;
    *.bz2)           bunzip2 -c "$archive" > "$dirname/${archive%.bz2}" ;;
    *.rar)           unrar x "$archive" "$dirname/" ;;
    *.7z)            7z x "$archive" -o"$dirname" ;;
    *)               echo "Unknown archive format: $1"; rmdir "$dirname" 2>/dev/null; return 1 ;;
  esac

  echo "Extracted to: $dirname/"
}

# ----------------------------------------------------------------------------
# Virtual Desktop Docker (vdd) - Smart wrapper for rdp-ssh
# ----------------------------------------------------------------------------

# Configuration
VDD_DEFAULT_SESSION="desktop-$USER"
VDD_BASE_PORT=6090

# Check if a session is already running on the remote host
_vdd_is_running() {
  local host="$1"
  local session="$2"
  rdp-ssh -a "$host" list 2>/dev/null | grep -q "^$session"
}

# Check if a local port is already in use
_vdd_port_in_use() {
  local port="$1"
  lsof -i ":$port" -sTCP:LISTEN -t >/dev/null 2>&1
}

# Find next available port starting from base port
_vdd_find_free_port() {
  local base_port="${1:-$VDD_BASE_PORT}"
  local port=$base_port
  while _vdd_port_in_use "$port"; do
    ((port++))
  done
  echo "$port"
}

# Smart wrapper for rdp-ssh that auto-detects whether to start or connect
# Usage:
#   vdd <ssh-host> [session-name] [extra-rdp-ssh-options...]
#   vdd -n <ssh-host> [session-name]  # no port forwarding (for 2nd+ terminal)
vdd() {
  local no_forward=false
  local host=""
  local session=""
  local extra_opts=""

  # Parse -n flag for no port forwarding
  if [[ "$1" == "-n" ]]; then
    no_forward=true
    shift
  fi

  host="${1:?SSH host required}"
  session="${2:-$VDD_DEFAULT_SESSION}"
  shift 2 2>/dev/null || shift 1
  extra_opts="$@"

  # Mount remote filesystem if sshfs is available
  # Skip sshfs for HPC hosts (no persistent home or incompatible)
  local skip_sshfs=false
  case "$host" in
    gmo|abci*|miyabi|wisteria|ipomoea|genkai*) skip_sshfs=true ;;
  esac

  local mount_point="$HOME/mnt/$host"
  local -a extra_mounts=()
  if ! $skip_sshfs; then
    case "$host" in
      robot_dev7*) extra_mounts+=("/robot-qnap-2/kamijo") ;;
    esac
  fi

  if ! $skip_sshfs && command -v sshfs >/dev/null 2>&1; then
    # Mount home directory
    if mount | grep -q "$mount_point"; then
      echo "→ Already mounted $host at $mount_point"
    else
      mkdir -p "$mount_point"
      if sshfs "$host": "$mount_point" -o reconnect,ServerAliveInterval=15 2>/dev/null; then
        echo "→ Mounted $host at $mount_point"
      fi
    fi
    # Mount extra paths (use flattened name to avoid nesting inside FUSE mount)
    for rpath in "${extra_mounts[@]}"; do
      local flat_name="${rpath//\//-}"
      flat_name="${flat_name#-}"
      local local_dir="$HOME/mnt/${host}-${flat_name}"
      if mount | grep -q "$local_dir"; then
        echo "→ Already mounted $host:$rpath"
      else
        mkdir -p "$local_dir"
        if sshfs "$host:$rpath" "$local_dir" -o reconnect,ServerAliveInterval=15 2>/dev/null; then
          echo "→ Mounted $host:$rpath at $local_dir"
        fi
      fi
    done
  fi

  # Auto-detect: connect if running, start if not
  local action=""
  if _vdd_is_running "$host" "$session"; then
    action="connect"
  else
    action="start"
  fi

  # Handle port forwarding
  local port_opts=""
  if $no_forward; then
    echo "→ ${action}ing session '$session' on $host (no port forwarding)..."
  else
    # Check if default port is in use, find alternative if needed
    if _vdd_port_in_use "$VDD_BASE_PORT"; then
      local free_port=$(_vdd_find_free_port)
      echo "→ ${action}ing session '$session' on $host (port $VDD_BASE_PORT in use, using $free_port)..."
      port_opts="-p $free_port"
    else
      echo "→ ${action}ing session '$session' on $host..."
    fi
  fi

  rdp-ssh -n "$session" -a "$host" $port_opts $extra_opts "$action"

  # Unmount after disconnection (always attempt if mounted)
  for rpath in "${extra_mounts[@]}"; do
    local flat_name="${rpath//\//-}"
    flat_name="${flat_name#-}"
    local local_dir="$HOME/mnt/${host}-${flat_name}"
    if mount | grep -q "$local_dir"; then
      umount "$local_dir" 2>/dev/null || diskutil unmount force "$local_dir" 2>/dev/null || true
      echo "→ Unmounted $local_dir"
    fi
  done
  if mount | grep -q "$mount_point"; then
    umount "$mount_point" 2>/dev/null || diskutil unmount force "$mount_point" 2>/dev/null || true
    echo "→ Unmounted $mount_point"
  fi
}

# Zsh completion for vdd (completes SSH hosts from ~/.ssh/config)
_vdd() {
  if (( CURRENT == 2 )); then
    _ssh_hosts
  fi
}
compdef _vdd vdd

# ----------------------------------------------------------------------------
# Git Commit Message Generation with Claude API
# ----------------------------------------------------------------------------
gc() {
  # Flags:
  #   -y, --yes           : skip the interactive prompt, auto-accept generated message
  #   -m, --message MSG   : skip AI generation, use literal MSG as the commit message
  #   -i, --intent  TEXT  : pass intent to the generator (skips interactive intent prompt)
  #   -h, --help          : show this help
  # Non-TTY stdin (piped / agent) implies -y.
  local literal_msg=""
  local intent_arg=""
  local auto_yes=0
  while (( $# )); do
    case "$1" in
      -y|--yes)     auto_yes=1; shift ;;
      -m|--message) literal_msg="$2"; auto_yes=1; shift 2 ;;
      -i|--intent)  intent_arg="$2"; shift 2 ;;
      -h|--help)
        cat <<'GC_HELP'
Usage: gc [OPTIONS]

  Stage-aware commit helper. Generates a conventional-commits message
  via Claude Haiku from the staged diff, then prompts for confirmation.

Options:
  -y, --yes           Skip the interactive prompt; auto-accept.
  -m, --message MSG   Skip AI generation; use MSG as the commit message.
  -i, --intent TEXT   Pass intent to the generator (skips interactive intent
                      prompt). Combine with -y for non-interactive runs.
  -h, --help          Show this help.

Notes:
  - When stdin is not a TTY (piped / agent invocation), behaves as if -y.
  - Without flags, runs the original interactive flow.
GC_HELP
        return 0 ;;
      *) echo "gc: unknown flag: $1" >&2; return 2 ;;
    esac
  done

  # If stdin isn't a tty, we can't prompt — auto-accept.
  [[ ! -t 0 ]] && auto_yes=1

  local diff=$(git diff --cached)
  if [[ -z "$diff" ]]; then
    echo "Nothing staged"
    return 1
  fi

  # Literal-message path: skip AI entirely.
  if [[ -n "$literal_msg" ]]; then
    git commit -m "$literal_msg"
    return $?
  fi

  local ANTHROPIC_API_KEY
  if [[ -f ~/.anthropic_api_key ]]; then
    ANTHROPIC_API_KEY=$(tr -d '[:space:]' < ~/.anthropic_api_key)
  fi
  if [[ -z "$ANTHROPIC_API_KEY" ]]; then
    echo "No API key found at ~/.anthropic_api_key"
    return 1
  fi

  # Limit diff but keep motivation clues
  local diff_excerpt=$(
    echo "$diff" | awk '
      NR<=200 {print}
      {buf[NR%200]=$0}
      END{
        if (NR>400) {
          print "\n--- snip ---\n"
          for (i=NR-199;i<=NR;i++) print buf[i%200]
        }
      }'
  )

  generate_msg() {
    local intent="$1"

    local prompt="You are generating a git commit message.

Internally infer the primary motivation behind this change (problem, improvement, or reason),
but DO NOT include that reasoning in the output.

Output ONLY a single conventional commit message line.

Commit format:
type(scope): description

Commit types:
- feat: new behavior or capability
- fix: incorrect or broken behavior
- perf: performance improvement
- style: formatting, whitespace, indentation or visual-only UI changes with no behavior or UX impact
- refactor: behavior-preserving internal change
- chore: tooling, config, dependencies, CI, scripts, non-product code
- docs: documentation only
- test: tests only

Type selection guide:
- feat/fix/perf: observable behavior or performance change
- refactor: structural or clarity improvement with no behavior change
- style: purely formatting, no semantic meaning
- chore: non-product code or tooling
- docs/test: documentation or tests only

Rules:
- Output exactly ONE line
- No preface, no explanation, no labels
- No markdown, no quotes, no backticks
- Describe the problem being addressed or benefit achieved
- Prefer architectural or behavioral meaning over raw diff summary
- Scope is optional; omit it if it does not clearly add information
- If present, scope must be conceptual, not a filename or directory
- Use abstraction level appropriate for git history
- If unsure, choose the most user-impacting type

Examples (for style and abstraction only, do not copy content):
- perf(controller): reduce control loop latency
- refactor(policy): clarify action timing semantics
- fix: prevent crash on empty input
- style(nvim): adjust statusline color scheme"

    if [[ -n "$intent" ]]; then
      prompt="$prompt

User-provided intent:
$intent"
    fi

    curl -s https://api.anthropic.com/v1/messages \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$(jq -n \
        --arg prompt "$prompt" \
        --arg diff "$diff_excerpt" \
        '{
          model: "claude-haiku-4-5-20251001",
          max_tokens: 80,
          messages: [
            {role: "user", content: ($prompt + "\n\nDiff:\n" + $diff)}
          ]
        }')" \
      | jq -r '.content[0].text // .error.message' \
      | sed 's/^```//;s/```$//;s/`//g' \
      | head -1
  }

  local start=$(date +%s.%N)
  local msg=$(generate_msg "$intent_arg")
  local elapsed=$(printf "%.1f" $(echo "$(date +%s.%N) - $start" | bc))

  # Non-interactive path: print the message + commit directly.
  if (( auto_yes )); then
    echo -e "\033[90m(${elapsed}s)\033[0m"
    echo -e "\033[38;5;159m$msg\033[0m"
    git commit -m "$msg"
    return $?
  fi

  while true; do
    echo -e "\033[90m(${elapsed}s)\033[0m"
    echo -e "\033[38;5;159m$msg\033[0m"
    read -k 1 "k?[Enter/e/i/n] "; echo

    case $k in
      $'\n'|'')  git commit -m "$msg"; break ;;
      e)   git commit -e -m "$msg"; break ;;
      n)   break ;;
      i)
        read "intent?Intent: "
        [[ -z "$intent" ]] && continue
        start=$(date +%s.%N)
        msg=$(generate_msg "$intent")
        elapsed=$(printf "%.1f" $(echo "$(date +%s.%N) - $start" | bc))
        ;;
    esac
  done
}

# ============================================================================
# Aliases
# ============================================================================

# ----------------------------------------------------------------------------
# Navigation
# ----------------------------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias dot='cd ~/dotfiles'
alias cls='clear'

