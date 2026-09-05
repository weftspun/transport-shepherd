defmodule Shepherd.Gates.GgmlSingleton do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_ggml_singleton.py`.
  Same rules, same 3 self-test controls.

  Only one GGML source tree lives in the workspace (RFD 2188) at
  `2-contract/ggml`. This gate walks the workspace and refuses a rogue
  `ggml.h` or `ggml.c` outside that path. Vendored llama.cpp is exempt
  per CLAUDE.md's ggml row (a vendor's own runtime is exempted).

  Detection floor: none. Every file matching the sentinel names is
  visited; skip-dirs (build/, .git/, .pixi/, etc.) prune the walk but
  are counted implicitly.
  """

  @canonical "2-contract/ggml"
  @skip_dirs MapSet.new(~w(.pixi .venv node_modules .git build dist target))
  @llama_cpp_exempt_prefixes [
    "3-interactor/llama-cpp-npu-vision-upstream/",
    "3-interactor/turboquant-godot/thirdparty/llama_cpp/"
  ]
  @sentinels MapSet.new(["ggml.h", "ggml.c"])

  def run(["--self-test"]), do: self_test()

  def run(argv) do
    root =
      case Enum.find_index(argv, &(&1 == "--repo")) do
        nil -> workspace_root(File.cwd!())
        i -> Enum.at(argv, i + 1)
      end
    gate(root)
  end

  def is_exempt?(rel) do
    cond do
      String.starts_with?(rel, @canonical <> "/") -> true
      Enum.any?(@llama_cpp_exempt_prefixes, &String.starts_with?(rel, &1)) -> true
      true -> false
    end
  end

  def scan(root) do
    walk(root, root, [])
    |> Enum.sort()
  end

  defp walk(dir, root, acc) do
    case File.ls(dir) do
      {:error, _} -> acc
      {:ok, entries} ->
        Enum.reduce(entries, acc, fn name, a ->
          full = Path.join(dir, name)
          cond do
            name in @skip_dirs -> a
            File.dir?(full) -> walk(full, root, a)
            File.regular?(full) and MapSet.member?(@sentinels, name) ->
              rel = full |> Path.relative_to(root) |> String.replace("\\", "/")
              if is_exempt?(rel), do: a, else: [rel | a]
            true -> a
          end
        end)
    end
  end

  defp gate(root) do
    if root == nil do
      IO.puts("no .repo/ found; nothing to gate.")
      0
    else
      hits = scan(root)
      Enum.each(hits, &IO.puts("  FAIL rogue ggml source at #{&1}"))
      IO.puts("#{length(hits)} rogue ggml source files outside #{@canonical}/ and llama.cpp exemptions.")
      if hits == [], do: 0, else: 1
    end
  end

  defp workspace_root(dir) do
    cond do
      File.dir?(Path.join(dir, ".repo")) -> dir
      Path.dirname(dir) == dir -> nil
      true -> workspace_root(Path.dirname(dir))
    end
  end

  def self_test do
    tmp = Path.join(System.tmp_dir!(), "shepherd-ggml-singleton-" <> rand())
    try do
      File.mkdir_p!(Path.join(tmp, ".repo"))
      canonical_dir = Path.join(tmp, @canonical)
      File.mkdir_p!(canonical_dir)
      File.write!(Path.join(canonical_dir, "ggml.h"), "/* canonical */\n")

      clean = scan(tmp)
      clean_ok? = clean == []

      rogue_dir = Path.join([tmp, "3-interactor", "rogue-consumer", "third_party", "ggml", "include"])
      File.mkdir_p!(rogue_dir)
      File.write!(Path.join(rogue_dir, "ggml.h"), "/* rogue */\n")
      expected = "3-interactor/rogue-consumer/third_party/ggml/include/ggml.h"
      hits1 = scan(tmp)
      rogue_ok? = hits1 == [expected]

      exempt_dir = Path.join([tmp, "3-interactor", "llama-cpp-npu-vision-upstream", "ggml", "include"])
      File.mkdir_p!(exempt_dir)
      File.write!(Path.join(exempt_dir, "ggml.h"), "/* vendored under llama.cpp */\n")
      hits2 = scan(tmp)
      exempt_ok? = hits2 == [expected]

      checks = [
        {"positive control: clean workspace with only canonical ggml passes", clean_ok?},
        {"negative control: planted rogue ggml.h fails", rogue_ok?},
        {"llama.cpp exemption honoured", exempt_ok?}
      ]
      Enum.each(checks, fn {name, ok} ->
        IO.puts("  #{if ok, do: "ok  ", else: "FAIL"} #{name}")
      end)
      bad = Enum.count(checks, fn {_, ok} -> not ok end)
      IO.puts("  #{length(checks) - bad} of #{length(checks)} controls fired.")
      if bad > 0, do: 1, else: 0
    after
      File.rm_rf!(tmp)
    end
  end

  defp rand, do: Integer.to_string(:erlang.unique_integer([:positive]))
end
