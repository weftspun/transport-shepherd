defmodule Shepherd.Gates do
  @moduledoc """
  Workspace gates ported into the shepherd binary.

  Every gate is a module implementing `run/1` (argv → 0 or 1) and
  `self_test/0` (→ 0 or 1). `mix gates <name>` and `shepherd gates
  <name>` both dispatch here, and each gate ports its Python original
  under `2-contract/manuals-weftspun/scripts/`, `.repo/manifests/`, and
  the per-project trees.

  A gate whose Python version depends on an ecosystem this runtime does
  not have (OpenUSD's `pxr`, `torch`, `pyarrow`, `markdown-it-py`) is
  wrapped by a Port to the existing Python for now, and the wrapper
  says which script it is calling and why. A Port wrapper is not a
  port; the module docstring names both sides.
  """

  @gates %{
    "asset-prefix" => Shepherd.Gates.AssetPrefix,
    "ggml-singleton" => Shepherd.Gates.GgmlSingleton,
    "manifest-root" => Shepherd.Gates.ManifestRoot,
    "no-auto" => Shepherd.Gates.NoAuto,
    "no-orphaned-branches" => Shepherd.Gates.NoOrphanedBranches,
    "project-readme-length" => Shepherd.Gates.ProjectReadmeLength,
    "rfd-canary" => Shepherd.Gates.RfdCanary,
    "rfd-readme-present" => Shepherd.Gates.RfdReadmePresent,
    "rfd-state-canonical" => Shepherd.Gates.RfdStateCanonical
  }

  def dispatch([name | argv]) do
    case Map.fetch(@gates, name) do
      {:ok, mod} -> mod.run(argv)
      :error ->
        IO.puts(:stderr, "shepherd gates: unknown gate `#{name}`")
        IO.puts(:stderr, "known: " <> Enum.join(Map.keys(@gates), " "))
        2
    end
  end

  def dispatch([]) do
    IO.puts("known gates:")
    for name <- Enum.sort(Map.keys(@gates)), do: IO.puts("  #{name}")
    0
  end
end
