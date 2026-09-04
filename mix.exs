defmodule Shepherd.MixProject do
  use Mix.Project

  def project do
    [
      app: :shepherd,
      version: "0.1.0-dev",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
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
      {:owl, "~> 0.12"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"}
    ]
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
            linux_amd64: [os: :linux, cpu: :x86_64],
            windows_amd64: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end
end
