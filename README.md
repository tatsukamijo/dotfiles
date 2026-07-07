# 🛠️ dotfiles

Maintainer: [tatsukamijo](https://github.com/tatsukamijo)
> ✨ Cross-platform dotfiles (macOS + Linux) managed with GNU stow. No sudo required.

## 🌳 Layout

A **single branch** (`main`) holds both macOS and Linux configs side by side.
The installer detects the OS and stows only the relevant packages.

| Scope | Packages |
|-------|----------|
| **Shared** (both OSes) | `claude`, `nvim`, `tmux`, `miyabi` |
| **macOS only** | `zsh`, `skhd`, `yabai`, `hammerspoon`, `starship` |
| **Linux only** | `bash`, `pueue`, `clipimg` |

Not stowed: `.submodules/` (git submodules), `docs/`, `.archive/`.

## 🚀 Installation

### Quick start (idempotent installer)

```bash
git clone --recursive git@github.com:tatsukamijo/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```

`install.sh` is **safe to re-run** from any partial state. It installs pixi, the
global tool list, Claude Code, and submodules, then symlinks the
**OS-appropriate** packages via `stow -R`. Pre-existing real files are
timestamp-backed up (`*.bak.<TS>`); existing symlinks are left alone.

<details>
<summary>What <code>install.sh</code> does under the hood</summary>

Equivalent to running these by hand:

```bash
# 1. pixi
curl -fsSL https://pixi.sh/install.sh | bash
exec $SHELL  # restart shell

# 2. tools via pixi
pixi global install \
  stow tmux=3.4 git curl jq bc nvim nodejs \
  stylua black isort clang-format python=3.11 \
  ripgrep pre-commit
# Linux only: also install `xclip pueue`

# 3. Claude Code
curl -fsSL https://claude.ai/install.sh | bash
```

Plus: `git submodule update --init --recursive`, pre-creating `~/.config`,
`~/.local`, `~/.claude` as real dirs so stow folds at file-level, timestamped
backup of any conflicting real files, OS-appropriate `stow -R`, and `tpm`.

</details>

### First-time Neovim setup

Launch `nvim` once. Plugins install via lazy.nvim and LSP servers via Mason.
☕ Neovim config is a submodule: see
[tatsukamijo/tatsukamijo.nvim](https://github.com/tatsukamijo/tatsukamijo.nvim).

### tmux Plugin Manager

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then in tmux press `prefix + I` to install plugins (prefix is `Ctrl+p`).

## ✨ Features

### 🤖 `gc`: Auto Commit Message Generator

Stage your changes and run `gc` (**g**it **c**ommit) to generate a conventional
commit message via the Claude API:

| Key | Action |
|-----|--------|
| `Enter` | Commit with generated message |
| `e` | Edit message before commit |
| `n` | Cancel |

> 🔑 Requires `ANTHROPIC_API_KEY` in `~/.bashrc.local` (Linux) or `~/.zshrc.local` (macOS).

### 📬 pueue-notify: Job Completion Email Notifications (Linux)

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

### 🔐 miyabi: Auto-TOTP SSH/SCP/rsync Login (Linux + macOS)

Types the miyabi TOTP code (RFC 6238, computed locally) at the
`Verification code:` prompt so `ssh`/`scp`/`sftp`/`rsync` don't stop to ask.

- `ssh-totp <cmd> ...` — runs a command under a pty and answers the prompt, then
  proxies I/O (file data and login shells pass through normally). `miyabi` is a
  convenience wrapper for `ssh-totp ssh miyabi`.
- `ssh()`/`scp()`/`sftp()` shell functions (bash + zsh) route miyabi-host
  commands through `ssh-totp`; everything else hits the real binary.
- `rsync()` can't use the pty (its protocol needs clean pipes over ssh), so it
  routes through ssh with `miyabi-askpass` as `SSH_ASKPASS` instead.

Pure Python stdlib — no `oathtool`, `expect`, or sudo.

1. Store the base32 TOTP secret (**not** tracked by git) at
   `~/.config/miyabi/secret`, `chmod 600`:
   ```bash
   umask 077; mkdir -p ~/.config/miyabi
   printf '%s\n' 'YOURBASE32SECRET' > ~/.config/miyabi/secret
   chmod 600 ~/.config/miyabi/secret
   ```
2. Ensure the ssh key + `Host miyabi` alias exist in `~/.ssh/config`.
3. Use plain commands (in an interactive bash/zsh shell), or `miyabi` from scripts:
   ```bash
   ssh miyabi                       # interactive login
   scp data.tar miyabi:~/           # copy up
   scp miyabi:~/out.log .           # copy down
   rsync -av ./run/ miyabi:~/run/   # incremental sync
   miyabi hostname                  # standalone wrapper, no shell function needed
   ```

> Miyabi sets `DISALLOW_REUSE`, so a code can't be used twice: `ssh-totp` records
> the last window it spent and waits for the next 30 s window before a
> back-to-back second connection — expect an occasional pause.

> The secret lives beside the ssh client, so 2FA effectively collapses to one
> factor on this host — keep the file locked down, and check your HPC center's
> acceptable-use policy before automating its 2FA.

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
./install.sh                    # re-stow (idempotent, OS-aware)
```

## 🗑️ Uninstalling

```bash
cd ~/dotfiles && ./install.sh --uninstall
```

`stow -D`s the OS-appropriate packages. Pixi tools and tpm stay installed
(remove those by hand if you really want a clean slate).
