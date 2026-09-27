#!/usr/bin/env bash
set -uo pipefail

apply_bool() {
  local domain="$1"
  local key="$2"
  local value="$3"
  defaults write "$domain" "$key" -bool "$value"
}

echo "Applying optional macOS preferences..."

if [[ "${SHOW_HIDDEN_FILES:-0}" == "1" ]]; then
  defaults write com.apple.finder AppleShowAllFiles -bool true
fi

if [[ "${SHOW_USER_LIBRARY:-0}" == "1" ]]; then
  chflags nohidden "$HOME/Library" || true
fi

if [[ "${TAP_TO_CLICK:-0}" == "1" ]]; then
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
  defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
fi

if [[ "${DISABLE_NATURAL_SCROLLING:-0}" == "1" ]]; then
  defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
fi

if [[ "${REQUIRE_PASSWORD_IMMEDIATELY:-0}" == "1" ]]; then
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0
fi

if [[ "${PREVENT_SLEEP_ON_AC:-0}" == "1" ]]; then
  sudo pmset -c sleep 0
fi

killall Finder >/dev/null 2>&1 || true
killall SystemUIServer >/dev/null 2>&1 || true

echo "Optional macOS preferences applied."
