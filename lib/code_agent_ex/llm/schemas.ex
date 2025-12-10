defmodule CodeAgentEx.LLM.Schemas do
  @moduledoc """
  Ecto schemas for structured LLM responses using InstructorLite.

  These schemas define the expected structure for different types of
  LLM responses in the CodeAgent system.
  """

  defmodule CodeStep do
    @moduledoc """
    Schema for intermediate code generation steps.

    The LLM must provide:
    - thought: Reasoning about what to do next
    - code: Elixir code to execute
    """
    use Ecto.Schema
    use InstructorLite.Instruction

    @primary_key false
    embedded_schema do
      field(:thought, :string)
      field(:code, :string)
    end
  end

  defmodule JsonResponse do
    @moduledoc """
    Generic JSON response schema for free-form structured output.

    Used when the agent needs to return arbitrary JSON data.
    This is similar to the old `response_format: %{type: "json_object"}`.
    """
    use Ecto.Schema
    use InstructorLite.Instruction

    @primary_key false
    embedded_schema do
      field(:data, :map)
    end
  end

  defmodule TextResponse do
    @moduledoc """
    Simple text response schema for final answers.

    Used when the agent provides a direct text answer without
    executing any code.
    """
    use Ecto.Schema
    use InstructorLite.Instruction

    @primary_key false
    embedded_schema do
      field(:answer, :string)
    end
  end

  defmodule MediaAttachment do
    @moduledoc """
    Schema for media attachments (images, videos, etc.)
    """
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:type, :string)  # "image", "video", etc.
      field(:path, :string)  # file path
      field(:caption, :string)  # optional description
    end
  end

  defmodule RichResponse do
    @moduledoc """
    Rich response schema that can include text and media attachments.

    Used when the agent needs to return a response with images, videos,
    or other media alongside text.
    """
    use Ecto.Schema
    use InstructorLite.Instruction

    @primary_key false
    embedded_schema do
      field(:text, :string)
      embeds_many(:attachments, MediaAttachment)
    end
  end
end
