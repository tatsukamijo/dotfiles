# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# History settings
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
HISTSIZE=10000
HISTFILESIZE=20000

# Check window size after each command
shopt -s checkwinsize

# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Chroot prompt
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# Enable color support
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias cls='clear'
alias open='xdg-open'

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias dot='cd ~/dotfiles'

# Alert alias for long running commands
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Load bash aliases if exists
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Git branch name visualization
function parse_git_branch {
    git branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ [\1]/'
}

function promps {
    local BLUE="\[\e[1;34m\]"
    local GREEN="\[\e[1;32m\]"
    local WHITE="\[\e[00m\]"
    case $TERM in
        xterm*) TITLEBAR='\[\e]0;\w\007\]';;
        *)      TITLEBAR="";;
    esac
    local BASE="\u@\h"
    PS1="${TITLEBAR}${GREEN}${BASE}${WHITE}:${BLUE}\w${GREEN}\$(parse_git_branch)${BLUE}\$${WHITE} "
}
promps

gc() {
  local diff=$(git diff --cached)
  if [[ -z "$diff" ]]; then
    echo "Nothing staged"
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
  local msg=$(generate_msg "")
  local elapsed=$(echo "$(date +%s.%N) - $start" | bc)

  while true; do
    echo -e "\033[90m(${elapsed}s)\033[0m"
    echo -e "\033[38;5;159m$msg\033[0m"
    read -n1 -p "[Enter/e/i/n] " k
    echo

    case $k in
      "")  git commit -m "$msg"; break ;;
      e)   git commit -e -m "$msg"; break ;;
      n)   break ;;
      i)
        read -p "Intent: " intent
        [[ -z "$intent" ]] && continue
        start=$(date +%s.%N)
        msg=$(generate_msg "$intent")
        elapsed=$(echo "$(date +%s.%N) - $start" | bc)
        ;;
    esac
  done
}



# Utility functions
mkcd() { mkdir -p "$1" && cd "$1"; }

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

# OSC 52 clipboard copy for tmux over SSH (used by tmux.conf)
yank() {
  local data=$(cat)
  local tty=$(tmux display-message -p '#{pane_tty}')
  printf '\033Ptmux;\033\033]52;c;%s\007\033\\' "$(echo -n "$data" | base64 -w 0)" > "$tty"
}

# Virtual Desktop Docker (vdd) - Smart wrapper for rdp-ssh
VDD_DEFAULT_SESSION="desktop-kamijo"
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
}

# Open files in parent nvim from :terminal
if [[ -n "$NVIM" ]]; then
  alias nvim='nvim --server "$NVIM" --remote'
fi

# Bash completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Cargo (Rust)
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# SSH agent forwarding fix for tmux
if [ -n "$SSH_AUTH_SOCK" ] && [ "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]; then
    ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
fi
export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"

# Pixi
export PATH="$HOME/.pixi/bin:$PATH"
if command -v pixi &> /dev/null; then
    eval "$(pixi completion --shell bash)"
fi

# Local bin
export PATH="$HOME/.local/bin:$PATH"

# ANTHROPIC_API_KEY should be set in ~/.bashrc.local or environment
# Load local overrides
[ -f ~/.bashrc.local ] && . ~/.bashrc.local
