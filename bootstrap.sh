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
echo "  4. Run: gh auth login"
echo "  5. Run: codex   (if installed) and authenticate interactively"
echo
echo "Rerunning this script is supported; already installed packages will be skipped."
