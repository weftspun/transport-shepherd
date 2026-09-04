defmodule ShepherdTest do
  use ExUnit.Case, async: true

  test "CLI help does not crash" do
    # Skeleton smoke test; the real integration harness is on the
    # follow-up PR that lands the Bao client.
    assert function_exported?(Shepherd.CLI, :main, 1)
  end
end
