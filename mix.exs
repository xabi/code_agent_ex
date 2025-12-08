defmodule CodeAgentEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :code_agent_ex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {CodeAgentEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # LLM client with structured outputs
      {:instructor_lite, "~> 1.1.2"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.2"},

      # Code execution sandbox (not used for now, using Code.eval_string instead)
      # {:mini_elixir, github: "sequinstream/mini_elixir"},

      # Python integration
      {:pythonx, "~> 0.4"}
    ]
  end
end
