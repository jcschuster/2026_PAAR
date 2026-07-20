# AtpClient / KinoAtpClient / AtpMcp workshop demo

This workspace demonstrates three Hex packages by jcschuster:

| Package         | Role                                                                  |
| --------------- | --------------------------------------------------------------------- |
| `atp_client`    | Unified Elixir client for ATP backends (SystemOnTPTP, StarExec, Isabelle, LocalExec) |
| `kino_atp_client` | Livebook smart cells on top of `atp_client` (`examples/demo.livemd`) |
| `atp_mcp`       | The same backends as MCP tools — connected in this project as server `atp` |

## Environment facts

- Elixir 1.20 / OTP 28 lives at `/usr/local/bin` (`elixir`, `mix`, `iex` are
  all on PATH — no asdf, no version manager).
- Isabelle2025-2 lives at `/opt/Isabelle2025-2`; `isabelle` is on PATH.
- The `atp_mcp` escript lives at `/home/node/.mix/escripts/atp_mcp` (on PATH).
  The image bakes in 0.5.0; it was upgraded in place to **0.5.1** with
  `mix escript.install hex atp_mcp 0.5.1 --force`. A container rebuild reverts
  it to 0.5.0 — re-run that command if `serverInfo.version` says 0.5.0.
  Otherwise leave it alone.
- E prover (`eprover`) is installed for the `local_exec` backend.
- `ELIXIR_ERL_OPTIONS=+fnu` and `ERL_AFLAGS=+fnu` are set image-wide (unicode
  filename mode for the BEAM); leave them alone.

## Using the `atp` MCP tools

Backends `sotptp` and `starexec` need network access; `local_exec` and
`isabelle` run entirely inside the container.

Both are configured for you by `.claude/atp-mcp-launch.sh`, which writes an
OTP `sys.config` (`~/.isabelle-atp/atp_mcp_sys.config`) and points the
escript at it via `ERL_FLAGS=-config …`. The escript bakes its own config at
build time and cannot read this project's `config.exs`, so this is how it
learns the Isabelle password and the `eprover` binary. **Call the tools with
their documented arguments only — no credentials, no `binary`.**

### local_exec

Just pass `problem`. The `eprover` binary comes from the injected config.

### Isabelle

The launcher starts a resident Isabelle server (`atp`, port 9999) and writes
its credentials to `/workspaces/2026_PAAR/.isabelle_server_info` (also read by
`config/config.exs` for in-project iex/Livebook code). Never print the
password in responses or commit the file.

Do **not** pass `host` / `port` / `password` to the Isabelle tools. As of
atp_mcp 0.5.0 all Isabelle traffic goes through the long-lived
`AtpMcp.IsabelleSession`, which reads application env only; per-call
credential overrides were removed. `prove_isabelle` rejects unknown keys
outright (`additionalProperties: false`), and `query_backend` silently drops
them.

The first Isabelle call in a container run loads the HOL session (heap is
prebuilt; expect a few seconds up to ~1 min). Prefer a generous
`timeout_ms` on the first call.

If an Isabelle tool reports a missing `:password` setting, the launcher failed
to obtain the server password (see `~/.isabelle-atp/server.log`) — re-run the
launcher rather than retrying with credentials as arguments. On atp_mcp 0.5.0
that error killed the whole MCP server; 0.5.1 reports it and stays up.

### Known bug: `query_backend` with `backend: "isabelle"` is broken

Fails on the escript with `{:tptp_thy_copy_failed, :enotdir}`, and even past
that returns `GaveUp` for everything. Two upstream bugs, neither fixed in a
release yet; patches for both sit at the repo root:

- `isabelle_elixir-0.4.0-escript-priv.patch` — `IsabelleClient.TPTP` finds
  `TPTP.thy` via `priv/`, which does not exist in an escript (only `ebin/` is
  bundled), so the read fails `:enotdir`. Invisible from iex/Livebook, where
  `priv/` is a real directory.
- `atp_client-0.6.0-tptp-axioms.patch` — `isabellize_theory/1` emits axioms as
  `axiomatization where a1: …`, which Isabelle never hands to a tactic, so the
  default `by auto` proves nothing that depends on the problem's own axioms.
  `proof_method` cannot be passed over MCP (`opts_from(args, "isabelle")`
  allows only `[:use_theories_timeout_ms, :raw]`).

Also note this path is **THF-only**: FOF input isabellizes to an empty body and
comes back `GaveUp`, indistinguishable from a failed proof. And `raw: true` is
accepted but ignored here.

Until those ship, use `prove_isabelle` (hand-written theory) or `local_exec` /
`sotptp` for TPTP problems.

## StarExec container & higher-order E prover

All of this is set up but **lives partly in the container image — after a
devcontainer rebuild re-run the two idempotent scripts below** (they detect
what is missing):

- `external/setup-starexec-host.sh` — nested rootless podman. Non-obvious
  environment constraints are encoded here (this devcontainer is itself a
  rootless container): file *capabilities* instead of setuid on
  newuidmap/newgidmap, subuid range 1001-65536, vfs storage driver, and
  containers must run `--network=host --pid=host --uts=host` (no
  /dev/net/tun, masked /proc). Don't "fix" any of these back to defaults.
- `scripts/build-eprover-ho.sh` — builds `eprover-ho` (E with `--enable-ho`,
  source kept in `external/eprover-src/`) and installs it to
  `/usr/local/bin`. Never install plain `eprover` from there: it would
  shadow `/usr/bin/eprover`, which the atp_mcp local_exec backend uses.

StarExec itself: `external/starexec-containerised/start.sh [start|stop|status|logs]`
(vendored from jcschuster/AtpClient, auto-detects environment). **The
canonical instance runs on the user's host machine** (they run start.sh
there), because the devcontainer's netns is isolated (pasta — the wlan0 you
see in here is a tap mirage, and ports bound here are NOT visible on the
host). Login `admin:admin`, state in `starexec_saved_state/` (never share one
state dir between a host and a nested instance — two MariaDBs corrupt it).
First boot initializes MariaDB and deploys the webapp — takes several
minutes. Reach the host instance from inside this container at
`https://host.containers.internal:7827` (self-signed cert — disable TLS
verification). The nested-in-devcontainer mode still works but is reachable
only from inside the devcontainer.

`scripts/make-host-binaries.sh` builds **static** `eprover` + `eprover-ho`
into `host-bin/` for the user's Arch host (bind-mounted workspace; the user
installs them host-side themselves — never suggest apt/pacman for this).

`scripts/make-starexec-zip.sh` regenerates
`starexec/eprover-ho-<ver>-starexec.zip` (statically linked `eprover-ho`,
`bin/starexec_run_*` configs, `starexec_description.txt`), ready to upload
as a StarExec solver.

## Working in the Mix project

- `mix deps.get && mix compile` before first use; `config/config.exs`
  already wires the Isabelle and LocalExec backends for in-project code
  (iex/Livebook), reading the password from `.isabelle_server_info`.
- `AtpDemo.smoke_test/0` proves a trivial FOF conjecture via LocalExec —
  a good first check that everything works end to end.

## Livebook (KinoAtpClient)

The KinoAtpClient demo (`examples/demo.livemd`) is **not** run in this
container — there is no `livebook` escript in the image. It runs on the
user's host machine (the workspace is bind-mounted, so the notebook is at
the same path there). See the "Livebook / KinoAtpClient" section of the
README. Don't try to `livebook server` in here.
