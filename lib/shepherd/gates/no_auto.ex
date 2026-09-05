defmodule Shepherd.Gates.NoAuto do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_no_auto.py`.
  Same rules, same self-test controls. See the Python docstring for the
  argument the gate carries.

  Strips C++ line comments, block comments, and string/char literals
  before scanning for the `auto` keyword bounded by `\b`, so the word in
  prose or inside a string or as part of a longer identifier
  (`autopilot`) does not trip the check. Comment and literal spans are
  replaced with a same-length run of spaces (newlines preserved) so the
  reported line numbers stay honest against the source file.

  Detection floor: none. Every eligible file is opened and every
  matching line is reported.
  """

  @extensions ~w(.cpp .cc .cxx .hpp .hh .h)

  # Regex mirrors the Python's `STRIP` re.DOTALL: a `//` line comment
  # runs to newline; `/* ... */` is DOT-matches-newline; the two string
  # literals cover `"..."` and `'...'` with backslash-escape support.
  @strip ~r{//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'}s
  @auto ~r/\bauto\b/

  def run(["--self-test"]), do: self_test()

  def run([]) do
    IO.puts(:stderr, "usage: no-auto <path...> [--self-test]")
    2
  end

  def run(paths) do
    n = scan(paths)
    IO.puts("#{if n > 0, do: "FAIL", else: "ok  "}   #{n} `auto` use(s)")
    if n > 0, do: 1, else: 0
  end

  # Core -----------------------------------------------------------------

  defp scan(paths) do
    paths
    |> Enum.flat_map(&expand/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce(0, fn file, acc ->
      file
      |> File.read!()
      |> violations()
      |> Enum.reduce(acc, fn {line_no, line}, count ->
        IO.puts("FAIL #{file}:#{line_no}: #{line}")
        count + 1
      end)
    end)
  end

  defp expand(arg) do
    cond do
      File.regular?(arg) and Path.extname(arg) in @extensions -> [arg]
      File.dir?(arg) ->
        arg
        |> Path.join("**/*")
        |> Path.wildcard(match_dot: false)
        |> Enum.filter(&(File.regular?(&1) and Path.extname(&1) in @extensions))
      true -> []
    end
  end

  def violations(text) do
    stripped = Regex.replace(@strip, text, &blank_preserving_newlines/1)
    stripped
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, i} ->
      if Regex.match?(@auto, line), do: [{i, String.trim(line)}], else: []
    end)
  end

  defp blank_preserving_newlines(chunk) do
    chunk
    |> String.graphemes()
    |> Enum.map_join(fn "\n" -> "\n"; _ -> " " end)
  end

  # Self-test ------------------------------------------------------------

  def self_test do
    planted = "int f() {\n    auto x = g();\n    return x;\n}\n"
    clean =
      "// an automatic variable, and the word auto in prose\n" <>
      ~s|const char* s = "auto";\n| <>
      "int autopilot = 0;\n"

    planted_hits = violations(planted)
    clean_hits = violations(clean)

    fail_planted? = length(planted_hits) != 1
    fail_clean? = clean_hits != []

    if fail_planted? do
      IO.puts("FAIL control: a planted `auto` was not seen (got #{inspect(planted_hits)})")
      1
    else
      if fail_clean? do
        IO.puts("FAIL control: comment, string or identifier misread as the keyword " <>
          "(got #{inspect(clean_hits)})")
        1
      else
        IO.puts("ok   2 of 2 controls fired")
        0
      end
    end
  end
end
