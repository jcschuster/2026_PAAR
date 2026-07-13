defmodule AtpDemo do
  @moduledoc """
  Workshop demo for the jcschuster ATP stack:

    * `AtpClient`     — unified Elixir client for the SystemOnTPTP,
      StarExec, Isabelle and LocalExec theorem-prover backends
    * `KinoAtpClient` — Livebook smart cells on top of AtpClient
      (see `examples/demo.livemd`)
    * `AtpMcp`        — the same backends exposed as MCP tools to
      Claude Code (wired up via `.mcp.json` in this project)
  """

  @doc """
  Smoke test for the LocalExec backend (E prover is installed in the
  container image): proves a trivially valid first-order conjecture.

      iex> AtpDemo.smoke_test()
  """
  def smoke_test do
    problem = """
    fof(tautology, conjecture, (p => p)).
    """

    AtpClient.LocalExec.query(problem, [])
  end
end
