defmodule Shepherd.Gates.RfdCanary do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_rfd_canary.py`.
  Same rules, same 7 self-test controls.

  Every new RFD directory added since the base branch must carry one of two
  canary sentences (verbatim) in its README.md or DETAILS.md. Existing RFDs
  are outside the scope — the trap is on the AI drafting a new RFD without
  reading CLAUDE.md.

  Detection floor: none. Every new `rfd/<id>-<slug>/README.md` since the
  base is enumerated and each dir returns ok or FAIL.
  """

  @ai_canary "This RFD was drafted by an AI and read by a human before it shipped."
  @human_canary "This RFD was drafted by a human without AI help."
  @rfd_root "rfd"

  def run(["--self-test"]), do: self_test()

  def run(argv) do
    base =
      case Enum.find_index(argv, &(&1 == "--base")) do
        nil -> "origin/main"
        i -> Enum.at(argv, i + 1)
      end
    root =
      case Enum.find_index(argv, &(&1 == "--repo")) do
        nil -> File.cwd!()
        i -> Enum.at(argv, i + 1)
      end
    gate(root, base)
  end

  def new_rfd_dirs(root, base) do
    {out, 0} =
      System.cmd("git", ["-C", root, "diff", "--diff-filter=A", "--name-only",
                         "#{base}...HEAD"])
    out
    |> String.split("\n", trim: true)
    |> Enum.filter(fn line ->
      case String.split(line, "/") do
        [@rfd_root, _slug, "README.md"] -> true
        _ -> false
      end
    end)
    |> Enum.map(fn line ->
      [_root, slug, _readme] = String.split(line, "/")
      Path.join(@rfd_root, slug)
    end)
    |> Enum.sort()
  end

  def carries_canary?(root, rel_dir) do
    Enum.any?(["README.md", "DETAILS.md"], fn name ->
      p = Path.join([root, rel_dir, name])
      case File.read(p) do
        {:ok, text} ->
          String.contains?(text, @ai_canary) or String.contains?(text, @human_canary)
        _ -> false
      end
    end)
  end

  defp gate(root, base) do
    news = new_rfd_dirs(root, base)
    missing = Enum.reject(news, &carries_canary?(root, &1))

    if missing != [] do
      IO.puts("FAIL #{length(missing)} new RFD(s) missing the canary:")
      Enum.each(missing, &IO.puts("       #{&1}"))
      IO.puts("")
      IO.puts("     add one of these sentences to the RFD's README.md or DETAILS.md:")
      IO.puts("     AI-drafted:    #{inspect(@ai_canary)}")
      IO.puts("     human-drafted: #{inspect(@human_canary)}")
      1
    else
      IO.puts("ok   #{length(news)} new RFD(s), canary in each.")
      0
    end
  end

  def self_test do
    tmp = Path.join(System.tmp_dir!(), "shepherd-rfd-canary-" <> rand())
    File.mkdir_p!(tmp)

    try do
      init_repo(tmp)
      plant(tmp, "1001-ai-canary-in-readme", "# a\n\n#{@ai_canary}\n", nil)
      plant(tmp, "1002-ai-canary-in-details", "# b\n", "# b details\n\n#{@ai_canary}\n")
      plant(tmp, "1003-no-canary", "# c\n", "# c details\n")
      plant(tmp, "1004-canary-misspelled",
            "# d\n\nThis RFD was drafted by AI and read by a human before it shipped.\n", nil)
      plant(tmp, "1005-human-canary", "# e\n\n#{@human_canary}\n", nil)
      plant(tmp, "1006-human-canary-in-details", "# f\n",
            "# f details\n\n#{@human_canary}\n")
      commit(tmp, "new")

      news = new_rfd_dirs(tmp, "main")
      missing = Enum.reject(news, &carries_canary?(tmp, &1))

      checks = [
        {"AI canary in README passes",
          "rfd/1001-ai-canary-in-readme" not in missing},
        {"AI canary in DETAILS passes",
          "rfd/1002-ai-canary-in-details" not in missing},
        {"no canary is rejected",
          "rfd/1003-no-canary" in missing},
        {"a misspelled canary is rejected",
          "rfd/1004-canary-misspelled" in missing},
        {"human canary in README passes",
          "rfd/1005-human-canary" not in missing},
        {"human canary in DETAILS passes",
          "rfd/1006-human-canary-in-details" not in missing},
        {"the baseline RFD is not rescanned",
          "rfd/1000-baseline" not in news}
      ]

      IO.puts("")
      Enum.each(checks, fn {name, ok} ->
        IO.puts("  #{if ok, do: "ok  ", else: "FAIL"} control: #{name}")
      end)
      bad = Enum.count(checks, fn {_, ok} -> not ok end)
      IO.puts("  #{length(checks) - bad} of #{length(checks)} controls fired.")
      if bad > 0, do: 1, else: 0
    after
      File.rm_rf!(tmp)
    end
  end

  defp init_repo(root) do
    {_, 0} = System.cmd("git", ["-C", root, "init", "-q", "-b", "main"])
    {_, 0} = System.cmd("git", ["-C", root, "config", "user.email", "t@t"])
    {_, 0} = System.cmd("git", ["-C", root, "config", "user.name", "t"])
    File.mkdir_p!(Path.join(root, @rfd_root))
    plant(root, "1000-baseline", "# baseline\n", nil)
    {_, 0} = System.cmd("git", ["-C", root, "add", "."])
    {_, 0} = System.cmd("git", ["-C", root, "commit", "-q", "-m", "base"])
    {_, 0} = System.cmd("git", ["-C", root, "checkout", "-q", "-b", "feature"])
  end

  defp plant(root, slug, readme_body, details_body) do
    d = Path.join([root, @rfd_root, slug])
    File.mkdir_p!(d)
    File.write!(Path.join(d, "README.md"), readme_body)
    if details_body, do: File.write!(Path.join(d, "DETAILS.md"), details_body)
  end

  defp commit(root, msg) do
    {_, 0} = System.cmd("git", ["-C", root, "add", "."])
    {_, 0} = System.cmd("git", ["-C", root, "commit", "-q", "-m", msg])
  end

  defp rand, do: Integer.to_string(:erlang.unique_integer([:positive]))
end
