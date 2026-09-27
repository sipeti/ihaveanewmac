# ihaveanewmac

Opinionated, rerunnable macOS bootstrap for a fresh Mac.

The goal is to turn a newly installed Mac into a useful development / admin workstation with as little manual setup as possible, while still asking before installing optional groups.

## Quick start

> The repository is currently private. The one-line installer below will work without authentication after the repository is made public.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sipeti/ihaveanewmac/main/bootstrap.sh)
```

Or clone it and run locally:

```bash
git clone https://github.com/sipeti/ihaveanewmac.git
cd ihaveanewmac
./bootstrap.sh
```

## What it can install

- Mac hostname / ComputerName setup
- Apple Command Line Tools (`xcode-select`)
- Homebrew, with PATH setup for Apple Silicon and Intel
- CLI/dev tools: Git, GitHub CLI, jq, wget, tree, htop, Python, pipx, Node.js
- media tools: ffmpeg, yt-dlp
- networking/admin tools: nmap, iperf3, mtr
- GUI apps: Docker Desktop, Google Chrome, Visual Studio Code, iTerm2, The Unarchiver, WireGuard
- Oh My Zsh
- Meslo Nerd Font (Powerline-compatible glyphs)
- optional legacy `powerline/fonts`
- OpenAI Codex CLI
- GitHub SSH setup with Ed25519 keys
- optional legacy RSA 4096 SSH key
- optional GitHub CLI authentication and SSH public-key upload

The script is intended to be **idempotent-ish**: already installed components are detected and skipped where practical. Homebrew package installs are safe to rerun.

## Modes

Interactive mode is the default.

```bash
./bootstrap.sh
```

Install the normal defaults without package-group questions:

```bash
./bootstrap.sh --yes
```

Show options:

```bash
./bootstrap.sh --help
```

## Design rules

- Do not run the whole script with `sudo`.
- Ask for elevated privileges only when an underlying installer needs them.
- Do not overwrite an existing `~/.zshrc`.
- Add Homebrew to `~/.zprofile` using a small managed block.
- Optional app failures should be reported without making the entire bootstrap useless.
- No credentials, API keys, SSH keys or machine-specific secrets belong in this repository.

## Notes

The original Powerline fonts repository is still available, but the default setup uses Meslo Nerd Font via Homebrew. It provides the glyph coverage normally wanted for modern Zsh prompts without cloning and installing the entire legacy font collection.

Codex CLI is installed with:

```bash
npm install -g @openai/codex
```

Authentication remains interactive and is intentionally not automated.


## Hostname and SSH

At startup the installer asks for the Mac's name and configures:

- `ComputerName`
- `LocalHostName`
- `HostName`

For GitHub SSH access, Ed25519 is the default and recommended key type:

```text
~/.ssh/id_ed25519
~/.ssh/id_ed25519.pub
```

A 4096-bit RSA key can also be generated when legacy compatibility is required:

```text
~/.ssh/id_rsa
~/.ssh/id_rsa.pub
```

Existing private keys are never overwritten.

The installer also adds a managed `github.com` block to `~/.ssh/config`, loads the Ed25519 key into the macOS keychain/ssh-agent, and can launch `gh auth login` and upload the public key to GitHub.
