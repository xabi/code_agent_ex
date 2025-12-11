defmodule CodeAgentEx.Memory do
  @moduledoc """
  CodeAgent memory management.

  Stores the history of steps (thought, code, result, errors)
  and converts them to messages for the LLM.
  """

  alias CodeAgentEx.LLMFormattable

  defstruct steps: []

  @doc """
  Creates a new empty memory.
  """
  def new do
    %__MODULE__{steps: []}
  end

  @doc """
  Adds a step to the memory.
  """
  def add_step(%__MODULE__{steps: steps} = memory, step) do
    %{memory | steps: steps ++ [step]}
  end

  @doc """
  Adds a task step to the memory.
  Used to mark the beginning of a new task in a multi-turn conversation.
  """
  def add_task(%__MODULE__{} = memory, task) do
    add_step(memory, %{type: :task, task: task})
  end

  @doc """
  Converts the memory to messages for the LLM.

  Different types of steps:
  - Task step: task to accomplish (user message)
  - Code step: thought + executed code (assistant) + observation (user)
  """
  def to_messages(%__MODULE__{steps: steps}) do
    steps
    |> Enum.flat_map(&step_to_messages/1)
  end

  defp step_to_messages(%{type: :task} = step) do
    # Task steps are just user messages with the task
    [%{role: "user", content: step.task}]
  end

  defp step_to_messages(step) do
    # Code steps are assistant (code) + user (observation)
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

  defp format_observation(%{error: error}) do
    """
    **Observation (Error):**
    ```
    #{error}
    ```

    Please fix the error and try again.
    """
  end

  defp format_observation(%{result: result} = step) do
    output = Map.get(step, :output, "")

    # Format result using LLMFormattable protocol
    formatted_result = LLMFormattable.to_llm_string(result)

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
  end

  defp format_observation(_step) do
    "**Observation:** No result"
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
