defmodule Shepherd.CLI do
  @moduledoc """
  Burrito entry point. `System.argv/0` on a Burrito binary is the CLI args.

  Commands:
    shepherd status             (any, snapshot fleet + own state)
    shepherd gates <name>       (run a workspace gate; `shepherd gates` lists)
    shepherd version            (any)

  The enrol / rotate / migrate / revoke ceremony was trimmed after
  per-agent `BAO_TOKEN` + `bao login -no-store` closed the stale-token
  failure mode RFD 2195 was written against. If those commands are
  needed again, retrofit from RFD 2195 DETAILS §"stale token file".
  """

  # Burrito invokes main/1 with argv.
  def main(argv) do
    case argv do
      ["status" | rest] -> Shepherd.Status.run(rest)
      ["gates" | rest] -> Shepherd.Gates.dispatch(rest)
      ["version"] -> IO.puts(vsn())
      [] -> IO.puts(help_text())
      ["help"] -> IO.puts(help_text())
      ["--help"] -> IO.puts(help_text())
      other ->
        IO.puts(:stderr, "shepherd: unknown command: #{inspect(other)}")
        IO.puts(:stderr, help_text())
        System.halt(2)
    end
  end

  defp vsn, do: "shepherd 0.1.0-dev"

  defp help_text do
    """
    shepherd — weftspun agent lifecycle TUI.

    Commands:
      status                 fleet snapshot + own state
      gates <name> [args]    run a workspace gate (see `shepherd gates`)
      version                print version
      help                   this text
    """
  end
end
