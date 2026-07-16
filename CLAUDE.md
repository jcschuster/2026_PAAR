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

## Working in the Mix project

- `mix deps.get && mix compile` before first use; `config/config.exs`
  already wires the Isabelle and LocalExec backends for in-project code
  (iex/Livebook), reading the password from `.isabelle_server_info`.
- `AtpDemo.smoke_test/0` proves a trivial FOF conjecture via LocalExec —
  a good first check that everything works end to end.

## Livebook (KinoAtpClient)

`livebook` is installed as an escript. Start it with:

```
livebook server --ip 0.0.0.0 --port 8080 examples/demo.livemd
```

and open the printed URL from the host (port must be reachable from the
host; see README).
