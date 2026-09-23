#!/usr/bin/env bash
# Build the qemu formula from this checkout locally.
#
# By default builds from source and installs it. Set BOTTLE=1 to also produce a
# redistributable bottle instead of a plain source install.
#
# Behind a corporate TLS-inspecting proxy (e.g. Zscaler), point SRC_CERT at your
# root CA bundle (or drop it at ~/.config/homebrew-certs/ca.pem) and it will be
# wired into Homebrew's curl, pip, git and meson downloads.
#
# Usage:
#   scripts/build.sh                 # build from source + install
#   BOTTLE=1 scripts/build.sh        # build a bottle
#   SIGN=1 scripts/build.sh          # ad-hoc re-sign + hvf entitlement after install
#   SRC_CERT=/path/ca.pem scripts/build.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP="mikeeq/qemu-virgl-kosmickrisp"
TAP_DIR="$(brew --repository)/Library/Taps/mikeeq/homebrew-qemu-virgl-kosmickrisp"

command -v brew >/dev/null || { echo "Homebrew is required." >&2; exit 1; }

# --- Optional: corporate root CA for downloads behind a TLS proxy ------------
SRC_CERT="${SRC_CERT:-${HOME}/.config/homebrew-certs/ca.pem}"
if [[ -r "$SRC_CERT" ]]; then
  CERT_DIR="$HOME/.config/homebrew-certs"
  mkdir -p "$CERT_DIR"
  CA_CERT="$CERT_DIR/ca.pem"
  [[ "$SRC_CERT" == "$CA_CERT" ]] || cp -f "$SRC_CERT" "$CA_CERT"
  chmod 644 "$CA_CERT"

  export SSL_CERT_FILE="$CA_CERT"
  export REQUESTS_CA_BUNDLE="$CA_CERT"
  export PIP_CERT="$CA_CERT"
  export CURL_CA_BUNDLE="$CA_CERT"
  export GIT_SSL_CAINFO="$CA_CERT"
  export NODE_EXTRA_CA_CERTS="$CA_CERT"
  export NPM_CONFIG_CAFILE="$CA_CERT"

  CURLRC="$CERT_DIR/curlrc"
  printf 'cacert = %s\n' "$CA_CERT" > "$CURLRC"
  export HOMEBREW_CURLRC="$CURLRC"
  export HOMEBREW_NO_SANDBOX=1
  echo "Using corporate CA bundle: $CA_CERT"
fi

# --- Point Homebrew at this working copy as a local tap ----------------------
mkdir -p "$(dirname "$TAP_DIR")"
if [[ -L "$TAP_DIR" || ! -e "$TAP_DIR" ]]; then
  ln -sfn "$REPO_ROOT" "$TAP_DIR"
  echo "Linked tap $TAP -> $REPO_ROOT"
else
  echo "Tap dir already exists and is not a symlink: $TAP_DIR" >&2
  echo "Remove it or run: brew untap $TAP" >&2
  exit 1
fi

# Use the local formula, not the JSON API.
export HOMEBREW_NO_INSTALL_FROM_API=1

echo "==> Auditing formula"
brew audit --formula --strict "$TAP/qemu" || true

brew uninstall qemu --force >/dev/null 2>&1 || true

if [[ "${BOTTLE:-0}" == "1" ]]; then
  echo "==> Building bottle"
  brew install --build-bottle "$TAP/qemu"
  brew link --overwrite qemu || true
  brew bottle --json --force-core-tap "$TAP_DIR/Formula/qemu.rb"
  echo "Bottle written to: $(pwd)"
else
  echo "==> Building from source and installing"
  brew install --build-from-source "$TAP/qemu"
fi

# --- Optional: repair signatures + add hvf entitlement -----------------------
if [[ "${SIGN:-0}" == "1" ]]; then
  echo "==> Re-signing qemu for HVF"
  QEMU_PREFIX="$(brew --prefix qemu)"
  ENT="$(mktemp -t qemu-ent).plist"
  cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.hypervisor</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
PLIST
  for bin in "$QEMU_PREFIX"/bin/qemu-system-*; do
    [[ -f "$bin" ]] || continue
    codesign --force --sign - --timestamp=none --entitlements "$ENT" "$bin"
    echo "signed: $bin"
  done
  rm -f "$ENT"
fi

echo
echo "Done. Verify user-mode networking:"
echo "  qemu-system-aarch64 -M virt -netdev help | grep -x user"
