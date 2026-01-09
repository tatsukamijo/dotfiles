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

# Commit message generation with Claude API
gc() {
  local diff=$(git diff --cached)
  if [[ -z "$diff" ]]; then
    echo "Nothing staged"; return 1
  fi
  local start=$(date +%s.%N)
  local prompt="Conventional commit for this diff. Format: type(scope): description. Be specific about what changed. 1 line only. No markdown, no quotes, no backticks, no explanation. Just the raw commit message."
  local msg=$(curl -s https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(jq -n --arg prompt "$prompt" --arg diff "$(echo "$diff" | head -300)" '{
      model: "claude-haiku-4-5-20251001",
      max_tokens: 100,
      messages: [{role: "user", content: ($prompt + "\n\n" + $diff)}]
    }')" | jq -r '.content[0].text // .error.message' | sed 's/^```//;s/```$//;s/^`//;s/`$//' | head -1)
  local elapsed=$(echo "$(date +%s.%N) - $start" | bc)
  echo -e "\033[90m(${elapsed}s)\033[0m"
  echo -e "\033[38;5;159m$msg\033[0m"
  read -n1 -p "[Enter/e/n] " k; echo
  case $k in
    e) git commit -e -m "$msg" ;;
    n) ;;
    *) git commit -m "$msg" ;;
  esac
}

# Utility functions
mkcd() { mkdir -p "$1" && cd "$1"; }

extract() {
  case $1 in
    *.tar.gz|*.tgz) tar xzf "$1" ;;
    *.tar.bz2) tar xjf "$1" ;;
    *.tar.xz) tar xJf "$1" ;;
    *.zip) unzip "$1" ;;
    *.gz) gunzip "$1" ;;
    *) echo "Unknown format: $1" ;;
  esac
}

# OSC 52 clipboard copy for tmux over SSH (used by tmux.conf)
yank() {
  local data=$(cat)
  local tty=$(tmux display-message -p '#{pane_tty}')
  printf '\033Ptmux;\033\033]52;c;%s\007\033\\' "$(echo -n "$data" | base64 -w 0)" > "$tty"
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
