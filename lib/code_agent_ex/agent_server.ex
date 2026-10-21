defmodule CodeAgentEx.AgentServer do
  @moduledoc """
  GenServer for running an agent asynchronously with message-based communication.

  ## Architecture

  Each managed agent runs in its own GenServer, enabling:
  - Asynchronous message-based communication
  - Interactive validation (pause/resume)
  - Supervision and fault tolerance
  - Isolated state per agent

  Long-running work (LLM calls and code execution) runs in a monitored
  worker process so the GenServer stays responsive to `:continue`, `:stop`,
  and status queries while a step is in flight.

  ## Supported Messages

  ### Sent to the GenServer (cast/call)
  - `{:run, task, from_pid}` - Start executing a task
  - `{:continue, decision, from_pid}` - Continue after validation
    - decision: :approve | {:modify, code} | {:feedback, msg} | :reject

  ### Sent by the GenServer (send)
  - `{:pending_validation, agent_pid, code_step}` - Request validation (code_step is a CodeStep struct)
  - `{:final_result, agent_pid, result, agent_state}` - Final result
  - `{:error, agent_pid, reason}` - Error occurred
  - `{:rejected, agent_pid}` - Execution rejected

  ## Usage Example

      # Start an agent
      {:ok, agent_pid} = AgentServer.start_link(agent_config, parent_pid)

      # Run a task
      AgentServer.run(agent_pid, "Calculate factorial of 5")

      # Parent agent receives messages
      receive do
        {:pending_validation, ^agent_pid, code_step} ->
          # Ask user
          IO.puts("Code: \#{code_step.code}")
          IO.puts("Safety: \#{code_step.safety_assessment}")
          AgentServer.continue(agent_pid, :approve)

        {:final_result, ^agent_pid, result, _agent_state} ->
          IO.puts("Result: \#{result}")
      end
  """

  use GenServer
  require Logger

  alias CodeAgentEx.CodeAgent

  @agent_opts [:execute_fun, :continue_fun]

  ## Client API

  @doc """
  Starts an AgentServer with a configuration.

  ## Options
  - `agent_config` - Agent configuration (%AgentConfig{})
  - `parent_pid` - PID of parent process that will receive messages
  - `opts` - Keyword list:
    - GenServer options (`:name`, etc.)
    - `:execute_fun` - `(task, config, previous_state -> result)` (default: `CodeAgent.run_direct/3`)
    - `:continue_fun` - `(decision, {code_step, agent_state} -> result)` (default: `CodeAgent.continue_validation/2`)
  """
  def start_link(agent_config, parent_pid, opts \\ []) do
    {agent_opts, genserver_opts} = Keyword.split(opts, @agent_opts)
    GenServer.start_link(__MODULE__, {agent_config, parent_pid, agent_opts}, genserver_opts)
  end

  @doc """
  Runs a task execution (asynchronous).

  ## Options
  - `previous_state` - Previous agent state for context preservation (optional)
  """
  def run(agent_pid, task, previous_state \\ nil) do
    GenServer.cast(agent_pid, {:run, task, previous_state, self()})
  end

  @doc """
  Continues execution after a validation request.

  ## Possible decisions
  - `:approve` - Approve and execute the code
  - `{:modify, new_code}` - Modify code before execution
  - `{:feedback, message}` - Give feedback without executing
  - `:reject` - Reject and stop
  """
  def continue(agent_pid, decision) do
    GenServer.cast(agent_pid, {:continue, decision, self()})
  end

  @doc """
  Returns the current agent status (`:idle`, `:running`, `:pending_validation`, etc.).

  This is a synchronous call and must remain responsive while a worker is running.
  """
  def get_status(agent_pid) do
    GenServer.call(agent_pid, :get_status)
  end

  @doc """
  Stops the agent gracefully.
  """
  def stop(agent_pid) do
    GenServer.stop(agent_pid, :normal)
  end

  ## Server Callbacks

  @impl true
  def init({agent_config, parent_pid, agent_opts}) do
    Logger.info(
      "[AgentServer] Starting agent '#{agent_config.name}' (parent: #{inspect(parent_pid)})"
    )

    Process.flag(:trap_exit, true)

    state = %{
      config: agent_config,
      parent_pid: parent_pid,
      status: :idle,
      current_task: nil,
      agent_state: nil,
      pending_validation: nil,
      worker_pid: nil,
      worker_ref: nil,
      execute_fun: Keyword.get(agent_opts, :execute_fun, &CodeAgent.run_direct/3),
      continue_fun: Keyword.get(agent_opts, :continue_fun, &CodeAgent.continue_validation/2)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_cast({:run, task, previous_state, from_pid}, state) do
    Logger.info("[AgentServer #{state.config.name}] Received :run from #{inspect(from_pid)}")

    cond do
      state.worker_pid != nil ->
        Logger.warning(
          "[AgentServer #{state.config.name}] Ignoring :run — worker already in flight"
        )

        {:noreply, state}

      state.status == :pending_validation ->
        Logger.warning(
          "[AgentServer #{state.config.name}] Ignoring :run — waiting for validation decision"
        )

        {:noreply, state}

      true ->
        send(state.parent_pid, {:agent_started, self(), state.config.name})

        state = %{
          state
          | agent_state: previous_state,
            current_task: task,
            status: :running,
            pending_validation: nil
        }

        {:noreply, start_worker(state, fn -> state.execute_fun.(task, state.config, previous_state) end)}
    end
  end

  def handle_cast({:continue, decision, from_pid}, state) do
    Logger.info(
      "[AgentServer #{state.config.name}] Received :continue with #{inspect(decision)} from #{inspect(from_pid)}"
    )

    cond do
      state.worker_pid != nil ->
        Logger.warning(
          "[AgentServer #{state.config.name}] Ignoring :continue — worker already in flight"
        )

        {:noreply, state}

      state.pending_validation == nil ->
        Logger.warning("[AgentServer #{state.config.name}] No pending validation to continue")
        {:noreply, state}

      true ->
        {code_step, agent_state} = state.pending_validation
        continue_fun = state.continue_fun

        state = %{
          state
          | pending_validation: nil,
            status: :running
        }

        {:noreply,
         start_worker(state, fn ->
           continue_fun.(decision, {code_step, agent_state})
         end)}
    end
  end

  @impl true
  def handle_info({:worker_result, worker_pid, result}, %{worker_pid: worker_pid} = state) do
    state = clear_worker(state)
    {:noreply, handle_execution_result(result, state)}
  end

  def handle_info({:worker_result, _other_pid, _result}, state) do
    # Stale result from a killed/previous worker
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, :normal}, %{worker_ref: ref, worker_pid: pid} = state) do
    # Normal exit — {:worker_result, ...} carries the outcome; keep monitoring state
    # until that message is handled (demonitor happens there).
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %{worker_ref: ref, worker_pid: pid} = state) do
    Logger.error(
      "[AgentServer #{state.config.name}] Worker crashed: #{inspect(reason)}"
    )

    state = clear_worker(state)
    send(state.parent_pid, {:error, self(), {:worker_crashed, reason}})
    {:noreply, %{state | status: :failed}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    # trap_exit: ignore linked exits we don't own as workers
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    kill_worker(state)
    :ok
  end

  ## Private Functions

  defp start_worker(state, work_fun) do
    server = self()
    name = state.config.name

    {worker_pid, worker_ref} =
      spawn_monitor(fn ->
        Logger.info("[AgentServer #{name}] Worker started")

        result =
          try do
            work_fun.()
          rescue
            e ->
              {:error, Exception.message(e), nil}
          catch
            kind, reason ->
              {:error, {kind, reason}, nil}
          end

        send(server, {:worker_result, self(), result})
      end)

    %{state | worker_pid: worker_pid, worker_ref: worker_ref, status: :running}
  end

  defp clear_worker(%{worker_ref: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    %{state | worker_pid: nil, worker_ref: nil}
  end

  defp clear_worker(state), do: %{state | worker_pid: nil, worker_ref: nil}

  defp kill_worker(%{worker_pid: nil}), do: :ok

  defp kill_worker(%{worker_pid: pid, worker_ref: ref}) do
    if is_reference(ref), do: Process.demonitor(ref, [:flush])
    Process.exit(pid, :kill)
    :ok
  end

  # Handles execution result and updates state
  defp handle_execution_result(result, server_state) do
    case result do
      {:ok, final_result, agent_state} ->
        Logger.info("[AgentServer #{server_state.config.name}] Task completed successfully")
        # Send agent_state back to orchestrator for context preservation
        send(server_state.parent_pid, {:final_result, self(), final_result, agent_state})
        %{server_state | status: :completed, agent_state: agent_state}

      {:pending_validation, code_step, agent_state} ->
        Logger.info("[AgentServer #{server_state.config.name}] Validation required")
        send(server_state.parent_pid, {:pending_validation, self(), code_step})

        %{
          server_state
          | status: :pending_validation,
            pending_validation: {code_step, agent_state},
            agent_state: agent_state
        }

      {:rejected, agent_state} ->
        Logger.warning("[AgentServer #{server_state.config.name}] Execution rejected by validator")
        send(server_state.parent_pid, {:rejected, self()})
        %{server_state | status: :rejected, agent_state: agent_state}

      {:error, reason, agent_state} ->
        Logger.error("[AgentServer #{server_state.config.name}] Task failed: #{inspect(reason)}")
        send(server_state.parent_pid, {:error, self(), reason})
        %{server_state | status: :failed, agent_state: agent_state}

      other ->
        Logger.error(
          "[AgentServer #{server_state.config.name}] Unexpected worker result: #{inspect(other)}"
        )

        send(server_state.parent_pid, {:error, self(), {:unexpected_result, other}})
        %{server_state | status: :failed}
    end
  end
end
