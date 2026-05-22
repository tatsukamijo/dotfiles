# 🛠️ dotfiles

Maintainer: [tatsukamijo](https://github.com/tatsukamijo)
> ✨ Cross-platform dotfiles (macOS + Linux) managed with GNU stow. No sudo required.

## 🌳 Layout

A **single branch** (`main`) holds both macOS and Linux configs side by side.
The installer detects the OS and stows only the relevant packages — there are
no per-OS branches to keep in sync.

| Scope | Packages |
|-------|----------|
| **Shared** (both OSes) | `claude`, `nvim`, `tmux` |
| **macOS only** | `zsh`, `skhd`, `yabai`, `hammerspoon`, `starship` |
| **Linux only** | `bash`, `pueue`, `clipimg` |

Not stowed: `.submodules/` (git submodules), `docs/`, `.archive/`.

## 📦 Prerequisites

### 1. Install pixi

```bash
curl -fsSL https://pixi.sh/install.sh | bash
exec $SHELL  # restart shell
```

### 2. Install tools via pixi

```bash
pixi global install \
  stow tmux=3.4 git curl jq bc nvim nodejs \
  stylua black isort clang-format python=3.11 \
  ripgrep pre-commit
# Linux only: also install `xclip pueue`
```

### 3. Install Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

> The `install.sh` quick start below does all three steps for you.

## 🚀 Installation

### Quick start (idempotent installer)

```bash
git clone --recursive git@github.com:tatsukamijo/dotfiles.git ~/dotfiles
cd ~/dotfiles && bash install.sh
```

`install.sh` is **safe to re-run** from any partial state. It installs pixi, the
global tool list, Claude Code, and submodules, then symlinks the
**OS-appropriate** packages via `stow -R`. Pre-existing real files are
timestamp-backed up (`*.bak.<TS>`); existing symlinks are left alone.

### Manual installation

```bash
# 1. Clone with submodules (--recursive pulls the nvim config submodule)
git clone --recursive git@github.com:tatsukamijo/dotfiles.git ~/dotfiles
cd ~/dotfiles
# If you forgot --recursive:
git submodule update --init --recursive

# 2. Back up any existing real config files (skip symlinks), then stow.
#    Pick the line for your OS:
stow -v claude nvim tmux zsh skhd yabai hammerspoon starship   # macOS
stow -v claude nvim tmux bash pueue clipimg                    # Linux
```

### First-time Neovim setup

Launch `nvim` once — plugins install via lazy.nvim and LSP servers via Mason.
☕ Neovim config is a submodule: see
[tatsukamijo/tatsukamijo.nvim](https://github.com/tatsukamijo/tatsukamijo.nvim).

### tmux Plugin Manager

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then in tmux press `prefix + I` to install plugins (prefix is `Ctrl+p`).

## ✨ Features

### 🤖 `gc` — Auto Commit Message Generator

Stage your changes and run `gc` (**g**it **c**ommit) to generate a conventional
commit message via the Claude API:

| Key | Action |
|-----|--------|
| `Enter` | Commit with generated message |
| `e` | Edit message before commit |
| `n` | Cancel |

> 🔑 Requires `ANTHROPIC_API_KEY` in `~/.bashrc.local` (Linux) or `~/.zshrc.local` (macOS).

### 📬 pueue-notify — Job Completion Email Notifications (Linux)

Get HTML email notifications when [pueue](https://github.com/Nukesor/pueue)
tasks complete, with success/failure status and truncated logs.

1. Create a Gmail App Password (enable 2FA, then generate at
   https://myaccount.google.com/apppasswords).
2. Add to `~/.bashrc.local`:
   ```bash
   export PUEUE_NOTIFY_EMAIL="your-email@example.com"  # Recipient
   export SMTP_GMAIL_ADDRESS="your-gmail@gmail.com"    # Sender
   export SMTP_GMAIL_PASSWORD="xxxxxxxxxxxxxxxx"       # App password (no spaces)
   ```
3. Start the daemon: `pueued -d`

- Emails are grouped into threads by pueue group.
- Set `PUEUE_NOTIFY_ONLY_FAILURE=true` to notify only on failures.
- Reset threads: `rm ~/.local/share/pueue-notify/threads.json`

## 🤖 Claude Code Global Config (`claude/` package)

Manages `~/.claude/` global config: `CLAUDE.md`, `settings.json`,
`statusline.js`, `commands/`, `skills/`, `hooks/`.

Machine-local state (`projects/`, `todos/`, `sessions/`, `.credentials.json`,
`settings.local.json`, `memory/`, etc.) is excluded via `.gitignore` and stays
per-machine.

The statusline shows model, dir, token usage, and % of auto-compact limit.
Requires `node` on `PATH`.

## ⚙️ Post-Installation

### Local Configuration

Create the machine-local override for your shell:

- Linux: `~/.bashrc.local`
- macOS: `~/.zshrc.local`

```bash
export ANTHROPIC_API_KEY="your-key-here"
```

### Reload configurations

```bash
source ~/.bashrc          # or ~/.zshrc on macOS
tmux source ~/.tmux.conf  # from within tmux
```

## 🔄 Updating

```bash
cd ~/dotfiles
git pull
git submodule update --remote   # update nvim config
bash install.sh                 # re-stow (idempotent, OS-aware)
```

## 🗑️ Uninstalling

```bash
cd ~/dotfiles
# macOS
stow -D claude nvim tmux zsh skhd yabai hammerspoon starship
# Linux
stow -D claude nvim tmux bash pueue clipimg
```
