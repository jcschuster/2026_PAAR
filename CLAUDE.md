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
- The `atp_mcp` escript is pre-installed at `/home/node/.mix/escripts/atp_mcp`
  (on PATH). Do not reinstall it.
- E prover (`eprover`) is installed for the `local_exec` backend.
- `ELIXIR_ERL_OPTIONS=+fnu` and `ERL_AFLAGS=+fnu` are set image-wide (unicode
  filename mode for the BEAM); leave them alone.

## Using the `atp` MCP tools

Backends `sotptp` and `starexec` need network access; `local_exec` and
`isabelle` run entirely inside the container.

### local_exec

Pass `binary: "eprover"` on `query_backend` calls with
`backend: "local_exec"` (the escript has no project config, so the binary
must be given per call).

### Isabelle — IMPORTANT: per-call credentials

The MCP launcher starts a resident Isabelle server (`atp`, port 9999) and
writes its credentials to `/workspace/.isabelle_server_info`:

```
host=127.0.0.1
port=9999
password=<generated per container run>
```

The escript cannot read this project's `config.exs`, and `AtpClient` accepts
the Isabelle password only via app config or per-call options. Therefore:
**before the first Isabelle tool call, read `/workspace/.isabelle_server_info`
and pass `host`, `port`, and `password` as arguments** on `prove_isabelle`
and on `query_backend` with `backend: "isabelle"`. Both tools forward these
keys. Never print the password in responses or commit the file.

The first Isabelle call in a container run loads the HOL session (heap is
prebuilt; expect a few seconds up to ~1 min). Prefer a generous
`timeout_ms` on the first call.

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
