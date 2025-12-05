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

      # Start orchestrator with agent config and task
      {:ok, orchestrator_pid} = AgentOrchestrator.start_link(agent_config, task)

      # Wait for messages
      receive do
        {:validation_request, orchestrator_pid, agent_info, thought, code} ->
          # Show to user, get decision
          AgentOrchestrator.submit_decision(orchestrator_pid, :approve)

        {:final_result, orchestrator_pid, result} ->
          IO.puts("Result: \#{result}")
      end
  """

  use GenServer
  require Logger

  alias CodeAgentEx.{AgentSupervisor, AgentServer}

  defstruct [
    # PID of the client who started the orchestrator
    :client_pid,
    # Configuration of the main agent
    :agent_config,
    # PID of the main agent (if running)
    :main_agent_pid,
    # Current status: :idle | :running | :waiting_validation | :completed | :failed
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
    # Caller waiting for sync result (for run_task)
    :sync_caller,
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
    - `:thought` - Agent's reasoning
    - `:code` - Code to execute

    The function should call `AgentServer.continue(agent_pid, decision)` with one of:
    - `:approve` - Execute the code as-is
    - `{:modify, new_code}` - Execute modified code
    - `{:feedback, message}` - Send feedback without executing
    - `:reject` - Reject and stop

  ## Example

      # Default: auto-approve
      {:ok, orch} = AgentOrchestrator.start_link(config)

      # Custom validation handler
      handler = fn %{agent_pid: pid, code: code} = req ->
        IO.puts("Validating: \#{code}")
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
  Runs a task synchronously and returns the result.

  This is a blocking call that waits for the task to complete.
  The orchestrator maintains agent state between calls, enabling
  multi-turn conversations with context.

  ## Example

      {:ok, orch} = AgentOrchestrator.start_link(config)
      {:ok, result1} = AgentOrchestrator.run_task(orch, "Calculate 5 + 3")
      {:ok, result2} = AgentOrchestrator.run_task(orch, "Multiply that by 2")
      # Agent remembers "8" from first task!

  Returns `{:ok, result}` or `{:error, reason}`.
  """
  def run_task(orchestrator_pid, task, timeout \\ :infinity) do
    GenServer.call(orchestrator_pid, {:run_task, task}, timeout)
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

  ## Handle messages from agents

  @impl true
  def handle_info({:agent_started, agent_pid, agent_name}, state) do
    Logger.info("[AgentOrchestrator] Agent '#{agent_name}' started (#{inspect(agent_pid)})")
    {:noreply, state}
  end

  @impl true
  def handle_info({:pending_validation, agent_pid, thought, code}, state) do
    Logger.info("[AgentOrchestrator] Validation request from agent #{inspect(agent_pid)}")

    # Get agent name
    agent_name = get_agent_name(agent_pid, state)

    validation_request = %{
      agent_pid: agent_pid,
      agent_name: agent_name,
      thought: thought,
      code: code
    }

    # Call the validation handler with the request
    # The handler is responsible for calling AgentServer.continue(agent_pid, decision)
    Logger.info("[AgentOrchestrator] Calling validation handler for '#{agent_name}'")
    state.validation_handler.(validation_request)

    # Continue running - the handler has already called AgentServer.continue
    {:noreply, %{state | status: :running}}
  end

  @impl true
  def handle_info({:final_result, agent_pid, result, agent_state}, state) do
    Logger.info("[AgentOrchestrator] Final result from agent #{inspect(agent_pid)}")

    # Check if it's a sub-agent or main agent
    case Map.get(state.sub_agents, agent_pid) do
      nil ->
        # Main agent finished
        Logger.info("[AgentOrchestrator] Main agent completed, saving agent_state for next task")

        # If there's a sync caller (run_task), reply to them
        if state.sync_caller do
          GenServer.reply(state.sync_caller, {:ok, result})
        else
          # Otherwise send to client (old async API)
          send(state.client_pid, {:final_result, self(), result})
        end

        AgentServer.stop(agent_pid)
        {:noreply, %{state | status: :completed, result: result, agent_state: agent_state, sync_caller: nil}}

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

  @impl true
  def handle_info({:error, agent_pid, reason}, state) do
    Logger.error("[AgentOrchestrator] Error from agent #{inspect(agent_pid)}: #{inspect(reason)}")

    # Check if it's a sub-agent or main agent
    case Map.get(state.sub_agents, agent_pid) do
      nil ->
        # Main agent error
        if state.sync_caller do
          GenServer.reply(state.sync_caller, {:error, reason})
        else
          send(state.client_pid, {:error, self(), reason})
        end

        AgentServer.stop(agent_pid)
        {:noreply, %{state | status: :failed, error: reason, sync_caller: nil}}

      %{from: from} ->
        # Sub-agent error, reply with error message
        error_msg = "Agent error: #{inspect(reason)}"
        GenServer.reply(from, error_msg)
        AgentServer.stop(agent_pid)
        new_sub_agents = Map.delete(state.sub_agents, agent_pid)
        {:noreply, %{state | sub_agents: new_sub_agents}}
    end
  end

  @impl true
  def handle_info({:rejected, agent_pid}, state) do
    Logger.info("[AgentOrchestrator] Execution rejected by agent #{inspect(agent_pid)}")

    # Reply to caller
    if state.sync_caller do
      GenServer.reply(state.sync_caller, {:error, "Execution rejected"})
    else
      send(state.client_pid, {:rejected, self()})
    end

    # Stop the agent
    AgentServer.stop(agent_pid)

    {:noreply, %{state | status: :rejected, sync_caller: nil}}
  end

  @impl true
  def handle_info({:agent_progress, info}, state) do
    # Forward progress notifications to client
    send(state.client_pid, {:agent_progress, self(), info})
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status_info = %{
      status: state.status,
      has_current_validation: state.current_validation != nil,
      result: state.result,
      error: state.error
    }

    {:reply, status_info, state}
  end

  @impl true
  def handle_call({:run_task, task}, from, state) do
    Logger.info("[AgentOrchestrator] Running task: #{String.slice(task, 0, 50)}...")

    # Start the main agent under supervision
    case AgentSupervisor.start_agent(state.agent_config, self()) do
      {:ok, agent_pid} ->
        # Run the task with previous agent_state for context preservation
        AgentServer.run(agent_pid, task, state.agent_state)

        # Store the caller to reply later when task completes
        {:noreply, %{state | main_agent_pid: agent_pid, status: :running, sync_caller: from}}

      {:error, reason} ->
        Logger.error("[AgentOrchestrator] Failed to start agent: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
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

  ## Private Functions

  defp get_agent_name(agent_pid, state) do
    cond do
      agent_pid == state.main_agent_pid -> state.agent_config.name
      true -> :sub_agent
    end
  end
end
