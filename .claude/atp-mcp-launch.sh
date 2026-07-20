#!/usr/bin/env bash
# Launcher for the atp_mcp MCP server.
#
# This does NOT install the escript lazily (it is baked into the image at
# /home/node/.mix/escripts/atp_mcp, which is on PATH). Its only jobs are:
#
#   1. ensure the resident Isabelle server "atp" is running on port 9999,
#   2. write its connection info (host/port/password) to
#      .isabelle_server_info in the workspace (informational; also read by
#      config/config.exs for in-project iex/Livebook code),
#   3. hand that password to the escript as OTP application env, and
#   4. exec atp_mcp on stdio.
#
# On (3): as of atp_mcp 0.5.0 all Isabelle traffic goes through the
# long-lived AtpMcp.IsabelleSession, which is configured from application
# env ONLY -- per-call host/port/password arguments are no longer accepted
# (see the "Isabelle session lifetime" section of AtpMcp's moduledoc).
# The escript bakes its config at build time and cannot read this project's
# config.exs, so the password is injected at runtime via an OTP sys.config
# passed through ERL_FLAGS. Without this the Isabelle backend raises
# ArgumentError on the first call and takes the whole MCP server down.
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
INFO_FILE="${INFO_FILE:-/workspaces/2026_PAAR/.isabelle_server_info}"

# OTP -config wants the path WITHOUT the .config suffix; the file itself
# must be "${SYS_CONFIG_BASE}.config". Kept outside the repo: it holds the
# Isabelle password.
SYS_CONFIG_BASE="${LOG_DIR}/atp_mcp_sys"

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

  write_sys_config "${password}"
}

# Erlang term file consumed by `erl -config`. Values must be binaries
# (<<"...">>), not charlists, to match what AtpClient.Config expects.
write_sys_config() {
  local password="$1"
  local isabelle_entry=""

  if [ -n "${password}" ]; then
    isabelle_entry="{isabelle,[{host,<<\"127.0.0.1\">>},{port,${SERVER_PORT}},{password,<<\"${password}\">>},{session,<<\"HOL\">>}]},"
  fi

  umask 077
  cat > "${SYS_CONFIG_BASE}.config" <<EOF
[{atp_client,[
  ${isabelle_entry}
  {local_exec,[{binary,<<"eprover">>},{args,[<<"--auto">>,<<"--tstp-format">>]},{cpu_timeout_s,10}]}
]}].
EOF
}

if command -v isabelle > /dev/null 2>&1; then
  ensure_isabelle_server
else
  echo "atp-mcp-launch: WARNING: 'isabelle' not on PATH; skipping server startup" >&2
  mkdir -p "${LOG_DIR}"
  # Still configure local_exec so the non-Isabelle backends work.
  write_sys_config ""
fi

# Feeds the sys.config above to the escript's BEAM. ERL_FLAGS is separate
# from the image-wide ERL_AFLAGS (+fnu), which still applies.
export ERL_FLAGS="${ERL_FLAGS:+${ERL_FLAGS} }-config ${SYS_CONFIG_BASE}"

exec atp_mcp "$@"
