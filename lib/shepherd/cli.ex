defmodule Shepherd.CLI do
  @moduledoc """
  Burrito entry point. `System.argv/0` on a Burrito binary is the CLI args.

  Commands:
    shepherd enroll             (peer, first-time onboarding)
    shepherd rotate             (peer, fresh keypair, same CN)
    shepherd migrate NEW_CN     (peer, full migration to new CN)
    shepherd revoke CN          (coordinator, tear down an identity)
    shepherd status             (any, snapshot fleet + own state)
    shepherd version            (any)
  """

  # Burrito invokes main/1 with argv.
  def main(argv) do
    case argv do
      ["enroll" | rest] -> Shepherd.Enrol.run(rest)
      ["rotate" | rest] -> Shepherd.Rotate.run(rest)
      ["migrate" | rest] -> Shepherd.Migrate.run(rest)
      ["revoke" | rest] -> Shepherd.Revoke.run(rest)
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
      enroll                 first-time onboarding for a new agent
      rotate                 fresh keypair against the current CN
      migrate NEW_CN         swap CN with a fresh keypair
      revoke CN              coordinator: tear down an identity
      status                 fleet snapshot + own state
      gates <name> [args]    run a workspace gate (see `shepherd gates`)
      version                print version
      help                   this text
    """
  end
end
