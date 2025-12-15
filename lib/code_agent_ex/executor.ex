defmodule CodeAgentEx.Executor do
  @moduledoc """
  Elixir code executor for CodeAgent.

  Uses Code.eval_string to execute LLM-generated code.
  Inspired by smolagents' local_python_executor.py.

  ## Usage

      Executor.execute_sandboxed(code, binding)

  Code is executed with access to tools via the binding.
  """

  require Logger

  @doc """
  Executes Elixir code with Code.eval_string.

  Inspired by smolagents' evaluate_python_code() which uses an AST walker.
  Here we use Code.eval_string with a prepared binding containing all tools.

  ## Expected code example

      result = 25 * 4
      result = result + 10
      tools.final_answer.(result)

  ## Parameters

  - `code` - The Elixir code to execute
  - `binding` - Keyword list containing available tools

  ## Returns

  - `{:ok, result, updated_binding}` - Successful execution with updated binding
  - `{:error, reason}` - Execution error

  ## Final Answer

  The binding is updated with `__final_answer__` only if the code
  calls `tools.final_answer.(value)`, which returns `{:__final_answer__, value}`.
  """
  def execute_sandboxed(code, binding) do
    Logger.debug("🔒 [Executor] Executing code:\n#{code}")

    # If code uses final_answer.( without tools. prefix, add a binding line for it
    code = maybe_add_final_answer_binding(code)

    # Prepare binding for Code.eval_string
    # Reuse previous bindings (variables defined in previous steps)
    eval_binding = prepare_binding(binding)

    # Execute with Code.eval_string
    try do
      {result, new_binding} = Code.eval_string(code, eval_binding)

      # Update binding with newly created variables
      # This allows variables to be reused from one step to another
      updated_binding = merge_bindings(binding, new_binding)

      # Check if the result is a final_answer marker
      updated_binding =
        case result do
          {:__final_answer__, answer} ->
            Map.put(updated_binding, :__final_answer__, answer)

          _ ->
            updated_binding
        end

      {:ok, result, updated_binding}
    rescue
      e ->
        Logger.error("🔒 [Executor] Execution error: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  # Automatically adds `final_answer = tools.final_answer` if code uses
  # final_answer.( without the tools. prefix
  defp maybe_add_final_answer_binding(code) do
    # Detect if code calls final_answer.( without the tools. prefix
    has_final_answer = String.contains?(code, "final_answer.(")
    has_tools_prefix = String.contains?(code, "tools.final_answer.(")

    if has_final_answer and not has_tools_prefix do
      # Add line at the beginning
      "final_answer = tools.final_answer\n" <> code
    else
      code
    end
  end

  # Prepares binding for Code.eval_string
  # We pass both tools AND variables from previous steps
  defp prepare_binding(binding) when is_map(binding) do
    # Get variables defined in previous steps
    previous_vars = Map.get(binding, :__vars__, [])

    # Combine tools, agents and previous variables
    [
      tools: Map.get(binding, :tools, %{}),
      agents: Map.get(binding, :agents, %{})
    ] ++ previous_vars
  end

  # Merges bindings: keeps tools/agents, adds new variables
  defp merge_bindings(original_binding, new_binding) when is_map(original_binding) do
    # Filter to keep only user variables (not tools/agents)
    user_vars =
      new_binding
      |> Enum.filter(fn {key, _} ->
        key not in [:tools, :agents]
      end)

    # Update original binding with new variables
    original_binding
    |> Map.put(:__vars__, user_vars)
  end
end
