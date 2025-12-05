defmodule CodeAgentMinimal.AgentServer do
  @moduledoc """
  GenServer for running an agent asynchronously with message-based communication.

  ## Architecture

  Each managed agent runs in its own GenServer, enabling:
  - Asynchronous message-based communication
  - Interactive validation (pause/resume)
  - Supervision and fault tolerance
  - Isolated state per agent

  ## Supported Messages

  ### Sent to the GenServer (cast/call)
  - `{:run, task, from_pid}` - Start executing a task
  - `{:continue, decision, from_pid}` - Continue after validation
    - decision: :approve | {:modify, code} | {:feedback, msg} | :reject

  ### Sent by the GenServer (send)
  - `{:pending_validation, agent_pid, thought, code}` - Request validation
  - `{:final_result, agent_pid, result}` - Final result
  - `{:error, agent_pid, reason}` - Error occurred
  - `{:step_completed, agent_pid, step_info}` - Step notification

  ## Usage Example

      # Start an agent
      {:ok, agent_pid} = AgentServer.start_link(agent_config, parent_pid)

      # Run a task
      AgentServer.run(agent_pid, "Calculate factorial of 5")

      # Parent agent receives messages
      receive do
        {:pending_validation, ^agent_pid, thought, code} ->
          # Ask user
          AgentServer.continue(agent_pid, :approve)

        {:final_result, ^agent_pid, result} ->
          IO.puts("Result: \#{result}")
      end
  """

  use GenServer
  require Logger

  alias CodeAgentMinimal.CodeAgent

  ## Client API

  @doc """
  Starts an AgentServer with a configuration.

  ## Options
  - `agent_config` - Agent configuration (%AgentConfig{})
  - `parent_pid` - PID of parent process that will receive messages
  - `opts` - GenServer options (optional)
  """
  def start_link(agent_config, parent_pid, opts \\ []) do
    GenServer.start_link(__MODULE__, {agent_config, parent_pid}, opts)
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
  Stops the agent gracefully.
  """
  def stop(agent_pid) do
    GenServer.stop(agent_pid, :normal)
  end

  ## Server Callbacks

  @impl true
  def init({agent_config, parent_pid}) do
    Logger.info(
      "[AgentServer] Starting agent '#{agent_config.name}' (parent: #{inspect(parent_pid)})"
    )

    state = %{
      config: agent_config,
      parent_pid: parent_pid,
      status: :idle,
      current_task: nil,
      agent_state: nil,
      pending_validation: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:run, task, previous_state, from_pid}, state) do
    Logger.info("[AgentServer #{state.config.name}] Received :run from #{inspect(from_pid)}")

    # Notify parent of start
    send(state.parent_pid, {:agent_started, self(), state.config.name})

    # Store previous_state if provided (for context preservation)
    state_with_context = %{state | agent_state: previous_state}

    # The execution will block, but that's okay - the GenServer waits for validation
    result = execute_task(task, state_with_context)

    # Handle result - update state accordingly
    new_state = handle_execution_result(result, state_with_context)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:continue, decision, from_pid}, state) do
    Logger.info(
      "[AgentServer #{state.config.name}] Received :continue with #{inspect(decision)} from #{inspect(from_pid)}"
    )

    case state.pending_validation do
      nil ->
        Logger.warning("[AgentServer #{state.config.name}] No pending validation to continue")
        {:noreply, state}

      {thought, code, agent_state} ->
        # Normal validation continuation - execute directly
        result = continue_execution(decision, thought, code, agent_state, state)
        new_state = handle_continue_result(result, state)
        {:noreply, new_state}
    end
  end

  ## Private Functions

  # Executes a task in the agent - returns result tuple
  defp execute_task(task, server_state) do
    Logger.info(
      "[AgentServer #{server_state.config.name}] Executing task: #{String.slice(task, 0, 50)}..."
    )

    # Use run_direct to avoid creating nested orchestrators
    # Pass previous agent_state for context preservation
    CodeAgent.run_direct(task, server_state.config, server_state.agent_state)
  end

  # Handles execution result and updates state
  defp handle_execution_result(result, server_state) do
    case result do
      {:ok, final_result, agent_state} ->
        Logger.info("[AgentServer #{server_state.config.name}] Task completed successfully")
        # Send agent_state back to orchestrator for context preservation
        send(server_state.parent_pid, {:final_result, self(), final_result, agent_state})
        %{server_state | status: :completed, agent_state: agent_state}

      {:pending_validation, thought, code, agent_state} ->
        Logger.info("[AgentServer #{server_state.config.name}] Validation required")
        send(server_state.parent_pid, {:pending_validation, self(), thought, code})

        %{
          server_state
          | status: :pending_validation,
            pending_validation: {thought, code, agent_state}
        }

      {:error, reason, agent_state} ->
        Logger.error("[AgentServer #{server_state.config.name}] Task failed: #{inspect(reason)}")
        send(server_state.parent_pid, {:error, self(), reason})
        %{server_state | status: :failed, agent_state: agent_state}
    end
  end

  # Continues execution after validation - returns result tuple
  defp continue_execution(decision, thought, code, agent_state, server_state) do
    Logger.info(
      "[AgentServer #{server_state.config.name}] Continuing with decision: #{inspect(decision)}"
    )

    CodeAgent.continue_validation(decision, {thought, code, agent_state})
  end

  # Handles continuation result (same as handle_execution_result)
  defp handle_continue_result(result, server_state) do
    handle_execution_result(result, server_state)
  end
end
