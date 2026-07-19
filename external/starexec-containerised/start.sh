#!/usr/bin/env bash
# Simplified StarExec startup for local validation — no mkcert required.
# The container generates a self-signed TLS cert on first boot.
# Ports: HTTPS → https://localhost:7827  HTTP → http://localhost:7826
# Credentials: admin / admin
#
# Usage: ./start.sh [start|stop|status|logs]
#
# Devcontainer adaptation (see ../setup-starexec-host.sh): this host is itself
# a rootless container without /dev/net/tun and with masked /proc paths, so
# the container runs with --network=host --pid=host --uts=host instead of
# slirp4netns + port mapping. Ports below 1024 cannot be bound either, so
# Apache inside the container is re-pointed to listen on 7826/7827 directly —
# the resulting URL is the same as with the original port mapping.
set -euo pipefail

CONTAINER=starexec-app
IMAGE=ghcr.io/starexecmiami/starexec-arc:latest
USER="${USER:-$(whoami)}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$SCRIPT_DIR/starexec_saved_state"
KEY="$SCRIPT_DIR/starexec_podman_key"
# Entry-point shim: makes Tomcat run with primary group star-web so solver
# uploads can be extracted by the sandbox user (see the script's header comment
# for the full analysis). Without it every solver upload returns HTTP 500
# "error when extracting solver".
TOMCAT_FIX="$SCRIPT_DIR/tomcat-stargroup-fix.sh"

cmd="${1:-start}"

case "$cmd" in
  start)
    if podman ps --filter "name=$CONTAINER" --format '{{.ID}}' | grep -q .; then
      echo "Already running. Visit https://localhost:7827  (admin:admin)"
      exit 0
    fi

    if ! podman image exists "$IMAGE"; then
      echo "Pulling $IMAGE ..."
      podman pull "$IMAGE"
    fi

    mkdir -p "$STATE_DIR"/{volDB,volExport,volStarexec}
    [ -f "$KEY" ] || ssh-keygen -t ed25519 -N '' -f "$KEY" -q

    echo "Starting StarExec…"
    # Two environments, one script:
    #  - normal host (has /dev/net/tun): default rootless networking with
    #    port mappings; MySQL/Tomcat stay isolated inside the container.
    #  - nested devcontainer (no tun, masked /proc): only host namespaces
    #    work; Apache is re-pointed at 7826/7827 after start. Note that in
    #    this mode the ports are only reachable INSIDE the devcontainer.
    if [ -e /dev/net/tun ]; then
      NET_ARGS=(-p 7827:443 -p 7826:80)
      PATCH_PORTS=false
    else
      NET_ARGS=(--network=host --pid=host --uts=host)
      PATCH_PORTS=true
    fi

    podman run -d --name "$CONTAINER" \
      "${NET_ARGS[@]}" \
      --tmpfs /var/run/mysqld:rw,size=128m,mode=775 \
      -v "$STATE_DIR/volDB:/var/lib/mysql:U" \
      -v "$STATE_DIR/volExport:/export" \
      -v "$STATE_DIR/volStarexec:/home/starexec" \
      -v "$KEY:/root/.ssh/starexec_podman_key" \
      -v "$TOMCAT_FIX:/tomcat-stargroup-fix.sh:ro" \
      --entrypoint /tomcat-stargroup-fix.sh \
      -e SSH_USERNAME="$USER" \
      -e HOST_MACHINE=host.containers.internal \
      -e SSH_PORT=22 \
      -e "SSH_SOCKET_PATH=/run/user/$(id -u)/podman/podman.sock" \
      -e MYSQL_START_TIMEOUT=180 \
      "$IMAGE"

    if $PATCH_PORTS; then
      # With host networking Apache cannot bind the privileged ports 80/443;
      # re-point it at 7826/7827 (same URLs as the original -p mapping).
      echo "Waiting for Apache config to appear…"
      until podman exec "$CONTAINER" test -f /etc/apache2/ports.conf 2>/dev/null; do
        sleep 2
      done
      podman exec "$CONTAINER" sed -i -E \
        -e 's/^([[:space:]]*)Listen 80$/\1Listen 7826/' \
        -e 's/^([[:space:]]*)Listen 443$/\1Listen 7827/' \
        /etc/apache2/ports.conf
      podman exec "$CONTAINER" bash -c \
        'sed -i -E -e "s/(<VirtualHost[^>]*):443>/\1:7827>/" -e "s/(<VirtualHost[^>]*):80>/\1:7826>/" /etc/apache2/sites-available/*.conf /etc/apache2/sites-enabled/*.conf 2>/dev/null || true'
    fi

    # The image's ssl.conf has 'Redirect permanent "/" "/starexec"' which
    # also matches /starexec/... paths and breaks API access. Replace it with
    # a regex-anchored RedirectMatch that only fires for the bare root. Done
    # as soon as the container is up (before Apache has been hit for a real
    # request) so the first request the user makes lands on the fixed config.
    echo "Waiting for Apache to come up…"
    until podman exec "$CONTAINER" test -f /etc/apache2/sites-available/ssl.conf 2>/dev/null; do
      sleep 2
    done
    echo "Patching Apache redirect rule…"
    podman exec "$CONTAINER" sed -i \
      's|Redirect permanent "/" "/starexec"|RedirectMatch permanent "^/$" "/starexec/"|' \
      /etc/apache2/sites-available/ssl.conf
    # Apache may have failed to start while 80/443 were unbindable.
    podman exec "$CONTAINER" bash -c 'apache2ctl restart || apache2ctl start' 2>/dev/null || true

    echo "Waiting for StarExec webapp to be deployed (may take several minutes on first boot)…"
    until podman exec "$CONTAINER" test -d /project/apache-tomcat-7/webapps/starexec 2>/dev/null; do
      sleep 10
      printf "."
    done
    echo
    echo "Waiting a few extra seconds for the webapp to finish loading…"
    sleep 15

    # The volExport bind mount masks the image's build-time /export/starexec/
    # sandbox staging dirs (mode 2770 setgid, tomcat:star-web). These are used
    # by benchmark-dependency staging; init-starexec.sh recreates
    # /export/starexec but not these subdirs, so restore them here. Idempotent;
    # runs on every start, fixing already-created state too.
    #
    # NOTE: this is NOT what causes the "error when extracting solver" HTTP 500.
    # That is fixed by tomcat-stargroup-fix.sh above: solver extraction happens
    # in /local/sandbox (compiled sandbox_dir), not here, and failed because the
    # root:root Tomcat JVM created temp dirs the sandbox user could not write.
    echo "Ensuring sandbox staging dirs exist under the mounted /export…"
    podman exec "$CONTAINER" bash -c '
      set -e
      for d in /export/starexec/sandbox /export/starexec/sandbox2; do
        mkdir -p "$d"
        chown -R tomcat:star-web "$d"
        chmod 2770 "$d"
        chmod g+s "$d"
        setfacl -d -m g::rwx "$d" 2>/dev/null || true
      done' || echo "WARN: could not set up sandbox staging dirs" >&2

    echo "Done.  Visit https://localhost:7827  (admin:admin)"
    ;;

  stop)
    id=$(podman ps --filter "name=$CONTAINER" --format '{{.ID}}')
    if [ -n "$id" ]; then
      podman stop "$id" && podman rm "$id"
      echo "Stopped."
    else
      echo "Not running."
    fi
    ;;

  status)
    podman ps --filter "name=$CONTAINER"
    ;;

  logs)
    podman logs -f "$CONTAINER"
    ;;

  *)
    echo "Usage: $0 [start|stop|status|logs]"
    exit 1
    ;;
esac
