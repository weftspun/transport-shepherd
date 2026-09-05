defmodule Shepherd.Gates.LogbookCount do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_logbook_count.py`.
  Same rules, same 3 self-test controls.

  If `pages/logbook.qmd` states an entry count ("These N entries..."), N must
  match the entries on disk (`logbook/logbook-*.md`). Rule 3: if the page
  carries no such phrase, the gate reports ok but names the observed count
  so an operator sees a number rather than a bare success.

  Detection floor: none. All `N entries` phrases in the .qmd are
  enumerated and every one must equal the disk count.
  """

  @count_rx ~r/\b(\d+)\s+entries\b/

  def run(["--self-test"]), do: self_test()

  def run(argv) do
    root =
      case Enum.find_index(argv, &(&1 == "--repo")) do
        nil -> File.cwd!()
        i -> Enum.at(argv, i + 1)
      end
    gate(root)
  end

  def entries_on_disk(root) do
    # Path.wildcard returns [] on Windows for a path with mixed forward and
    # back slashes (System.tmp_dir!() returns `C:\...\Temp` and Path.join
    # doesn't normalise). Enumerate File.ls and filter by the sentinel
    # prefix + extension instead — same match set, no OS-quirks glob.
    dir = Path.join(root, "logbook")
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.count(entries, fn n ->
          String.starts_with?(n, "logbook-") and Path.extname(n) == ".md"
        end)
      _ -> 0
    end
  end

  def scan(root) do
    disk = entries_on_disk(root)
    qmd = Path.join([root, "pages", "logbook.qmd"])
    declared =
      case File.read(qmd) do
        {:ok, text} ->
          Regex.scan(@count_rx, text)
          |> Enum.map(fn [_, n] -> String.to_integer(n) end)
        _ -> []
      end
    {disk, declared}
  end

  def check(root) do
    {disk, declared} = scan(root)
    cond do
      declared == [] -> {:ok, "pages/logbook.qmd declares no count; disk has #{disk} entries"}
      Enum.any?(declared, &(&1 != disk)) ->
        {:fail, "pages/logbook.qmd declares #{inspect(declared)}, disk has #{disk} entries"}
      true ->
        {:ok, "pages/logbook.qmd declares #{hd(declared)}, matches #{disk} entries on disk"}
    end
  end

  defp gate(root) do
    case check(root) do
      {:ok, msg} -> IO.puts("ok   #{msg}"); 0
      {:fail, msg} -> IO.puts("FAIL #{msg}"); 1
    end
  end

  def self_test do
    tmp1 = plant_temp("These 3 entries...\n", 3)
    positive = check(tmp1)
    File.rm_rf!(tmp1)

    tmp2 = plant_temp("These 145 entries...\n", 26)
    negative = check(tmp2)
    File.rm_rf!(tmp2)

    tmp3 = plant_temp("no count here.\n", 5)
    silent_skip = check(tmp3)
    File.rm_rf!(tmp3)

    checks = [
      {"positive control: declared 3 matches disk 3", match?({:ok, _}, positive)},
      {"negative control: declared 145 vs disk 26 rejected", match?({:fail, _}, negative)},
      {"silent-skip: no phrase but disk count reported", match?({:ok, _}, silent_skip)}
    ]
    Enum.each(checks, fn {name, ok} ->
      IO.puts("  #{if ok, do: "ok  ", else: "FAIL"} #{name}")
    end)
    bad = Enum.count(checks, fn {_, ok} -> not ok end)
    IO.puts("  #{length(checks) - bad} of #{length(checks)} controls fired.")
    if bad > 0, do: 1, else: 0
  end

  defp plant_temp(qmd_body, n_entries) do
    tmp = Path.join(System.tmp_dir!(), "shepherd-logbook-count-" <> rand())
    File.mkdir_p!(Path.join(tmp, "pages"))
    File.mkdir_p!(Path.join(tmp, "logbook"))
    File.write!(Path.join([tmp, "pages", "logbook.qmd"]), qmd_body)
    Enum.each(0..(n_entries - 1), fn i ->
      name = "logbook-#{String.pad_leading(Integer.to_string(i), 4, "0")}.md"
      File.write!(Path.join([tmp, "logbook", name]), "x\n")
    end)
    tmp
  end

  defp rand, do: Integer.to_string(:erlang.unique_integer([:positive]))
end
