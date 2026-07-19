# atp_demo — PAAR'26 demo for AtpClient / KinoAtpClient / AtpMcp

A self-contained project + claudeman container that demonstrates the
[`atp_client`](https://hex.pm/packages/atp_client),
[`kino_atp_client`](https://hex.pm/packages/kino_atp_client) and
[`atp_mcp`](https://hex.pm/packages/atp_mcp) packages, with Elixir 1.20 and
a full Isabelle/HOL installation available inside the container.

## Quick start

```bash
./.start_claudeman.sh
```

This runs `claudeman run --workspace . --profile elixir-isabelle
--no-firewall`, building the image from
`.claude/claudeman/profiles/Dockerfile` on first use. Note: the image
downloads the ~1.2 GB Isabelle2025-2 Linux bundle and compiles the
`atp_mcp` and `livebook` escripts at build time — the first build takes a
while; afterwards everything is cached in the image and startup is instant.

Inside Claude Code, the `atp` MCP server is preconfigured (`.mcp.json` +
`enabledMcpjsonServers` in `.claude/settings.json`). Try:

> "List the available ATP backends, then prove `p => p` with the local
> E prover, and then prove the same lemma in Isabelle/HOL."

## What's in the image

- **Elixir 1.20 / OTP 28** (`elixir:1.20-otp-28`, Debian) — the only Elixir
  in the image, at `/usr/local/bin`.
- **Isabelle2025-2** at `/opt/Isabelle2025-2`, on PATH, HOL heap ready.
- **`atp_mcp` escript** pre-installed at `/home/node/.mix/escripts/atp_mcp`.
- **`livebook` escript** for the KinoAtpClient smart-cell demo.
- **E prover** (Debian package) for the offline `local_exec` backend.
- `LANG=C.UTF-8`, `ELIXIR_ERL_OPTIONS=+fnu`, `ERL_AFLAGS=+fnu` set
  image-wide.

## How the Isabelle backend is wired

`AtpClient`'s Isabelle backend talks to a resident **Isabelle server**
(TCP, password-authenticated). The MCP launcher
(`.claude/atp-mcp-launch.sh`) ensures a server named `atp` is running on
port 9999 and writes `host`/`port`/`password` to `.isabelle_server_info`
(git-ignored). Because the escript cannot see this project's `config.exs`,
the credentials are passed **per tool call** — `CLAUDE.md` instructs Claude
to read the info file and forward `host`, `port`, `password` on
`prove_isabelle` / `query_backend(backend: "isabelle")`, both of which
accept these keys as per-call overrides.

Code running _inside_ the Mix project (iex, Livebook) instead picks the
password up from `config/config.exs`, which reads the same info file.

## Differences from the old ShotTx container setup

The ShotTx `.devcontainer`/launcher had several intertwined problems; this
setup fixes each at the root:

1. **Elixir 1.19 vs. 1.20.** The old image pinned `elixir:1.19-alpine`,
   but `atp_mcp` requires `~> 1.20`, so `mix escript.install hex atp_mcp`
   failed — silently, because the launcher appended `|| true`. The MCP
   server then never came up. → Base image is now `elixir:1.20-otp-28`,
   and the escript is installed (and verified with `test -x`) at image
   build time, so a broken install fails the build, not the demo.
2. **PATH breakage.** The old profile layered asdf devcontainer features
   on top of the image's Elixir, and `settings.json` replaced PATH with a
   hardcoded list of asdf shim directories that didn't exist in every
   build (a `RUN export PATH=...` line in the Dockerfile additionally did
   nothing — `export` doesn't persist across Docker layers). → There is
   now exactly one Elixir installation; PATH is set once as image `ENV`,
   and `settings.json` repeats the identical value.
3. **`+fnu`.** On the old Alpine (musl) base the BEAM fell back to latin1
   filename/IO encoding, and the `:user` device escaped characters like
   `…` as `\x{2026}` — invalid JSON, MCP `tools/list` timeout. → Debian
   base with `LANG=LC_ALL=C.UTF-8`, plus `ELIXIR_ERL_OPTIONS=+fnu` and
   `ERL_AFLAGS=+fnu` baked in as `ENV` (and defensively re-exported in the
   launcher).
4. **No Isabelle.** → Isabelle2025-2 installed under `/opt` (glibc base is
   required — Isabelle's bundled Poly/ML and JDK don't run on musl, which
   is the other reason Alpine had to go), with the resident-server
   lifecycle handled by the MCP launcher.
5. **Install race on first MCP connect.** The old lazy-install launcher
   (and a `SessionStart` hook variant) raced the MCP client's first
   `tools/list`. → Nothing is installed at session start anymore.

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

## Livebook / KinoAtpClient

Inside the container:

```bash
mix deps.get
livebook server --ip 0.0.0.0 --port 8080 examples/demo.livemd
```

Reaching the Livebook UI from the host requires the container port to be
exposed; how to do that depends on your claudeman/podman networking (with
`--no-firewall` and host networking it may already be reachable). If not,
add a port mapping to your claudeman invocation or profile.

## Caveats

- `.claude/settings.json` hardcodes `/opt/Isabelle2025-2` in PATH; if you
  bump `ISABELLE_VERSION` in the Dockerfile, update it there too.
- `sotptp` and `starexec` backends need outbound network from the
  container; with a restrictive firewall profile only `local_exec` and
  `isabelle` will work.
- The Isabelle server password rotates per container run; anything cached
  from a previous run's `.isabelle_server_info` is stale after a restart.
