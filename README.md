# ihaveanewmac

Opinionated, rerunnable macOS bootstrap for a fresh Mac.

## Quick start

> The repository is currently private. The one-line installer will work without authentication after the repository is public.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sipeti/ihaveanewmac/main/bootstrap.sh)
```

Or:

```bash
git clone https://github.com/sipeti/ihaveanewmac.git
cd ihaveanewmac
./bootstrap.sh
```

## Profiles

`minimal`

- Apple Command Line Tools
- Homebrew
- Git + GitHub CLI
- jq, wget, tree, htop
- Node.js, pipx
- ripgrep, fd, bat, fzf, tmux, rsync, watch, shellcheck
- ssh-copy-id
- Google Chrome
- iTerm2
- The Unarchiver
- Meslo Nerd Font
- zsh-autosuggestions
- zsh-syntax-highlighting
- Oh My Zsh with the `agnoster` theme

`dev`

Everything in `minimal`, plus:

- Python
- pyenv
- uv
- kcat
- Docker Desktop
- WireGuard
- nmap, iperf3, mtr
- kubectl, helm, k9s
- Terraform
- Ansible
- SDKMAN
- Temurin Java 17 + 21
- OpenAI Codex CLI

`studio`

Everything in `minimal`, plus:

- ffmpeg
- yt-dlp
- VLC
- OBS
- Docker Desktop
- nmap, iperf3, mtr

`full`

Union of `dev` and `studio`.

## Usage

Interactive:

```bash
./bootstrap.sh
```

Choose a profile directly:

```bash
./bootstrap.sh --profile dev
./bootstrap.sh --profile studio
./bootstrap.sh --profile full
```

Set the machine name too:

```bash
./bootstrap.sh --profile dev --hostname sipeti-mbp
```

Accept default answers:

```bash
./bootstrap.sh --profile dev --hostname sipeti-mbp --yes
```

Preview the resolved plan without changing the Mac:

```bash
./bootstrap.sh --profile dev --hostname sipeti-mbp --dry-run
```

## Brewfile layout

Packages are intentionally kept outside the main installer:

```text
Brewfile.minimal
Brewfile.dev
Brewfile.studio
```

The `full` profile installs both the dev and studio Brewfiles after the minimal one.

This keeps package maintenance separate from provisioning logic.

## macOS identity

The installer can configure:

- `ComputerName`
- `LocalHostName`
- `HostName`

The DNS-style hostname is generated from the friendly Mac name.

## Git and GitHub

The installer can configure global Git identity and these defaults:

```text
init.defaultBranch = main
fetch.prune = true
push.autoSetupRemote = true
core.autocrlf = input
pull.rebase = false
rerere.enabled = true
```

It also creates `~/.gitignore_global` and ignores `.DS_Store`.

GitHub SSH setup uses Ed25519 by default:

```text
~/.ssh/id_ed25519
~/.ssh/id_ed25519.pub
```

An RSA 4096 key is optional for legacy use.

Existing private keys are never overwritten.

The script can:

- add a managed GitHub block to `~/.ssh/config`
- add the Ed25519 key to the macOS keychain/ssh-agent
- run `gh auth login`
- configure GitHub CLI for SSH
- upload the public key
- test `ssh -T git@github.com`

## Shell

The default shell configuration is stored in:

```text
config/zshrc
```

It uses:

```text
ZSH_THEME="agnoster"
```

and enables:

- git
- macos
- docker
- docker-compose
- zsh-autosuggestions
- zsh-syntax-highlighting

If `~/.zshrc` already exists, it is preserved. The installer can optionally back it up and replace it with the managed starting point.

Shared aliases live in:

```text
config/aliases.zsh
```

and are installed to:

```text
~/.config/ihaveanewmac/aliases.zsh
```

The current aliases cover common Git, Docker, kubectl and kcat workflows without bloating `~/.zshrc`.

SDKMAN initialization stays near the end of the managed shell configuration.

The old `powerline/fonts` repository remains available as an optional legacy installation; Meslo Nerd Font is the default.

## Java

For `dev` and `full`, Java is managed through SDKMAN rather than Homebrew.

The installer attempts to install current Temurin builds for:

- Java 17
- Java 21

and sets Java 21 as the default when available.

## macOS defaults

The optional defaults script currently configures:

- Finder file extensions
- Finder path bar
- Finder status bar
- list view
- no extension-change warning
- no `.DS_Store` on network volumes
- no `.DS_Store` on USB volumes
- faster keyboard repeat
- Dock auto-hide
- no recent apps in Dock
- PNG screenshots
- screenshots under `~/Pictures/Screenshots`

The settings live in:

```text
scripts/macos-defaults.sh
```

A second optional preference pass asks individually about:

- showing hidden files
- showing `~/Library`
- tap-to-click
- disabling natural scrolling
- requiring a password immediately after sleep/screensaver
- preventing system sleep while on AC power

Those settings are implemented in:

```text
scripts/macos-preferences.sh
```

## Docker check

For non-minimal profiles, if Docker Desktop is installed, the bootstrap can:

1. start Docker Desktop
2. wait for the engine
3. run `docker run --rm hello-world`

## Design rules

- never run the entire bootstrap with `sudo`
- only request elevation when macOS itself requires it
- do not overwrite SSH private keys
- preserve an existing `~/.zshrc` unless the user explicitly chooses replacement
- keep package lists in Brewfiles
- keep credentials, tokens and machine-specific secrets out of the repository
- make reruns safe where practical
- keep `--dry-run` non-destructive
