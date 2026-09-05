defmodule Shepherd.Gates.Tropes do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_tropes.py`.
  Same 5 tell patterns, same 9 self-test controls.

  Trope density did not rise. Scans `rfd/*/README.md`, `rfd/*/DETAILS.md`,
  and `logbook/*.md` for five recurring tells the prose-detrope subagent
  removes most often. In gate mode (--base), a changed file may not raise
  its density above what it was on the base branch.

  Detection floor: report mode enumerates every scoped file and shows the
  density; a file that scores 0 is silent (there's nothing to report).
  """

  # Elixir regex flag `i` for case-insensitive, `s` for dot-matches-newline.
  # Backslashes doubled where needed for the Elixir sigil.
  @tells [
    {:em_dash_join, ~r/ [-—][-—]? /u},
    {:counting_announcement,
      ~r/\b(in|for|on)\s+(two|three|four|five|six)\s+(ways|reasons|counts|things|senses)\b/i},
    {:reasoning_leak,
      ~r/\b(the reason .+? is that|the whole point .+? is that|what makes .+? is)\b/i},
    {:pompous_copula, ~r/\b(is|are)\s+what\s+(makes|proves|shows|says)\b/i},
    {:exact_window, ~r/\bthe exact (window|moment|shape|line|point|reason|failure)\b/i}
  ]

  @file_patterns [
    ~r{^rfd/[^/]+/(README|DETAILS)\.md$},
    ~r{^logbook/.+\.md$}
  ]

  @code_fence ~r/```.*?```/s

  def run(["--self-test"]), do: self_test()

  def run(argv) do
    root =
      case Enum.find_index(argv, &(&1 == "--repo")) do
        nil -> File.cwd!()
        i -> Enum.at(argv, i + 1)
      end
    base =
      case Enum.find_index(argv, &(&1 == "--base")) do
        nil -> nil
        i -> Enum.at(argv, i + 1)
      end
    if base, do: gate(root, base), else: report(root)
  end

  def in_scope?(path) do
    p = String.replace(path, "\\", "/")
    Enum.any?(@file_patterns, &Regex.match?(&1, p))
  end

  def count_tropes(text) do
    stripped = Regex.replace(@code_fence, text, "")
    per =
      for {name, rx} <- @tells,
          into: %{},
          do: {name, length(Regex.scan(rx, stripped))}
    {Enum.reduce(Map.values(per), 0, &+/2), per}
  end

  def non_blank_lines(text) do
    text
    |> String.split("\n")
    |> Enum.count(fn line -> String.trim(line) != "" end)
  end

  def density(text) do
    n = non_blank_lines(text)
    {hits, _} = count_tropes(text)
    if n == 0, do: 0.0, else: 100.0 * hits / n
  end

  defp git_show(ref, path, root) do
    case System.cmd("git", ["show", "#{ref}:#{path}"], cd: root, stderr_to_stdout: true) do
      {out, 0} -> out
      _ -> nil
    end
  end

  defp changed_files(base, root) do
    {out, 0} = System.cmd("git", ["diff", "--name-only", "#{base}...HEAD"], cd: root)
    out |> String.split("\n", trim: true) |> Enum.filter(&in_scope?/1)
  end

  defp gate(root, base) do
    changed = changed_files(base, root)
    if changed == [] do
      IO.puts("0 changed prose file(s) in scope.")
      0
    else
      fails =
        Enum.reduce(changed, 0, fn path, acc ->
          full = Path.join(root, path)
          if not File.regular?(full) do
            acc
          else
            after_text = File.read!(full)
            before_text = git_show(base, path, root) || ""
            d_now = density(after_text)
            d_was = density(before_text)
            if d_now > d_was + 0.001 do
              {hits, per} = count_tropes(after_text)
              top =
                per
                |> Enum.filter(fn {_, v} -> v > 0 end)
                |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
                |> Enum.join(", ")
              IO.puts("  FAIL #{path}  #{fmt(d_now)}% was #{fmt(d_was)}%  (#{hits} hits: #{top})")
              acc + 1
            else
              IO.puts("  ok   #{path}  #{fmt(d_now)}% was #{fmt(d_was)}%")
              acc
            end
          end
        end)
      IO.puts("#{fails} of #{length(changed)} scoped file(s) rose above their prior density.")
      if fails > 0, do: 1, else: 0
    end
  end

  defp report(root) do
    scanned =
      walk_rfd(Path.join(root, "rfd"), root, 0) +
      walk_logbook(Path.join(root, "logbook"), root)
    IO.puts("#{scanned} scoped file(s) scanned.")
    0
  end

  defp walk_rfd(dir, root, count) do
    case File.ls(dir) do
      {:error, _} -> count
      {:ok, entries} ->
        Enum.reduce(entries, count, fn name, acc ->
          full = Path.join(dir, name)
          cond do
            File.dir?(full) -> walk_rfd(full, root, acc)
            name in ["README.md", "DETAILS.md"] ->
              rel = Path.relative_to(full, root)
              d = density(File.read!(full))
              if d > 0, do: IO.puts("  #{fmt5(d)}%  #{rel}")
              acc + 1
            true -> acc
          end
        end)
    end
  end

  defp walk_logbook(dir, root) do
    case File.ls(dir) do
      {:error, _} -> 0
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.reduce(0, fn name, acc ->
          full = Path.join(dir, name)
          rel = Path.relative_to(full, root)
          d = density(File.read!(full))
          if d > 0, do: IO.puts("  #{fmt5(d)}%  #{rel}")
          acc + 1
        end)
    end
  end

  defp fmt(d), do: :io_lib.format("~.2f", [d]) |> to_string()
  defp fmt5(d), do: :io_lib.format("~5.2f", [d]) |> to_string()

  def self_test do
    controls = [
      {"em-dash between clauses", "The gate ran — every control fired.", :em_dash_join, 1},
      {"hyphen range unchanged", "The window is day 11-14.", :em_dash_join, 0},
      {"markdown bullet is not a join",
        "See the deployment notes:\n\n- first item\n- second item\n- third item\n",
        :em_dash_join, 0},
      {"counting announcement", "It shapes the checks in three ways.", :counting_announcement, 1},
      {"prose that mentions three ways", "Three ways lead there.", :counting_announcement, 0},
      {"reasoning leak", "The reason it holds is that quorum tolerates one down.", :reasoning_leak, 1},
      {"pompous copula", "The second check is what proves the restart.", :pompous_copula, 1},
      {"plain because", "The second check proves the restart because a stale write would fail.", :pompous_copula, 0},
      {"exact window", "That is the exact window in which a shard can stall.", :exact_window, 1}
    ]

    fails =
      Enum.reduce(controls, 0, fn {label, text, tell, expected}, acc ->
        {_, per} = count_tropes(text)
        got = Map.get(per, tell, 0)
        if got != expected do
          IO.puts("  FAIL #{label}: #{tell} expected #{expected}, got #{got}")
          acc + 1
        else
          acc
        end
      end)

    total = length(controls)
    if fails > 0 do
      IO.puts("#{fails} of #{total} controls failed")
      1
    else
      IO.puts("ok   #{total} of #{total} controls fired in both directions")
      0
    end
  end
end
