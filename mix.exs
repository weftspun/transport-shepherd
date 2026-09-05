defmodule Shepherd.MixProject do
  use Mix.Project

  def project do
    [
      app: :shepherd,
      version: "0.1.0-dev",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      escript: [main_module: Shepherd.CLI]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :public_key, :ssl, :inets, :crypto]
    ]
  end

  defp deps do
    [
      {:burrito, "~> 1.3"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"}
    ]
  end

  # `mix gates <name> …` dispatches into Shepherd.Gates without a
  # Burrito build. Same code path the binary uses.
  defp aliases do
    [gates: ["compile", &gates_task/1]]
  end

  defp gates_task(argv) do
    Mix.Task.run("app.start")
    System.halt(Shepherd.Gates.dispatch(argv))
  end

  # Burrito builds one self-contained binary per target platform.
  # `mix release shepherd` produces the artefacts under `burrito_out/`.
  defp releases do
    [
      shepherd: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos_arm64: [os: :darwin, cpu: :aarch64],
            windows_amd64: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end
end
