defmodule CodeAgentEx.CodeAgent do
  @moduledoc """
  Agent that generates and executes Elixir code to accomplish tasks.

  Inspired by smolagents CodeAgent - the LLM generates Elixir code which is
  evaluated with variable persistence between steps.

  ## Example

      config = CodeAgentEx.AgentConfig.new(
        tools: [CodeAgentEx.Tool.final_answer()],
        model: "meta-llama/Llama-4-Scout-17B-16E-Instruct"
      )

      {:ok, result, _state} = CodeAgentEx.CodeAgent.run(
        "Calculate 25 * 4 and add 10",
        config
      )
      # => "110"

  ## Architecture

  - ReAct Loop: Think → Code → Execute → Observe → Repeat
  - Elixir variables persist between steps
  - Tools are functions available in the binding
  - `final_answer/1` terminates execution
  """

  alias CodeAgentEx.{Executor, Memory, Prompts, Tool, AgentConfig, AgentOrchestrator}
  alias CodeAgentEx.LLM.{Client, Schemas}
  require Logger

  defstruct [
    # %AgentConfig{} - Agent configuration
    :config,
    # Current task
    :task,
    # Tools derived from managed_agents
    :agent_tools,
    # Execution history
    :memory,
    # Current Elixir variables
    :binding,
    # Current step
    :current_step,
    # Final result
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
    # Use orchestrator for all executions
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
    # Create or reuse state
    state =
      if previous_state do
        # Continue with previous state (memory preserved)
        Logger.info(
          "🔄 [CodeAgent] Continuing from previous state (#{Memory.count(previous_state.memory)} steps)"
        )

        # Clean up __final_answer__ from previous task's binding
        cleaned_binding = Map.delete(previous_state.binding, :__final_answer__)

        %{
          previous_state
          | task: task,
            current_step: 0,
            final_result: nil,
            binding: cleaned_binding
        }
      else
        # New state
        tools = ensure_final_answer(config.tools)
        agent_tools = AgentConfig.to_tools(config.managed_agents, config.listener_pid)

        Logger.info(
          "🤖 [CodeAgent] Starting '#{config.name}' with #{length(tools)} tools + #{length(agent_tools)} agents"
        )

        # Create binding with tools.* and agents.*
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

  defp execute_loop(%{current_step: step, config: %{max_steps: max}} = state) when step >= max do
    Logger.warning("⏰ [CodeAgent] Max steps reached (#{max})")
    # Force a final answer
    force_final_answer(state)
  end

  defp execute_loop(state) do
    step = state.current_step + 1
    Logger.info("🔄 [CodeAgent] Step #{step}/#{state.config.max_steps}")

    # Construire les messages pour le LLM
    messages = build_messages(state)

    # Detect if this is the final step (to apply custom response_schema)
    is_final_step = step >= state.config.max_steps

    # Define appropriate response_schema
    response_schema =
      cond do
        # Final step with custom response_schema
        is_final_step && state.config.response_schema ->
          state.config.response_schema

        # Intermediate steps: schema for code generation
        true ->
          Schemas.CodeStep
      end

    # Call LLM with appropriate schema
    # Merge adapter into llm_opts
    llm_opts = Keyword.put(state.config.llm_opts, :adapter, state.config.adapter)
    case call_llm(state.config.model, messages, response_schema, llm_opts) do
      {:ok, %Schemas.CodeStep{thought: thought, code: code}} ->
        Logger.info("💭 [CodeAgent] Thought: #{String.slice(thought, 0, 100)}...")
        Logger.debug("📝 [CodeAgent] Code:\n#{code}")

        # Always send validation request to orchestrator
        # Orchestrator decides whether to auto-approve or ask user
        {:pending_validation, thought, code, %{state | current_step: step}}

      {:ok, custom_response} ->
        # Custom schema response (final step with custom schema)
        Logger.info("📋 [CodeAgent] Custom schema response")
        # Convert struct to JSON string for compatibility
        response_json = Jason.encode!(Map.from_struct(custom_response))
        {:ok, response_json, state}

      {:error, llm_error} ->
        Logger.error("❌ [CodeAgent] LLM error: #{inspect(llm_error)}")

        step_record = %{
          step: step,
          error: "LLM call failed: #{inspect(llm_error)}"
        }

        new_state = %{
          state
          | memory: Memory.add_step(state.memory, step_record),
            current_step: step
        }

        execute_loop(new_state)
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

        # Check if this is a final answer
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

  ## Possible decisions

  - `:approve` - Execute code as-is
  - `{:modify, new_code}` - Execute modified code
  - `{:feedback, message}` - Send back to LLM with feedback
  - `:reject` - Stop execution
  """
  def continue_validation(decision, {thought, code, state}) do
    step = state.current_step

    # Handle validation decision
    case decision do
      :approve ->
        execute_code(code, thought, step, state)

      {:modify, new_code} ->
        Logger.info("📝 [CodeAgent] Code modified by user")
        execute_code(new_code, thought, step, state)

      {:feedback, message} ->
        Logger.info("💬 [CodeAgent] User feedback: #{String.slice(message, 0, 50)}...")

        # Add feedback as error so LLM retries
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

  # Call LLM with structured output via InstructorLite
  defp call_llm(model, messages, response_schema, llm_opts) do
    # Use the new Client based on InstructorLite
    Client.chat_completion(model, messages, response_schema, llm_opts)
  end

  # Note: parse_response is no longer needed as InstructorLite handles parsing
  # Keeping it for backward compatibility but it won't be called in the new flow

  defp check_final_answer(_result, binding) do
    # Check if __final_answer__ is in the binding
    case Map.get(binding, :__final_answer__) do
      nil -> :continue
      answer -> {:final, answer}
    end
  end

  # Force a final answer when max_steps is reached
  defp force_final_answer(state) do
    # Build a message explicitly requesting a final answer
    messages =
      build_messages(state) ++
        [
          %{
            role: "user",
            content:
              "You have reached the maximum number of steps. Please provide your final answer now using tools.final_answer()."
          }
        ]

    # Use CodeStep schema to force code generation with final_answer call
    llm_opts = Keyword.put(state.config.llm_opts, :adapter, state.config.adapter)
    case call_llm(state.config.model, messages, Schemas.CodeStep, llm_opts) do
      {:ok, %Schemas.CodeStep{code: code}} ->
        case Executor.execute_sandboxed(code, state.binding) do
          {:ok, _result, new_binding} ->
            case Map.get(new_binding, :__final_answer__) do
              nil -> {:error, "Agent did not provide final answer", state}
              answer -> {:ok, answer, %{state | binding: new_binding}}
            end

          {:error, error} ->
            {:error, "Failed to execute final answer: #{inspect(error)}", state}
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
