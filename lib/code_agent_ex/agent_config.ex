defmodule CodeAgentEx.AgentConfig do
  @moduledoc """
  Configuration for creating agents that can be used as managed agents.

  An AgentConfig defines agent configuration: name, description, tools,
  sub-agents, etc. This configuration can then be used as a managed agent
  in a main CodeAgent.

  ## Simple Example

      # Create a specialized web research agent configuration
      web_agent = AgentConfig.new(
        name: "web_researcher",
        instructions: "You are a specialized web research agent. Search for accurate information using Wikipedia tools.",
        tools: [WikipediaTools.all_tools()]
      )

      # Use it as a managed agent in a main agent
      CodeAgent.run(task,
        tools: [Tool.final_answer()],
        managed_agents: [web_agent]
      )

      # The main agent can then call:
      # result = agents.web_researcher.("search for latest Elixir news")

  ## Nested Agents

  An AgentConfig can itself have managed_agents, creating a hierarchy:

      # Level 2: Python agent configuration
      python_agent = AgentConfig.new(
        name: :python_executor,
        instructions: "You are a Python code executor. Execute Python code safely and return results.",
        tools: [PythonTools.python_interpreter()],
        max_steps: 3
      )

      # Level 1: Math agent configuration that uses Python
      math_agent = AgentConfig.new(
        name: :math_specialist,
        instructions: "You are a mathematical specialist. Solve complex math problems. You can delegate to Python for calculations.",
        tools: [Tool.final_answer()],
        managed_agents: [python_agent],  # ← Nested agent config
        max_steps: 5
      )

      # Main agent
      CodeAgent.run(
        "Calculate factorial of 10 using math_specialist",
        managed_agents: [math_agent],
        max_steps: 6
      )

  In this example, the main agent can call math_specialist, which can
  itself call python_executor for complex calculations.
  """

  alias CodeAgentEx.{AgentSupervisor, AgentServer, AgentOrchestrator}

  @default_model "Qwen/Qwen3-Coder-30B-A3B-Instruct"

  @default_max_steps 10
  # Désactiver tool calling natif
  @default_llm_opts [tool_choice: "none", temperature: 0.7, max_tokens: 4000]
  @default_adapter InstructorLite.Adapters.ChatCompletionsCompatible

  defstruct [
    :instructions,
    :response_schema,
    name: :agent,
    tools: [],
    managed_agents: [],
    listener_pid: nil,
    llm_opts: @default_llm_opts,
    adapter: @default_adapter,
    model: @default_model,
    max_steps: @default_max_steps
  ]

  @doc """
  Creates a new agent configuration.

  ## Options

  - `:name` - Agent name (default: :agent)
  - `:instructions` - Instructions describing the agent's role and behavior (optional)
  - `:tools` - List of tools available for this agent (default: [])
  - `:managed_agents` - List of sub-agents this agent can use (default: [])
  - `:model` - LLM model to use (optional)
  - `:max_steps` - Maximum number of iterations (optional)
  - `:listener_pid` - Orchestrator PID (required for managed agents, automatically provided)
  - `:llm_opts` - Additional options for the LLM API (default: [])
  - `:adapter` - InstructorLite adapter module (default: InstructorLite.Adapters.ChatCompletionsCompatible)
  - `:response_schema` - Ecto schema module for structured LLM response (optional)
    When provided, this schema will be used for the final step instead of the default CodeStep.
    Example: `MyApp.CustomResponseSchema` (must use InstructorLite.Instruction)
  """
  def new(opts \\ []) do
    struct!(__MODULE__, opts)
  end

  @doc """
  Converts an agent configuration into a callable tool.

  The created tool takes a `task` parameter and launches the sub-agent.
  Accepts an orchestrator `listener_pid` (required).
  """
  def to_tool(%__MODULE__{} = agent_config, listener_pid \\ nil) do
    %CodeAgentEx.Tool{
      name: agent_config.name,
      description: "#{agent_config.instructions}. Call with: agents.#{agent_config.name}.(task)",
      inputs: %{
        "task" => %{
          type: "string",
          description: "Detailed description of the task for this agent to accomplish"
        }
      },
      output_type: "string",
      function: create_agent_function(agent_config, listener_pid)
    }
  end

  @doc """
  Converts a list of agent configurations into tools.
  Accepts an orchestrator `listener_pid` (required).
  """
  def to_tools(agent_configs, listener_pid \\ nil) do
    Enum.map(agent_configs, &to_tool(&1, listener_pid))
  end

  # Creates the function that will be called when the tool is invoked
  # Now uses GenServer-based architecture for async communication
  defp create_agent_function(%__MODULE__{} = agent_config, listener_pid) do
    fn task ->
      task = normalize_arg(task)

      # Start the agent as a supervised GenServer
      # IMPORTANT: listener_pid is ALWAYS the orchestrator now
      orchestrator_pid = listener_pid

      case AgentSupervisor.start_agent(agent_config, orchestrator_pid) do
        {:ok, agent_pid} ->
          # Run the task asynchronously
          AgentServer.run(agent_pid, task)

          # Wait for orchestrator to send us the final result
          wait_for_orchestrator_result(agent_pid, agent_config.name, orchestrator_pid)

        {:error, reason} ->
          "Agent '#{agent_config.name}' failed to start: #{inspect(reason)}"
      end
    end
  end

  # Waits for sub-agent result from orchestrator using GenServer.call
  defp wait_for_orchestrator_result(agent_pid, agent_name, orchestrator_pid) do
    # Use GenServer.call to register and wait for sub-agent result
    # This is cleaner than send/receive as it handles timeouts and errors automatically
    AgentOrchestrator.track_sub_agent(orchestrator_pid, agent_pid, agent_name)
  end

  # Normalize charlists to binaries
  defp normalize_arg(arg) when is_list(arg), do: List.to_string(arg)
  defp normalize_arg(arg), do: arg
end
