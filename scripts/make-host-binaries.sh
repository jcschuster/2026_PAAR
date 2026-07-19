#!/usr/bin/env bash
# Produce statically linked E prover binaries for the HOST machine in
# host-bin/: `eprover` (first-order) and `eprover-ho` (higher-order).
#
# Static linking makes them independent of the host distribution's glibc, so
# the same binaries built in this Debian devcontainer run on Arch (or any
# other x86_64 Linux). The workspace is bind-mounted from the host, so after
# this script finishes, install them ON THE HOST with e.g.:
#
#     sudo install -m755 host-bin/eprover host-bin/eprover-ho /usr/local/bin/
#     # or, without root:  install -m755 host-bin/* ~/.local/bin/
#
# Runs inside the devcontainer. Uses external/eprover-src (cloned on demand)
# and leaves that tree in the same state build-eprover-ho.sh produces
# (dynamic --enable-ho build), so the two scripts do not fight.
set -euo pipefail

E_VERSION="${E_VERSION:-E-3.5.1}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$REPO_ROOT/external/eprover-src"
OUT="$REPO_ROOT/host-bin"
STATIC_LDFLAGS="-O03 -fno-common -fomit-frame-pointer -static"

say() { printf '\n==> %s\n' "$*"; }

[ -d "$SRC_DIR/.git" ] || "$REPO_ROOT/scripts/build-eprover-ho.sh"
mkdir -p "$OUT"

# --- 1. First-order eprover, static ----------------------------------------
# make clean is required when switching configurations: configure changes
# compile flags but does not invalidate existing object files.
say "Building first-order eprover (static)"
(cd "$SRC_DIR" && ./configure >/dev/null && make clean >/dev/null 2>&1 \
  && make -j"$(nproc)" >/dev/null 2>&1)
rm -f "$SRC_DIR/PROVER/eprover"
make -C "$SRC_DIR/PROVER" eprover LDFLAGS="$STATIC_LDFLAGS" >/dev/null
cp "$SRC_DIR/PROVER/eprover" "$OUT/eprover"

# --- 2. Higher-order eprover-ho, static ------------------------------------
say "Building higher-order eprover-ho (static)"
(cd "$SRC_DIR" && ./configure --enable-ho >/dev/null && make clean >/dev/null 2>&1 \
  && make -j"$(nproc)" >/dev/null 2>&1)
rm -f "$SRC_DIR/PROVER/eprover-ho"
make -C "$SRC_DIR/PROVER" eprover-ho LDFLAGS="$STATIC_LDFLAGS" >/dev/null
cp "$SRC_DIR/PROVER/eprover-ho" "$OUT/eprover-ho"

# --- 3. Leave the tree as build-eprover-ho.sh expects (dynamic HO) ----------
say "Restoring dynamic --enable-ho build in the source tree"
rm -f "$SRC_DIR/PROVER/eprover-ho"
make -C "$SRC_DIR/PROVER" eprover-ho >/dev/null

# --- 4. Verify --------------------------------------------------------------
for b in eprover eprover-ho; do
  if ldd "$OUT/$b" >/dev/null 2>&1; then
    echo "ERROR: $OUT/$b is not statically linked" >&2; exit 1
  fi
  chmod 755 "$OUT/$b"
done
say "Done. Host binaries in host-bin/:"
"$OUT/eprover" --version
"$OUT/eprover-ho" --version
echo
echo "On the host:  sudo install -m755 host-bin/eprover host-bin/eprover-ho /usr/local/bin/"
