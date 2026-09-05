defmodule Shepherd.Gates.ManifestRoot do
  @moduledoc """
  Elixir port of `.repo/manifests/check_manifest_root.py`. Same rules,
  same exit codes, same self-test controls. See the Python docstring
  for the argument the gate carries — this file does not restate it.

  The workspace root is a `repo` client, not a git repository, so root
  files are placed by `<linkfile>` and every link must resolve to the
  file it names. `<copyfile>` is blocked on construction, before any
  bytes are compared: a copy that happens to agree today is exactly the
  case the block exists to catch.

  Detection floor: none. `<linkfile>` and `<copyfile>` declarations are
  enumerated from `default.xml`, and every entry returns ok or FAIL.
  """

  @default_manifest Path.join([".repo", "manifests", "default.xml"])
  @bookkeeping Path.join([".repo", "copy-link-files.json"])

  # Public entry ---------------------------------------------------------

  def run(argv) do
    {opts, rest, _} =
      OptionParser.parse(argv,
        strict: [manifest: :string, manifest_only: :boolean, self_test: :boolean]
      )

    cond do
      opts[:self_test] -> self_test()
      opts[:manifest_only] -> manifest_only(opts[:manifest] || "default.xml")
      match?([_ | _], rest) -> workspace(hd(rest), opts[:manifest])
      true ->
        IO.puts(:stderr, "usage: manifest-root <workspace> [--manifest PATH] " <>
          "[--manifest-only] [--self-test]")
        2
    end
  end

  # Manifest-only mode ---------------------------------------------------

  defp manifest_only(manifest) do
    IO.puts("")
    case entries(manifest) do
      {:error, reason} ->
        IO.puts("  FAIL #{pad("(manifest)", 12)} #{pad("", 9)} does not parse: #{reason}")
        IO.puts("")
        1

      {:ok, declared} ->
        copies = for {:copyfile, project, _, dest} <- declared, do: {dest, project}
        for {dest, project} <- copies,
            do: IO.puts("  FAIL #{pad(dest, 12)} #{pad("copyfile", 9)} declared by #{project}")
        if copies == [] do
          IO.puts("  ok   #{pad("(manifest)", 12)} #{pad("", 9)} " <>
            "#{length(declared)} entries, none of them copies")
          IO.puts("")
          IO.puts("#{length(declared)} entries declared, 0 copyfile. The links themselves " <>
            "are NOT checked here;")
          IO.puts("that needs a workspace.")
          0
        else
          IO.puts("")
          IO.puts("Replace each <copyfile> with <linkfile>: a copy drifts, a link cannot.")
          1
        end
    end
  end

  # Workspace mode -------------------------------------------------------

  defp workspace(ws, manifest_arg) do
    root = Path.expand(ws)
    manifest = manifest_arg || Path.join(root, @default_manifest)
    unless File.exists?(manifest) do
      IO.puts("no manifest at #{manifest}")
      System.halt(1)
    end

    IO.puts("")
    {declared, failures, book} = check(root, manifest, true)
    links = Enum.count(declared, fn {k, _, _, _} -> k == :linkfile end)
    copies = Enum.count(declared, fn {k, _, _, _} -> k == :copyfile end)

    IO.puts("")
    IO.puts("#{length(declared)} entries enumerated (#{links} linkfile, " <>
      "#{copies} copyfile), 0 unchecked.")

    cond do
      failures != [] or book != [] ->
        IO.puts("#{length(failures) + length(book)} root file(s) disagree with the manifest.")
        if copies > 0,
          do: IO.puts("Replace each <copyfile> with <linkfile>: a copy drifts, a link cannot.")
        IO.puts("Then `repo sync` to place them.")
        1

      true ->
        IO.puts("All #{links} root file(s) are links, and each resolves to " <>
          "the file it names.")
        0
    end
  end

  # Core -----------------------------------------------------------------

  defp check(root, manifest, verbose?) do
    case entries(manifest) do
      {:error, reason} ->
        if verbose?, do:
          IO.puts("  FAIL #{pad("(manifest)", 12)} #{pad("", 9)} " <>
            "manifest does not parse: #{reason}")
        {[], [], ["manifest does not parse: #{reason}"]}

      {:ok, declared} ->
        failures =
          for {kind, project, src, dest} <- declared, reduce: [] do
            acc ->
              {ok?, note} = check_entry(root, kind, project, src, dest)
              if verbose?, do:
                IO.puts("  #{pad(if(ok?, do: "ok", else: "FAIL"), 4)} " <>
                  "#{pad(dest, 12)} #{pad(to_string(kind), 9)} #{note}")
              if ok?, do: acc, else: [{dest, kind, note} | acc]
          end
          |> Enum.reverse()

        book = check_bookkeeping(root, declared)
        if verbose? do
          Enum.each(book, fn problem ->
            IO.puts("  FAIL #{pad("(bookkeeping)", 12)} #{pad("", 9)} #{problem}")
          end)
        end

        {declared, failures, book}
    end
  end

  defp check_entry(_root, :copyfile, _project, _src, _dest),
    do: {false, "copyfile is blocked; declare it as <linkfile> instead"}

  defp check_entry(root, :linkfile, project, src, dest) do
    src_abs = Path.join([root, project, src])
    dest_abs = Path.join(root, dest)

    cond do
      not File.exists?(src_abs) -> {false, "source missing: #{project}/#{src}"}
      not lexists?(dest_abs) -> {false, "destination missing"}
      not is_link?(dest_abs) ->
        note = "not a symlink"
        note =
          if File.regular?(dest_abs) and sha(dest_abs) == sha(src_abs),
            do: note <> " (bytes agree today; a copy is free to drift tomorrow)",
            else: note
        {false, note}

      not File.exists?(dest_abs) ->
        {:ok, target} = File.read_link(dest_abs)
        {false, "dangling -> #{target}"}

      realpath(dest_abs) != realpath(src_abs) ->
        {false, "resolves to #{Path.relative_to(realpath(dest_abs), root)}"}

      true ->
        {true, "-> #{project}/#{src}"}
    end
  end

  defp check_bookkeeping(root, declared) do
    path = Path.join(root, @bookkeeping)
    if not File.exists?(path) do
      ["#{@bookkeeping} missing"]
    else
      case Jason.decode(File.read!(path)) do
        {:ok, book} ->
          want = for({:linkfile, _, _, d} <- declared, do: d) |> Enum.sort()
          got = book |> Map.get("linkfile", []) |> Enum.sort()
          copies = book |> Map.get("copyfile", []) |> Enum.sort()

          []
          |> then(fn acc ->
            if want != got,
              do: ["linkfile: repo records #{inspect(got)}, manifest declares #{inspect(want)}" | acc],
              else: acc
          end)
          |> then(fn acc ->
            if copies != [],
              do: ["copyfile: repo has placed #{inspect(copies)} at the root" | acc],
              else: acc
          end)

        {:error, err} ->
          ["#{@bookkeeping} does not parse: #{inspect(err)}"]
      end
    end
  end

  # XML parsing ----------------------------------------------------------

  defp entries(manifest_path) do
    try do
      xml = File.read!(manifest_path)
      validate_xml_comments!(xml)
      {:ok, parse_projects(xml)}
    rescue
      e in File.Error -> {:error, Exception.message(e)}
      e in RuntimeError -> {:error, e.message}
    end
  end

  # A double-hyphen in an XML comment is illegal per XML 1.0; catch it
  # explicitly to match the Python original's report shape (which is how
  # this failure is usually hit — an em-dash-shaped sentence typed as
  # two hyphens).
  defp validate_xml_comments!(xml) do
    Regex.scan(~r/<!--(.*?)-->/s, xml)
    |> Enum.each(fn [_, body] ->
      if String.contains?(body, "--"),
        do: raise("comment contains '--': #{inspect(body)}")
    end)
  end

  # A dependency-free parser for this shape: <project name= path=>
  # contains <linkfile src= dest=/> and/or <copyfile src= dest=/>. The
  # opening-tag pattern requires the last character before the closing
  # `>` to be neither `/` nor whitespace, which excludes self-closing
  # `<project … />` entries — a self-closing project has no child, so
  # skipping it costs nothing, and matching it once ate the paired-tag
  # scan across intervening self-closes and misattributed every child
  # to the wrong project's path.
  defp parse_projects(xml) do
    Regex.scan(~r|<project\s+([^>]*?[^/\s])\s*>(.*?)</project>|s, xml)
    |> Enum.flat_map(fn [_, attrs, body] ->
      project = attr(attrs, "path") || attr(attrs, "name") || ""
      collect_kind(:linkfile, project, body) ++ collect_kind(:copyfile, project, body)
    end)
  end

  defp collect_kind(kind, project, body) do
    tag = Atom.to_string(kind)
    # `src` and `dest` values contain `/`, so `[^/>]*` from an earlier
    # revision missed every entry with a path in either attribute — a
    # regex that only matched attribute-free tags. `[^>]*?/>` allows
    # any character except `>` up to the self-close.
    Regex.scan(~r|<#{tag}\b([^>]*?)/>|s, body)
    |> Enum.map(fn [_, attrs] ->
      {kind, project, attr(attrs, "src"), attr(attrs, "dest")}
    end)
  end

  defp attr(attrs, name) do
    case Regex.run(~r|\b#{name}\s*=\s*"([^"]*)"|, attrs) do
      [_, v] -> v
      _ -> nil
    end
  end

  # Filesystem helpers ---------------------------------------------------

  defp lexists?(path), do: match?({:ok, _}, :file.read_link_info(String.to_charlist(path)))
  defp is_link?(path), do:
    (case :file.read_link_info(String.to_charlist(path)) do
       {:ok, {:file_info, _, :symlink, _, _, _, _, _, _, _, _, _, _, _}} -> true
       _ -> false
     end)

  defp realpath(path) do
    # Elixir's Path.expand does not resolve symlinks; use OS realpath.
    {out, 0} = System.cmd("realpath", [path])
    String.trim(out)
  end

  defp sha(path) do
    :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
  end

  defp pad(str, n), do: String.pad_trailing(to_string(str), n)

  # Self-test ------------------------------------------------------------

  def self_test do
    tmp_dir = fn -> System.tmp_dir!() |> Path.join("shepherd-manifest-root-" <> rand()) end

    positive = fixture(tmp_dir.())
    {_, failures, book} = check(positive, Path.join(positive, "default.xml"), false)
    clean? = failures == [] and book == []
    IO.puts("  #{pad(if(clean?, do: "ok", else: "FAIL"), 4)} positive control: " <>
      "a correct linkfile-only tree passes")
    unless clean? do
      IO.puts("       the gate rejects a correct tree; the controls below prove nothing.")
      File.rm_rf!(positive)
      System.halt(1)
    end
    File.rm_rf!(positive)

    controls = [
      {"a copyfile entry whose bytes match its source", &declare_copyfile/2},
      {"a linkfile repointed at another file", &repoint/2},
      {"a linkfile replaced by a byte-identical copy", &swap_for_copy/2},
      {"a linkfile left dangling by a moved source", &dangle/2},
      {"a destination removed outright", &vanish/2},
      {"bookkeeping naming a link the manifest does not", &stale_book/2},
      {"bookkeeping recording a copy at the root", &stray_copy/2},
      {"a manifest that does not parse", &unparseable/2}
    ]

    bad =
      for {name, mutate} <- controls, reduce: 0 do
        acc ->
          tmp = tmp_dir.()
          fixture(tmp)
          manifest = Path.join(tmp, "default.xml")
          mutate.(tmp, manifest)
          {_, failures, book} = check(tmp, manifest, false)
          caught = failures != [] or book != []
          IO.puts("  #{pad(if(caught, do: "ok", else: "FAIL"), 4)} " <>
            "negative control: #{name} is rejected")
          File.rm_rf!(tmp)
          if caught, do: acc, else: acc + 1
      end

    manifest_only_controls = [
      {"a copyfile declared, with no workspace to compare against", &declare_copyfile/2},
      {"a manifest that does not parse, with no workspace", &unparseable/2}
    ]

    tmp = tmp_dir.()
    fixture(tmp)
    manifest = Path.join(tmp, "default.xml")
    case entries(manifest) do
      {:ok, [_ | _]} ->
        IO.puts("  ok   positive control: a linkfile-only manifest passes with no workspace")
      _ ->
        IO.puts("  FAIL positive control: a linkfile-only manifest passes with no workspace")
        File.rm_rf!(tmp)
        System.halt(1)
    end
    File.rm_rf!(tmp)

    bad =
      for {name, mutate} <- manifest_only_controls, reduce: bad do
        acc ->
          tmp = tmp_dir.()
          fixture(tmp)
          manifest = Path.join(tmp, "default.xml")
          mutate.(tmp, manifest)
          {failed?, _} =
            case entries(manifest) do
              {:error, _} -> {true, nil}
              {:ok, declared} ->
                copies = for {:copyfile, _, _, _} <- declared, do: :x
                {copies != [], nil}
            end
          IO.puts("  #{pad(if(failed?, do: "ok", else: "FAIL"), 4)} " <>
            "negative control: #{name} is rejected")
          File.rm_rf!(tmp)
          if failed?, do: acc, else: acc + 1
      end

    if bad > 0 do
      IO.puts("       #{bad} mode(s) the gate claims to catch and does not.")
      1
    else
      total = length(controls) + length(manifest_only_controls)
      IO.puts("  #{total} of #{total} rejected.")
      0
    end
  end

  # Fixture + mutations --------------------------------------------------

  defp fixture(root) do
    File.mkdir_p!(Path.join(root, "proj"))
    File.write!(Path.join([root, "proj", "SRC.md"]), "the source\n")
    File.write!(Path.join([root, "proj", "OTHER.md"]), "a different file\n")
    File.ln_s!(Path.join("proj", "SRC.md"), Path.join(root, "LINK.md"))
    File.write!(Path.join(root, "default.xml"),
      ~s|<manifest><project name="proj" path="proj">| <>
      ~s|<linkfile src="SRC.md" dest="LINK.md" />| <>
      ~s|</project></manifest>\n|)
    File.mkdir_p!(Path.join(root, ".repo"))
    File.write!(Path.join(root, @bookkeeping),
      Jason.encode!(%{"linkfile" => ["LINK.md"], "copyfile" => []}))
    root
  end

  defp declare_copyfile(tmp, manifest) do
    File.cp!(Path.join([tmp, "proj", "SRC.md"]), Path.join(tmp, "COPY.md"))
    File.write!(manifest,
      ~s|<manifest><project name="proj" path="proj">| <>
      ~s|<linkfile src="SRC.md" dest="LINK.md" />| <>
      ~s|<copyfile src="SRC.md" dest="COPY.md" />| <>
      ~s|</project></manifest>\n|)
    File.write!(Path.join(tmp, @bookkeeping),
      Jason.encode!(%{"linkfile" => ["LINK.md"], "copyfile" => ["COPY.md"]}))
  end

  defp repoint(tmp, _) do
    File.rm!(Path.join(tmp, "LINK.md"))
    File.ln_s!(Path.join("proj", "OTHER.md"), Path.join(tmp, "LINK.md"))
  end

  defp swap_for_copy(tmp, _) do
    File.rm!(Path.join(tmp, "LINK.md"))
    File.cp!(Path.join([tmp, "proj", "SRC.md"]), Path.join(tmp, "LINK.md"))
  end

  defp dangle(tmp, _), do: File.rm!(Path.join([tmp, "proj", "SRC.md"]))
  defp vanish(tmp, _), do: File.rm!(Path.join(tmp, "LINK.md"))

  defp stale_book(tmp, _) do
    File.write!(Path.join(tmp, @bookkeeping),
      Jason.encode!(%{"linkfile" => ["LINK.md", "GONE.md"], "copyfile" => []}))
  end

  defp stray_copy(tmp, _) do
    File.write!(Path.join(tmp, @bookkeeping),
      Jason.encode!(%{"linkfile" => ["LINK.md"], "copyfile" => ["STRAY.md"]}))
  end

  defp unparseable(_tmp, manifest) do
    File.write!(manifest,
      ~s|<manifest><!-- a -- b --><project name="proj" path="proj">| <>
      ~s|<linkfile src="SRC.md" dest="LINK.md" />| <>
      ~s|</project></manifest>\n|)
  end

  defp rand, do: Integer.to_string(:erlang.unique_integer([:positive]))
end
