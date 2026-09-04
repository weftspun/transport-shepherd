defmodule Shepherd.Status do
  @moduledoc """
  Fleet snapshot + own state. Reads:
    - `~/.shepherd/current` for own CN
    - `agents/*.agents.weftspun` for fleet heartbeats
    - `auth/cert/certs?list=true` for live cert-auth entries

  Prints a table: CN, role, host, last heartbeat, serial, group set.
  """

  def run(_argv) do
    Owl.IO.puts(Owl.Data.tag("shepherd status", :cyan))
    Owl.IO.puts("skeleton — implementation pending")
    System.halt(0)
  end
end
