defmodule Shepherd.Gates.AssetPrefix do
  @moduledoc """
  Elixir port of `2-contract/manuals-weftspun/scripts/check_asset_prefix.py`.
  Same prefix set, same skip lists, same self-test controls.

  Assets under `5-repository/` and `6-datasource/` carry a typed prefix
  (T_, DA_, SM_, etc. per the Allar UE5 style guide) followed by an
  underscore and a PascalCase stem. This gate scans filenames and
  reports the ones that violate the shape.

  Detection floor: none. Every eligible file is opened by name and
  either passes or fails; unchecked files (skip list, out-of-scope
  extension, skip-dir tokens) are silent and counted by the report path.
  """

  @prefixes MapSet.new(~w(T DA SM SK A AS AC M MI MF MPC S SC VFX PS BP EUW WBP F))

  @asset_ext MapSet.new(~w(
    .png .jpg .jpeg .webp .exr .bmp .tif .tiff
    .json .yaml .yml .toml
    .glb .gltf .fbx .obj .stl .ply .usdz .usdc
    .wav .ogg .mp3 .flac
  ))

  @scoped_roots ~w(6-datasource/ 5-repository/)

  @skip_names MapSet.new(~w(
    README.md CITATION.cff LICENSE NOTICE
    pixi.lock pixi.toml .gitattributes .gitignore
    manifest.json mix.lock mix.exs package.json package-lock.json
    pyproject.toml poetry.lock Cargo.toml Cargo.lock
    Makefile CMakeLists.txt tsconfig.json compile_commands.json
    .DS_Store
    config.json adapter_config.json tokenizer.json tokenizer_config.json
    special_tokens_map.json generation_config.json training_args.json
    preprocessor_config.json processor_config.json chat_template.jinja
    vocab.json merges.txt
  ))

  @skip_dir_tokens ~w(.git .pixi .lake _build deps node_modules build dist .venv __pycache__ .repo thirdparty third_party vendor)

  @name_rx ~r/^([A-Z]+)_([A-Z][A-Za-z0-9]*(?:_[A-Z0-9][A-Za-z0-9]*)*)$/

  # Public entry ---------------------------------------------------------

  def run(["--self-test"]), do: self_test()
  def run(["--base", base | _]), do: gate_diff(base)
  def run([]), do: report()
  def run(paths), do: gate(paths)

  # Scope check ----------------------------------------------------------

  def in_scope?(path) do
    # Normalise Windows backslashes and locate the scoped-root marker anywhere
    # in the path, so callers passing workspace-relative, absolute, or
    # `../../`-prefixed paths all resolve consistently. The Python original
    # matches Python's `.startswith(SCOPED_ROOTS)` on workspace-relative
    # input; the Elixir port normalises to the same effective check.
    p = String.replace(path, "\\", "/")
    name = Path.basename(p)
    ext = Path.extname(name) |> String.downcase()

    scoped? =
      Enum.any?(@scoped_roots, fn root ->
        String.starts_with?(p, root) or String.contains?(p, "/" <> root)
      end)

    cond do
      not scoped? -> false
      MapSet.member?(@skip_names, name) -> false
      not MapSet.member?(@asset_ext, ext) -> false
      Enum.any?(@skip_dir_tokens, &String.contains?("/" <> p, "/#{&1}/")) -> false
      true -> true
    end
  end

  def name_violates(name) do
    stem = Path.rootname(name)
    case Regex.run(@name_rx, stem) do
      nil -> "shape (want <PREFIX>_PascalCase, e.g. T_Az000_A)"
      [_, prefix, _] ->
        if MapSet.member?(@prefixes, prefix),
          do: nil,
          else: "prefix #{inspect(prefix)} not in Allar set"
    end
  end

  # Gate paths -----------------------------------------------------------

  defp gate(paths) do
    fails =
      paths
      |> Enum.filter(&in_scope?/1)
      |> Enum.reduce(0, fn p, acc ->
        case name_violates(Path.basename(p)) do
          nil ->
            IO.puts("  ok   #{p}")
            acc
          why ->
            IO.puts("  FAIL #{p}  #{why}")
            acc + 1
        end
      end)
    if fails > 0, do: 1, else: 0
  end

  # Gate --base ----------------------------------------------------------

  defp gate_diff(base) do
    root = workspace_root()
    {out, 0} = System.cmd("git",
      ["diff", "--name-only", "--diff-filter=AR", "#{base}...HEAD"],
      cd: root)
    paths = out |> String.split("\n", trim: true) |> Enum.filter(&in_scope?/1)
    if paths == [] do
      IO.puts("0 in-scope asset(s) added or renamed since #{base}.")
      0
    else
      gate(paths)
    end
  end

  # Report -------------------------------------------------------------

  defp report do
    ws = workspace_root()
    {fails, scanned} =
      @scoped_roots
      |> Enum.reduce({0, 0}, fn root, {f, s} ->
        base = Path.join(ws, root)
        if File.dir?(base), do: walk(base, ws, {f, s}), else: {f, s}
      end)
    IO.puts("scouts: #{fails} violation(s) across #{scanned} asset(s) in scope.")
    0
  end

  defp walk(dir, ws, acc) do
    case File.ls(dir) do
      {:error, _} -> acc
      {:ok, entries} ->
        Enum.reduce(entries, acc, fn name, {f, s} = a ->
          full = Path.join(dir, name)
          cond do
            name in @skip_dir_tokens -> a
            File.dir?(full) -> walk(full, ws, a)
            File.regular?(full) ->
              rel = Path.relative_to(full, ws)
              if in_scope?(rel) do
                case name_violates(name) do
                  nil -> {f, s + 1}
                  why -> IO.puts("  #{rel}  #{why}"); {f + 1, s + 1}
                end
              else
                a
              end
            true -> a
          end
        end)
    end
  end

  defp workspace_root do
    cwd = File.cwd!()
    find_ws(cwd)
  end

  defp find_ws(dir) do
    if File.dir?(Path.join(dir, ".repo")), do: dir,
      else: (
        parent = Path.dirname(dir)
        if parent == dir, do: File.cwd!(), else: find_ws(parent)
      )
  end

  # Self-test ------------------------------------------------------------

  def self_test do
    ok_cases = [
      "T_Az000_A.png", "T_Msl256_00.png", "T_Baseline_Msl1024_00.png",
      "DA_Ladder.json", "DA_AzimuthRecoveryA.json",
      "SM_AnnyHead_LOD0.glb", "S_ClickTick_01.wav", "M_Skin_Base.json"
    ]
    bad_cases = [
      {"az000_A.png", "no prefix"},
      {"t_az000_A.png", "lowercase prefix"},
      {"T_az000_A.png", "lowercase after prefix"},
      {"T-Az000-A.png", "hyphens not underscores"},
      {"XYZ_Foo_A.png", "prefix not in Allar set"},
      {"Az000_A.png", "no underscore-terminated prefix"}
    ]
    fails =
      Enum.reduce(ok_cases, 0, fn good, acc ->
        case name_violates(good) do
          nil -> acc
          why -> IO.puts("  FAIL positive control #{inspect(good)}: got #{why}"); acc + 1
        end
      end)
    fails =
      Enum.reduce(bad_cases, fails, fn {bad, label}, acc ->
        case name_violates(bad) do
          nil -> IO.puts("  FAIL negative control #{inspect(bad)} (#{label}): passed but should not have"); acc + 1
          _ -> acc
        end
      end)
    total = length(ok_cases) + length(bad_cases)
    if fails > 0 do
      IO.puts("#{fails} of #{total} controls failed")
      1
    else
      IO.puts("ok   #{total} of #{total} controls fired in both directions")
      0
    end
  end
end
