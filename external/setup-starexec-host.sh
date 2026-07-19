#!/usr/bin/env bash
# Prepare this devcontainer to run the StarExec container (nested rootless podman).
#
# Idempotent: safe to re-run any time, and REQUIRED again after a devcontainer
# rebuild (apt packages, file capabilities and /usr/local/bin are baked into
# the image and lost on rebuild).
#
# This devcontainer is itself a rootless container, which imposes four
# non-obvious constraints (all encoded below):
#
#   1. Only uids 0-65536 exist here (see /proc/self/uid_map), so the
#      conventional 100000+ subuid ranges are unmappable. We use 1001-65536.
#   2. setuid-root newuidmap/newgidmap get EPERM writing uid_map on this
#      kernel (the privileged path is refused for a euid that does not own the
#      child namespace). File capabilities keep the caller's euid, which owns
#      the namespace, so we replace the setuid bits with file caps —
#      a configuration shadow-utils officially supports.
#   3. /dev/fuse does not exist and the rootfs is fuse-overlayfs (no
#      kernel-whiteout support), so neither fuse-overlayfs nor native overlay
#      work. The vfs storage driver is the one that works (slower, more disk).
#   4. /dev/net/tun does not exist and /proc has masked paths, so pasta /
#      slirp4netns and private pid namespaces fail. Containers must run with
#      --network=host --pid=host --uts=host (start.sh does this).
set -euo pipefail

say() { printf '\n==> %s\n' "$*"; }

# This script runs INSIDE the (Debian) devcontainer — never on the host
# machine (which may be Arch or anything else without apt).
if ! command -v apt-get >/dev/null 2>&1 || [ ! -d /workspaces/2026_PAAR ]; then
  echo "ERROR: run this inside the project devcontainer (Debian), not on your host OS." >&2
  echo "Nothing needs to be installed on the host — podman, StarExec and E all live in the devcontainer." >&2
  exit 1
fi

# --- 1. Packages ------------------------------------------------------------
PKGS=(podman uidmap zip unzip)
MISSING=()
for p in "${PKGS[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  say "Installing: ${MISSING[*]}"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${MISSING[@]}"
else
  say "All packages already installed."
fi
# fuse-overlayfs cannot work without /dev/fuse, and its mere presence makes
# podman prefer it over the configured driver on fresh storage.
if dpkg -s fuse-overlayfs >/dev/null 2>&1; then
  say "Removing fuse-overlayfs (unusable without /dev/fuse)"
  sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq fuse-overlayfs
fi

# --- 2. newuidmap/newgidmap: file capabilities instead of setuid ------------
if [ -u /usr/bin/newuidmap ] || ! getcap /usr/bin/newuidmap | grep -q cap_setuid; then
  say "Switching newuidmap/newgidmap from setuid to file capabilities"
  sudo chmod u-s /usr/bin/newuidmap /usr/bin/newgidmap
  sudo setcap cap_setuid+ep /usr/bin/newuidmap
  sudo setcap cap_setgid+ep /usr/bin/newgidmap
else
  say "newuidmap/newgidmap already use file capabilities."
fi

# --- 3. subuid/subgid: a range that fits the available uid space ------------
ME="$(whoami)"
MAX_UID=$(awk '{ m = $1 + $3 - 1; if (m > max) max = m } END { print max }' /proc/self/uid_map)
if [ "$MAX_UID" -ge 165535 ]; then
  RANGE="100000-165535"
else
  RANGE="1001-${MAX_UID}"
fi
CUR=$(grep "^${ME}:" /etc/subuid 2>/dev/null || true)
WANT="${ME}:${RANGE%-*}:$(( ${RANGE#*-} - ${RANGE%-*} + 1 ))"
if [ "$CUR" != "$WANT" ]; then
  say "Setting subuid/subgid range for ${ME} to ${RANGE} (max mappable uid: ${MAX_UID})"
  [ -n "$CUR" ] && sudo usermod --del-subuids 0-4294967294 --del-subgids 0-4294967294 "$ME"
  sudo usermod --add-subuids "$RANGE" --add-subgids "$RANGE" "$ME"
  podman system migrate || true
else
  say "subuid/subgid ranges already correct (${RANGE})."
fi

# --- 4. Storage driver: vfs (see header, constraint 3) ----------------------
CONF_DIR="$HOME/.config/containers"
mkdir -p "$CONF_DIR"
STORAGE_CONF='[storage]
driver = "vfs"

[storage.options.vfs]
ignore_chown_errors = "true"
'
if [ "$(cat "$CONF_DIR/storage.conf" 2>/dev/null)" != "$STORAGE_CONF" ]; then
  say "Writing vfs storage.conf"
  printf '%s' "$STORAGE_CONF" > "$CONF_DIR/storage.conf"
  # A storage database created under another driver pins that driver; clear it.
  if [ -d "$HOME/.local/share/containers/storage" ] \
     && ! grep -qs 'driver = "vfs"' "$HOME/.local/share/containers/storage/storage.lock.driver" 2>/dev/null; then
    if ! podman info >/dev/null 2>&1; then
      say "Resetting incompatible podman storage"
      podman system reset --force >/dev/null 2>&1 || true
      sudo rm -rf "$HOME/.local/share/containers/storage"
    fi
  fi
fi

# --- 5. ~/.ssh (the vendored Makefile's ssh-setup appends to known_hosts) ---
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

# --- 6. Smoke test ----------------------------------------------------------
say "Smoke-testing nested rootless podman (pulls alpine on first run)..."
if podman run --rm --network=host --pid=host --uts=host \
     docker.io/library/alpine:latest true; then
  say "podman works (driver: $(podman info --format '{{.Store.GraphDriverName}}'))."
else
  echo "ERROR: podman cannot run containers in this environment." >&2
  echo "Diagnose with: podman --log-level=debug run --rm --network=host --pid=host --uts=host docker.io/library/alpine:latest true" >&2
  exit 1
fi

say "Done. Next: external/starexec-containerised/start.sh"
echo "    (first start pulls the multi-GB StarExec image; login admin:admin at https://localhost:7827)"
