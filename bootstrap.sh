#!/usr/bin/env bash
set -uo pipefail

REPO="sipeti/ihaveanewmac"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
YES=0
PROFILE=""
HOSTNAME_ARG=""

usage() {
  cat <<'EOF'
ihaveanewmac - macOS bootstrap

Usage:
  ./bootstrap.sh
  ./bootstrap.sh --profile minimal|dev|studio|full
  ./bootstrap.sh --hostname my-mac
  ./bootstrap.sh --profile dev --hostname sipeti-mbp --yes

Options:
  --profile NAME     minimal, dev, studio or full
  --hostname NAME    set ComputerName/LocalHostName/HostName
  --yes, -y          accept default answers
  --help, -h         show help

Do not run this script with sudo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --hostname)
      HOSTNAME_ARG="${2:-}"
      shift 2
      ;;
    --yes|-y)
      YES=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

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

fetch_repo_file() {
  local path="$1"
  local target="$2"

  if [[ -f "$path" ]]; then
    cp "$path" "$target"
  else
    curl -fsSL "$RAW_BASE/$path" -o "$target"
  fi
}

choose_profile() {
  if [[ -n "$PROFILE" ]]; then
    return
  fi

  if [[ "$YES" -eq 1 ]]; then
    PROFILE="dev"
    return
  fi

  echo "Profiles:"
  echo "  minimal - shell, Git/GitHub, browser, terminal and core CLI tools"
  echo "  dev     - minimal + Python/pyenv/uv, Docker, kcat, DevOps, SDKMAN/JDK"
  echo "  studio  - minimal + ffmpeg, yt-dlp, VLC, OBS, Docker, network tools"
  echo "  full    - dev + studio"
  echo
  read -r -p "Profile [dev]: " PROFILE
  PROFILE="${PROFILE:-dev}"
}

choose_profile
case "$PROFILE" in
  minimal|dev|studio|full) ;;
  *)
    echo "Invalid profile: $PROFILE"
    exit 1
    ;;
esac

bold "ihaveanewmac"
echo "Profile: $PROFILE"
echo

# ---------------------------------------------------------------------------
# Mac identity / hostname
# ---------------------------------------------------------------------------
CURRENT_COMPUTER_NAME="$(scutil --get ComputerName 2>/dev/null || hostname)"
if [[ -n "$HOSTNAME_ARG" ]]; then
  MACHINE_NAME="$HOSTNAME_ARG"
elif [[ "$YES" -eq 1 ]]; then
  MACHINE_NAME="$CURRENT_COMPUTER_NAME"
else
  read -r -p "Mac name [$CURRENT_COMPUTER_NAME]: " MACHINE_NAME
  MACHINE_NAME="${MACHINE_NAME:-$CURRENT_COMPUTER_NAME}"
fi

MACHINE_HOSTNAME="$(printf '%s' "$MACHINE_NAME" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
[[ -n "$MACHINE_HOSTNAME" ]] || MACHINE_HOSTNAME="mac"

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
  echo "Finish the macOS Command Line Tools installer, then press Enter."
  read -r
  xcode-select -p >/dev/null 2>&1 || warn "Command Line Tools still not detected"
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

[[ -n "${BREW_BIN:-}" ]] || { echo "Homebrew installation failed."; exit 1; }
eval "$("$BREW_BIN" shellenv)"

ZPROFILE="$HOME/.zprofile"
if ! grep -Fq "# >>> ihaveanewmac homebrew >>>" "$ZPROFILE" 2>/dev/null; then
  {
    echo
    echo "# >>> ihaveanewmac homebrew >>>"
    echo "eval \"\$($BREW_BIN shellenv)\""
    echo "# <<< ihaveanewmac homebrew <<<"
  } >> "$ZPROFILE"
fi

info "Updating Homebrew metadata"
brew update || warn "brew update failed; continuing"

# ---------------------------------------------------------------------------
# Brewfiles / profiles
# ---------------------------------------------------------------------------
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

install_brewfile() {
  local name="$1"
  local file="$TMP_DIR/Brewfile.$name"
  info "Installing Brewfile.$name"
  fetch_repo_file "Brewfile.$name" "$file"
  brew bundle --file="$file" || warn "Some packages from Brewfile.$name failed"
}

install_brewfile minimal
case "$PROFILE" in
  dev)
    install_brewfile dev
    ;;
  studio)
    install_brewfile studio
    ;;
  full)
    install_brewfile dev
    install_brewfile studio
    ;;
esac

command_exists pipx && pipx ensurepath >/dev/null 2>&1 || true

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

[[ -n "$GIT_NAME" ]] && git config --global user.name "$GIT_NAME"
[[ -n "$GIT_EMAIL" ]] && git config --global user.email "$GIT_EMAIL"
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
# SSH / GitHub
# ---------------------------------------------------------------------------
bold "SSH / GitHub"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
SSH_COMMENT="${GIT_EMAIL:-$USER@$MACHINE_HOSTNAME}"

if [[ ! -f "$HOME/.ssh/id_ed25519" ]] && ask_yes_no "Create GitHub Ed25519 key?" y; then
  ssh-keygen -t ed25519 -C "$SSH_COMMENT" -f "$HOME/.ssh/id_ed25519"
fi

if ask_yes_no "Also create a legacy RSA 4096 key?" n; then
  [[ -f "$HOME/.ssh/id_rsa" ]] || ssh-keygen -t rsa -b 4096 -C "$SSH_COMMENT" -f "$HOME/.ssh/id_rsa"
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
fi

if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
  ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" >/dev/null 2>&1 || \
    ssh-add -K "$HOME/.ssh/id_ed25519" >/dev/null 2>&1 || true

  if ask_yes_no "Authenticate GitHub and upload this SSH key?" y; then
    gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol ssh --web || true
    if gh auth status >/dev/null 2>&1; then
      gh config set git_protocol ssh --host github.com >/dev/null 2>&1 || true
      gh auth setup-git >/dev/null 2>&1 || true
      KEY_TITLE="$MACHINE_HOSTNAME-$(date +%Y-%m-%d)"
      PUBLIC_KEY="$(cat "$HOME/.ssh/id_ed25519.pub")"
      EXISTING_KEYS="$(gh ssh-key list 2>/dev/null || true)"
      if printf '%s\n' "$EXISTING_KEYS" | grep -Fq "$PUBLIC_KEY"; then
        ok "SSH key already registered on GitHub"
      else
        gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$KEY_TITLE" || warn "SSH key upload failed"
      fi
      SSH_TEST_OUTPUT="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 || true)"
      printf '%s' "$SSH_TEST_OUTPUT" | grep -qi "successfully authenticated" \
        && ok "GitHub SSH authentication works" \
        || warn "GitHub SSH authentication test did not confirm success"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Oh My Zsh / agnoster
# ---------------------------------------------------------------------------
bold "Shell"

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  info "Installing Oh My Zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    || warn "Oh My Zsh install failed"
fi

ZSHRC="$HOME/.zshrc"
ZSHRC_TEMPLATE="$TMP_DIR/zshrc"
fetch_repo_file "config/zshrc" "$ZSHRC_TEMPLATE"

if [[ ! -f "$ZSHRC" ]]; then
  cp "$ZSHRC_TEMPLATE" "$ZSHRC"
  ok "Created ~/.zshrc with agnoster theme"
elif grep -Fq "# Managed starting point for ihaveanewmac." "$ZSHRC"; then
  ok "ihaveanewmac ~/.zshrc already exists"
else
  warn "Existing ~/.zshrc preserved"
  if ask_yes_no "Back it up and replace it with the ihaveanewmac agnoster config?" n; then
    cp "$ZSHRC" "$ZSHRC.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$ZSHRC_TEMPLATE" "$ZSHRC"
    ok "Installed managed agnoster ~/.zshrc"
  fi
fi

# ---------------------------------------------------------------------------
# SDKMAN / Java for dev/full
# ---------------------------------------------------------------------------
if [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]; then
  bold "SDKMAN / Java"

  if [[ ! -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    info "Installing SDKMAN"
    curl -s "https://get.sdkman.io?rcupdate=false" | bash
  fi

  if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.sdkman/bin/sdkman-init.sh"

    install_temurin_major() {
      local major="$1"
      local version
      version="$(sdk list java 2>/dev/null | awk -v m="$major" '$0 ~ /Temurin/ {vendor=1; next} vendor && $0 ~ m"\." && $0 ~ /-tem/ {for(i=1;i<=NF;i++) if($i ~ "^"m"\." && $i ~ /-tem$/) {print $i; exit}}')"
      if [[ -z "$version" ]]; then
        version="$(sdk list java 2>/dev/null | awk -v m="$major" '{for(i=1;i<=NF;i++) if($i ~ "^"m"\." && $i ~ /-tem$/) {print $i; exit}}')"
      fi

      if [[ -n "$version" ]]; then
        if [[ -d "$HOME/.sdkman/candidates/java/$version" ]]; then
          ok "Java $version already installed"
        else
          yes | sdk install java "$version" || warn "Java $major Temurin install failed"
        fi
      else
        warn "Could not resolve a Temurin Java $major build from SDKMAN"
      fi
    }

    install_temurin_major 17
    install_temurin_major 21

    JAVA21="$(sdk list java 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ "^21\." && $i ~ /-tem$/) {print $i; exit}}')"
    [[ -n "$JAVA21" ]] && sdk default java "$JAVA21" >/dev/null 2>&1 || true
  fi
fi

# ---------------------------------------------------------------------------
# macOS defaults
# ---------------------------------------------------------------------------
if ask_yes_no "Apply opinionated macOS defaults (Finder, Dock, keyboard, screenshots)?" y; then
  DEFAULTS_SCRIPT="$TMP_DIR/macos-defaults.sh"
  fetch_repo_file "scripts/macos-defaults.sh" "$DEFAULTS_SCRIPT"
  bash "$DEFAULTS_SCRIPT" || warn "Some macOS defaults could not be applied"
fi

# ---------------------------------------------------------------------------
# Codex CLI
# ---------------------------------------------------------------------------
if [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]; then
  if ask_yes_no "Install OpenAI Codex CLI?" y; then
    if command_exists codex; then
      ok "Codex already installed"
    elif command_exists npm; then
      npm install -g @openai/codex || warn "Codex installation failed"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Rosetta
# ---------------------------------------------------------------------------
if [[ "$(uname -m)" == "arm64" ]] && ask_yes_no "Install Rosetta 2?" y; then
  if /usr/bin/pgrep oahd >/dev/null 2>&1; then
    ok "Rosetta appears to be installed"
  else
    sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license || warn "Rosetta install failed"
  fi
fi

# ---------------------------------------------------------------------------
# Docker sanity check
# ---------------------------------------------------------------------------
if [[ "$PROFILE" != "minimal" ]] && [[ -d "/Applications/Docker.app" ]]; then
  if ask_yes_no "Start Docker Desktop and run a sanity check?" y; then
    open -a Docker
    for _ in {1..60}; do
      docker info >/dev/null 2>&1 && break
      sleep 2
    done

    if docker info >/dev/null 2>&1; then
      docker run --rm hello-world >/dev/null 2>&1 \
        && ok "Docker engine works" \
        || warn "Docker started, but hello-world failed"
    else
      warn "Docker Desktop did not become ready during the sanity check"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
bold "Installation summary"
printf '  %-16s %s\n' "Profile:" "$PROFILE"
printf '  %-16s %s\n' "ComputerName:" "$(scutil --get ComputerName 2>/dev/null || true)"
printf '  %-16s %s\n' "HostName:" "$(scutil --get HostName 2>/dev/null || true)"
printf '  %-16s %s\n' "macOS:" "$(sw_vers -productVersion)"
printf '  %-16s %s\n' "Architecture:" "$(uname -m)"
printf '  %-16s %s\n' "Homebrew:" "$(brew --prefix 2>/dev/null || echo missing)"
printf '  %-16s %s\n' "Git:" "$(git --version 2>/dev/null || echo missing)"
printf '  %-16s %s\n' "Python:" "$(python3 --version 2>/dev/null || echo missing)"
printf '  %-16s %s\n' "Node:" "$(node --version 2>/dev/null || echo missing)"
if command_exists java; then
  printf '  %-16s %s\n' "Java:" "$(java -version 2>&1 | head -n1)"
fi
if command_exists docker; then
  printf '  %-16s %s\n' "Docker:" "$(docker --version 2>/dev/null || echo installed/not running)"
fi
if command_exists kcat; then
  printf '  %-16s %s\n' "kcat:" "$(kcat -V 2>&1 | head -n1)"
fi
if gh auth status >/dev/null 2>&1; then
  printf '  %-16s %s\n' "GitHub:" "authenticated"
else
  printf '  %-16s %s\n' "GitHub:" "not authenticated"
fi

echo
echo "Open a new terminal (or run: exec zsh -l) to load the final shell environment."
