defmodule CodeAgentEx.AgentOrchestratorTest do
  use ExUnit.Case, async: false

  alias CodeAgentEx.{AgentConfig, AgentOrchestrator}

  setup do
    config =
      AgentConfig.new(
        name: :test_agent,
        max_steps: 1,
        tools: []
      )

    {:ok, orch} = AgentOrchestrator.start_link(config)
    on_exit(fn -> if Process.alive?(orch), do: AgentOrchestrator.stop(orch) end)
    %{orch: orch, config: config}
  end

  describe "run_task/2 (synchronous)" do
    test "returns {:error, reason} when the agent cannot complete", %{orch: orch} do
      # No API key → LLM calls fail → agent reports an error
      clear_api_keys!()

      assert {:error, _reason} = AgentOrchestrator.run_task(orch, "Calculate 1 + 1", 30_000)

      status = AgentOrchestrator.get_status(orch)
      assert status.status == :failed
    end

    test "returns {:error, :busy} while another task is running", %{orch: orch} do
      :sys.replace_state(orch, fn state ->
        %{state | status: :running, main_agent_pid: self()}
      end)

      assert {:error, :busy} = AgentOrchestrator.run_task(orch, "second task", 5_000)
    end

    test "can run another task after a previous one finishes", %{orch: orch} do
      clear_api_keys!()

      assert {:error, _} = AgentOrchestrator.run_task(orch, "first", 30_000)
      assert {:error, _} = AgentOrchestrator.run_task(orch, "second", 30_000)
    end
  end

  describe "run_task_async/2" do
    test "notifies the client process with an error message when the agent fails", %{
      orch: orch
    } do
      clear_api_keys!()

      assert :ok = AgentOrchestrator.run_task_async(orch, "Calculate 1 + 1")

      assert_receive {:error, ^orch, _reason}, 30_000
    end

    test "notifies the client with :busy when already running", %{orch: orch} do
      :sys.replace_state(orch, fn state ->
        %{state | status: :running, main_agent_pid: self()}
      end)

      assert :ok = AgentOrchestrator.run_task_async(orch, "second task")
      assert_receive {:error, ^orch, :busy}, 1_000
    end
  end

  describe "get_status/1" do
    test "starts idle", %{orch: orch} do
      assert %{status: :idle} = AgentOrchestrator.get_status(orch)
    end
  end

  defp clear_api_keys! do
    original_hf = System.get_env("HF_TOKEN")
    original_openai = System.get_env("OPENAI_API_KEY")
    System.delete_env("HF_TOKEN")
    System.delete_env("OPENAI_API_KEY")

    on_exit(fn ->
      if original_hf, do: System.put_env("HF_TOKEN", original_hf)
      if original_openai, do: System.put_env("OPENAI_API_KEY", original_openai)
    end)
  end
end
