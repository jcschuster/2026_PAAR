#!/usr/bin/env bash
# Build E prover in higher-order mode (./configure --enable-ho -> eprover-ho)
# and install it onto PATH (/usr/local/bin).
#
# Idempotent, and safe to re-run after a devcontainer rebuild: the source tree
# and built binaries live in the workspace (external/eprover-src, survives
# rebuilds); only the cheap install step is repeated.
#
# The stock /usr/bin/eprover (used by the atp_mcp local_exec backend) is left
# untouched — only `eprover-ho` is installed.
#
# Usage: scripts/build-eprover-ho.sh [--force]
# Env:   E_VERSION  git tag to build (default: E-3.5.1)
set -euo pipefail

E_VERSION="${E_VERSION:-E-3.5.1}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$REPO_ROOT/external/eprover-src"
BIN="$SRC_DIR/PROVER/eprover-ho"
FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

say() { printf '\n==> %s\n' "$*"; }

# --- Fetch source -----------------------------------------------------------
if [ ! -d "$SRC_DIR/.git" ]; then
  say "Cloning eprover ($E_VERSION)"
  git clone --depth 1 --branch "$E_VERSION" \
    https://github.com/eprover/eprover.git "$SRC_DIR"
elif [ "$(git -C "$SRC_DIR" describe --tags --always)" != "$E_VERSION" ]; then
  say "Switching eprover source to $E_VERSION"
  git -C "$SRC_DIR" fetch --depth 1 origin tag "$E_VERSION"
  git -C "$SRC_DIR" checkout -f "$E_VERSION"
  FORCE=true
fi

# --- Build ------------------------------------------------------------------
if [ ! -x "$BIN" ] || $FORCE; then
  say "Configuring with --enable-ho"
  (cd "$SRC_DIR" && ./configure --enable-ho)
  say "Building (make -j$(nproc))"
  (cd "$SRC_DIR" && make -j"$(nproc)")
  [ -x "$BIN" ] || { echo "ERROR: $BIN was not produced" >&2; exit 1; }
else
  say "eprover-ho already built ($BIN); use --force to rebuild."
fi

# --- Install onto PATH ------------------------------------------------------
if ! cmp -s "$BIN" /usr/local/bin/eprover-ho 2>/dev/null; then
  say "Installing eprover-ho to /usr/local/bin"
  sudo install -m 755 "$BIN" /usr/local/bin/eprover-ho
else
  say "/usr/local/bin/eprover-ho already up to date."
fi

say "Done: $(eprover-ho --version)"
