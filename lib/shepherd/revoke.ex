defmodule Shepherd.Revoke do
  @moduledoc """
  Coordinator side: pull a peer's identity. Deletes the cert-auth entry,
  revokes the PKI serial, drops the ReBAC tuples, and removes the entity
  from all identity groups. The peer's local cert bundle is left in
  place — this command runs on the coordinator, and can't reach the peer
  filesystem.
  """

  alias Shepherd.TUI

  @steps [
    "resolve CN",
    "read cert-auth entry (serial + accessor)",
    "delete cert-auth entry",
    "revoke PKI serial",
    "drop ReBAC tuples where subject or object == CN",
    "remove entity from identity groups",
    "delete Bao KV row certs/<cn>",
    "delete Bao KV row agents/<cn>.agents.weftspun"
  ]

  def run(argv) do
    case argv do
      [cn | _] ->
        _state = TUI.start("shepherd revoke #{cn}", @steps)
        IO.puts(:stderr, "shepherd revoke: skeleton — implementation pending")
        System.halt(0)

      [] ->
        IO.puts(:stderr, "shepherd revoke: missing CN")
        IO.puts(:stderr, "usage: shepherd revoke CN")
        System.halt(2)
    end
  end
end
