defmodule Shepherd.Gates.BlocklistDetail do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_blocklist_detail.py`.
  Same rules, same 6 self-test controls.

  A blocklist row saying "see below" must resolve to a section in
  BLOCKLIST.md, and every section in BLOCKLIST.md must correspond to a
  row in the table. Matching is on distinctive stems (first 6 chars,
  lowercase, stopwords removed) with best-match one-to-one assignment.

  Detection floor: a section whose title shares no stem with its row
  reads as unmatched even when a human would pair them (false alarm;
  fix by naming the subject in the title). Two rows sharing stems can
  match the same section; a duplicated argument is not caught.
  """

  @stopwords MapSet.new(~w(
    a an and as at the is it its for from in into no not of on or to with that
    this which why what we use only here own are was were must be has have than
  ))

  def run(["--self-test"]), do: self_test()

  def run(argv) do
    root =
      case argv do
        [] -> "."
        [dir | _] when not (dir in ["--self-test"]) -> dir
        _ -> "."
      end

    claude = Path.join(root, "CLAUDE.md")
    block = Path.join(root, "BLOCKLIST.md")

    cond do
      not File.exists?(claude) ->
        IO.puts("FAIL: #{claude} does not exist"); 1
      not File.exists?(block) ->
        IO.puts("FAIL: #{block} does not exist"); 1
      true ->
        problems = check(File.read!(claude), File.read!(block))
        if problems == [] do
          rows = length(table_rows(File.read!(claude)))
          secs = length(detail_sections(File.read!(block)))
          IO.puts("ok   #{rows} rows promising an argument, #{secs} sections, and they agree")
          0
        else
          IO.puts("FAIL: the blocklist and its reasoning disagree")
          Enum.each(problems, &IO.puts("  " <> &1))
          1
        end
    end
  end

  def tokens(text) do
    text = String.replace(String.downcase(text), ~r/[\*_`]/, " ")
    Regex.scan(~r/[a-z0-9][a-z0-9.\-]{2,}/, text)
    |> Enum.map(fn [t] -> t end)
    |> Enum.reject(&MapSet.member?(@stopwords, &1))
    |> Enum.map(&String.slice(&1, 0, 6))
    |> MapSet.new()
  end

  def table_rows(claude_md) do
    claude_md
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "|"))
    |> Enum.map(fn line ->
      cells = line |> String.trim("|") |> String.split("|") |> Enum.map(&String.trim/1)
      {cells, String.downcase(line)}
    end)
    |> Enum.reject(fn {cells, _} ->
      length(cells) < 2 or
        String.replace(hd(cells), ~r/[- ]/, "") == "" or
        String.starts_with?(String.downcase(hd(cells)), "source")
    end)
    |> Enum.filter(fn {_, low} -> String.contains?(low, "see below") end)
    |> Enum.map(fn {cells, _} ->
      first = hd(cells)
      {first, tokens(first)}
    end)
  end

  def detail_sections(blocklist_md) do
    Regex.scan(~r/^### (.+)$/m, blocklist_md)
    |> Enum.map(fn [_, title] -> {title, tokens(title)} end)
  end

  def check(claude_md, blocklist_md) do
    rows = table_rows(claude_md)
    sections = detail_sections(blocklist_md)

    []
    |> maybe_add(rows == [],
      "no blocklist row says 'see below' -- either the table lost its promises or this " <>
      "gate is looking at the wrong document, and both are worth stopping for")
    |> maybe_add(sections == [],
      "BLOCKLIST.md has no ### sections; the detail document is empty")
    |> assign_matches(rows, sections)
  end

  defp maybe_add(list, false, _), do: list
  defp maybe_add(list, true, msg), do: list ++ [msg]

  defp assign_matches(problems, rows, sections) do
    scored =
      for {r, {_, row_toks}} <- Enum.with_index(rows) |> Enum.map(fn {v, i} -> {i, v} end),
          {i, {_, sec_toks}} <- Enum.with_index(sections) |> Enum.map(fn {v, i} -> {i, v} end),
          overlap = MapSet.intersection(row_toks, sec_toks),
          MapSet.size(overlap) > 0,
          do: {MapSet.size(overlap), r, i}

    scored = Enum.sort(scored, :desc)

    {claimed, matched} =
      Enum.reduce(scored, {%{}, MapSet.new()}, fn {_score, r, i}, {c, m} ->
        cond do
          Map.has_key?(c, r) -> {c, m}
          MapSet.member?(m, i) -> {c, m}
          true -> {Map.put(c, r, i), MapSet.put(m, i)}
        end
      end)

    unmatched_rows =
      rows
      |> Enum.with_index()
      |> Enum.reject(fn {_, r} -> Map.has_key?(claimed, r) end)
      |> Enum.map(fn {{label, _}, _r} ->
        "row #{inspect(label)} says 'see below' and no unclaimed section in BLOCKLIST.md shares a word with it"
      end)

    unmatched_sections =
      sections
      |> Enum.with_index()
      |> Enum.reject(fn {_, i} -> MapSet.member?(matched, i) end)
      |> Enum.map(fn {{title, _}, _i} ->
        "section #{inspect(title)} matches no blocklist row -- either the row was lifted and its " <>
          "argument left behind, or the title names no subject"
      end)

    problems ++ unmatched_rows ++ unmatched_sections
  end

  def self_test do
    good_table =
      "| source | reason |\n| --- | --- |\n" <>
      "| **Blender** | renders are not reproducible -- see below |\n" <>
      "| CMU mocap | provenance |\n"
    good_detail = "### Blender is blocklisted, and reproducibility is why\n\nbody\n"

    cases = [
      {"a row with its section, and a row needing none", good_table, good_detail, true},
      {"a row promising an argument that does not exist",
        good_table <> "| **Krea 2** | revenue-gated -- see below |\n",
        good_detail, false},
      {"a section whose row was lifted from the table",
        good_table,
        good_detail <> "\n### Krea 2 is revenue-gated, and that propagates\n\nbody\n",
        false},
      {"a row matched only by a stopword must NOT count as matched",
        "| source | reason |\n| --- | --- |\n| **the model** | see below |\n",
        "### Blender is blocklisted, and reproducibility is why\n",
        false},
      {"an empty detail document", good_table, "", false},
      {"a table with no promises at all", "| source | reason |\n| --- | --- |\n", good_detail, false}
    ]

    IO.puts("controls:")
    bad =
      Enum.reduce(cases, 0, fn {label, table, detail, want_ok}, acc ->
        problems = check(table, detail)
        ok = (problems == []) == want_ok
        IO.puts("  #{if ok, do: "ok  ", else: "BAD "} #{label}")
        if not ok do
          IO.puts("        got: #{inspect(Enum.take(problems, 1))}")
          acc + 1
        else
          acc
        end
      end)

    IO.puts("\n#{bad} control(s) wrong")
    if bad > 0, do: 1, else: 0
  end
end
