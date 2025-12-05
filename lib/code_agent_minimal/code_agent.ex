defmodule CodeAgentMinimal.CodeAgent do
  @moduledoc """
  Agent qui génère et exécute du code Elixir pour accomplir des tâches.

  Inspiré de smolagents CodeAgent - le LLM génère du code Elixir qui est
  évalué avec persistance des variables entre les steps.

  ## Exemple

      config = CodeAgentMinimal.AgentConfig.new(
        tools: [CodeAgentMinimal.Tool.final_answer()],
        model: "meta-llama/Llama-4-Scout-17B-16E-Instruct"
      )

      {:ok, result, _state} = CodeAgentMinimal.CodeAgent.run(
        "Calculate 25 * 4 and add 10",
        config
      )
      # => "110"

  ## Architecture

  - Boucle ReAct: Think → Code → Execute → Observe → Repeat
  - Les variables Elixir persistent entre les steps
  - Les tools sont des fonctions disponibles dans le binding
  - `final_answer/1` termine l'exécution
  """

  alias CodeAgentMinimal.{Executor, Memory, Prompts, Tool, AgentConfig, AgentOrchestrator}
  alias CodeAgentMinimal.OpenaiChat
  require Logger

  defstruct [
    # %AgentConfig{} - Configuration de l'agent
    :config,
    # Tâche en cours
    :task,
    # Tools dérivés des managed_agents
    :agent_tools,
    # Historique d'exécution
    :memory,
    # Variables Elixir en cours
    :binding,
    # Étape actuelle
    :current_step,
    # Résultat final
    :final_result
  ]

  @doc """
  Exécute une tâche en générant et exécutant du code Elixir.

  IMPORTANT: Cette fonction est maintenant un wrapper qui utilise toujours
  un AgentOrchestrator en arrière-plan pour gérer la validation.

  ## Arguments

  - `task` - La tâche à accomplir (string)
  - `config` - Configuration de l'agent (%AgentConfig{})
  - `opts` - Options (keyword list)
    - `:validation_handler` - Custom validation handler function (optional)

  ## Exemple

      config = AgentConfig.new(
        name: :my_agent,
        instructions: "You are a helpful assistant",
        tools: [Tool.final_answer()],
        max_steps: 10
      )

      # Default: auto-approve all validations
      {:ok, result} = CodeAgent.run("Calculate 10 + 5", config)

      # Custom validation handler
      handler = fn %{code: code, agent_pid: pid} ->
        IO.puts("Validating: \#{code}")
        AgentServer.continue(pid, :approve)
      end
      {:ok, result} = CodeAgent.run("Calculate 10 + 5", config, validation_handler: handler)

  ## Validation

  Auto-approves all validations by default. For custom validation logic,
  pass a `:validation_handler` function or use `AgentOrchestrator.start_link/2`
  directly for more control.
  """
  def run(task, %AgentConfig{} = config, opts \\ []) do
    # Utiliser l'orchestrator pour toutes les exécutions
    run_with_orchestrator(task, config, opts)
  end

  # Internal version that always uses orchestrator
  defp run_with_orchestrator(task, config, opts) do
    # Get validation_handler from opts (defaults to auto-approve in orchestrator)
    orchestrator_opts = Keyword.take(opts, [:validation_handler])

    # Start orchestrator with validation_handler option (no task required)
    {:ok, orch_pid} = AgentOrchestrator.start_link(config, orchestrator_opts)

    # Run task synchronously using GenServer.call
    result = AgentOrchestrator.run_task(orch_pid, task)

    # Stop orchestrator
    AgentOrchestrator.stop(orch_pid)

    result
  end

  def run_direct(task, %AgentConfig{} = config, previous_state \\ nil) do
    # Créer ou réutiliser le state
    state =
      if previous_state do
        # Continuer avec l'état précédent (mémoire préservée)
        Logger.info(
          "🔄 [CodeAgent] Continuing from previous state (#{Memory.count(previous_state.memory)} steps)"
        )

        %{
          previous_state
          | task: task,
            current_step: 0,
            final_result: nil
        }
      else
        # Nouveau state
        tools = ensure_final_answer(config.tools)
        agent_tools = AgentConfig.to_tools(config.managed_agents, config.listener_pid)

        Logger.info(
          "🤖 [CodeAgent] Starting '#{config.name}' with #{length(tools)} tools + #{length(agent_tools)} agents"
        )

        # Créer le binding avec tools.* et agents.*
        binding = create_combined_binding(tools, agent_tools)

        %__MODULE__{
          config: config,
          task: task,
          agent_tools: agent_tools,
          memory: Memory.new(),
          binding: binding,
          current_step: 0,
          final_result: nil
        }
      end

    Logger.info("📝 [CodeAgent] Task: #{String.slice(task, 0, 100)}...")

    execute_loop(state)
  end

  # Boucle principale ReAct
  defp execute_loop(%{final_result: result} = state) when not is_nil(result) do
    Logger.info("✅ [CodeAgent] Completed in #{state.current_step} steps")
    {:ok, result, state}
  end

  defp execute_loop(%{current_step: step, max_steps: max} = state) when step >= max do
    Logger.warning("⏰ [CodeAgent] Max steps reached (#{max})")
    # Forcer une réponse finale
    force_final_answer(state)
  end

  defp execute_loop(state) do
    step = state.current_step + 1
    Logger.info("🔄 [CodeAgent] Step #{step}/#{state.config.max_steps}")

    # Construire les messages pour le LLM
    messages = build_messages(state)

    # Détecter si c'est la dernière étape (pour appliquer response_format custom)
    is_final_step = step >= state.config.max_steps

    # Définir le response_format approprié
    llm_opts =
      cond do
        # Dernière étape avec response_format custom
        is_final_step && state.config.response_format ->
          Keyword.put(state.config.llm_opts, :response_format, state.config.response_format)

        # Étapes intermédiaires : forcer JSON pour code generation
        not is_final_step ->
          code_response_format = %{
            type: "json_object",
            schema: %{
              type: "object",
              properties: %{
                thought: %{type: "string", description: "Your reasoning about what to do next"},
                code: %{type: "string", description: "The Elixir code to execute"}
              },
              required: ["thought", "code"]
            }
          }

          Keyword.put(state.config.llm_opts, :response_format, code_response_format)

        # Pas de response_format
        true ->
          state.config.llm_opts
      end

    # Appeler le LLM
    case call_llm(state.config.model, messages, llm_opts, state.config.backend) do
      {:ok, response} ->
        # Parser la réponse pour extraire le code
        case parse_response(response) do
          {:code, thought, code} ->
            Logger.info("💭 [CodeAgent] Thought: #{String.slice(thought, 0, 100)}...")
            Logger.debug("📝 [CodeAgent] Code:\n#{code}")

            # Always send validation request to orchestrator
            # Orchestrator decides whether to auto-approve or ask user
            {:pending_validation, thought, code, %{state | current_step: step}}

          {:final_text, answer} ->
            # Le LLM a répondu directement sans code
            Logger.info("📋 [CodeAgent] Direct text response")
            {:ok, answer, state}

          {:error, parse_error} ->
            Logger.error("❌ [CodeAgent] Parse error: #{parse_error}")

            step_record = %{
              step: step,
              error: "Failed to parse response: #{parse_error}"
            }

            new_state = %{
              state
              | memory: Memory.add_step(state.memory, step_record),
                current_step: step
            }

            execute_loop(new_state)
        end

      {:error, llm_error} ->
        Logger.error("❌ [CodeAgent] LLM error: #{inspect(llm_error)}")
        {:error, llm_error, state}
    end
  end

  # Execute code and continue the loop
  defp execute_code(code, thought, step, state) do
    # Execute in sandbox mode
    exec_result = Executor.execute_sandboxed(code, state.binding)

    # Process the execution result
    process_execution_result(exec_result, code, thought, step, state)
  end

  # Process the execution result (extracted for clarity)
  defp process_execution_result(exec_result, code, thought, step, state) do
    case exec_result do
      {:ok, result, new_binding} ->
        Logger.info("✅ [CodeAgent] Code executed successfully")

        # Vérifier si c'est une réponse finale
        case check_final_answer(result, new_binding) do
          {:final, answer} ->
            step_record = %{
              step: step,
              thought: thought,
              code: code,
              result: result
            }

            new_state = %{
              state
              | memory: Memory.add_step(state.memory, step_record),
                binding: new_binding,
                current_step: step,
                final_result: answer
            }

            execute_loop(new_state)

          :continue ->
            step_record = %{
              step: step,
              thought: thought,
              code: code,
              result: result
            }

            new_state = %{
              state
              | memory: Memory.add_step(state.memory, step_record),
                binding: new_binding,
                current_step: step
            }

            execute_loop(new_state)
        end

      {:error, error} ->
        Logger.error("❌ [CodeAgent] Execution error: #{inspect(error)}")

        step_record = %{
          step: step,
          thought: thought,
          code: code,
          error: inspect(error)
        }

        new_state = %{
          state
          | memory: Memory.add_step(state.memory, step_record),
            current_step: step
        }

        execute_loop(new_state)
    end
  end

  @doc """
  Continue execution after user validation.

  ## Décisions possibles

  - `:approve` - Exécuter le code tel quel
  - `{:modify, new_code}` - Exécuter le code modifié
  - `{:feedback, message}` - Renvoyer au LLM avec feedback
  - `:reject` - Arrêter l'exécution
  """
  def continue_validation(decision, {thought, code, state}) do
    step = state.current_step

    # Gestion de la décision de validation
    case decision do
      :approve ->
        execute_code(code, thought, step, state)

      {:modify, new_code} ->
        Logger.info("📝 [CodeAgent] Code modified by user")
        execute_code(new_code, thought, step, state)

      {:feedback, message} ->
        Logger.info("💬 [CodeAgent] User feedback: #{String.slice(message, 0, 50)}...")

        # Ajouter le feedback comme erreur pour que le LLM réessaie
        step_record = %{
          step: step,
          thought: thought,
          code: code,
          error: "User feedback: #{message}"
        }

        new_state = %{
          state
          | memory: Memory.add_step(state.memory, step_record)
        }

        execute_loop(new_state)

      :reject ->
        Logger.info("🛑 [CodeAgent] Execution rejected by user")
        {:rejected, state}
    end
  end

  # Construit les messages pour le LLM
  defp build_messages(state) do
    tools = ensure_final_answer(state.config.tools)
    system_prompt = Prompts.system_prompt(tools, state.agent_tools, state.config.instructions)
    task_prompt = Prompts.task_prompt(state.task)
    memory_messages = Memory.to_messages(state.memory)

    [
      %{role: "system", content: system_prompt},
      %{role: "user", content: task_prompt}
    ] ++ memory_messages
  end

  # Appelle le LLM
  defp call_llm(model, messages, llm_opts, _backend) do
    # Utiliser OpenaiChat (compatible OpenAI, HuggingFace, etc.)
    case OpenaiChat.chat_completion(model, messages, llm_opts) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        {:ok, content}

      {:ok, %{content: content}} ->
        {:ok, content}

      {:error, _} = error ->
        error
    end
  end

  # Parse la réponse du LLM pour extraire le code
  defp parse_response(response) do
    case Jason.decode(response) do
      {:ok, %{"thought" => thought, "code" => code}} ->
        {:code, thought, code}

      {:ok, json_response} ->
        # JSON valide mais pas le format attendu pour le code
        # Peut-être une réponse finale en JSON (dernière étape)
        {:final_text, Jason.encode!(json_response)}

      {:error, parse_error} ->
        {:error,
         "Failed to parse JSON response: #{inspect(parse_error)}\nResponse: #{String.slice(response, 0, 200)}"}
    end
  end

  defp check_final_answer(_result, binding) do
    # Vérifier si __final_answer__ est dans le binding
    case Map.get(binding, :__final_answer__) do
      nil -> :continue
      answer -> {:final, answer}
    end
  end

  # Force une réponse finale quand max_steps atteint
  defp force_final_answer(state) do
    # Construire un message demandant explicitement une réponse finale
    messages =
      build_messages(state) ++
        [
          %{
            role: "user",
            content:
              "You have reached the maximum number of steps. Please provide your final answer now using tools.final_answer()."
          }
        ]

    case call_llm(state.config.model, messages, state.config.llm_opts, state.config.backend) do
      {:ok, response} ->
        case parse_response(response) do
          {:code, _thought, code} ->
            case Executor.execute_sandboxed(code, state.binding) do
              {:ok, _result, new_binding} ->
                case Map.get(new_binding, :__final_answer__) do
                  nil -> {:error, "Agent did not provide final answer", state}
                  answer -> {:ok, answer, %{state | binding: new_binding}}
                end

              {:error, error} ->
                {:error, "Failed to execute final answer: #{inspect(error)}", state}
            end

          {:final_text, answer} ->
            {:ok, answer, state}

          {:error, _} ->
            {:error, "Agent did not provide final answer", state}
        end

      {:error, error} ->
        {:error, error, state}
    end
  end

  # Ensure final_answer is in the tools
  defp ensure_final_answer(tools) do
    has_final = Enum.any?(tools, fn tool -> tool.name == :final_answer end)

    if has_final do
      tools
    else
      tools ++ [Tool.final_answer()]
    end
  end

  # Create combined binding with tools.* and agents.*
  defp create_combined_binding(tools, agent_tools) do
    tools_map = Tool.create_binding(tools) |> Enum.into(%{})
    agents_map = Tool.create_binding(agent_tools) |> Enum.into(%{})

    %{
      tools: tools_map,
      agents: agents_map
    }
  end
end
