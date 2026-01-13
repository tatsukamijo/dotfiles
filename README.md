# 🐧 dotfiles for Ubuntu

Maintainer: [tatsukamijo](https://github.com/tatsukamijo)
> ✨ Complete setup guide for Ubuntu dotfiles configuration. No sudo required!

## 📦 Prerequisites

### 1. Install pixi

```bash
curl -fsSL https://pixi.sh/install.sh | bash
source ~/.bashrc  # or restart shell
```

### 2. Install all tools via pixi

```bash
pixi global install \
  stow \
  tmux=3.4 \
  git \
  curl \
  jq \
  bc \
  xclip \
  nvim \
  nodejs \
  stylua \
  black \
  isort \
  clang-format \
  python=3.11 \
  pueue
```

## 🚀 Installation

### 1. Clone this repository with submodules

```bash
git clone --recursive git@github.com:tatsukamijo/dotfiles.git ~/dotfiles
cd ~/dotfiles
git checkout ubuntu
```

> 💡 The `--recursive` flag clones the nvim configuration (managed as a git submodule).

If you already cloned without it, initialize the submodule:
```bash
git submodule update --init --recursive
```

### 2. Symlink configurations with GNU stow

```bash
# Backup existing config files
for f in .bashrc .inputrc .tmux.conf; do [ -f ~/$f ] && mv ~/$f ~/$f.bak; done
[ -d ~/.config/nvim ] && mv ~/.config/nvim ~/.config/nvim.bak
[ -d ~/.config/pueue ] && mv ~/.config/pueue ~/.config/pueue.bak
[ -f ~/.local/bin/rdp-ssh ] && mv ~/.local/bin/rdp-ssh ~/.local/bin/rdp-ssh.bak

# Stow all configurations
stow -v */
```

This creates symlinks from each configuration directory to your home directory.

### 3. First-time Neovim setup

Launch Neovim to auto-install plugins and LSP servers:
```bash
nvim
```

On first launch, plugins will be installed via lazy.nvim and LSP servers via Mason. ☕ Grab a coffee!

> 📝 Neovim configuration is managed separately. For details, keybindings, and troubleshooting, see: [tatsukamijo/tatsukamijo.nvim](https://github.com/tatsukamijo/tatsukamijo.nvim)

### 4. tmux Plugin Manager

Install TPM:
```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then in tmux, press `prefix + I` to install plugins. (prefix is `Ctrl+p` in this config)

## ✨ Features

### 🤖 `gc` - Auto Commit Message Generator

Stage your changes and run `gc` (**g**it **c**ommit) to generate a conventional commit message using Claude API:

```bash
git add .
gc
# Example output:
# tatsuya.kamijo@robot-dev7:~/hipar [feat/baseline]$ git add .
# tatsuya.kamijo@robot-dev7:~/hipar [feat/baseline]$ gc
# (1.212070126s)
# refactor(plot_utils): centralize color palette and plotting utilities into unified module
# [Enter/e/n]
```

| Key | Action |
|-----|--------|
| `Enter` | Commit with generated message |
| `e` | Edit message before commit |
| `n` | Cancel |

> 🔑 Requires `ANTHROPIC_API_KEY` in `~/.bashrc.local`

### 📬 pueue-notify - Job Completion Email Notifications

Get email notifications when [pueue](https://github.com/Nukesor/pueue) tasks complete. Features HTML-formatted emails with success/failure status, command details, and truncated logs.

**Setup:**

1. Create a Gmail App Password:
   - Enable 2FA at https://myaccount.google.com/security
   - Generate app password at https://myaccount.google.com/apppasswords

2. Add to `~/.bashrc.local`:
   ```bash
   export PUEUE_NOTIFY_EMAIL="your-email@example.com"  # Recipient
   export SMTP_GMAIL_ADDRESS="your-gmail@gmail.com"    # Sender
   export SMTP_GMAIL_PASSWORD="xxxx xxxx xxxx xxxx"    # App password (no spaces)
   ```

3. Start pueue daemon:
   ```bash
   pueued -d
   ```

**Features:**
- Emails grouped into threads by pueue group
- Long logs truncated (first 10 + last 10 lines)
- Optional: Set `PUEUE_NOTIFY_ONLY_FAILURE=true` to only notify on failures

**Reset email threads:**
```bash
rm ~/.local/share/pueue-notify/threads.json
```

## ⚙️ Post-Installation

### Local Configuration

Create `~/.bashrc.local` for machine-specific settings:

```bash
export ANTHROPIC_API_KEY="your-key-here"
```

### Reload configurations

```bash
# Reload bash
source ~/.bashrc

# Reload tmux (from within tmux)
tmux source ~/.tmux.conf
```

## 🔄 Updating

```bash
cd ~/dotfiles
git pull
git submodule update --remote  # Update nvim config
stow -R */  # Restow all packages
```

## 🗑️ Uninstalling

```bash
cd ~/dotfiles
stow -D */
```


