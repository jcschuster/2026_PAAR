#!/usr/bin/env bash
# Launcher for the atp_mcp MCP server.
#
# Unlike the old ShotTx launcher, this does NOT install the escript lazily
# (it is baked into the image at /home/node/.mix/escripts/atp_mcp, which is
# on PATH) and does NOT go spelunking through asdf install dirs. Its only
# jobs are:
#
#   1. ensure the resident Isabelle server "atp" is running on port 9999,
#   2. write its connection info (host/port/password) to
#      .isabelle_server_info in the workspace, so Claude can pass them as
#      per-call arguments to the Isabelle MCP tools (the escript cannot
#      read project config.exs, and AtpClient takes the password from
#      app config or per-call opts only),
#   3. exec atp_mcp on stdio.
set -euo pipefail

# Defensive re-export: the image ENV already sets all of these, but MCP
# servers can be spawned with a reduced environment. Under a latin1 locale
# the BEAM's :user device escapes non-latin1 chars (e.g. U+2026) as
# \x{2026}, which is invalid JSON and times out the MCP client.
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+fnu}"
export ERL_AFLAGS="${ERL_AFLAGS:-+fnu}"

SERVER_NAME="atp"
SERVER_PORT="9999"
LOG_DIR="${HOME}/.isabelle-atp"
LOG_FILE="${LOG_DIR}/server.log"
INFO_FILE="${INFO_FILE:-/workspace/.isabelle_server_info}"

ensure_isabelle_server() {
  mkdir -p "${LOG_DIR}"
  : > "${LOG_FILE}"

  # Semantics of `isabelle server` (system manual, §Server): if no server
  # with this name is registered, the invocation BECOMES the server and
  # keeps running — hence setsid+background. If one is already running,
  # the invocation prints its info line and exits. Either way the first
  # line of output is:
  #   server "atp" = 127.0.0.1:9999 (password "...")
  setsid nohup isabelle server -n "${SERVER_NAME}" -p "${SERVER_PORT}" \
    >> "${LOG_FILE}" 2>&1 < /dev/null &

  # Wait for the info line (server startup is a few seconds; the HOL
  # session is only loaded later, on the first use_theories call).
  for _ in $(seq 1 60); do
    if grep -q "^server \"${SERVER_NAME}\"" "${LOG_FILE}"; then
      break
    fi
    sleep 0.5
  done

  local password
  password="$(sed -nE "s/^server \"${SERVER_NAME}\".*password \"([^\"]*)\".*/\1/p" \
    "${LOG_FILE}" | head -n 1)"

  if [ -n "${password}" ]; then
    umask 077
    printf 'host=127.0.0.1\nport=%s\npassword=%s\n' \
      "${SERVER_PORT}" "${password}" > "${INFO_FILE}"
  else
    echo "atp-mcp-launch: WARNING: could not obtain Isabelle server info;" \
         "Isabelle-backend tools will fail (see ${LOG_FILE})" >&2
  fi
}

if command -v isabelle > /dev/null 2>&1; then
  ensure_isabelle_server
else
  echo "atp-mcp-launch: WARNING: 'isabelle' not on PATH; skipping server startup" >&2
fi

exec atp_mcp "$@"
