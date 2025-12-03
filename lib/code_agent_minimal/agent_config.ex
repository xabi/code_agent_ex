defmodule CodeAgentMinimal.AgentConfig do
  @moduledoc """
  Configuration pour créer des agents qui peuvent être utilisés comme managed agents.

  Un AgentConfig définit la configuration d'un agent : nom, description, outils,
  sous-agents, etc. Cette configuration peut ensuite être utilisée comme managed agent
  dans un CodeAgent principal.

  ## Exemple simple

      # Créer une configuration d'agent web spécialisé
      web_agent = AgentConfig.new(
        name: "web_researcher",
        instructions: "You are a specialized web research agent. Search for accurate information using Wikipedia tools.",
        tools: [WikipediaTools.all_tools()]
      )

      # L'utiliser comme managed agent dans un agent principal
      CodeAgent.run(task,
        tools: [Tool.final_answer()],
        managed_agents: [web_agent]
      )

      # L'agent principal peut alors appeler:
      # result = agents.web_researcher.("recherche les dernières news sur Elixir")

  ## Agents imbriqués (nested agents)

  Un AgentConfig peut lui-même avoir des managed_agents, créant une hiérarchie:

      # Niveau 2: Configuration agent Python
      python_agent = AgentConfig.new(
        name: :python_executor,
        instructions: "You are a Python code executor. Execute Python code safely and return results.",
        tools: [PythonTools.python_interpreter()],
        max_steps: 3
      )

      # Niveau 1: Configuration agent math qui utilise Python
      math_agent = AgentConfig.new(
        name: :math_specialist,
        instructions: "You are a mathematical specialist. Solve complex math problems. You can delegate to Python for calculations.",
        tools: [Tool.final_answer()],
        managed_agents: [python_agent],  # ← Nested agent config
        max_steps: 5
      )

      # Agent principal
      CodeAgent.run(
        "Calculate factorial of 10 using math_specialist",
        managed_agents: [math_agent],
        max_steps: 6
      )

  Dans cet exemple, l'agent principal peut appeler math_specialist, qui peut
  lui-même appeler python_executor pour des calculs complexes.
  """

  alias CodeAgentMinimal.CodeAgent

  # Qwen/Qwen3-30B-A3B-Thinking-2507 (invente des données au lieu d'utiliser les tools)
  # meta-llama/Llama-4-Scout-17B-16E-Instruct (plus disponible)
  # meta-llama/Llama-4-Maverick-17B-128E-Instruct (plus disponible)
  # mistralai/Mixtral-8x22B-Instruct-v0.1 (plus disponible)
  # openai/gpt-oss-20b (utilise tool calling natif malgré tool_choice: none)
  # meta-llama/Llama-3.3-70B-Instruct (bon mais parfois n'utilise pas les tools)
  @default_model "Qwen/Qwen3-Coder-30B-A3B-Instruct"

  @default_max_steps 10
  # Désactiver tool calling natif
  @default_llm_opts [tool_choice: "none", temperature: 0.7, max_tokens: 4000]

  defstruct [
    :instructions,
    :response_format,
    name: :agent,
    tools: [],
    managed_agents: [],
    listener_pid: nil,
    llm_opts: @default_llm_opts,
    require_validation: false,
    backend: :hf,
    model: @default_model,
    max_steps: @default_max_steps
  ]

  @doc """
  Crée une nouvelle configuration d'agent.

  ## Options

  - `:name` - Nom de l'agent (défaut: :agent)
  - `:instructions` - Instructions décrivant le rôle et comportement de l'agent (optionnel)
  - `:tools` - Liste des tools disponibles pour cet agent (défaut: [])
  - `:managed_agents` - Liste des sous-agents que cet agent peut utiliser (défaut: [])
  - `:model` - Modèle LLM à utiliser (optionnel)
  - `:max_steps` - Nombre max d'itérations (optionnel)
  - `:listener_pid` - PID pour les notifications de progression (optionnel)
  - `:llm_opts` - Options additionnelles pour l'API LLM (défaut: [])
  - `:require_validation` - Requiert validation utilisateur (défaut: false)
  - `:backend` - Backend LLM à utiliser: :hf ou :mistral (défaut: :hf)
  - `:response_format` - Format de réponse structuré pour le LLM (optionnel)
    Peut être une map avec `type: "json_object"` et optionnellement `schema: {...}`
    Exemple: `%{type: "json_object", schema: %{type: "object", properties: %{...}}}`
  """
  def new(opts \\ []) do
    struct!(__MODULE__, opts)
  end

  @doc """
  Convertit une configuration d'agent en tool appelable.

  Le tool créé prend une `task` en paramètre et lance le sous-agent.
  Accepte un `listener_pid` optionnel pour la progression.
  """
  def to_tool(%__MODULE__{} = agent_config, listener_pid \\ nil) do
    %CodeAgentMinimal.Tool{
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
  Convertit une liste de configurations d'agents en tools.
  Accepte un `listener_pid` optionnel pour la progression.
  """
  def to_tools(agent_configs, listener_pid \\ nil) do
    Enum.map(agent_configs, &to_tool(&1, listener_pid))
  end

  # Crée la fonction qui sera appelée quand le tool est invoqué
  defp create_agent_function(%__MODULE__{} = agent_config, listener_pid) do
    fn task ->
      task = normalize_arg(task)

      # Notifier le début de l'exécution du sous-agent
      if listener_pid do
        send(
          listener_pid,
          {:agent_progress,
           %{
             type: :sub_agent_start,
             agent_name: agent_config.name,
             task: task
           }}
        )
      end

      # Exécuter le sous-agent directement (pas de validation des sous-agents)
      result =
        case CodeAgent.run(task, agent_config) do
          {:ok, result, _state} ->
            wrap_result(agent_config.name, result)

          {:error, reason, _state} ->
            "Agent '#{agent_config.name}' error: #{inspect(reason)}"
        end

      # Notifier la fin de l'exécution du sous-agent
      if listener_pid do
        send(
          listener_pid,
          {:agent_progress,
           %{
             type: :sub_agent_end,
             agent_name: agent_config.name
           }}
        )
      end

      result
    end
  end

  # Wrap le résultat pour le parent agent
  defp wrap_result(agent_name, result) do
    """
    === Report from agent '#{agent_name}' ===

    #{result}

    === End of report ===
    """
  end

  # Normalise les charlists en binaries
  defp normalize_arg(arg) when is_list(arg), do: List.to_string(arg)
  defp normalize_arg(arg), do: arg
end
