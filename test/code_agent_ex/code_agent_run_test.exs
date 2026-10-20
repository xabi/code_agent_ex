defmodule CodeAgentEx.CodeAgentRunTest do
  use ExUnit.Case, async: false

  alias CodeAgentEx.{AgentConfig, CodeAgent}

  test "CodeAgent.run/3 returns {:error, reason} from the orchestrator (not bare :ok)" do
    original_hf = System.get_env("HF_TOKEN")
    original_openai = System.get_env("OPENAI_API_KEY")
    System.delete_env("HF_TOKEN")
    System.delete_env("OPENAI_API_KEY")

    on_exit(fn ->
      if original_hf, do: System.put_env("HF_TOKEN", original_hf)
      if original_openai, do: System.put_env("OPENAI_API_KEY", original_openai)
    end)

    config = AgentConfig.new(name: :run_api_agent, max_steps: 1, tools: [])

    result = CodeAgent.run("Calculate 1 + 1", config)

    # Previously this returned :ok from GenServer.cast and stopped the orch too early.
    assert match?({:error, _}, result)
    refute result == :ok
  end
end
