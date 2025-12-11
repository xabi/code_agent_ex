defmodule CodeAgentEx.MemoryTest do
  use ExUnit.Case, async: true

  alias CodeAgentEx.Memory

  describe "task steps" do
    test "add_task/2 creates a task step" do
      memory = Memory.new()
      memory = Memory.add_task(memory, "Calculate 5 + 3")

      assert Memory.count(memory) == 1

      [step] = memory.steps
      assert step.type == :task
      assert step.task == "Calculate 5 + 3"
    end

    test "task steps convert to user messages" do
      memory =
        Memory.new()
        |> Memory.add_task("First task")

      messages = Memory.to_messages(memory)

      assert length(messages) == 1
      assert [%{role: "user", content: "First task"}] = messages
    end

    test "multiple task steps in sequence" do
      memory =
        Memory.new()
        |> Memory.add_task("First task")
        |> Memory.add_step(%{
          step: 1,
          thought: "Let me calculate",
          code: "5 + 3",
          result: 8
        })
        |> Memory.add_task("Second task")

      messages = Memory.to_messages(memory)

      # First task (user) + Code step (assistant + user) + Second task (user)
      # = 1 + 2 + 1 = 4 messages
      assert length(messages) == 4

      [msg1, msg2, msg3, msg4] = messages
      assert msg1.role == "user"
      assert msg1.content == "First task"

      assert msg2.role == "assistant"
      # Code step assistant message

      assert msg3.role == "user"
      # Code step observation

      assert msg4.role == "user"
      assert msg4.content == "Second task"
    end
  end

  describe "code steps" do
    test "code steps convert to assistant + user messages" do
      memory =
        Memory.new()
        |> Memory.add_step(%{
          step: 1,
          thought: "I'll calculate the sum",
          code: "result = 5 + 3",
          result: 8
        })

      messages = Memory.to_messages(memory)

      assert length(messages) == 2

      [assistant_msg, user_msg] = messages
      assert assistant_msg.role == "assistant"
      assert user_msg.role == "user"

      # Assistant message should contain thought and code as JSON
      assert String.contains?(assistant_msg.content, "calculate")
      assert String.contains?(assistant_msg.content, "result = 5 + 3")

      # User message should contain observation
      assert String.contains?(user_msg.content, "Observation")
    end

    test "error steps show error in observation" do
      memory =
        Memory.new()
        |> Memory.add_step(%{
          step: 1,
          thought: "This will fail",
          code: "1 / 0",
          error: "ArithmeticError: division by zero"
        })

      messages = Memory.to_messages(memory)

      [_assistant_msg, user_msg] = messages
      assert user_msg.role == "user"
      assert String.contains?(user_msg.content, "Error")
      assert String.contains?(user_msg.content, "division by zero")
    end
  end

  describe "mixed steps (simulating multi-turn)" do
    test "task -> code -> task -> code sequence" do
      memory =
        Memory.new()
        |> Memory.add_task("Calculate 5 + 3")
        |> Memory.add_step(%{
          step: 1,
          thought: "Let me calculate",
          code: "result = 5 + 3\ntools.final_answer(result)",
          result: 8
        })
        |> Memory.add_task("What was the result? Double it.")
        |> Memory.add_step(%{
          step: 1,
          thought: "I'll double the previous result",
          code: "doubled = result * 2\ntools.final_answer(doubled)",
          result: 16
        })

      messages = Memory.to_messages(memory)

      # Task1 (user) + Code1 (assistant + user) + Task2 (user) + Code2 (assistant + user)
      # = 1 + 2 + 1 + 2 = 6 messages
      assert length(messages) == 6

      [task1, code1_assistant, code1_user, task2, code2_assistant, code2_user] = messages

      # Verify structure
      assert task1.role == "user"
      assert task1.content == "Calculate 5 + 3"

      assert code1_assistant.role == "assistant"
      assert code1_user.role == "user"

      assert task2.role == "user"
      assert task2.content == "What was the result? Double it."

      assert code2_assistant.role == "assistant"
      assert code2_user.role == "user"
    end
  end
end
