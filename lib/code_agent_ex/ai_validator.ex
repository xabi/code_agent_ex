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
  alias CodeAgentEx.AgentServer

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
    You are a code safety validator. Analyze the following code execution request and decide if it should be approved.

    AGENT: #{agent_name}

    AGENT'S REASONING:
    #{thought}

    CODE TO EXECUTE:
    ```elixir
    #{code}
    ```

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
    - REJECT only for dangerous/malicious code
    """
  end

  @doc """
  Creates a validation handler function that uses AI to validate code.

  ## Options
  - `:model` - HuggingFace model to use (default: "Qwen/Qwen3-Coder-30B-A3B-Instruct")
  - `:api_key` - HuggingFace API key (default: from HF_TOKEN env var)
  - `:auto_approve_threshold` - Auto-approve if safety_score >= this (default: 80)
  - `:verbose` - Show detailed validation info (default: false)
  - `:prompt_fn` - Custom prompt function (default: `&default_prompt_fn/1`)
    Function receives a map with :thought, :code, :agent_name and returns a string

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
    model = Keyword.get(opts, :model, "Qwen/Qwen3-Coder-30B-A3B-Instruct")
    api_key = Keyword.get(opts, :api_key, System.get_env("HF_TOKEN"))
    auto_approve_threshold = Keyword.get(opts, :auto_approve_threshold, 80)
    verbose = Keyword.get(opts, :verbose, false)
    prompt_fn = Keyword.get(opts, :prompt_fn, &default_prompt_fn/1)

    fn validation_request ->
      validate_with_ai(validation_request, model, api_key, auto_approve_threshold, verbose, prompt_fn)
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
  def validate_with_ai(validation_request, model, api_key, auto_approve_threshold, verbose, prompt_fn) do
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

    case call_instructor(prompt, model, api_key) do
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

  # Call InstructorLite to get structured output from LLM
  # Uses ChatCompletionsCompatible adapter for HuggingFace
  defp call_instructor(prompt, model, api_key) do
    try do
      result = InstructorLite.instruct(
        %{
          model: model,
          messages: [
            %{role: "user", content: prompt}
          ]
        },
        response_model: ValidationDecision,
        adapter: InstructorLite.Adapters.ChatCompletionsCompatible,
        adapter_context: [
          api_key: api_key,
          url: "https://router.huggingface.co/v1/chat/completions"
        ]
      )

      case result do
        {:ok, decision} -> {:ok, decision}
        {:error, reason} -> {:error, reason}
        other -> {:error, "Unexpected result: #{inspect(other)}"}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
end
