defmodule Shepherd.Enrol do
  @moduledoc """
  First-time onboarding for a new agent. Runs on the peer's box.

  State machine, all internal to this one command:

    1. read/confirm CN (`--cn` or prompt)
    2. generate keypair under `~/.shepherd/<cn>/`
    3. build CSR
    4. hand CSR to coordinator via SendMessage relay (out-of-band today;
       skeleton stops here and prints the CSR + polling instructions)
    5. poll Bao KV `certs/<cn>` for the signed bundle
    6. install cert bundle (leaf + full-chain) with 0600 / 0644 perms
    7. `bao login -method=cert` and stash token at `~/.bao-token`
    8. write first heartbeat row at `agents/<cn>.agents.weftspun`
    9. `repo sync` at workspace root
  """

  alias Shepherd.TUI

  @steps [
    "resolve CN",
    "generate keypair",
    "build CSR",
    "hand CSR to coordinator",
    "poll Bao KV for signed bundle",
    "install cert bundle",
    "bao login -method=cert",
    "write heartbeat row",
    "repo sync"
  ]

  def run(_argv) do
    _state = TUI.start("shepherd enroll", @steps)
    IO.puts(:stderr, "shepherd enroll: skeleton — implementation pending")
    System.halt(0)
  end
end
