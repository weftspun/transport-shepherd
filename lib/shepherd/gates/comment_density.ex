defmodule Shepherd.Gates.CommentDensity do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/check_comment_density.py`.
  Same rule, same negative-control shape.

  A change must match the density of the code it edits. C/C++ sources
  (.c .cc .cpp .cxx .h .hpp .m .mm) — a changed file may not exceed the
  greater of its own density before the change and the p90 of its peers.
  Peers are files with the same extension under the same top-level
  directory, so a header is judged against headers.

  Detection floor: files under 200 non-blank lines are silent (one
  comment swings the ratio). Vendored trees (thirdparty/, third_party/,
  external/, vendor/, modules/mono/glue/) are skipped. The Godot licence
  banner (first 31 lines when the first 3 contain `/*****`) is skipped
  so it does not dominate small files.
  """

  @source_ext MapSet.new([".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".m", ".mm"])
  @vendored ["thirdparty/", "third_party/", "external/", "vendor/", "modules/mono/glue/"]
  @min_lines 200
  @banner_lines 31

  def run(["--self-test"]), do: self_test()

  def run(argv) do
    {repo, base, self_test?} = parse(argv)
    if repo == nil do
      IO.puts(:stderr, "usage: mix gates comment-density <repo> [--base HEAD] [--self-test]")
      2
    else
      {n, failures} = check(repo, base, true)
      rc =
        if self_test? do
          self_test_against(repo, base)
        else
          0
        end
      IO.puts("")
      cond do
        rc != 0 -> rc
        failures != [] ->
          Enum.each(failures, fn {path, ratio, ceiling} ->
            IO.puts("#{path} is #{pct(ratio)}% comments, above the #{pct(ceiling)}% its peers allow.")
          end)
          IO.puts("Move the reasoning into the commit message.")
          1
        true ->
          IO.puts("#{n} changed source file(s) within the density of their peers.")
          0
      end
    end
  end

  defp parse(argv) do
    {flags, positional} = Enum.split_with(argv, &String.starts_with?(&1, "--"))
    repo = List.first(positional)
    base =
      case Enum.find_index(argv, &(&1 == "--base")) do
        nil -> "HEAD"
        i -> Enum.at(argv, i + 1)
      end
    {repo, base, "--self-test" in flags}
  end

  def density(lines) do
    body =
      if length(lines) > 40 and String.contains?(Enum.join(Enum.take(lines, 3), ""), "/*****") do
        Enum.drop(lines, @banner_lines)
      else
        lines
      end
    {comment, code, _} =
      Enum.reduce(body, {0, 0, false}, fn raw, {c, k, in_block} ->
        line = String.trim(raw)
        cond do
          line == "" -> {c, k, in_block}
          in_block ->
            still = not String.contains?(line, "*/")
            {c + 1, k, still}
          String.starts_with?(line, "/*") ->
            still = not String.contains?(line, "*/")
            {c + 1, k, still}
          String.starts_with?(line, "//") or String.starts_with?(line, "*") ->
            {c + 1, k, false}
          true ->
            {c, k + 1, false}
        end
      end)
    total = comment + code
    {comment, code, (if total == 0, do: 0.0, else: comment / total)}
  end

  defp git(repo, args) do
    case System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) do
      {out, 0} -> out
      _ -> nil
    end
  end

  defp read_file(repo, path) do
    case File.read(Path.join(repo, path)) do
      {:ok, text} -> String.split(text, "\n")
      _ -> nil
    end
  end

  defp at_ref(repo, ref, path) do
    case git(repo, ["show", "#{ref}:#{path}"]) do
      nil -> nil
      text -> String.split(text, "\n")
    end
  end

  defp vendored?(f) do
    p = String.replace(f, "\\", "/")
    Enum.any?(@vendored, &String.starts_with?(p, &1))
  end

  defp source?(f), do: MapSet.member?(@source_ext, Path.extname(f))

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
    |> Enum.filter(&source?/1)
    |> Enum.reject(&vendored?/1)
    |> Enum.sort()
  end

  defp peers(repo, path, cache) do
    ext = Path.extname(path)
    top = path |> String.split("/") |> List.first()
    key = {top, ext}
    case Map.fetch(cache, key) do
      {:ok, v} -> {v, cache}
      :error ->
        listing = git(repo, ["ls-files", "#{top}/*#{ext}"]) || ""
        vals =
          listing
          |> String.split()
          |> Enum.reject(fn f -> f == path or vendored?(f) end)
          |> Enum.reduce([], fn f, acc ->
            case read_file(repo, f) do
              nil -> acc
              lines ->
                {c, k, r} = density(lines)
                if c + k >= @min_lines, do: [r | acc], else: acc
            end
          end)
        {vals, Map.put(cache, key, vals)}
    end
  end

  def check(repo, base, verbose) do
    files = changed_files(repo, base)
    if files == [] do
      if verbose, do: IO.puts("no source files changed against #{base}")
      {0, []}
    else
      {failures, _cache} =
        Enum.reduce(files, {[], %{}}, fn path, {fails, cache} ->
          case read_file(repo, path) do
            nil -> {fails, cache}
            now ->
              {n_com, n_code, n_ratio} = density(now)
              if n_com + n_code < @min_lines do
                {fails, cache}
              else
                {peer, cache2} = peers(repo, path, cache)
                if peer == [] do
                  {fails, cache2}
                else
                  sorted = Enum.sort(peer)
                  p90 = Enum.at(sorted, trunc(length(sorted) * 0.9))
                  med = median(sorted)
                  before = at_ref(repo, base, path)
                  b_ratio = if before, do: elem(density(before), 2), else: 0.0
                  ceiling = max(p90, b_ratio)
                  ok = n_ratio <= ceiling + 1.0e-9
                  if verbose do
                    IO.puts("  #{if ok, do: "ok  ", else: "FAIL"} #{String.pad_trailing(path, 52)} #{pad(n_ratio)}%  was #{pad(b_ratio)}%  peers median #{pad4(med)}% p90 #{pad4(p90)}%")
                  end
                  if ok, do: {fails, cache2}, else: {[{path, n_ratio, ceiling} | fails], cache2}
                end
              end
          end
        end)
      {length(files), Enum.reverse(failures)}
    end
  end

  defp self_test_against(repo, base) do
    files = changed_files(repo, base)
    if files == [] do
      IO.puts("self test needs at least one changed source file")
      1
    else
      target = hd(files)
      full = Path.join(repo, target)
      original = File.read!(full)
      try do
        padding = Enum.map_join(0..399, "\n", fn i -> "// padding line #{i}" end)
        File.write!(full, original <> "\n" <> padding <> "\n")
        {_, padded} = check(repo, base, false)
        caught = Enum.any?(padded, fn {p, _, _} -> p == target end)
        IO.puts("  #{if caught, do: "ok  ", else: "FAIL"} negative control: #{target} padded with 400 comment lines is rejected")
        if not caught do
          IO.puts("       the gate accepted an obviously over-commented file.")
          1
        else
          0
        end
      after
        File.write!(full, original)
      end
    end
  end

  # Self-test builds a temp git repo with C++ peers and modifies one file.
  def self_test do
    with {:ok, repo} <- make_tmp_repo() do
      try do
        _git(repo, ["init", "-q"])
        _git(repo, ["config", "user.email", "gate@example.com"])
        _git(repo, ["config", "user.name", "gate"])
        _git(repo, ["config", "commit.gpgsign", "false"])

        File.mkdir_p!(Path.join(repo, "servers"))
        for i <- 1..10 do
          # Peer files: 220 lines of code, ~4% comments = ~9 comment lines
          body =
            Enum.map_join(1..9, "", fn j -> "// peer #{i} note #{j}\n" end) <>
            Enum.map_join(1..220, "", fn j -> "int peer#{i}_var#{j} = #{j};\n" end)
          File.write!(Path.join(repo, "servers/peer#{i}.cpp"), body)
        end
        # Target starts at ~4% too.
        target_body =
          Enum.map_join(1..9, "", fn j -> "// target note #{j}\n" end) <>
          Enum.map_join(1..220, "", fn j -> "int target_var#{j} = #{j};\n" end)
        File.write!(Path.join(repo, "servers/target.cpp"), target_body)
        _git(repo, ["add", "-A"])
        _git(repo, ["commit", "-qm", "base"])

        controls = []

        # 1. positive control: an unpadded edit is accepted
        edit_body =
          Enum.map_join(1..9, "", fn j -> "// target note #{j}\n" end) <>
          Enum.map_join(1..222, "", fn j -> "int target_var#{j} = #{j};\n" end)
        File.write!(Path.join(repo, "servers/target.cpp"), edit_body)
        {_, f} = check(repo, "HEAD", false)
        controls = controls ++ [{"an unpadded edit is accepted", f == []}]

        # 2. negative control: pad target with 100 comments, expect FAIL
        padded_body = target_body <> Enum.map_join(1..100, "", fn j -> "// pad #{j}\n" end)
        File.write!(Path.join(repo, "servers/target.cpp"), padded_body)
        {_, f} = check(repo, "HEAD", false)
        controls = controls ++ [{"a file padded past peer p90 is rejected",
                                  Enum.any?(f, fn {p, _, _} -> p == "servers/target.cpp" end)}]

        # 3. a file below MIN_LINES is silent (accepted regardless)
        File.write!(Path.join(repo, "servers/target.cpp"),
                    Enum.map_join(1..50, "", fn j -> "// small #{j}\n" end) <>
                    Enum.map_join(1..50, "", fn j -> "int s#{j} = #{j};\n" end))
        {_, f} = check(repo, "HEAD", false)
        controls = controls ++ [{"a short file (<200 lines) is silent",
                                  not Enum.any?(f, fn {p, _, _} -> p == "servers/target.cpp" end)}]

        # 4. vendored path is skipped
        File.mkdir_p!(Path.join(repo, "thirdparty"))
        File.write!(Path.join(repo, "thirdparty/vendor.cpp"),
                    Enum.map_join(1..200, "", fn j -> "// vendor pad #{j}\n" end) <>
                    Enum.map_join(1..50, "", fn j -> "int v#{j} = #{j};\n" end))
        _git(repo, ["add", "-A"])
        {_, f} = check(repo, "HEAD", false)
        controls = controls ++ [{"vendored path is skipped",
                                  not Enum.any?(f, fn {p, _, _} -> p == "thirdparty/vendor.cpp" end)}]

        # 5. Godot banner is skipped: put a licence banner + comments; density measured on body.
        banner = "/*****************\n" <> String.duplicate(" * banner\n", 30) <>
                 Enum.map_join(1..2, "", fn j -> "// real note #{j}\n" end) <>
                 Enum.map_join(1..250, "", fn j -> "int b#{j} = #{j};\n" end)
        {_, _, ratio} = density(String.split(banner, "\n"))
        controls = controls ++ [{"Godot banner is skipped so it does not dominate", ratio < 0.05}]

        bad = Enum.count(controls, fn {_, ok?} -> not ok? end)
        Enum.each(controls, fn {name, ok?} ->
          IO.puts("  #{if ok?, do: "ok  ", else: "FAIL"} control: #{name}")
        end)
        IO.puts("  #{length(controls) - bad} of #{length(controls)} controls fired.")
        if bad > 0, do: 1, else: 0
      after
        File.rm_rf!(repo)
      end
    end
  end

  defp make_tmp_repo do
    dir = Path.join(System.tmp_dir!(), "shepherd_density_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    {:ok, dir}
  end

  defp _git(repo, args), do: System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)

  defp median(sorted) do
    n = length(sorted)
    cond do
      n == 0 -> 0.0
      rem(n, 2) == 1 -> Enum.at(sorted, div(n, 2))
      true -> (Enum.at(sorted, div(n, 2) - 1) + Enum.at(sorted, div(n, 2))) / 2
    end
  end

  defp pct(x), do: :io_lib.format("~.1f", [x * 100]) |> to_string()
  defp pad(x), do: :io_lib.format("~5.1f", [x * 100]) |> to_string()
  defp pad4(x), do: :io_lib.format("~4.1f", [x * 100]) |> to_string()
end
