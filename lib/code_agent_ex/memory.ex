defmodule CodeAgentEx.Memory do
  @moduledoc """
  CodeAgent memory management.

  Stores the history of steps (thought, code, result, errors)
  and converts them to messages for the LLM.
  """

  alias CodeAgentEx.AgentTypes

  defstruct steps: []

  @doc """
  Creates a new empty memory.
  """
  def new do
    %__MODULE__{steps: []}
  end

  @doc """
  Ajoute un step à la mémoire.
  """
  def add_step(%__MODULE__{steps: steps} = memory, step) do
    %{memory | steps: steps ++ [step]}
  end

  @doc """
  Convertit la mémoire en messages pour le LLM.

  Chaque step devient un échange assistant/user:
  - Assistant: le code exécuté
  - User: le résultat ou l'erreur (observation)
  """
  def to_messages(%__MODULE__{steps: steps}) do
    steps
    |> Enum.flat_map(&step_to_messages/1)
  end

  defp step_to_messages(step) do
    assistant_content = format_assistant_message(step)
    user_content = format_observation(step)

    [
      %{role: "assistant", content: assistant_content},
      %{role: "user", content: user_content}
    ]
  end

  defp format_assistant_message(step) do
    thought = Map.get(step, :thought, "")
    code = Map.get(step, :code, "")

    if code != "" do
      Jason.encode!(%{
        thought: thought,
        code: code
      })
    else
      # Fallback for steps without code
      thought
    end
  end

  defp format_observation(step) do
    cond do
      Map.has_key?(step, :error) ->
        """
        **Observation (Error):**
        ```
        #{step.error}
        ```

        Please fix the error and try again.
        """

      Map.has_key?(step, :result) ->
        output = Map.get(step, :output, "")
        result = step.result

        # Convert AgentTypes to their LLM representation (paths)
        formatted_result = AgentTypes.to_llm_value(result)

        output_section =
          if output != "" do
            """

            **Output:**
            ```
            #{output}
            ```
            """
          else
            ""
          end

        """
        **Observation:**
        Result: #{inspect(formatted_result)}
        #{output_section}
        """

      true ->
        "**Observation:** No result"
    end
  end

  @doc """
  Returns the number of steps.
  """
  def count(%__MODULE__{steps: steps}), do: length(steps)

  @doc """
  Returns the last step.
  """
  def last_step(%__MODULE__{steps: []}), do: nil
  def last_step(%__MODULE__{steps: steps}), do: List.last(steps)
end
