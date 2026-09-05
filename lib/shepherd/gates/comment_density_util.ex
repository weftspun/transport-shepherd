defmodule Shepherd.Gates.CommentDensityUtil do
  @moduledoc """
  Shared measurement for `comment-ladder` and `comment-density` gates.

  Ports `scripts/comment_density.py`. Same extensions (`.py`, `.ex`, `.exs`),
  same rule: `#` lines and docstring blocks count as comments; blank lines
  count as neither.

  Detection floor: Python docstring detection is line-toggle on `\"\"\"` (or
  `'''`), not AST — a non-docstring triple-quoted literal still counts. The
  Python original does AST-scoped detection; this approximation is close
  enough for the gate's rung comparisons but is not byte-identical on files
  with non-docstring triple-quoted literals.
  """

  @source_ext MapSet.new([".py", ".ex", ".exs"])

  def source?(path) do
    MapSet.member?(@source_ext, Path.extname(path))
  end

  def density(text, ext) do
    lines = String.split(text, "\n")
    marked =
      case ext do
        ".py" -> python_marks(lines)
        e when e in [".ex", ".exs"] -> elixir_marks(lines)
        _ -> MapSet.new()
      end
    {comment, code} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0}, fn {raw, n}, {c, k} ->
        cond do
          String.trim(raw) == "" -> {c, k}
          MapSet.member?(marked, n) -> {c + 1, k}
          true -> {c, k + 1}
        end
      end)
    total = comment + code
    ratio = if total == 0, do: 0.0, else: comment / total
    {comment, code, ratio}
  end

  # Line-toggle docstring approximation: any line starting or ending a
  # triple-quoted block (""" or ''') flips state; lines inside count.
  defp python_marks(lines) do
    {marks, _in_doc, _delim} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({MapSet.new(), false, nil}, fn {raw, n}, {acc, in_doc, delim} ->
        s = String.trim(raw)
        cond do
          in_doc ->
            acc2 = MapSet.put(acc, n)
            if String.contains?(s, delim), do: {acc2, false, nil}, else: {acc2, true, delim}
          String.starts_with?(s, "#") ->
            {MapSet.put(acc, n), false, nil}
          triple_open = detect_triple(s) ->
            {marker, remainder} = triple_open
            acc2 = MapSet.put(acc, n)
            # If remainder also contains the same triple, docstring is single line.
            if String.contains?(remainder, marker) do
              {acc2, false, nil}
            else
              {acc2, true, marker}
            end
          true ->
            {acc, false, nil}
        end
      end)
    marks
  end

  defp detect_triple(s) do
    cond do
      String.starts_with?(s, "\"\"\"") -> {"\"\"\"", String.slice(s, 3..-1//1) || ""}
      String.starts_with?(s, "'''") -> {"'''", String.slice(s, 3..-1//1) || ""}
      true -> nil
    end
  end

  defp elixir_marks(lines) do
    {marks, _in_doc} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({MapSet.new(), false}, fn {raw, n}, {acc, in_doc} ->
        s = String.trim(raw)
        cond do
          in_doc ->
            acc2 = MapSet.put(acc, n)
            if String.contains?(s, "\"\"\""), do: {acc2, false}, else: {acc2, true}
          String.starts_with?(s, "#") ->
            {MapSet.put(acc, n), false}
          Enum.any?(["@moduledoc", "@doc", "@shortdoc", "@typedoc"], &String.starts_with?(s, &1)) ->
            acc2 = MapSet.put(acc, n)
            triples = length(String.split(s, "\"\"\"")) - 1
            if triples == 1, do: {acc2, true}, else: {acc2, false}
          true ->
            {acc, false}
        end
      end)
    marks
  end
end
