defmodule CodeAgentEx.AgentOrchestrator do
  @moduledoc """
  Central orchestrator for managing all agent communications and validations.

  This GenServer works with AgentSupervisor to provide a unified interface
  for agent execution and validation handling. It:
  - Intercepts all validation requests from any agent (main or sub-agents)
  - Routes validation decisions to the correct agent
  - Provides a single point of interaction for the user
  - Manages the complete execution lifecycle

  ## Architecture

  ```
  User/Client
      |
      v
  AgentOrchestrator (this GenServer - communication hub)
      |
      v
  AgentSupervisor (supervision tree)
      |
      +---> Main Agent (GenServer)
      |         |
      |         +---> Sub-Agent 1 (GenServer)
      |         +---> Sub-Agent 2 (GenServer)
  ```

  ## Usage

      {:ok, orch} = AgentOrchestrator.start_link(agent_config)

      # Synchronous (preferred): blocks until the task completes
      {:ok, result} = AgentOrchestrator.run_task(orch, "Calculate 5 + 3")

      # Asynchronous: results arrive as messages to the caller of start_link/2
      :ok = AgentOrchestrator.run_task_async(orch, "Calculate 5 + 3")

      receive do
        {:final_result, ^orch, result} -> IO.puts("Result: \#{result}")
        {:error, ^orch, reason} -> IO.puts("Error: \#{inspect(reason)}")
        {:rejected, ^orch} -> IO.puts("Rejected")
      end
  """

  use GenServer
  require Logger

  alias CodeAgentEx.{AgentSupervisor, AgentServer}

  @default_task_timeout 120_000

  defstruct [
    # PID of the client who started the orchestrator
    :client_pid,
    # Configuration of the main agent
    :agent_config,
    # PID of the main agent (if running)
    :main_agent_pid,
    # Current status: :idle | :running | :waiting_validation | :completed | :failed | :rejected
    :status,
    # Current validation being processed
    :current_validation,
    # Final result of last task
    :result,
    # Error if any
    :error,
    # Function to handle validation requests: fn(validation_request) -> any()
    # Default: auto-approve by calling AgentServer.continue(agent_pid, :approve)
    :validation_handler,
    # Agent state persisted between tasks (memory, binding, etc.)
    :agent_state,
    # GenServer.from waiting on a synchronous run_task/2 call (nil when async)
    :task_from,
    # Map of sub-agent tracking: %{agent_pid => %{from, agent_name}}
    sub_agents: %{}
  ]

  ## Client API

  @doc """
  Starts the orchestrator with an agent configuration.

  The orchestrator is reusable - you can run multiple tasks with `run_task/2`
  and it will maintain agent state (memory, bindings) between tasks.

  ## Options
  - `:validation_handler` - Function to handle validation requests (default: auto-approve)
    The function receives a validation_request map with keys:
    - `:agent_pid` - PID of the agent requesting validation
    - `:agent_name` - Name of the agent
    - `:code_step` - CodeStep struct with thought, code, safety_assessment, and safety_reasoning

    The function should call `AgentServer.continue(agent_pid, decision)` with one of:
    - `:approve` - Execute the code as-is
    - `{:modify, new_code}` - Execute modified code
    - `{:feedback, message}` - Send feedback without executing
    - `:reject` - Reject and stop

  ## Example

      # Default: auto-approve
      {:ok, orch} = AgentOrchestrator.start_link(config)

      # Custom validation handler
      handler = fn %{agent_pid: pid, code_step: code_step} = req ->
        IO.puts("Validating: \#{code_step.code}")
        IO.puts("Safety: \#{code_step.safety_assessment}")
        AgentServer.continue(pid, :approve)
      end
      {:ok, orch} = AgentOrchestrator.start_link(config, validation_handler: handler)

  Returns `{:ok, orchestrator_pid}`.
  """
  def start_link(agent_config, opts \\ []) do
    validation_handler = Keyword.get(opts, :validation_handler, &default_validation_handler/1)
    genserver_opts = Keyword.drop(opts, [:validation_handler])
    GenServer.start_link(__MODULE__, {agent_config, self(), validation_handler}, genserver_opts)
  end

  # Default validation handler: auto-approve all validations
  defp default_validation_handler(%{agent_pid: agent_pid}) do
    AgentServer.continue(agent_pid, :approve)
  end

  @doc """
  Runs a task synchronously and waits for completion.

  The orchestrator maintains agent state between calls, enabling
  multi-turn conversations with context.

  ## Returns

  - `{:ok, result}` - Task completed successfully
  - `{:error, reason}` - Task failed or orchestrator is busy
  - `{:error, :rejected}` - Task was rejected by validation

  ## Example

      {:ok, orch} = AgentOrchestrator.start_link(config)

      with {:ok, answer1} <- AgentOrchestrator.run_task(orch, "What is 2 + 2?"),
           {:ok, answer2} <- AgentOrchestrator.run_task(orch, "Multiply that by 3") do
        {answer1, answer2}
      end

  For non-blocking execution, use `run_task_async/2`.
  """
  def run_task(orchestrator_pid, task, timeout \\ @default_task_timeout) do
    GenServer.call(orchestrator_pid, {:run_task, task}, timeout)
  end

  @doc """
  Runs a task asynchronously.

  Non-blocking: starts execution and returns `:ok` immediately.
  Results are sent as messages to the process that called `start_link/2`:

  - `{:final_result, orchestrator_pid, result}` - Task completed successfully
  - `{:error, orchestrator_pid, reason}` - Task failed
  - `{:rejected, orchestrator_pid}` - Task was rejected

  ## Example

      {:ok, orch} = AgentOrchestrator.start_link(config)
      :ok = AgentOrchestrator.run_task_async(orch, "Calculate 5 + 3")

      receive do
        {:final_result, ^orch, res} -> IO.puts("Result: \#{res}")
        {:error, ^orch, reason} -> IO.puts("Error: \#{inspect(reason)}")
        {:rejected, ^orch} -> IO.puts("Rejected")
      end
  """
  def run_task_async(orchestrator_pid, task) do
    GenServer.cast(orchestrator_pid, {:run_task_async, task})
  end

  @doc """
  Submits a validation decision for the current validation request.

  Decisions:
  - `:approve` - Execute the code as-is
  - `{:modify, new_code}` - Execute modified code
  - `{:feedback, message}` - Send feedback, don't execute
  - `:reject` - Reject and stop execution
  """
  def submit_decision(orchestrator_pid, decision) do
    GenServer.cast(orchestrator_pid, {:submit_decision, decision})
  end

  @doc """
  Gets the current status of the orchestrator.
  """
  def get_status(orchestrator_pid) do
    GenServer.call(orchestrator_pid, :get_status)
  end

  @doc """
  Gets the full state of the orchestrator for debugging/monitoring.
  """
  def get_state(orchestrator_pid) do
    GenServer.call(orchestrator_pid, :get_state)
  end

  @doc """
  Registers a sub-agent and waits for its result.

  This is a synchronous call that blocks until the sub-agent completes.
  Used by managed agents to delegate work to sub-agents.

  Returns: result string or error message
  """
  def track_sub_agent(orchestrator_pid, agent_pid, agent_name, timeout \\ 120_000) do
    GenServer.call(orchestrator_pid, {:track_sub_agent, agent_pid, agent_name}, timeout)
  end

  @doc """
  Stops the orchestrator and all managed agents.
  """
  def stop(orchestrator_pid) do
    GenServer.stop(orchestrator_pid, :normal)
  end

  ## Server Callbacks

  @impl true
  def init({agent_config, client_pid, validation_handler}) do
    Logger.info("[AgentOrchestrator] Initializing orchestrator")
    Logger.info("[AgentOrchestrator] Validation handler: #{inspect(validation_handler)}")

    # Set the orchestrator as the listener for all agent progress
    agent_config_with_listener = %{agent_config | listener_pid: self()}

    state = %__MODULE__{
      client_pid: client_pid,
      agent_config: agent_config_with_listener,
      status: :idle,
      validation_handler: validation_handler,
      agent_state: nil
    }

    # Don't start execution - wait for run_task call
    {:ok, state}
  end


  @impl true
  def handle_call({:run_task, task}, from, state) do
    Logger.info("[AgentOrchestrator] Running task (sync): #{String.slice(task, 0, 50)}...")

    case start_main_agent(task, state) do
      {:ok, new_state} ->
        # Reply later via GenServer.reply/2 when the agent finishes
        {:noreply, %{new_state | task_from: from}}

      {:error, :busy} ->
        {:reply, {:error, :busy}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | status: :failed, error: reason}}
    end
  end

  def handle_call(:get_status, _from, state) do
    status_info = %{
      status: state.status,
      has_current_validation: state.current_validation != nil,
      result: state.result,
      error: state.error
    }

    {:reply, status_info, state}
  end

  def handle_call(:get_state, _from, state) do
    # Return the full orchestrator state - let the view handle what to display
    {:reply, state, state}
  end

  def handle_call({:track_sub_agent, agent_pid, agent_name}, from, state) do
    Logger.info(
      "[AgentOrchestrator] Tracking sub-agent '#{agent_name}' (#{inspect(agent_pid)}) for #{inspect(from)}"
    )

    # Store the caller's info so we can reply when the sub-agent completes
    sub_agent_info = %{from: from, agent_name: agent_name}
    new_sub_agents = Map.put(state.sub_agents, agent_pid, sub_agent_info)

    # Don't reply yet - we'll reply when we receive {:final_result, agent_pid, result}
    {:noreply, %{state | sub_agents: new_sub_agents}}
  end

  @impl true
  def handle_cast({:submit_decision, decision}, state) do
    Logger.info("[AgentOrchestrator] Received decision: #{inspect(decision)}")

    case state.current_validation do
      nil ->
        Logger.warning("[AgentOrchestrator] No pending validation for decision")
        {:noreply, state}

      %{agent_pid: agent_pid} ->
        # Forward decision to the agent
        AgentServer.continue(agent_pid, decision)

        # Clear current validation and go back to running
        {:noreply, %{state | current_validation: nil, status: :running}}
    end
  end

  def handle_cast({:run_task_async, task}, state) do
    Logger.info("[AgentOrchestrator] Running task (async): #{String.slice(task, 0, 50)}...")

    case start_main_agent(task, state) do
      {:ok, new_state} ->
        {:noreply, %{new_state | task_from: nil}}

      {:error, :busy} ->
        send(state.client_pid, {:error, self(), :busy})
        {:noreply, state}

      {:error, reason} ->
        send(state.client_pid, {:error, self(), reason})
        {:noreply, %{state | status: :failed, error: reason}}
    end
  end

  ## Handle messages from agents

  @impl true
  def handle_info({:agent_started, agent_pid, agent_name}, state) do
    Logger.info("[AgentOrchestrator] Agent '#{agent_name}' started (#{inspect(agent_pid)})")
    {:noreply, state}
  end

  def handle_info({:pending_validation, agent_pid, code_step}, state) do
    Logger.info("[AgentOrchestrator] Validation request from agent #{inspect(agent_pid)}")

    # Get agent name
    agent_name = get_agent_name(agent_pid, state)

    validation_request = %{
      agent_pid: agent_pid,
      agent_name: agent_name,
      code_step: code_step
    }

    # Call the validation handler with the request
    # The handler is responsible for calling AgentServer.continue(agent_pid, decision)
    Logger.info("[AgentOrchestrator] Calling validation handler for '#{agent_name}'")
    state.validation_handler.(validation_request)

    # Continue running - the handler has already called AgentServer.continue
    {:noreply, %{state | status: :running}}
  end

  def handle_info({:final_result, agent_pid, result, agent_state}, state) do
    Logger.info("[AgentOrchestrator] Final result from agent #{inspect(agent_pid)}")

    # Check if it's a sub-agent or main agent
    case Map.get(state.sub_agents, agent_pid) do
      nil ->
        # Main agent finished
        Logger.info("[AgentOrchestrator] Main agent completed, saving agent_state for next task")

        AgentServer.stop(agent_pid)
        new_state = %{
          state
          | status: :completed,
            result: result,
            agent_state: agent_state,
            main_agent_pid: nil
        }

        {:noreply, reply_task_caller(new_state, {:ok, result})}

      %{from: from} ->
        # Sub-agent finished, reply to the waiting GenServer.call
        Logger.info(
          "[AgentOrchestrator] Sub-agent completed, replying to #{inspect(from)}"
        )

        GenServer.reply(from, result)
        AgentServer.stop(agent_pid)

        # Remove from tracking
        new_sub_agents = Map.delete(state.sub_agents, agent_pid)
        {:noreply, %{state | sub_agents: new_sub_agents}}
    end
  end

  def handle_info({:error, agent_pid, reason}, state) do
    Logger.error("[AgentOrchestrator] Error from agent #{inspect(agent_pid)}: #{inspect(reason)}")

    # Check if it's a sub-agent or main agent
    case Map.get(state.sub_agents, agent_pid) do
      nil ->
        AgentServer.stop(agent_pid)
        new_state = %{state | status: :failed, error: reason, main_agent_pid: nil}
        {:noreply, reply_task_caller(new_state, {:error, reason})}

      %{from: from} ->
        # Sub-agent error, reply with error message
        error_msg = "Agent error: #{inspect(reason)}"
        GenServer.reply(from, error_msg)
        AgentServer.stop(agent_pid)
        new_sub_agents = Map.delete(state.sub_agents, agent_pid)
        {:noreply, %{state | sub_agents: new_sub_agents}}
    end
  end

  def handle_info({:rejected, agent_pid}, state) do
    Logger.info("[AgentOrchestrator] Execution rejected by agent #{inspect(agent_pid)}")

    AgentServer.stop(agent_pid)
    new_state = %{state | status: :rejected, main_agent_pid: nil}
    {:noreply, reply_task_caller(new_state, {:error, :rejected})}
  end

  def handle_info({:agent_progress, info}, state) do
    # Forward progress notifications to client
    send(state.client_pid, {:agent_progress, self(), info})
    {:noreply, state}
  end

  ## Private Functions

  defp start_main_agent(_task, %{status: status}) when status in [:running, :waiting_validation] do
    {:error, :busy}
  end

  defp start_main_agent(_task, %{task_from: task_from}) when not is_nil(task_from) do
    {:error, :busy}
  end

  defp start_main_agent(task, state) do
    case AgentSupervisor.start_agent(state.agent_config, self()) do
      {:ok, agent_pid} ->
        AgentServer.run(agent_pid, task, state.agent_state)

        {:ok,
         %{
           state
           | main_agent_pid: agent_pid,
             status: :running,
             result: nil,
             error: nil
         }}

      {:error, reason} ->
        Logger.error("[AgentOrchestrator] Failed to start agent: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Reply to a sync run_task caller, or notify the async client via messages.
  defp reply_task_caller(%{task_from: nil} = state, {:ok, result}) do
    send(state.client_pid, {:final_result, self(), result})
    state
  end

  defp reply_task_caller(%{task_from: nil} = state, {:error, :rejected}) do
    send(state.client_pid, {:rejected, self()})
    state
  end

  defp reply_task_caller(%{task_from: nil} = state, {:error, reason}) do
    send(state.client_pid, {:error, self(), reason})
    state
  end

  defp reply_task_caller(%{task_from: from} = state, reply) do
    GenServer.reply(from, reply)
    %{state | task_from: nil}
  end

  defp get_agent_name(agent_pid, state) do
    cond do
      agent_pid == state.main_agent_pid -> state.agent_config.name
      true -> :sub_agent
    end
  end
end
