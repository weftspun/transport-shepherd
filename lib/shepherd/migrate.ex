defmodule Shepherd.Migrate do
  @moduledoc """
  Swap CN with a fresh keypair. Peer side. `shepherd migrate NEW_CN`.

  This is the ceremony with the most gotchas in RFD 2195 DETAILS: the
  ReBAC tuples key on CN, the identity groups key on entity IDs, and the
  cert-auth entry keys on its own name. The coordinator half of the
  migration reconciles all three, and the peer half is enroll-like with
  an explicit teardown of the old identity at the end.
  """

  alias Shepherd.TUI

  @steps [
    "resolve NEW_CN + old CN",
    "generate fresh keypair under NEW_CN",
    "build CSR for NEW_CN",
    "hand CSR + migration intent to coordinator",
    "coordinator: sign, create cert-auth, migrate tuples, reconcile groups",
    "poll Bao KV for signed bundle",
    "install cert bundle at NEW_CN path",
    "bao login -method=cert",
    "write heartbeat row at NEW_CN",
    "coordinator: tear down old cert-auth + revoke old serial",
    "update ~/.shepherd/current"
  ]

  def run(argv) do
    case argv do
      [new_cn | _] ->
        _state = TUI.start("shepherd migrate #{new_cn}", @steps)
        IO.puts(:stderr, "shepherd migrate: skeleton — implementation pending")
        System.halt(0)

      [] ->
        IO.puts(:stderr, "shepherd migrate: missing NEW_CN")
        IO.puts(:stderr, "usage: shepherd migrate NEW_CN")
        System.halt(2)
    end
  end
end
