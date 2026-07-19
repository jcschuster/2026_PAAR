#!/usr/bin/env bash
# Build a ready-to-submit StarExec solver archive for eprover-ho.
#
# Produces starexec/eprover-ho-<version>-starexec.zip containing
#   starexec_description.txt   solver description (auto-read on upload)
#   bin/eprover-ho             statically linked higher-order E (mode 755)
#   bin/starexec_run_eprover-ho        default config: auto-schedule, proofs
#   bin/starexec_run_eprover-ho-sat    config for sat/counter-sat problems
#
# The binary is linked statically so it runs on StarExec hosts regardless of
# their (usually much older) glibc. Requires a prior scripts/build-eprover-ho.sh
# run (the script calls it if needed).
set -euo pipefail

E_VERSION="${E_VERSION:-E-3.5.1}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$REPO_ROOT/external/eprover-src"
OUT_DIR="$REPO_ROOT/starexec"
VER="${E_VERSION#E-}"
PKG="$OUT_DIR/build/eprover-ho-$VER"
ZIP="$OUT_DIR/eprover-ho-$VER-starexec.zip"

say() { printf '\n==> %s\n' "$*"; }

[ -x "$SRC_DIR/PROVER/eprover-ho" ] || "$REPO_ROOT/scripts/build-eprover-ho.sh"

# --- Static relink ----------------------------------------------------------
say "Relinking eprover-ho statically"
rm -f "$SRC_DIR/PROVER/eprover-ho"
make -C "$SRC_DIR/PROVER" eprover-ho \
  LDFLAGS="-O03 -fno-common -fomit-frame-pointer -static" >/dev/null
if ldd "$SRC_DIR/PROVER/eprover-ho" >/dev/null 2>&1; then
  echo "WARNING: static link did not take; shipping dynamically linked binary." >&2
  STATIC_NOTE="dynamically linked, static link unavailable on build host"
else
  STATIC_NOTE="statically linked"
fi

# --- Package tree -----------------------------------------------------------
say "Assembling package in $PKG"
rm -rf "$PKG" && mkdir -p "$PKG/bin"
cp "$SRC_DIR/PROVER/eprover-ho" "$PKG/bin/eprover-ho"

# StarExec's description validator rejects several characters, notably
# hyphens, plus signs, parentheses, ampersands, semicolons and quotes —
# keep this text free of them (verified against StarExec empirically).
cat > "$PKG/starexec_description.txt" <<EOF
E $VER built in higher order mode, $STATIC_NOTE. E is a superposition based
theorem prover for full first order logic with equality, with higher order
extensions. It accepts FOF, TFF and THF in TPTP syntax and reports SZS
statuses with proof objects. The default configuration runs an automatic
strategy schedule with proof output. The sat configuration targets
satisfiability and counter satisfiability. Author: Stephan Schulz and
contributors. Source: github.com/eprover/eprover
EOF

cat > "$PKG/bin/starexec_run_eprover-ho" <<'EOF'
#!/bin/sh
# Default configuration: proof search with automatic strategy schedule.
# $1 = benchmark file; StarExec provides the resource-limit variables.
MEM_OPT=""
[ -n "$STAREXEC_MAX_MEM" ] && MEM_OPT="--memory-limit=$STAREXEC_MAX_MEM"
exec ./eprover-ho --auto-schedule -s --proof-object --print-statistics \
  --cpu-limit="${STAREXEC_CPU_LIMIT:-300}" $MEM_OPT "$1"
EOF

cat > "$PKG/bin/starexec_run_eprover-ho-sat" <<'EOF'
#!/bin/sh
# Configuration aimed at establishing (counter-)satisfiability.
MEM_OPT=""
[ -n "$STAREXEC_MAX_MEM" ] && MEM_OPT="--memory-limit=$STAREXEC_MAX_MEM"
exec ./eprover-ho --satauto-schedule -s --proof-object --print-statistics \
  --cpu-limit="${STAREXEC_CPU_LIMIT:-300}" $MEM_OPT "$1"
EOF

chmod 755 "$PKG/bin/"*

# --- Zip (Info-ZIP preserves the unix mode bits) ----------------------------
say "Creating $ZIP"
mkdir -p "$OUT_DIR"
rm -f "$ZIP"
(cd "$PKG" && zip -r -X "$ZIP" starexec_description.txt bin >/dev/null)
unzip -l "$ZIP"

# --- Leave the source tree dynamically linked again -------------------------
say "Restoring dynamic eprover-ho in the source tree"
rm -f "$SRC_DIR/PROVER/eprover-ho"
make -C "$SRC_DIR/PROVER" eprover-ho >/dev/null

say "Done: $ZIP"
