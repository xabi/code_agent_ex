defmodule CodeAgentEx.AIValidator do
  @moduledoc """
  AI-powered code validation using Instructor.Lite.

  This module uses an LLM to analyze code before execution and make
  decisions about whether it's safe and correct to run.

  ## Usage

      # Create a validation handler using AI
      validation_handler = AIValidator.create_handler()

      # Use with orchestrator
      {:ok, orch} = AgentOrchestrator.start_link(config, validation_handler: validation_handler)
  """

  require Logger
  alias CodeAgentEx.{AgentServer, LLM.Client}

  defmodule ValidationDecision do
    @moduledoc """
    Structured output from the AI validator.
    """
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :decision, Ecto.Enum, values: [:approve, :reject, :modify, :feedback]
      field :reasoning, :string
      field :modified_code, :string
      field :feedback_message, :string
      field :safety_score, :integer
    end
  end

  @doc """
  Default validation prompt function.

  Takes a map with keys: :thought, :code, :agent_name
  Returns the prompt string with interpolated values.
  """
  def default_prompt_fn(%{thought: thought, code: code, agent_name: agent_name}) do
    """
    You are a code safety validator for an Elixir AI agent system. Analyze the following code execution request and decide if it should be approved.

    AGENT: #{agent_name}

    AGENT'S REASONING:
    #{thought}

    CODE TO EXECUTE:
    ```elixir
    #{code}
    ```

    IMPORTANT CONTEXT:
    - The agent has access to tools via `tools.tool_name.(args)` syntax (e.g., `tools.final_answer.("result")`)
    - The agent can call sub-agents via `agents.agent_name.(task)` syntax
    - These are valid Elixir function calls using anonymous functions from a binding
    - Variables persist between steps, so the agent can reference previously computed values

    Analyze this code for:
    1. **Safety**: No destructive operations, dangerous file access, or network calls
    2. **Correctness**: Does the code match the agent's stated intention?
    3. **Quality**: Is it clean, readable, and follows best practices?

    Provide your response as a JSON object with these fields:
    - decision: "approve", "reject", "modify", or "feedback"
    - reasoning: Why you made this decision (1-2 sentences)
    - safety_score: 0-100 (how safe/correct is this code?)
    - modified_code: If decision is "modify", provide corrected code (otherwise null)
    - feedback_message: If decision is "feedback", provide guidance for the agent (otherwise null)

    Guidelines:
    - APPROVE if safety_score >= 70 and code looks correct
    - MODIFY if code needs small fixes (syntax errors, minor improvements)
    - FEEDBACK if agent misunderstood the task
    - REJECT only for dangerous/malicious code (file deletion, system commands, etc.)
    - Tool calls like `tools.final_answer.()` and agent calls like `agents.xxx.()` are VALID and SAFE
    """
  end

  @handler_schema NimbleOptions.new!(
    model: [
      type: :string,
      default: "Qwen/Qwen3-Coder-30B-A3B-Instruct",
      doc: "Model to use for validation"
    ],
    adapter: [
      type: :atom,
      default: InstructorLite.Adapters.ChatCompletionsCompatible,
      doc: "InstructorLite adapter module"
    ],
    api_key: [
      type: :string,
      doc: "API key (defaults to HF_TOKEN or OPENAI_API_KEY env var)"
    ],
    base_url: [
      type: :string,
      doc: "Base URL for the API"
    ],
    auto_approve_threshold: [
      type: :integer,
      default: 80,
      doc: "Auto-approve if safety_score >= this value"
    ],
    verbose: [
      type: :boolean,
      default: false,
      doc: "Show detailed validation info"
    ],
    prompt_fn: [
      type: {:fun, 1},
      default: &__MODULE__.default_prompt_fn/1,
      doc: "Custom prompt function (receives map with :thought, :code, :agent_name)"
    ]
  )

  @doc """
  Creates a validation handler function that uses AI to validate code.

  ## Options

  #{NimbleOptions.docs(@handler_schema)}

  ## Example

      handler = AIValidator.create_handler(verbose: true, auto_approve_threshold: 90)
      {:ok, orch} = AgentOrchestrator.start_link(config, validation_handler: handler)

      # With custom prompt function
      custom_prompt_fn = fn %{thought: t, code: c, agent_name: _} ->
        "Analyze: \#{c}. Reasoning: \#{t}. Respond with JSON."
      end
      handler = AIValidator.create_handler(prompt_fn: custom_prompt_fn)
  """
  def create_handler(opts \\ []) do
    validated_opts = NimbleOptions.validate!(opts, @handler_schema)

    model = validated_opts[:model]
    adapter = validated_opts[:adapter]
    api_key = validated_opts[:api_key]
    base_url = validated_opts[:base_url]
    auto_approve_threshold = validated_opts[:auto_approve_threshold]
    verbose = validated_opts[:verbose]
    prompt_fn = validated_opts[:prompt_fn]

    fn validation_request ->
      validate_with_ai(validation_request, model, adapter, api_key, base_url, auto_approve_threshold, verbose, prompt_fn)
    end
  end

  @doc """
  Validates a code execution request using AI.

  The AI analyzes:
  - Code safety (no destructive operations, file access, network calls)
  - Correctness (matches the agent's intention)
  - Best practices (clean, readable code)

  Returns a decision: :approve, :reject, {:modify, code}, or {:feedback, message}
  """
  def validate_with_ai(validation_request, model, adapter, api_key, base_url, auto_approve_threshold, verbose, prompt_fn) do
    %{
      agent_pid: agent_pid,
      agent_name: agent_name,
      thought: thought,
      code: code
    } = validation_request

    if verbose do
      IO.puts("""

      ═══════════════════════════════════════════════════════════════════
      🤖 AI Validator analyzing code from '#{agent_name}'...
      ═══════════════════════════════════════════════════════════════════
      """)
    end

    # Call prompt function with validation data
    prompt = prompt_fn.(%{
      thought: thought,
      code: code,
      agent_name: agent_name
    })

    # Build options for LLM.Client
    llm_opts = []
    llm_opts = if api_key, do: Keyword.put(llm_opts, :api_key, api_key), else: llm_opts
    llm_opts = if base_url, do: Keyword.put(llm_opts, :base_url, base_url), else: llm_opts
    llm_opts = Keyword.put(llm_opts, :adapter, adapter)

    case call_llm_client(prompt, model, llm_opts) do
      {:ok, %ValidationDecision{} = decision} ->
        if verbose do
          IO.puts("""

          📊 AI Decision: #{decision.decision} (safety: #{decision.safety_score}/100)
          💭 Reasoning: #{decision.reasoning}
          """)
        end

        # Convert AI decision to AgentServer decision
        final_decision = make_decision(decision, auto_approve_threshold)

        if verbose do
          IO.puts("✅ Action: #{inspect(final_decision)}\n")
        end

        # Send decision to agent
        AgentServer.continue(agent_pid, final_decision)

      {:error, reason} ->
        Logger.error("[AIValidator] Failed to validate code: #{inspect(reason)}")

        if verbose do
          IO.puts("❌ AI validation failed: #{inspect(reason)}")
          IO.puts("⚠️  Falling back to AUTO-APPROVE\n")
        end

        # Fallback: auto-approve on error
        AgentServer.continue(agent_pid, :approve)
    end
  end

  # Convert ValidationDecision to AgentServer decision format
  defp make_decision(%ValidationDecision{} = decision, auto_approve_threshold) do
    case decision.decision do
      :approve ->
        if decision.safety_score >= auto_approve_threshold do
          :approve
        else
          # Low safety score - send feedback instead
          {:feedback, "Safety score too low (#{decision.safety_score}): #{decision.reasoning}"}
        end

      :reject ->
        :reject

      :modify ->
        if decision.modified_code && String.trim(decision.modified_code) != "" do
          {:modify, decision.modified_code}
        else
          # No modified code provided, send feedback instead
          {:feedback, decision.reasoning}
        end

      :feedback ->
        {:feedback, decision.feedback_message || decision.reasoning}
    end
  end

  # Call LLM.Client to get structured output from LLM
  defp call_llm_client(prompt, model, llm_opts) do
    messages = [%{role: "user", content: prompt}]
    Client.chat_completion(model, messages, ValidationDecision, llm_opts)
  end
end
