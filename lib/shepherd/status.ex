defmodule Shepherd.Status do
  @moduledoc """
  Fleet snapshot + own state. Reads:
    - `~/.shepherd/current` for own CN
    - `agents/*.agents.weftspun` for fleet heartbeats
    - `auth/cert/certs?list=true` for live cert-auth entries

  Prints a table: CN, role, host, last heartbeat, serial, group set.

  First line is an identity assertion: `bao token lookup` must return the
  entity behind this agent's own cert-auth alias. A mismatch is a FAIL,
  not a note — a stale `~/.bao-token` can be another agent's identity.
  """

  def run(_argv) do
    IO.puts("shepherd status")
    IO.puts("skeleton — implementation pending")
    System.halt(0)
  end
end
