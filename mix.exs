defmodule CodeAgentMinimal.MixProject do
  use Mix.Project

  def project do
    [
      app: :code_agent_minimal,
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
      mod: {CodeAgentMinimal.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # LLM clients
      {:req, "~> 0.5"},
      {:jason, "~> 1.2"},
      {:openai_ex, "~> 0.9.18"},

      # Code execution sandbox
      {:mini_elixir, github: "sequinstream/mini_elixir"},

      # Python integration
      {:pythonx, "~> 0.4"},

      # AI-powered validation
      {:instructor_lite, "~> 1.1.2"}
    ]
  end
end
