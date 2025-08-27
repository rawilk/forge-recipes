#!/usr/bin/env bash

# This script is useful if you are using website isolation in Forge and want to use a global
# nvm installation to manage node and npm.

set -euo pipefail

# Config
NVM_DIR="/opt/nvm"
PROFILE_SNIPPET="/etc/profile.d/nvm.sh"
STABLE_LINK="/opt/nvm/current"

# Ensure we are running as root; if not, re-exec via sudo to "enter sudo mode".
# Uses sudo -E to preserve environment where appropriate. If sudo is unavailable
# or the user declines, the script exits with a clear message.
require_root() {
  local uid
  uid="${EUID:-$(id -u)}"
  if [[ "$uid" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      echo "🔐 Elevating privileges with sudo..." >&2
      # Re-exec this script with the same arguments under sudo, preserving env.
      exec sudo -E -- "$0" "$@"
    else
      echo "✋ This script requires root privileges, and 'sudo' was not found. Please run as root." >&2
      exit 1
    fi
  fi
}

check_prereqs() {
  if [[ ! -d "$NVM_DIR" ]]; then
    echo "❌ $NVM_DIR not found. Install shared nvm to /opt/nvm first." >&2
    exit 1
  fi

  if [[ ! -f "$PROFILE_SNIPPET" ]]; then
    echo "❌ $PROFILE_SNIPPET not found. Create it so all shells load nvm:" >&2
    echo '    echo -e "export NVM_DIR=\"/opt/nvm\"\n[ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"" | sudo tee /etc/profile.d/nvm.sh' >&2
    exit 1
  fi
}

load_nvm() {
  . "$PROFILE_SNIPPET"
  if ! command -v nvm >/dev/null 2>&1; then
    echo "❌ nvm not available after sourcing $PROFILE_SNIPPET" >&2
    exit 1
  fi
}

prompt_version() {
  local arg="${1:-}"
  if [[ -n "$arg" ]]; then
    VERSION_SPEC="$arg"
  else
    read -rp "Enter Node version to use (e.g. 24 or 24.3.0): " VERSION_SPEC
  fi

  VERSION_SPEC="${VERSION_SPEC#v}"  # allow 'v24' or 'v24.3.0'
  if [[ -z "$VERSION_SPEC" ]]; then
    echo "❌ No version provided." >&2
    exit 1
  fi
}

install_version_if_needed() {
  echo "🔎 Ensuring Node $VERSION_SPEC is installed in shared nvm ..."
  # nvm install is idempotent; it will skip if already installed
  nvm install "$VERSION_SPEC" >/dev/null
  # Resolve to the canonical 'vX.Y.Z'
  RESOLVED_VERSION="$(nvm version "$VERSION_SPEC")"
  if [[ "$RESOLVED_VERSION" == "N/A" ]]; then
    echo "❌ Could not resolve version '$VERSION_SPEC'." >&2
    exit 1
  fi
  TARGET_DIR="$NVM_DIR/versions/node/$RESOLVED_VERSION"
  if [[ ! -x "$TARGET_DIR/bin/node" ]]; then
    echo "❌ Node binary not found at $TARGET_DIR/bin/node" >&2
    exit 1
  fi
  echo "✅ Using $RESOLVED_VERSION at $TARGET_DIR"
}

make_default_and_enable_corepack() {
  echo "🔧 Setting default Node to $RESOLVED_VERSION ..."
  nvm alias default "$RESOLVED_VERSION" >/dev/null
  nvm use --silent default >/dev/null
  # Optional: make yarn/pnpm available consistently
  if command -v corepack >/dev/null 2>&1; then
    corepack enable >/dev/null || true
  fi
}

update_symlinks() {
  echo "🔗 Updating stable symlink $STABLE_LINK -> $TARGET_DIR ..."
  ln -sfn "$TARGET_DIR" "$STABLE_LINK"

  echo "🔗 Refreshing /usr/bin symlinks to stable 'current' ..."
  ln -sfn "$STABLE_LINK/bin/node" /usr/bin/node
  ln -sfn "$STABLE_LINK/bin/npm"  /usr/bin/npm
  ln -sfn "$STABLE_LINK/bin/npx"  /usr/bin/npx
}

verify() {
  echo "✔️  Verifying:"
  echo -n "node: "; /usr/bin/node -v
  echo -n "npm:  "; /usr/bin/npm -v
  echo -n "path: "; which node
}

main() {
    require_root "$@"
    check_prereqs
    load_nvm
    prompt_version "${1:-}"
    install_version_if_needed
    make_default_and_enable_corepack
    update_symlinks
    verify
}

main "$@"
