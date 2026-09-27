#!/usr/bin/env bash
set -uo pipefail

REPO="sipeti/ihaveanewmac"
YES=0

if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
  YES=1
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
ihaveanewmac - macOS bootstrap

Usage:
  ./bootstrap.sh        interactive mode
  ./bootstrap.sh --yes  accept default package groups
  ./bootstrap.sh --help show this help

Do not run this script with sudo.
EOF
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS only."
  exit 1
fi

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Please run this as your normal user, not with sudo."
  exit 1
fi

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '==> %s\n' "$*"; }
ok()   { printf '    ✓ %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*" >&2; }

ask_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local answer

  if [[ "$YES" -eq 1 ]]; then
    [[ "$default" == "y" ]]
    return
  fi

  if [[ "$default" == "y" ]]; then
    read -r -p "$prompt [Y/n] " answer
    answer="${answer:-y}"
  else
    read -r -p "$prompt [y/N] " answer
    answer="${answer:-n}"
  fi

  [[ "$answer" =~ ^[Yy]$ ]]
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

append_line_once() {
  local line="$1"
  local file="$2"

  touch "$file"
  if ! grep -Fqx "$line" "$file" 2>/dev/null; then
    printf '%s\n' "$line" >> "$file"
  fi
}

brew_formula() {
  local pkg="$1"
  if brew list --formula "$pkg" >/dev/null 2>&1; then
    ok "$pkg already installed"
  else
    info "Installing $pkg"
    if brew install "$pkg"; then
      ok "$pkg installed"
    else
      warn "Could not install $pkg; continuing"
    fi
  fi
}

brew_cask() {
  local pkg="$1"
  if brew list --cask "$pkg" >/dev/null 2>&1; then
    ok "$pkg already installed"
  else
    info "Installing $pkg"
    if brew install --cask "$pkg"; then
      ok "$pkg installed"
    else
      warn "Could not install $pkg; continuing"
    fi
  fi
}

bold "ihaveanewmac"
echo "Bootstrap for a fresh macOS workstation"
echo

# ---------------------------------------------------------------------------
# Mac identity / hostname
# ---------------------------------------------------------------------------
CURRENT_COMPUTER_NAME="$(scutil --get ComputerName 2>/dev/null || hostname)"
if [[ "$YES" -eq 1 ]]; then
  MACHINE_NAME="$CURRENT_COMPUTER_NAME"
else
  read -r -p "Mac name [$CURRENT_COMPUTER_NAME]: " MACHINE_NAME
  MACHINE_NAME="${MACHINE_NAME:-$CURRENT_COMPUTER_NAME}"
fi

# LocalHostName and HostName should be DNS-friendly.
MACHINE_HOSTNAME="$(printf '%s' "$MACHINE_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"

if [[ -z "$MACHINE_HOSTNAME" ]]; then
  MACHINE_HOSTNAME="mac"
fi

if [[ "$MACHINE_NAME" != "$CURRENT_COMPUTER_NAME" ]] || \
   [[ "$(scutil --get LocalHostName 2>/dev/null || true)" != "$MACHINE_HOSTNAME" ]] || \
   [[ "$(scutil --get HostName 2>/dev/null || true)" != "$MACHINE_HOSTNAME" ]]; then
  info "Setting Mac name to '$MACHINE_NAME' ($MACHINE_HOSTNAME)"
  sudo scutil --set ComputerName "$MACHINE_NAME"
  sudo scutil --set LocalHostName "$MACHINE_HOSTNAME"
  sudo scutil --set HostName "$MACHINE_HOSTNAME"
  ok "Mac hostname configured"
else
  ok "Mac hostname already configured"
fi


# ---------------------------------------------------------------------------
# Apple Command Line Tools
# ---------------------------------------------------------------------------
if xcode-select -p >/dev/null 2>&1; then
  ok "Apple Command Line Tools already installed"
else
  info "Requesting Apple Command Line Tools installation"
  xcode-select --install >/dev/null 2>&1 || true
  echo
  echo "macOS opened the Command Line Tools installer."
  echo "Finish that installer, then press Enter here."
  read -r
  if ! xcode-select -p >/dev/null 2>&1; then
    warn "Command Line Tools still not detected. Homebrew may fail."
  fi
fi

# ---------------------------------------------------------------------------
# Homebrew
# ---------------------------------------------------------------------------
if ! command_exists brew; then
  info "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_BIN="/opt/homebrew/bin/brew"
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_BIN="/usr/local/bin/brew"
else
  BREW_BIN="$(command -v brew 2>/dev/null || true)"
fi

if [[ -z "${BREW_BIN:-}" ]]; then
  echo "Homebrew installation failed or brew is not in a known location."
  exit 1
fi

eval "$("$BREW_BIN" shellenv)"

ZPROFILE="$HOME/.zprofile"
BREW_MARKER_BEGIN="# >>> ihaveanewmac homebrew >>>"
BREW_MARKER_END="# <<< ihaveanewmac homebrew <<<"

if ! grep -Fq "$BREW_MARKER_BEGIN" "$ZPROFILE" 2>/dev/null; then
  {
    echo
    echo "$BREW_MARKER_BEGIN"
    echo "eval \"\$($BREW_BIN shellenv)\""
    echo "$BREW_MARKER_END"
  } >> "$ZPROFILE"
  ok "Homebrew shellenv added to ~/.zprofile"
fi

info "Updating Homebrew metadata"
brew update || warn "brew update failed; continuing"

# ---------------------------------------------------------------------------
# Core command line tools
# ---------------------------------------------------------------------------
bold "Core CLI tools"
CORE_FORMULAE=(
  git
  gh
  jq
  wget
  tree
  htop
  python
  pipx
  node
)
for pkg in "${CORE_FORMULAE[@]}"; do
  brew_formula "$pkg"
done

# pipx path
if command_exists pipx; then
  pipx ensurepath >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Git identity
# ---------------------------------------------------------------------------
bold "Git identity"

CURRENT_GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
CURRENT_GIT_EMAIL="$(git config --global user.email 2>/dev/null || true)"

if [[ "$YES" -eq 0 ]]; then
  read -r -p "Git full name${CURRENT_GIT_NAME:+ [$CURRENT_GIT_NAME]}: " GIT_NAME
  GIT_NAME="${GIT_NAME:-$CURRENT_GIT_NAME}"

  read -r -p "Git email${CURRENT_GIT_EMAIL:+ [$CURRENT_GIT_EMAIL]}: " GIT_EMAIL
  GIT_EMAIL="${GIT_EMAIL:-$CURRENT_GIT_EMAIL}"
else
  GIT_NAME="$CURRENT_GIT_NAME"
  GIT_EMAIL="$CURRENT_GIT_EMAIL"
fi

if [[ -n "$GIT_NAME" ]]; then
  git config --global user.name "$GIT_NAME"
  ok "Git user.name = $GIT_NAME"
else
  warn "Git user.name is not configured"
fi

if [[ -n "$GIT_EMAIL" ]]; then
  git config --global user.email "$GIT_EMAIL"
  ok "Git user.email = $GIT_EMAIL"
else
  warn "Git user.email is not configured"
fi

# Safe, generally useful defaults for new machines.
git config --global init.defaultBranch main
git config --global fetch.prune true
git config --global push.autoSetupRemote true
git config --global core.autocrlf input
git config --global pull.rebase false
git config --global rerere.enabled true

GLOBAL_GITIGNORE="$HOME/.gitignore_global"
touch "$GLOBAL_GITIGNORE"
append_line_once ".DS_Store" "$GLOBAL_GITIGNORE"
git config --global core.excludesfile "$GLOBAL_GITIGNORE"
ok "Git defaults configured"

# ---------------------------------------------------------------------------
# SSH / GitHub identity
# ---------------------------------------------------------------------------
bold "SSH / GitHub"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

SSH_COMMENT="${GIT_EMAIL:-$USER@$MACHINE_HOSTNAME}"

if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
  ok "~/.ssh/id_ed25519 already exists"
else
  if ask_yes_no "Create a GitHub SSH Ed25519 key (~/.ssh/id_ed25519)?" y; then
    info "Creating Ed25519 SSH key"
    ssh-keygen -t ed25519 -C "$SSH_COMMENT" -f "$HOME/.ssh/id_ed25519"
    ok "Ed25519 SSH key created"
  fi
fi

if ask_yes_no "Also create a legacy RSA 4096 key (~/.ssh/id_rsa)?" n; then
  if [[ -f "$HOME/.ssh/id_rsa" ]]; then
    ok "~/.ssh/id_rsa already exists"
  else
    info "Creating RSA 4096 SSH key"
    ssh-keygen -t rsa -b 4096 -C "$SSH_COMMENT" -f "$HOME/.ssh/id_rsa"
    ok "RSA SSH key created"
  fi
fi

SSH_CONFIG="$HOME/.ssh/config"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if [[ -f "$HOME/.ssh/id_ed25519" ]] && ! grep -Fq "# >>> ihaveanewmac github >>>" "$SSH_CONFIG"; then
  cat >> "$SSH_CONFIG" <<'EOF'

# >>> ihaveanewmac github >>>
Host github.com
  HostName github.com
  User git
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
# <<< ihaveanewmac github <<<
EOF
  ok "GitHub SSH config added"
fi

if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
  ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" >/dev/null 2>&1 || \
    ssh-add -K "$HOME/.ssh/id_ed25519" >/dev/null 2>&1 || true

  if ask_yes_no "Authenticate GitHub CLI and upload the Ed25519 public key now?" y; then
    if ! gh auth status >/dev/null 2>&1; then
      gh auth login --hostname github.com --git-protocol ssh --web || \
        warn "GitHub authentication was not completed"
    fi

    if gh auth status >/dev/null 2>&1; then
      gh config set git_protocol ssh --host github.com >/dev/null 2>&1 || true
      gh auth setup-git >/dev/null 2>&1 || true

      KEY_TITLE="$MACHINE_HOSTNAME-$(date +%Y-%m-%d)"
      EXISTING_KEYS="$(gh ssh-key list 2>/dev/null || true)"
      PUBLIC_KEY="$(cat "$HOME/.ssh/id_ed25519.pub")"

      if printf '%s\n' "$EXISTING_KEYS" | grep -Fq "$PUBLIC_KEY"; then
        ok "Ed25519 public key is already registered on GitHub"
      elif gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$KEY_TITLE"; then
        ok "SSH public key uploaded to GitHub as '$KEY_TITLE'"
      else
        warn "Could not upload SSH key"
      fi

      info "Testing SSH authentication to GitHub"
      SSH_TEST_OUTPUT="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 || true)"
      if printf '%s' "$SSH_TEST_OUTPUT" | grep -qi "successfully authenticated"; then
        ok "GitHub SSH authentication works"
      else
        warn "GitHub SSH authentication test did not confirm success"
        printf '    %s\n' "$SSH_TEST_OUTPUT" >&2
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Oh My Zsh
# ---------------------------------------------------------------------------
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  ok "Oh My Zsh already installed"
else
  info "Installing Oh My Zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || \
    warn "Oh My Zsh install failed"
fi

ZSHRC="$HOME/.zshrc"
if [[ ! -f "$ZSHRC" ]]; then
  cat > "$ZSHRC" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source "$ZSH/oh-my-zsh.sh"
EOF
  ok "Created ~/.zshrc"
elif [[ -d "$HOME/.oh-my-zsh" ]] && ! grep -Fq 'oh-my-zsh.sh' "$ZSHRC"; then
  warn "~/.zshrc already exists, so it was left untouched."
  warn "Oh My Zsh is installed, but you may want to source it manually."
else
  ok "Existing ~/.zshrc preserved"
fi

# ---------------------------------------------------------------------------
# Font
# ---------------------------------------------------------------------------
bold "Terminal font"
brew_cask "font-meslo-lg-nerd-font"

if ask_yes_no "Also install the legacy powerline/fonts collection?" n; then
  TMP_POWERLINE="$(mktemp -d)"
  info "Installing legacy Powerline fonts"
  if git clone --depth=1 https://github.com/powerline/fonts.git "$TMP_POWERLINE/powerline-fonts"; then
    (
      cd "$TMP_POWERLINE/powerline-fonts"
      ./install.sh
    ) || warn "Legacy Powerline font installer failed"
  else
    warn "Could not clone powerline/fonts"
  fi
  rm -rf "$TMP_POWERLINE"
fi

# ---------------------------------------------------------------------------
# Useful admin/media tooling
# ---------------------------------------------------------------------------
if ask_yes_no "Install networking/admin tools (nmap, iperf3, mtr)?" y; then
  for pkg in nmap iperf3 mtr; do
    brew_formula "$pkg"
  done
fi

if ask_yes_no "Install media tools (ffmpeg, yt-dlp)?" y; then
  for pkg in ffmpeg yt-dlp; do
    brew_formula "$pkg"
  done
fi

# ---------------------------------------------------------------------------
# Power CLI tools
# ---------------------------------------------------------------------------
if ask_yes_no "Install power CLI tools (ripgrep, fd, bat, fzf, tmux, rsync, watch, shellcheck)?" y; then
  POWER_CLI_FORMULAE=(
    ripgrep
    fd
    bat
    fzf
    tmux
    rsync
    watch
    shellcheck
  )
  for pkg in "${POWER_CLI_FORMULAE[@]}"; do
    brew_formula "$pkg"
  done
fi

# ---------------------------------------------------------------------------
# DevOps / infrastructure tooling
# ---------------------------------------------------------------------------
if ask_yes_no "Install DevOps/Kafka workstation tools (kubectl, helm, k9s, terraform, ansible, JDK 17)?" y; then
  DEVOPS_FORMULAE=(
    kubectl
    helm
    k9s
    terraform
    ansible
    openjdk@17
  )
  for pkg in "${DEVOPS_FORMULAE[@]}"; do
    brew_formula "$pkg"
  done

  if [[ -d "$(brew --prefix openjdk@17 2>/dev/null)/libexec/openjdk.jdk" ]]; then
    warn "JDK 17 is installed. Some GUI apps may require linking it into /Library/Java/JavaVirtualMachines manually."
  fi
fi

# ---------------------------------------------------------------------------
# GUI applications
# ---------------------------------------------------------------------------
if ask_yes_no "Install common GUI apps?" y; then
  GUI_CASKS=(
    google-chrome
    visual-studio-code
    docker
    iterm2
    the-unarchiver
    wireguard
  )
  for pkg in "${GUI_CASKS[@]}"; do
    brew_cask "$pkg"
  done
fi

# ---------------------------------------------------------------------------
# OpenAI Codex CLI
# ---------------------------------------------------------------------------
if ask_yes_no "Install OpenAI Codex CLI?" y; then
  if command_exists codex; then
    ok "Codex already installed"
  elif command_exists npm; then
    info "Installing OpenAI Codex CLI"
    if npm install -g @openai/codex; then
      ok "Codex installed"
    else
      warn "Codex installation failed"
    fi
  else
    warn "npm is unavailable; skipping Codex"
  fi
fi

# ---------------------------------------------------------------------------
# Optional Rosetta on Apple Silicon
# ---------------------------------------------------------------------------
if [[ "$(uname -m)" == "arm64" ]]; then
  if ask_yes_no "Install Rosetta 2 for older Intel-only apps?" y; then
    if /usr/bin/pgrep oahd >/dev/null 2>&1; then
      ok "Rosetta appears to be installed"
    else
      info "Installing Rosetta 2"
      sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license || \
        warn "Rosetta installation failed"
    fi
  fi
fi

echo
bold "Bootstrap finished"
echo
echo "Recommended next steps:"
echo "  1. Open a new Terminal window (or run: exec zsh -l)"
echo "  2. Set MesloLGS Nerd Font in your terminal profile"
echo "  3. Start Docker Desktop once so macOS can finish its setup"
echo "  4. GitHub SSH authentication was tested during setup when GitHub login was enabled"
echo "  5. Run: codex   (if installed) and authenticate interactively"
echo
echo "Rerunning this script is supported; already installed packages will be skipped."
