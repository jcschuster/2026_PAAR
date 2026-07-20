# atp_demo — PAAR'26 demo for AtpClient / KinoAtpClient / AtpMcp

A self-contained project + container that demonstrates the
[`atp_client`](https://hex.pm/packages/atp_client),
[`kino_atp_client`](https://hex.pm/packages/kino_atp_client) and
[`atp_mcp`](https://hex.pm/packages/atp_mcp) packages, with Elixir 1.20 and
a full Isabelle/HOL installation available inside the container.

The three packages share one set of ATP backends — **SystemOnTPTP**,
**StarExec**, **Isabelle** and **LocalExec** — exposed three ways:

| Package           | How you drive the backends                                          |
| ----------------- | ------------------------------------------------------------------- |
| `atp_client`      | Plain Elixir API (iex, scripts, releases)                           |
| `kino_atp_client` | Livebook smart cells (`examples/demo.livemd`)                       |
| `atp_mcp`         | The same backends as MCP tools, for use from an LLM agent           |

The container in this repo is deliberately narrow: it runs **claudeman**
(Claude Code with the `atp` MCP server wired in) and hosts the **local
StarExec** tooling. The **Livebook** demo (`kino_atp_client`) is run on your
**host machine**, not in the container — see the Livebook section below.

## Quick start

```bash
./.start_claudeman.sh
```

This runs `claudeman run --workspace . --profile elixir-isabelle
--no-firewall`, building the image from
`.claude/claudeman/profiles/Dockerfile` on first use. claudeman is a
containerised launcher for Claude Code: it builds the profile's devcontainer
image and starts Claude Code inside it, with the workspace bind-mounted.

The first build downloads the ~1.2 GB Isabelle2025-2 Linux bundle and
compiles the `atp_mcp` escript, so it takes a while; afterwards everything
is cached in the image and startup is quick.

Inside Claude Code the `atp` MCP server is preconfigured (`.mcp.json` +
`enabledMcpjsonServers` in `.claude/settings.json`), so you can go straight
to the demo below.

## Using the `atp` MCP server (the workshop demo)

Once Claude Code is running, the `atp_mcp` tools are available to the agent.
They cover the whole workflow: backend discovery and verification, TPTP
linting, single-prover and portfolio SystemOnTPTP calls, and the Isabelle
and StarExec backends. The agent calls them with their documented arguments
only — no credentials and no backend binary are ever passed by hand; the
container wiring (below) supplies those.

A warm-up to confirm everything is connected:

> "List the available ATP backends, then prove `p => p` with the local
> E prover, and then prove the same lemma in Isabelle/HOL."

The workshop demo itself formalizes a natural-language argument and checks
it mechanically. The full prompt is in [`prompts/nemo.txt`](prompts/nemo.txt);
paste it in verbatim. In outline it asks the agent to:

1. formalize a short argument (all fish live in water; Nemo is a clownfish;
   therefore Nemo lives in water) in **TPTP (THF)**, using *only* the stated
   premises and conclusion — no background knowledge;
2. **lint** the problem before running it;
3. check it with a **small portfolio of provers** and report the SZS verdict;
4. explain what the verdict says about the argument's validity.

Because the premises never connect "clownfish" to "fish", the argument is
*not* valid as stated, and the portfolio should report a non-Theorem
verdict — the point of the demo is that a faithful formalization exposes the
missing premise rather than papering over it.

The StarExec backend used in the demo expects a StarExec instance the
container can reach — see the StarExec section below for how the canonical
instance runs on the host and is reached at
`https://host.containers.internal:7827`.

## What's in the image

- **Elixir 1.20 / OTP 28** (`elixir:1.20-otp-28`, Debian) — the only Elixir
  in the image, at `/usr/local/bin`.
- **Isabelle2025-2** at `/opt/Isabelle2025-2`, on PATH, HOL heap ready.
- **`atp_mcp` escript** pre-installed at `/home/node/.mix/escripts/atp_mcp`.
- **E prover** (Debian package) for the offline `local_exec` backend.
- `LANG=C.UTF-8`, `ELIXIR_ERL_OPTIONS=+fnu`, `ERL_AFLAGS=+fnu` set
  image-wide (unicode filename mode; without it the BEAM's latin1 fallback
  escapes characters like `…` as `\x{2026}`, which is invalid JSON and
  times out the MCP client).

## How the Isabelle backend is wired

`AtpClient`'s Isabelle backend talks to a resident **Isabelle server**
(TCP, password-authenticated). The MCP launcher
(`.claude/atp-mcp-launch.sh`) ensures a server named `atp` is running on
port 9999 and writes its `host`/`port`/`password` to `.isabelle_server_info`
(git-ignored).

The `atp_mcp` escript bakes its own config at build time and cannot read
this project's `config.exs`, so the launcher hands it the credentials at
runtime a different way: it writes an OTP `sys.config`
(`~/.isabelle-atp/atp_mcp_sys.config`) and points the escript's BEAM at it
via `ERL_FLAGS=-config …`. As of atp_mcp 0.5.0 all Isabelle traffic goes
through the long-lived `AtpMcp.IsabelleSession`, which reads this
**application env only** — per-call `host`/`port`/`password` arguments were
removed. That is why the agent never passes credentials on a tool call:
there is nowhere to pass them.

Code running _inside_ the Mix project (e.g. iex) instead reads the same
`.isabelle_server_info` through `config/config.exs`.

The first Isabelle call in a container run loads the HOL session (the heap is
prebuilt; expect a few seconds up to ~1 min), so allow a generous timeout on
the first call.

## Local StarExec container + higher-order E prover

Three additions for working with StarExec and higher-order E. All of the
commands below run **inside the devcontainer** (Debian — nothing is ever
installed on your host OS); they are idempotent, re-run the first two after a
devcontainer rebuild:

```bash
external/setup-starexec-host.sh          # one-time host prep: nested rootless podman
external/starexec-containerised/start.sh # start StarExec → https://localhost:7827 (admin:admin)
scripts/build-eprover-ho.sh              # build E with --enable-ho → eprover-ho on PATH
scripts/make-starexec-zip.sh             # build starexec/eprover-ho-<ver>-starexec.zip
```

- `external/starexec-containerised/` is vendored from
  [jcschuster/AtpClient](https://github.com/jcschuster/AtpClient)'s
  `external/` (itself from
  [StarExecMiami/StarExec-ARC](https://github.com/StarExecMiami/StarExec-ARC));
  `start.sh [start|stop|status|logs]` manages the container, state persists in
  `starexec_saved_state/`. **Run it on the host** (needs host podman): the
  devcontainer's network namespace is isolated (pasta), so a StarExec started
  *inside* the devcontainer is unreachable from the host browser. Host-run
  StarExec is at `https://localhost:7827` on the host and at
  `https://host.containers.internal:7827` from inside the devcontainer.
  `start.sh` auto-detects the environment (nested devcontainer mode still
  works, but is reachable only from within the devcontainer);
  `external/setup-starexec-host.sh` is only needed for the nested mode and
  encodes its workarounds (file-capability newuidmap, vfs storage, host
  namespaces); see its header comment.
- `scripts/build-eprover-ho.sh` keeps sources in `external/eprover-src/`
  (survives rebuilds) and installs only `eprover-ho` — the stock
  `/usr/bin/eprover` used by the `local_exec` backend stays untouched.
- **E on the host machine** (e.g. for a Livebook running on the host, whose
  LocalExec backend needs a host-visible binary): `scripts/make-host-binaries.sh`
  (run inside the devcontainer) puts **statically linked** `eprover` and
  `eprover-ho` into `host-bin/` — the workspace is bind-mounted, so on the host
  they appear at the same repo path and run on any x86_64 Linux (no glibc
  dependency, no packages needed). Install on the host with
  `sudo install -m755 host-bin/eprover host-bin/eprover-ho /usr/local/bin/`
  (or into `~/.local/bin` without root), or point the LocalExec `binary:`
  option straight at `host-bin/eprover`.
- The solver zip contains a **statically linked** `eprover-ho` (runs on any
  StarExec host glibc), `bin/starexec_run_eprover-ho` (auto-schedule, proofs),
  `bin/starexec_run_eprover-ho-sat` ((counter-)satisfiability schedule) and a
  `starexec_description.txt` that StarExec reads on upload. Upload it in the
  StarExec web UI via *Spaces → your space → upload solver*, choosing
  "description from archive". Port 7827 must be forwarded to reach the UI
  from the host browser.

## Livebook / KinoAtpClient (run on the host)

The Livebook demo runs on your **host machine**, not in the container — the
container has no Livebook, and its network namespace is isolated (pasta), so
a Livebook served from inside would not be reachable from the host browser.
The workspace is bind-mounted, so `examples/demo.livemd` is already on the
host at the same path.

On the host you need Elixir and Livebook installed. The notebook uses
`Mix.install`, so it pulls `kino_atp_client` itself — no `mix deps.get`:

```bash
livebook server examples/demo.livemd
```

The demo exercises all four backends, so on the host you also need:

- **E prover** for the `LocalExec` cells (the notebook uses `eprover-ho`).
  Build host binaries from inside the container with
  `scripts/make-host-binaries.sh` — it writes **statically linked** `eprover`
  and `eprover-ho` into `host-bin/`, which appears at the same path on the
  host (see the StarExec section). Put them on the host PATH or point the
  `LocalExec` `binary:` option at `host-bin/eprover-ho`.
- **Isabelle** installed on the host for the Isabelle cells (the notebook
  starts its own Isabelle server with `IsabelleClient.start_server`).
- A **StarExec** instance for the StarExec cells, and outbound network for
  the SystemOnTPTP cells.

## Caveats

- `.claude/settings.json` hardcodes `/opt/Isabelle2025-2` in PATH; if you
  bump `ISABELLE_VERSION` in the Dockerfile, update it there too.
- `sotptp` and `starexec` backends need outbound network from the
  container; with a restrictive firewall profile only `local_exec` and
  `isabelle` will work.
- The Isabelle server password rotates per container run; anything cached
  from a previous run's `.isabelle_server_info` is stale after a restart.
