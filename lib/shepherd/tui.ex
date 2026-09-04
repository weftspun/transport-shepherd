defmodule Shepherd.TUI do
  @moduledoc """
  Owl-based progress rendering. Every command declares its steps up
  front; the TUI shows a live checklist and prints where each artefact
  landed, so the operator can see and audit what the CLI did.
  """

  def start(title, steps) do
    Owl.IO.puts([Owl.Data.tag(title, :cyan), "\n"])
    for {n, label} <- Enum.with_index(steps, 1) do
      Owl.IO.puts(["  ", Owl.Data.tag("[ ]", :faint), " ", "#{n}. #{label}"])
    end
    Owl.IO.puts("")
    %{title: title, steps: steps, current: 0}
  end

  def step_ok(state, message \\ nil) do
    n = state.current + 1
    label = Enum.at(state.steps, state.current)
    Owl.IO.puts([
      "  ",
      Owl.Data.tag("[✓]", :green),
      " #{n}. ",
      label,
      if(message, do: [" — ", Owl.Data.tag(message, :faint)], else: [])
    ])
    %{state | current: n}
  end

  def step_fail(state, reason) do
    n = state.current + 1
    label = Enum.at(state.steps, state.current)
    Owl.IO.puts([
      "  ",
      Owl.Data.tag("[✗]", :red),
      " #{n}. ",
      label,
      " — ",
      Owl.Data.tag(inspect(reason), :red)
    ])
    {:error, reason}
  end

  def artefact(path) do
    Owl.IO.puts(["    ", Owl.Data.tag("→ ", :faint), path])
  end
end
