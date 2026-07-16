defmodule AtpDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :atp_demo,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:atp_client, "~> 0.6"}
    ]
  end
end
