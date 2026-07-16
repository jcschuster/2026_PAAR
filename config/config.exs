import Config

# Backend configuration for code run inside THIS mix project (iex -S mix,
# Livebook attached to the project, scripts). Note: the atp_mcp escript
# does NOT read this file — the escript carries its own compile-time
# config, so .claude/atp-mcp-launch.sh injects the same settings into it
# at runtime via an OTP sys.config (see CLAUDE.md).

# The MCP launcher (.claude/atp-mcp-launch.sh) writes the resident Isabelle
# server's credentials here. If you use the Isabelle backend from iex
# before ever starting Claude Code in this container, start the server
# manually first (`isabelle server -n atp -p 9999 &`) and export the
# printed password as ISABELLE_PASSWORD.
isabelle_password =
  case File.read(Path.join(__DIR__, "../.isabelle_server_info")) do
    {:ok, content} ->
      content
      |> String.split("\n", trim: true)
      |> Enum.find_value(fn
        "password=" <> pw -> pw
        _ -> nil
      end)

    _ ->
      System.get_env("ISABELLE_PASSWORD")
  end

config :atp_client, :isabelle,
  host: "127.0.0.1",
  port: 9999,
  password: isabelle_password,
  session: "HOL"

config :atp_client, :local_exec,
  binary: "eprover",
  args: ["--auto", "--tstp-format", "--cpu-limit=10"],
  cpu_timeout_s: 10
