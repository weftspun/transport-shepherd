defmodule Shepherd.Gates.RfdReadmePresent do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_rfd_readme_present.py`.
  Same rules, same 2 self-test controls.

  Every RFD directory with a DETAILS.md must carry a README.md beside it.
  render_site.py's RFD lister filters on README.md presence, so a directory
  with only DETAILS.md renders no page and 404s on the site. The
  2026-09-03 QA sweep found 90 such directories that had accumulated
  silently.

  Detection floor: none. Every RFD directory matching the id-slug pattern
  is inspected and returns ok or FAIL.
  """

  @rfd_dir_rx ~r/^[12]\d{3}-[a-z0-9-]+$/

  def run(["--self-test"]), do: self_test()

  def run(argv) do
    root =
      case Enum.find_index(argv, &(&1 == "--repo")) do
        nil -> File.cwd!()
        i -> Enum.at(argv, i + 1)
      end
    gate(root)
  end

  def scan(root) do
    rfd_root = Path.join(root, "rfd")
    case File.ls(rfd_root) do
      {:error, _} -> []
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.filter(&Regex.match?(@rfd_dir_rx, &1))
        |> Enum.filter(fn name ->
          d = Path.join(rfd_root, name)
          File.regular?(Path.join(d, "DETAILS.md")) and
            not File.regular?(Path.join(d, "README.md"))
        end)
    end
  end

  defp gate(root) do
    bad = scan(root)
    if bad != [] do
      IO.puts("FAIL #{length(bad)} RFD dir(s) have DETAILS.md but no README.md:")
      Enum.each(bad, &IO.puts("       rfd/#{&1}/"))
      1
    else
      IO.puts("ok   every RFD dir with DETAILS.md carries a README.md")
      0
    end
  end

  def self_test do
    tmp = Path.join(System.tmp_dir!(), "shepherd-rfd-readme-present-" <> rand())
    File.mkdir_p!(Path.join(tmp, "rfd/1000-clean"))
    File.write!(Path.join(tmp, "rfd/1000-clean/README.md"), "# x\n")
    File.write!(Path.join(tmp, "rfd/1000-clean/DETAILS.md"), "# d\n")
    File.mkdir_p!(Path.join(tmp, "rfd/1001-broken"))
    File.write!(Path.join(tmp, "rfd/1001-broken/DETAILS.md"), "# d\n")

    negative = scan(tmp)
    neg_ok? = negative == ["1001-broken"]

    File.rm!(Path.join(tmp, "rfd/1001-broken/DETAILS.md"))
    positive = scan(tmp)
    pos_ok? = positive == []

    File.rm_rf!(tmp)

    checks = [
      {"negative control: planted defect (DETAILS without README) rejected", neg_ok?},
      {"positive control: clean tree passes", pos_ok?}
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
