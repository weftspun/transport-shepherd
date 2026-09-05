defmodule Shepherd.Gates.ProjectReadmeLength do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_project_readme_length.py`.
  Same rules, same fork-exempt list, same 7 self-test controls.

  Every manifest project's `README.md` first non-blank line must be <= 144
  characters. Silently skips projects with no README.md; reports the count so
  the skip does not read as a pass (rule 3).

  Detection floor: none. Every project in `default.xml` is inspected and
  counted (have / missing / fork-exempt).
  """

  @limit 144

  # Fork READMEs open with upstream's first line, not ours. Grows when a new
  # fork lands; keep aligned with the Python's FORK_EXEMPT set.
  @fork_exempt MapSet.new(~w(
    3-interactor/datasource-flow
    3-interactor/idtx-flow
  ))

  def run(["--self-test"]), do: self_test()

  def run(_args) do
    case workspace_root() do
      nil ->
        IO.puts("no .repo above this checkout, so there is no workspace to check")
        0
      root -> gate(root)
    end
  end

  def first_line(text) do
    text
    |> String.split("\n")
    |> Enum.find("", fn line -> String.trim(line) != "" end)
    |> String.trim_trailing()
  end

  defp gate(root) do
    manifest = Path.join([root, ".repo", "manifests", "default.xml"])
    xml = File.read!(manifest)

    projects =
      Regex.scan(~r{<project\s+([^>]*?)/?>}s, xml)
      |> Enum.map(fn [_, attrs] -> attr(attrs, "path") || attr(attrs, "name") end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    {have, missing, exempt, over} =
      Enum.reduce(projects, {[], [], [], []}, fn path, {h, m, e, o} ->
        cond do
          MapSet.member?(@fork_exempt, path) -> {h, m, [path | e], o}
          not File.regular?(Path.join([root, path, "README.md"])) -> {h, [path | m], e, o}
          true ->
            text = File.read!(Path.join([root, path, "README.md"]))
            line = first_line(text)
            len = String.length(line)
            if len > @limit,
              do: {[path | h], m, e, [{path, len} | o]},
              else: {[path | h], m, e, o}
        end
      end)

    Enum.each(Enum.reverse(over), fn {path, ln} ->
      IO.puts("  FAIL #{path}/README.md  first line #{ln} chars > #{@limit}")
    end)

    IO.puts("  #{length(have)} projects with README.md, #{length(missing)} without, #{length(exempt)} fork-exempt.")
    IO.puts("#{length(over)} of #{length(have)} first lines over #{@limit} chars.")
    if over == [], do: 0, else: 1
  end

  defp attr(attrs, name) do
    case Regex.run(~r|\b#{name}\s*=\s*"([^"]*)"|, attrs) do
      [_, v] -> v
      _ -> nil
    end
  end

  defp workspace_root do
    find_ws(File.cwd!())
  end

  defp find_ws(dir) do
    cond do
      File.dir?(Path.join(dir, ".repo")) -> dir
      Path.dirname(dir) == dir -> nil
      true -> find_ws(Path.dirname(dir))
    end
  end

  def self_test do
    long_body = String.duplicate("x", 143)
    controls = [
      {"short heading", "# short\n\nbody", true},
      {"blank then short", "\n\n# short heading after blanks\n", true},
      {"exactly 144", "# " <> String.duplicate("x", 142), true},
      {"145 chars", "# " <> String.duplicate("x", 143), false},
      {"blank then long", "\n\n" <> String.duplicate("x", 200) <> "\n", false},
      {"only whitespace", "   \n\n\t\n", true},
      {"long line 2, short line 1", "# ok\n\n" <> long_body <> long_body, true}
    ]

    fails =
      Enum.reduce(controls, 0, fn {label, text, expected_pass}, acc ->
        line = first_line(text)
        got_pass = String.length(line) <= @limit
        if got_pass != expected_pass do
          IO.puts("  FAIL #{label}: got #{if got_pass, do: "pass", else: "fail"}, " <>
            "expected #{if expected_pass, do: "pass", else: "fail"} (line len #{String.length(line)})")
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
