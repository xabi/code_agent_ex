defmodule CodeAgentEx.Tool do
  @moduledoc """
  Tool definitions for CodeAgent.

  A tool is a function that the agent can call in its generated code.
  Tools are injected into the binding during execution.

  ## Tool structure

      %Tool{
        name: :calculator,
        description: "Performs mathematical calculations",
        inputs: %{
          "expression" => %{type: "string", description: "Mathematical expression"}
        },
        output_type: "number",
        function: fn expression -> ... end,
        safety: :safe  # or :unsafe (default)
      }

  ## Safety levels

  - `:safe` - Read-only operations (API calls, searches, reads)
  - `:unsafe` - Operations that can modify state (file writes, shell commands, code execution)
  """

  defstruct [:name, :description, :inputs, :output_type, :function, safety: :unsafe]

  @tool_schema NimbleOptions.new!(
    name: [
      type: :atom,
      required: true,
      doc: "Tool name identifier (must be a valid Elixir atom)"
    ],
    description: [
      type: :string,
      required: true,
      doc: "Description of what the tool does"
    ],
    inputs: [
      type: :any,
      required: true,
      doc: "Map describing input parameters with their types and descriptions"
    ],
    output_type: [
      type: :string,
      required: true,
      doc: "Description of the output type"
    ],
    function: [
      type: {:custom, __MODULE__, :validate_function, []},
      required: true,
      doc: "The function to execute (can be any arity)"
    ],
    safety: [
      type: {:in, [:safe, :unsafe]},
      default: :unsafe,
      doc: "Safety level: :safe (read-only) or :unsafe (can modify state)"
    ]
  )

  @doc false
  def validate_function(value) do
    if is_function(value) do
      {:ok, value}
    else
      {:error, "expected a function, got: #{inspect(value)}"}
    end
  end

  @doc """
  Creates a new tool with validation.

  ## Options

  #{NimbleOptions.docs(@tool_schema)}

  ## Example

      Tool.new(
        name: :calculator,
        description: "Performs calculations",
        inputs: %{"expr" => %{type: "string", description: "Math expression"}},
        output_type: "number",
        function: fn expr -> eval(expr) end
      )
  """
  def new(opts) do
    validated_opts = NimbleOptions.validate!(opts, @tool_schema)
    struct!(__MODULE__, validated_opts)
  end

  @doc """
  Creates an Elixir binding with all available tools.

  Each tool becomes a function in the binding that code can call.
  Tool names must be atoms.
  """
  def create_binding(tools) do
    tools
    |> Enum.map(fn tool ->
      {tool.name, tool.function}
    end)
    |> Keyword.new()
  end

  @doc """
  Generates tools documentation for the system prompt.
  """
  def tools_documentation(tools) do
    tools
    |> Enum.map(&tool_doc/1)
    |> Enum.join("\n\n")
  end

  defp tool_doc(%__MODULE__{} = tool) do
    inputs_doc =
      tool.inputs
      |> Enum.map(fn {name, spec} ->
        type = Map.get(spec, :type, "any")
        desc = Map.get(spec, :description, "")
        "  - #{name} (#{type}): #{desc}"
      end)
      |> Enum.join("\n")

    safety_badge =
      case tool.safety do
        :safe -> "[SAFE]"
        :unsafe -> "[UNSAFE]"
      end

    """
    ### #{tool.name} #{safety_badge}
    #{tool.description}

    **Inputs:**
    #{inputs_doc}

    **Output:** #{tool.output_type}
    """
  end

  # ==================== PREDEFINED TOOLS ====================

  @doc """
  Required tool to terminate execution with an answer.
  """
  def final_answer do
    %__MODULE__{
      name: :final_answer,
      description:
        "Provides the final answer to the task. Call this when you have the complete answer.",
      inputs: %{
        "answer" => %{type: "any", description: "The final answer to return"}
      },
      output_type: "any",
      safety: :safe,
      function: fn answer ->
        # Return a special marker tuple to signal completion
        {:__final_answer__, answer}
      end
    }
  end


  @doc """
  Tool to read a file.
  """
  def read_file do
    %__MODULE__{
      name: :read_file,
      description: "Reads the content of a file.",
      inputs: %{
        "path" => %{type: "string", description: "Path to the file to read"}
      },
      output_type: "string",
      safety: :safe,
      function: fn path ->
        case File.read(path) do
          {:ok, content} -> content
          {:error, reason} -> "Error reading file: #{reason}"
        end
      end
    }
  end

  @doc """
  Tool to write to a file.
  """
  def write_file do
    %__MODULE__{
      name: :write_file,
      description: "Writes content to a file.",
      inputs: %{
        "path" => %{type: "string", description: "Path to the file"},
        "content" => %{type: "string", description: "Content to write"}
      },
      output_type: "string",
      safety: :unsafe,
      function: fn path, content ->
        case File.write(path, content) do
          :ok -> "File written successfully: #{path}"
          {:error, reason} -> "Error writing file: #{reason}"
        end
      end
    }
  end

  @doc """
  Tool to execute a shell command.
  """
  def shell_command do
    %__MODULE__{
      name: :shell,
      description: "Executes a shell command and returns the output.",
      inputs: %{
        "command" => %{type: "string", description: "Shell command to execute"}
      },
      output_type: "string",
      safety: :unsafe,
      function: fn command ->
        case System.cmd("sh", ["-c", command], stderr_to_stdout: true) do
          {output, 0} -> output
          {output, code} -> "Command failed (exit code #{code}):\n#{output}"
        end
      end
    }
  end

  @doc """
  Tool to make an HTTP GET request.
  """
  def http_get do
    %__MODULE__{
      name: :http_get,
      description: "Makes an HTTP GET request to a URL.",
      inputs: %{
        "url" => %{type: "string", description: "URL to fetch"}
      },
      output_type: "string",
      safety: :safe,
      function: fn url ->
        case Req.get(url) do
          {:ok, %{status: status, body: body}} when status in 200..299 ->
            if is_binary(body), do: body, else: inspect(body)

          {:ok, %{status: status}} ->
            "HTTP error: status #{status}"

          {:error, reason} ->
            "Request failed: #{inspect(reason)}"
        end
      end
    }
  end
end
