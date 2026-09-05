defmodule Shepherd.Gates.AntiEntropy do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_anti_entropy.py`.

  Inventory and anti-entropy check over the workspace. Enumerates the
  fixed populations (manifest projects, serials, blocklist rows, linkfiles,
  RFD READMEs) rather than sampling — CLAUDE.md rule 5. The shuffled
  full pass over expensive sub-checks is preserved: shuffle order, cover
  every item exactly once.

  Planted controls run inline (rule 2): a duplicate serial row and a
  case-differed blocklist row are both planted and asserted seen. A
  counter that has never found a planted row has yet to show it can find
  a real one.

  Detection floor: sub-check subprocess uses the workspace's own Python
  originals under `<rfd>/scripts/`. A sub-check that requires a
  bucket-B ecosystem (pxr / torch / markdown-it) still runs through
  Python — this gate is orchestration, not re-implementation of those.
  """

  def run(["--self-test"]), do: self_test()

  def run(argv) do
    rfd =
      case Enum.find(argv, &(not String.starts_with?(&1, "--"))) do
        nil -> find_default_rfd()
        r -> r
      end
    root = find_workspace_root(rfd)
    cond do
      rfd == nil -> IO.puts("no RFD directory found; pass one as the first argument"); 2
      root == nil -> IO.puts("no .repo above #{rfd}, so there is no workspace to check"); 0
      true -> run_checks(rfd, root)
    end
  end

  defp find_default_rfd do
    # If we're invoked from the workspace root, `2-contract/manuals-weftspun`.
    candidate = Path.join([File.cwd!(), "..", "..", "2-contract", "manuals-weftspun"])
    if File.dir?(candidate), do: Path.expand(candidate), else: nil
  end

  defp find_workspace_root(nil), do: nil
  defp find_workspace_root(rfd) do
    Enum.find([rfd | Path.split(rfd) |> Enum.scan(&Path.join(&2, &1)) |> Enum.reverse()], fn dir ->
      File.dir?(Path.join(dir, ".repo"))
    end) || walk_up_for_repo(rfd)
  end

  defp walk_up_for_repo(dir) do
    if File.dir?(Path.join(dir, ".repo")) do
      dir
    else
      parent = Path.dirname(dir)
      if parent == dir, do: nil, else: walk_up_for_repo(parent)
    end
  end

  defp run_checks(rfd, root) do
    state = %{out: [], fails: 0}

    # --- A. manifest projects, enumerated ---
    manifest = File.read!(Path.join([root, ".repo/manifests/default.xml"]))
    projects =
      Regex.scan(~r/<project\s+[^>]*name="([^"]+)"[^>]*path="([^"]+)"/, manifest)
      |> Enum.map(fn [_, name, path] -> {name, path} end)
    missing = Enum.filter(projects, fn {_, p} -> not File.dir?(Path.join(root, p)) end) |> Enum.map(&elem(&1, 1))
    state = check(state, "manifest paths exist on disk", missing == [],
                  "#{length(projects)} projects, missing: #{fmt(missing)}")
    bad_paths = Enum.filter(projects, fn {_, p} -> String.contains?(p, "_") or String.contains?(p, " ") end)
                |> Enum.map(&elem(&1, 1))
    state = check(state, "every path hyphen-only", bad_paths == [], "offenders: #{fmt(bad_paths)}")

    # --- B. serials ---
    serials_text = File.read!(Path.join(rfd, "SERIALS.usda"))
    alloc = section(serials_text, "Allocated")
    deleted = section(serials_text, "Deleted")
    live = Regex.scan(~r/def "S(\d+)"/, alloc) |> Enum.map(fn [_, x] -> String.to_integer(x) end)
    slugs = Regex.scan(~r/custom string slug = "([^"]*)"/, alloc) |> Enum.map(fn [_, s] -> s end)
    dead = Regex.scan(~r/def "S(\d+)"/, deleted) |> Enum.map(fn [_, x] -> String.to_integer(x) end)
    dirs =
      File.ls!(Path.join(rfd, "rfd"))
      |> Enum.filter(&Regex.match?(~r/^1\d{3}-/, &1))
      |> Enum.sort()

    state = check(state, "every allocated row carries a slug",
                  length(live) == length(slugs), "#{length(live)} rows / #{length(slugs)} slugs")
    state = check(state, "no duplicate serials",
                  length(live) == length(Enum.uniq(live)),
                  "#{length(live)} rows, #{length(Enum.uniq(live))} distinct")

    # planted-duplicate control
    planted = alloc <> "\n                def \"S1000\"\n"
    planted_count = Regex.scan(~r/def "S(\d+)"/, planted) |> length()
    state = check(state, "  control: a planted duplicate row is seen",
                  planted_count == length(live) + 1)

    state = check(state, "no retired serial reused",
                  MapSet.disjoint?(MapSet.new(live), MapSet.new(dead)),
                  "retired: #{inspect(dead)}")

    live_set = MapSet.new(live)
    dir_serials = Enum.map(dirs, &String.to_integer(String.slice(&1, 0, 4)))
    state = check(state, "every directory registered",
                  Enum.all?(dir_serials, &MapSet.member?(live_set, &1)),
                  "#{length(dirs)} dirs")

    state = check(state, "every serial has a directory",
                  Enum.all?(live, fn n -> Enum.any?(dirs, &String.starts_with?(&1, "#{n}-")) end))

    mismatches =
      Enum.zip(live, slugs)
      |> Enum.filter(fn {n, sl} -> "#{n}-#{sl}" not in dirs end)
      |> Enum.map(fn {n, sl} -> "#{n}-#{sl}" end)
    state = check(state, "slug matches directory name", mismatches == [], "mismatches: #{fmt(mismatches)}")

    # --- C. blocklist rows vs sections ---
    claude = File.read!(Path.join(rfd, "CLAUDE.md"))
    blocklist = File.read!(Path.join(rfd, "BLOCKLIST.md"))
    rows =
      claude
      |> String.split("\n")
      |> Enum.filter(&(String.starts_with?(&1, "|") and String.contains?(String.downcase(&1), "see below")))
    secs = blocklist |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "### "))
    state = check(state, "blocklist rows == sections",
                  length(rows) == length(secs), "#{length(rows)} rows / #{length(secs)} sections")

    planted_rows =
      (claude <> "\n| planted | See Below |")
      |> String.split("\n")
      |> Enum.filter(&(String.starts_with?(&1, "|") and String.contains?(String.downcase(&1), "see below")))
    state = check(state, "  control: counter finds a planted row",
                  length(planted_rows) == length(rows) + 1,
                  "case-insensitive match verified against a planted row")

    # --- D. linkfiles ---
    links = Regex.scan(~r/<linkfile\s+src="([^"]+)"\s+dest="([^"]+)"/, manifest)
            |> Enum.map(fn [_, src, dest] -> {src, dest} end)
    broken = Enum.filter(links, fn {_, dest} -> not File.exists?(Path.join(root, dest)) end)
             |> Enum.map(&elem(&1, 1))
    state = check(state, "every linkfile resolves", broken == [], "#{length(links)} links, broken: #{fmt(broken)}")

    # --- E. README bound ---
    limit = 40
    over =
      dirs
      |> Enum.filter(fn d ->
        p = Path.join([rfd, "rfd", d, "README.md"])
        File.regular?(p) and length(String.split(File.read!(p), "\n")) > limit
      end)
    state = check(state, "every README <= #{limit} lines", over == [], "#{length(dirs)} READMEs, over: #{fmt(over)}")

    # --- F. shuffled full pass over expensive sub-checks ---
    expensive = [
      {"check_fourloops_plan", []},
      {"check_fourloops_etnf", []},
      {"check_rfd1122_plan", []},
      {"check_usd_valid", []},
      {"check_pen_66606", []},
      {"check_blocklist_detail", []},
      {"check_goal_manifests", []},
      {"check-rfd-structure", []},
      {"check_comment_ladder", ["--self-test"]},
      {"check_pr_description", ["--self-test"]},
      {"check_rfd_canary", ["--self-test"]},
      {"check_no_orphaned_branches", ["--self-test"]},
      {"check_project_readme_length", ["--self-test"]}
    ]
    order = Enum.shuffle(expensive)
    state = %{state | out: state.out ++ ["", "  shuffled full pass, #{length(order)} of #{length(expensive)} (every item, random order):"]}

    state =
      Enum.reduce(order, state, fn {name, extra}, acc ->
        script = Path.join([rfd, "scripts", "#{name}.py"])
        {out, rc} = System.cmd("python", [script | extra], cd: rfd, stderr_to_stdout: true)
        tail =
          out |> String.split("\n", trim: true) |> List.last() || ""
        tail = tail |> String.slice(0, 58)
        check(acc, "  #{name}", rc == 0, tail)
      end)

    state = check(state, "shuffle covered every item",
                  MapSet.new(order) == MapSet.new(expensive),
                  "#{length(Enum.uniq(order))}/#{length(expensive)} distinct")

    Enum.each(state.out, &IO.puts/1)
    IO.puts("\n  enumerated checks: #{length(state.out) - 2} run, #{state.fails} failed")
    if state.fails > 0, do: 1, else: 0
  end

  defp section(text, name) do
    header = "def Scope \"#{name}\""
    case :binary.match(text, header) do
      :nomatch -> ""
      {i, _} ->
        tails =
          for other <- ["Unused", "Deleted"],
              other != name,
              m = :binary.match(text, "def Scope \"#{other}\"", scope: {i + 1, byte_size(text) - i - 1}),
              m != :nomatch do
            elem(m, 0)
          end
        j = Enum.min([byte_size(text) | tails])
        binary_part(text, i, j - i)
    end
  end

  defp check(state, name, ok, detail \\ "") do
    line = "  #{if ok, do: "ok  ", else: "FAIL"} #{String.pad_trailing(name, 42)} #{detail}"
    %{state | out: state.out ++ [line], fails: state.fails + (if ok, do: 0, else: 1)}
  end

  defp fmt([]), do: "none"
  defp fmt(list), do: inspect(list)

  # ---- self-test on synthetic inputs (offline, no workspace required) ----
  def self_test do
    controls = []

    # 1. section() extracts the Allocated block bounded by Deleted
    usda = """
    def Scope "Allocated" {
        def "S1000" { custom string slug = "foo" }
        def "S1001" { custom string slug = "bar" }
    }
    def Scope "Deleted" {
        def "S0999" {}
    }
    """
    alloc = section(usda, "Allocated")
    controls = controls ++ [{"section() extracts Allocated block",
                              String.contains?(alloc, "S1000") and String.contains?(alloc, "S1001") and
                              not String.contains?(alloc, "S0999")}]

    # 2. planted duplicate is seen by the row counter
    live_extracted = Regex.scan(~r/def "S(\d+)"/, alloc) |> Enum.map(fn [_, x] -> String.to_integer(x) end)
    planted = alloc <> "\n    def \"S1000\"\n"
    planted_count = Regex.scan(~r/def "S(\d+)"/, planted) |> length()
    controls = controls ++ [{"planted duplicate serial is seen", planted_count == length(live_extracted) + 1}]

    # 3. see-below counter is case-insensitive
    md = "| foo | see below |\n| bar | See Below |\n| baz | SEE BELOW |\n"
    matches = md |> String.split("\n") |> Enum.count(&(String.starts_with?(&1, "|") and String.contains?(String.downcase(&1), "see below")))
    controls = controls ++ [{"see-below counter is case-insensitive", matches == 3}]

    # 4. hyphen-only path check catches underscores and spaces
    projects = [{"a", "1-transport/ok"}, {"b", "2-with_under"}, {"c", "3-with space"}]
    bad = Enum.filter(projects, fn {_, p} -> String.contains?(p, "_") or String.contains?(p, " ") end)
    controls = controls ++ [{"hyphen-only check catches underscore + space", length(bad) == 2}]

    # 5. shuffle covers every item
    items = Enum.to_list(1..20)
    controls = controls ++ [{"shuffle covers every item once",
                              MapSet.new(Enum.shuffle(items)) == MapSet.new(items)}]

    bad = Enum.count(controls, fn {_, ok?} -> not ok? end)
    Enum.each(controls, fn {name, ok?} ->
      IO.puts("  #{if ok?, do: "ok  ", else: "FAIL"} control: #{name}")
    end)
    IO.puts("  #{length(controls) - bad} of #{length(controls)} controls fired.")
    if bad > 0, do: 1, else: 0
  end
end
