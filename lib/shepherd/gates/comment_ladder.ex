defmodule Shepherd.Gates.CommentLadder do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_comment_ladder.py`.
  Same rungs, same 8 self-test controls.

  A changed source file may not climb the comment-density ladder. Rungs
  3/5/10/15/20/25/30/35/40 %. New files enter at 10 %. Files under 100
  non-blank lines are silent. Deleting code raises density without a
  comment added, so the rung is slack in that direction (the control
  bounds how much).

  Detection floor: `comment_density_util` uses line-toggle docstring
  detection, not AST — a non-docstring triple-quoted literal still
  counts as comment. Good enough for rung comparison, not byte-exact
  against the Python original on unusual files.
  """

  alias Shepherd.Gates.CommentDensityUtil

  @frozen ["rfd/2", "changelog/", "data/"]
  @rungs [0.03, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40]
  @entry 0.10
  @min_lines 100

  def run(["--self-test"]), do: self_test()

  def run(argv) do
    {repo, base, mode} = parse(argv)
    case mode do
      :baseline -> baseline(repo)
      :gate ->
        {n, failures} = check(repo, base, true)
        IO.puts("")
        if failures != [] do
          Enum.each(failures, fn {path, ratio, ceiling, was} ->
            IO.puts("#{path} is #{pct(ratio)}% comments, above the #{Float.round(ceiling * 100)}% rung it #{if was, do: "sits on", else: "enters at"}.")
          end)
          IO.puts("Move the reasoning into the commit message.")
          1
        else
          IO.puts("#{n} changed source file(s) within their rung.")
          0
        end
    end
  end

  defp parse(argv) do
    repo =
      case Enum.find(argv, &(not String.starts_with?(&1, "--"))) do
        nil -> "."
        r -> r
      end
    base =
      case Enum.find_index(argv, &(&1 == "--base")) do
        nil -> "HEAD"
        i -> Enum.at(argv, i + 1)
      end
    mode = if "--baseline" in argv, do: :baseline, else: :gate
    {repo, base, mode}
  end

  def rung_of(ratio) do
    Enum.find(@rungs, fn r -> ratio <= r + 1.0e-9 end)
  end

  defp git(repo, args) do
    case System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) do
      {out, 0} -> out
      _ -> nil
    end
  end

  defp renames(repo, base) do
    (git(repo, ["diff", "--name-status", "-M", base]) || "")
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, "\t") do
        [status, from, to] ->
          if String.starts_with?(status, "R"), do: Map.put(acc, to, from), else: acc
        _ -> acc
      end
    end)
  end

  defp at_ref(repo, ref, path, moved) do
    text = git(repo, ["show", "#{ref}:#{path}"])
    if text == nil and Map.has_key?(moved, path) do
      git(repo, ["show", "#{ref}:#{moved[path]}"])
    else
      text
    end
  end

  defp changed_files(repo, base) do
    sets =
      for args <- [["diff", "--name-only", base],
                   ["diff", "--name-only", "--cached"],
                   ["ls-files", "--others", "--exclude-standard"]] do
        (git(repo, args) || "") |> String.split() |> MapSet.new()
      end
    sets
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
    |> Enum.to_list()
    |> Enum.filter(&CommentDensityUtil.source?/1)
    |> Enum.reject(fn f -> Enum.any?(@frozen, &String.starts_with?(f, &1)) end)
    |> Enum.sort()
  end

  defp tracked(repo) do
    (git(repo, ["ls-files"]) || "")
    |> String.split()
    |> Enum.filter(&CommentDensityUtil.source?/1)
    |> Enum.reject(fn f -> Enum.any?(@frozen, &String.starts_with?(f, &1)) end)
  end

  defp read_file(repo, path) do
    full = Path.join(repo, path)
    case File.read(full) do
      {:ok, text} -> text
      _ -> nil
    end
  end

  def check(repo, base, verbose) do
    moved = renames(repo, base)
    rows =
      changed_files(repo, base)
      |> Enum.reduce([], fn path, acc ->
        now = read_file(repo, path)
        cond do
          now == nil -> acc
          true ->
            {n_com, n_code, n_ratio} = CommentDensityUtil.density(now, Path.extname(path))
            if n_com + n_code < @min_lines do
              acc
            else
              before = at_ref(repo, base, path, moved)
              {ceiling, was} =
                if before == nil do
                  {@entry, nil}
                else
                  {b_com, _, w} = CommentDensityUtil.density(before, Path.extname(path))
                  rung = rung_of(w) || w
                  ceil = if n_com <= b_com, do: rung, else: min(w, rung)
                  {ceil, w}
                end
              ok = n_ratio <= ceiling + 1.0e-9
              [{ok, path, n_ratio, was, ceiling} | acc]
            end
        end
      end)
      |> Enum.reverse()
    failures =
      Enum.reduce(rows, [], fn {ok, path, r, w, c}, acc ->
        if ok, do: acc, else: [{path, r, c, w} | acc]
      end)
      |> Enum.reverse()
    if verbose do
      if rows == [], do: IO.puts("no source files changed against #{base}")
      Enum.each(rows, fn {ok, path, r, w, c} ->
        was = if w == nil, do: "new", else: "#{pct(w)}%"
        IO.puts("  #{if ok, do: "ok  ", else: "FAIL"} #{String.pad_trailing(path, 48)} #{pad_pct(r)}%  was #{String.pad_leading(was, 6)}  rung #{pad_pct_int(c)}%")
      end)
    end
    {length(rows), failures}
  end

  defp baseline(repo) do
    vals =
      tracked(repo)
      |> Enum.reduce([], fn path, acc ->
        case read_file(repo, path) do
          nil -> acc
          text ->
            {com, code, ratio} = CommentDensityUtil.density(text, Path.extname(path))
            if com + code >= @min_lines, do: [{ratio, path} | acc], else: acc
        end
      end)
      |> Enum.sort()
    if vals == [] do
      IO.puts("no source files of #{@min_lines}+ lines")
      1
    else
      only = Enum.map(vals, fn {v, _} -> v end)
      n = length(only)
      IO.puts("  #{n} files of #{@min_lines}+ non-blank lines")
      IO.puts("  floor #{pct(hd(only))}% (#{elem(hd(vals), 1)})")
      p90 = Enum.at(only, trunc(n * 0.9))
      IO.puts("  median #{pct(median(only))}%   p90 #{pct(p90)}%   max #{pct(List.last(only))}% (#{elem(List.last(vals), 1)})")
      Enum.each(@rungs, fn r ->
        cnt = Enum.count(only, &(rung_of(&1) == r))
        tag = if r == @entry, do: "<- entry", else: ""
        IO.puts("    rung #{String.pad_leading("#{trunc(r * 100)}", 2)}% #{String.pad_trailing(tag, 9)} #{cnt}")
      end)
      IO.puts("    off the top         #{Enum.count(only, &(rung_of(&1) == nil))}")
      0
    end
  end

  defp median(list) do
    sorted = Enum.sort(list)
    n = length(sorted)
    if rem(n, 2) == 1 do
      Enum.at(sorted, div(n, 2))
    else
      (Enum.at(sorted, div(n, 2) - 1) + Enum.at(sorted, div(n, 2))) / 2
    end
  end

  defp pct(x), do: :io_lib.format("~.1f", [x * 100]) |> to_string()
  defp pad_pct(x), do: :io_lib.format("~5.1f", [x * 100]) |> to_string()
  defp pad_pct_int(x), do: :io_lib.format("~4.0f", [x * 100]) |> to_string()

  # ---- self-test: mirrors the Python fixture set. ---------------------

  def self_test do
    with {:ok, repo} <- make_tmp_repo() do
      try do
        _run(repo, ["init", "-q"])
        _run(repo, ["config", "user.email", "gate@example.com"])
        _run(repo, ["config", "user.name", "gate"])
        _run(repo, ["config", "commit.gpgsign", "false"])

        fixture(repo, "a.py", 40, 180)
        _run(repo, ["add", "-A"])
        _run(repo, ["commit", "-qm", "base"])

        results = []

        # 1. padded past its rung
        fixture(repo, "a.py", 60, 180)
        {_, f} = check(repo, "HEAD", false)
        results = results ++ [{"a file padded past its rung is rejected", has?(f, "a.py")}]

        # 2. added inside the rung
        fixture(repo, "a.py", 43, 180)
        {_, f} = check(repo, "HEAD", false)
        results = results ++ [{"a comment added inside the rung is rejected", has?(f, "a.py")}]

        # 3. density falls
        fixture(repo, "a.py", 40, 220)
        {_, f} = check(repo, "HEAD", false)
        results = results ++ [{"a file whose density falls is accepted", f == []}]

        # 4. deletion inside the rung
        fixture(repo, "a.py", 40, 170)
        {_, f} = check(repo, "HEAD", false)
        results = results ++ [{"deleting code inside the rung is accepted, comments untouched", f == []}]

        # 5. deletion past the rung
        fixture(repo, "a.py", 40, 120)
        {_, f} = check(repo, "HEAD", false)
        results = results ++ [{"deleting code past the rung is rejected, comments untouched", has?(f, "a.py")}]

        # 6. new file above entry rung
        fixture(repo, "a.py", 40, 180)
        fixture(repo, "new.py", 40, 180)
        _run(repo, ["add", "-A"])
        {_, f} = check(repo, "HEAD", false)
        results = results ++ [{"a new file above the entry rung is rejected", has?(f, "new.py")}]

        # 7. new file under entry rung
        File.rm!(Path.join(repo, "new.py"))
        fixture(repo, "ok.py", 18, 180)
        _run(repo, ["add", "-A"])
        {_, f} = check(repo, "HEAD", false)
        results = results ++ [{"a new file under the entry rung is accepted", f == []}]

        # 8. 3% rung deletion
        fixture(repo, "three.py", 6, 250)
        _run(repo, ["add", "-A"])
        _run(repo, ["commit", "-qm", "three base"])
        fixture(repo, "three.py", 6, 130)
        {_, f} = check(repo, "HEAD", false)
        results = results ++ [{"deleting code past the 3% rung is rejected", has?(f, "three.py")}]

        bad = Enum.count(results, fn {_, ok?} -> not ok? end)
        Enum.each(results, fn {name, ok?} ->
          IO.puts("  #{if ok?, do: "ok  ", else: "FAIL"} control: #{name}")
        end)
        IO.puts("  #{length(results) - bad} of #{length(results)} controls fired.")
        if bad > 0, do: 1, else: 0
      after
        File.rm_rf!(repo)
      end
    end
  end

  defp make_tmp_repo do
    dir = Path.join(System.tmp_dir!(), "shepherd_ladder_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    {:ok, dir}
  end

  defp has?(failures, path), do: Enum.any?(failures, fn {p, _, _, _} -> p == path end)

  defp fixture(repo, name, comments, code_lines) do
    body =
      Enum.map_join(0..(comments - 1), "", fn i -> "# note #{i}\n" end) <>
      Enum.map_join(0..(code_lines - 1), "", fn i -> "x#{i} = #{i}\n" end)
    File.write!(Path.join(repo, name), body)
  end

  defp _run(repo, args) do
    System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
  end
end
