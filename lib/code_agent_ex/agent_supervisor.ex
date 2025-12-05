defmodule CodeAgentEx.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for managing AgentServer processes.

  This supervisor allows dynamic creation and supervision of agent processes,
  providing fault tolerance and automatic restart capabilities.

  ## Usage

      # Start the supervisor (typically in application.ex)
      {:ok, sup_pid} = AgentSupervisor.start_link([])

      # Start a new agent under supervision
      {:ok, agent_pid} = AgentSupervisor.start_agent(agent_config, parent_pid)

      # Stop a specific agent
      AgentSupervisor.stop_agent(agent_pid)

      # List all running agents
      agents = AgentSupervisor.list_agents()
  """

  use DynamicSupervisor
  require Logger

  alias CodeAgentEx.AgentServer

  @doc """
  Starts the AgentSupervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a new AgentServer under supervision.

  ## Parameters
  - `agent_config` - Configuration for the agent (%AgentConfig{})
  - `parent_pid` - PID that will receive agent messages

  ## Returns
  - `{:ok, agent_pid}` - Success with the agent's PID
  - `{:error, reason}` - Failure reason
  """
  def start_agent(agent_config, parent_pid) do
    Logger.info("[AgentSupervisor] Starting supervised agent '#{agent_config.name}'")

    # Child spec for DynamicSupervisor
    spec = %{
      id: AgentServer,
      start: {AgentServer, :start_link, [agent_config, parent_pid]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} = success ->
        Logger.info(
          "[AgentSupervisor] Agent '#{agent_config.name}' started with PID #{inspect(pid)}"
        )

        success

      {:error, reason} = error ->
        Logger.error(
          "[AgentSupervisor] Failed to start agent '#{agent_config.name}': #{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Stops a supervised agent.

  ## Parameters
  - `agent_pid` - PID of the agent to stop

  ## Returns
  - `:ok` - Successfully stopped
  - `{:error, :not_found}` - Agent not found
  """
  def stop_agent(agent_pid) when is_pid(agent_pid) do
    Logger.info("[AgentSupervisor] Stopping agent #{inspect(agent_pid)}")

    case DynamicSupervisor.terminate_child(__MODULE__, agent_pid) do
      :ok ->
        Logger.info("[AgentSupervisor] Agent #{inspect(agent_pid)} stopped")
        :ok

      {:error, :not_found} = error ->
        Logger.warning("[AgentSupervisor] Agent #{inspect(agent_pid)} not found")
        error
    end
  end

  @doc """
  Lists all currently running agents under this supervisor.

  ## Returns
  List of `{:undefined, agent_pid, :worker, [AgentServer]}` tuples
  """
  def list_agents do
    DynamicSupervisor.which_children(__MODULE__)
  end

  @doc """
  Counts the number of running agents.

  ## Returns
  Integer count of active agents
  """
  def count_agents do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @impl true
  def init(_init_arg) do
    Logger.info("[AgentSupervisor] Initializing DynamicSupervisor")

    # Strategy :one_for_one means if one agent crashes, only that agent is restarted
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
