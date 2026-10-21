defmodule CodeAgentEx.AgentServerTest do
  use ExUnit.Case, async: true

  alias CodeAgentEx.{AgentConfig, AgentServer}

  test "get_status/1 answers during long-running execute_fun" do
    parent = self()
    config = AgentConfig.new(name: :responsive_agent, max_steps: 1, tools: [])

    execute_fun = fn _task, _config, _prev ->
      send(parent, {:worker_started, self()})

      receive do
        :finish -> {:ok, "ok", %{}}
      after
        5_000 -> {:error, :timeout, nil}
      end
    end

    {:ok, agent} = AgentServer.start_link(config, parent, execute_fun: execute_fun)
    AgentServer.run(agent, "task")

    assert_receive {:agent_started, ^agent, :responsive_agent}, 1_000
    assert_receive {:worker_started, worker_pid}, 1_000

    assert :running = AgentServer.get_status(agent)

    send(worker_pid, :finish)

    assert_receive {:final_result, ^agent, "ok", %{}}, 1_000
    assert :completed = AgentServer.get_status(agent)
  end

  test "continue/2 runs in a worker and keeps GenServer responsive" do
    parent = self()
    config = AgentConfig.new(name: :continue_agent, max_steps: 2, tools: [])

    code_step = %{thought: "t", code: "1 + 1", safety_assessment: :safe, safety_reasoning: "ok"}

    execute_fun = fn _task, _config, _prev ->
      {:pending_validation, code_step, %{step: 1}}
    end

    continue_fun = fn decision, {_code_step, agent_state} ->
      send(parent, {:continue_started, self(), decision})

      receive do
        :finish -> {:ok, "approved", agent_state}
      after
        5_000 -> {:error, :timeout, agent_state}
      end
    end

    {:ok, agent} =
      AgentServer.start_link(config, parent,
        execute_fun: execute_fun,
        continue_fun: continue_fun
      )

    AgentServer.run(agent, "needs-validation")

    assert_receive {:pending_validation, ^agent, ^code_step}, 1_000
    assert :pending_validation = AgentServer.get_status(agent)

    AgentServer.continue(agent, :approve)

    assert_receive {:continue_started, worker_pid, :approve}, 1_000
    assert :running = AgentServer.get_status(agent)

    send(worker_pid, :finish)

    assert_receive {:final_result, ^agent, "approved", %{step: 1}}, 1_000
    assert :completed = AgentServer.get_status(agent)
  end

  test "worker exception is reported to the parent" do
    parent = self()
    config = AgentConfig.new(name: :crash_agent, max_steps: 1, tools: [])

    execute_fun = fn _task, _config, _prev ->
      raise "boom"
    end

    {:ok, agent} = AgentServer.start_link(config, parent, execute_fun: execute_fun)
    AgentServer.run(agent, "explode")

    assert_receive {:error, ^agent, "boom"}, 1_000
    assert :failed = AgentServer.get_status(agent)
  end

  test "worker process crash (exit) is reported to the parent" do
    parent = self()
    config = AgentConfig.new(name: :kill_agent, max_steps: 1, tools: [])

    execute_fun = fn _task, _config, _prev ->
      send(parent, {:worker_started, self()})
      Process.sleep(10_000)
      {:ok, "never", %{}}
    end

    {:ok, agent} = AgentServer.start_link(config, parent, execute_fun: execute_fun)
    AgentServer.run(agent, "kill-me")

    assert_receive {:worker_started, worker_pid}, 1_000
    Process.exit(worker_pid, :kill)

    assert_receive {:error, ^agent, {:worker_crashed, :killed}}, 1_000
    assert :failed = AgentServer.get_status(agent)
  end

  test "stop/1 kills an in-flight worker" do
    parent = self()
    config = AgentConfig.new(name: :stop_agent, max_steps: 1, tools: [])

    execute_fun = fn _task, _config, _prev ->
      send(parent, {:worker_started, self()})
      Process.sleep(10_000)
      {:ok, "late", %{}}
    end

    {:ok, agent} = AgentServer.start_link(config, parent, execute_fun: execute_fun)
    AgentServer.run(agent, "long")

    assert_receive {:worker_started, worker_pid}, 1_000
    assert Process.alive?(worker_pid)

    assert :ok = AgentServer.stop(agent)
    refute Process.alive?(agent)

    Process.sleep(50)
    refute Process.alive?(worker_pid)
  end
end
