defmodule Shepherd.Gates.RfdStateCanonical do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_rfd_state_canonical.py`.
  Same rules, same 3 self-test controls.

  Every RFD README's `**State:**` field is one of the canonical values RFD
  1000 lists. Four RFDs on 2026-09-03 carried a parenthetical annotation
  after the value ("discussion (implemented 2026-09-01...)"), which is
  neither canonical nor parseable by strict tooling; this gate refuses
  that shape.

  The state list is read out of RFD 1000 rather than restated, so this
  gate and the document cannot drift. Fallback to a frozen list only if
  RFD 1000's README is missing or unparseable.
  """

  @fallback_states MapSet.new(~w(prediscussion ideation discussion published committed abandoned moved))
  @rfd_dir_rx ~r/^[12]\d{3}-[a-z0-9-]+$/
  @state_line_rx ~r/^\*\*State:\*\*\s*(.+?)\s*$/m
  @state_list_rx ~r/has a state:\s*([a-z,\s]+?)\./s

  def run(["--self-test"]), do: self_test()

  def run(argv) do
    root =
      case Enum.find_index(argv, &(&1 == "--repo")) do
        nil -> File.cwd!()
        i -> Enum.at(argv, i + 1)
      end
    gate(root)
  end

  def canonical_states(root) do
    p = Path.join([root, "rfd", "1000-conventions", "README.md"])
    case File.read(p) do
      {:error, _} -> @fallback_states
      {:ok, text} ->
        flat = Regex.replace(~r/\s+/, text, " ")
        case Regex.run(@state_list_rx, flat) do
          [_, body] ->
            body
            |> String.split(",")
            |> Enum.map(&Regex.replace(~r/^or\s+/, String.trim(&1), ""))
            |> Enum.reject(&(&1 == ""))
            |> MapSet.new()
          _ -> @fallback_states
        end
    end
  end

  def scan(root) do
    states = canonical_states(root)
    rfd_root = Path.join(root, "rfd")
    case File.ls(rfd_root) do
      {:error, _} -> []
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.flat_map(fn name -> scan_one(rfd_root, name, states) end)
    end
  end

  defp scan_one(rfd_root, name, states) do
    if not Regex.match?(@rfd_dir_rx, name), do: [], else: do_scan(rfd_root, name, states)
  end

  defp do_scan(rfd_root, name, states) do
    p = Path.join([rfd_root, name, "README.md"])
    case File.read(p) do
      {:error, _} -> []
      {:ok, text} ->
        case Regex.run(@state_line_rx, text) do
          nil -> []
          [_, value] ->
            value = String.trim(value)
            first = value |> String.split() |> List.first()
            if value != first or not MapSet.member?(states, first),
              do: [{name, value}],
              else: []
        end
    end
  end

  defp gate(root) do
    bad = scan(root)
    if bad != [] do
      IO.puts("FAIL #{length(bad)} RFD(s) with non-canonical State:")
      Enum.each(bad, fn {name, value} ->
        IO.puts("       rfd/#{name}/README.md: #{inspect(value)}")
      end)
      IO.puts("     the canonical values are in rfd/1000-conventions/README.md;")
      IO.puts("     move any annotation into the Decision body.")
      1
    else
      IO.puts("ok   every RFD State is a canonical value")
      0
    end
  end

  def self_test do
    tmp = Path.join(System.tmp_dir!(), "shepherd-rfd-state-" <> rand())
    File.mkdir_p!(Path.join(tmp, "rfd/1000-conventions"))
    File.write!(Path.join(tmp, "rfd/1000-conventions/README.md"),
      "# RFD 1000\n\nEach RFD has a state: prediscussion, ideation, " <>
      "discussion, published, committed, abandoned, or moved.\n")

    File.mkdir_p!(Path.join(tmp, "rfd/1001-ok"))
    File.write!(Path.join(tmp, "rfd/1001-ok/README.md"),
      "# RFD 1001\n\n**State:** discussion\n")
    bad = scan(tmp)
    positive_ok? = bad == []

    File.mkdir_p!(Path.join(tmp, "rfd/1002-bad"))
    File.write!(Path.join(tmp, "rfd/1002-bad/README.md"),
      "# RFD 1002\n\n**State:** discussion (implemented 2026-09-01)\n")
    bad = scan(tmp)
    paren_caught? = length(bad) == 1 and elem(hd(bad), 0) == "1002-bad"

    File.mkdir_p!(Path.join(tmp, "rfd/1003-unknown"))
    File.write!(Path.join(tmp, "rfd/1003-unknown/README.md"),
      "# RFD 1003\n\n**State:** invented\n")
    bad = scan(tmp)
    names = bad |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    unknown_caught? = names == ["1002-bad", "1003-unknown"]

    File.rm_rf!(tmp)

    checks = [
      {"positive control: clean State passes", positive_ok?},
      {"negative control: parenthetical annotation rejected", paren_caught?},
      {"negative control: unknown state rejected", unknown_caught?}
    ]
    Enum.each(checks, fn {name, ok} ->
      IO.puts("  #{if ok, do: "ok  ", else: "FAIL"} #{name}")
    end)
    bad_count = Enum.count(checks, fn {_, ok} -> not ok end)
    IO.puts("  #{length(checks) - bad_count} of #{length(checks)} controls fired.")
    if bad_count > 0, do: 1, else: 0
  end

  defp rand, do: Integer.to_string(:erlang.unique_integer([:positive]))
end
