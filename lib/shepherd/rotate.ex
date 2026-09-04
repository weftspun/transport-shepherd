defmodule Shepherd.Rotate do
  @moduledoc """
  Fresh keypair against the current CN. Peer side.

  Same steps as enroll except step 1 reads the current CN from
  `~/.shepherd/current` and step 9 is `revoke-old` rather than
  `repo sync` — the workspace is already synced, and the old serial
  must not outlive the rotation.
  """

  alias Shepherd.TUI

  @steps [
    "read current CN",
    "generate fresh keypair",
    "build CSR",
    "hand CSR to coordinator",
    "poll Bao KV for signed bundle",
    "install cert bundle",
    "bao login -method=cert",
    "write heartbeat row",
    "coordinator revokes old serial"
  ]

  def run(_argv) do
    _state = TUI.start("shepherd rotate", @steps)
    IO.puts(:stderr, "shepherd rotate: skeleton — implementation pending")
    System.halt(0)
  end
end
