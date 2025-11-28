defmodule CodeAgentMinimal.Tools.PythonTools do
  @moduledoc """
  Tools for executing Python code in CodeAgent.

  Provides a python_interpreter tool that can execute Python code
  and return results, including images from matplotlib.
  """

  alias CodeAgentMinimal.AgentTypes.AgentImage
  require Logger

  @doc """
  Safe stdlib imports allowed by default.
  """
  def safe_stdlib_imports do
    [
      "math",
      "statistics",
      "decimal",
      "fractions",
      "random",
      "datetime",
      "time",
      "calendar",
      "collections",
      "itertools",
      "functools",
      "string",
      "textwrap",
      "re",
      "json",
      "csv",
      "io",
      "base64"
    ]
  end

  @doc """
  Returns the python_interpreter tool for CodeAgent.

  ## Options

  - `:allowed_imports` - List of allowed Python modules (nil = all allowed)
  """
  def python_interpreter(opts \\ []) do
    allowed_imports = Keyword.get(opts, :allowed_imports)

    %CodeAgentMinimal.Tool{
      name: :python_interpreter,
      description: """
      Execute Python code and return the result.
      IMPORTANT: Set a 'result' variable with the value to return. Do NOT use print().
      Example: result = 2 + 2  # returns "4"
      For matplotlib plots, also set 'image_base64' with the base64 PNG data.
      """,
      inputs: %{
        "code" => %{
          type: "string",
          description:
            "Python code to execute. Must set 'result' variable (not print). Example: result = sum([1,2,3])"
        }
      },
      output_type: "string",
      function: fn args ->
        code = normalize_arg(args)
        execute_python(code, allowed_imports)
      end
    }
  end

  @doc """
  Returns all Python tools for CodeAgent.
  """
  def all_tools(opts \\ []) do
    [python_interpreter(opts)]
  end

  # Execute Python code
  defp execute_python(code, allowed_imports) do
    Logger.info("[PythonTools] Executing Python code (#{String.length(code)} chars)")

    case validate_imports(code, allowed_imports) do
      :ok ->
        try do
          # Indent user code
          indented_code =
            code |> String.split("\n") |> Enum.map(&("    " <> &1)) |> Enum.join("\n")

          wrapped_code = """
          try:
              # User code
          #{indented_code}

              # Check for image
              if 'image_base64' in globals():
                  output = ("ok_with_image", image_base64, str(globals().get('result', 'Computation completed')))
              else:
                  if 'result' in globals():
                      output = ("ok", str(result))
                  else:
                      output = ("ok", "Execution completed successfully")
          except Exception as e:
              import traceback
              error_details = traceback.format_exc()
              output = ("error", f"{type(e).__name__}: {str(e)}\\n\\nTraceback:\\n{error_details}")

          output
          """

          {result, _globals} = Pythonx.eval(wrapped_code, %{})
          decoded_result = Pythonx.decode(result)

          case decoded_result do
            {"ok_with_image", base64_data, result_text} ->
              Logger.info("[PythonTools] Execution successful with image")

              # Decode base64 and create AgentImage
              case Base.decode64(base64_data) do
                {:ok, image_data} ->
                  image = AgentImage.from_binary(image_data, "png")
                  # Use markdown image syntax for easy parsing
                  "#{result_text}\n\n![Generated image](#{image.path})"

                :error ->
                  "#{result_text}\n\n(Image generated but could not be decoded)"
              end

            {"ok", message} ->
              Logger.info("[PythonTools] Execution successful")
              message

            {"error", error_msg} ->
              Logger.error("[PythonTools] Python error: #{error_msg}")
              "Error: #{error_msg}"

            other ->
              inspect(other)
          end
        rescue
          error ->
            Logger.error("[PythonTools] Exception: #{inspect(error)}")
            "Execution error: #{inspect(error)}"
        end

      {:error, unauthorized_imports} ->
        "Unauthorized imports: #{Enum.join(unauthorized_imports, ", ")}"
    end
  end

  # Normalize charlist to binary
  defp normalize_arg(arg) when is_list(arg), do: List.to_string(arg)
  defp normalize_arg(arg) when is_map(arg), do: Map.get(arg, "code", "")
  defp normalize_arg(arg), do: arg

  # Validate imports
  defp validate_imports(_code, nil), do: :ok

  defp validate_imports(code, allowed_imports) when is_list(allowed_imports) do
    detected_imports = extract_imports(code)

    unauthorized =
      Enum.reject(detected_imports, fn import_name ->
        Enum.any?(allowed_imports, fn allowed ->
          import_name == allowed or String.starts_with?(import_name, "#{allowed}.")
        end)
      end)

    if length(unauthorized) > 0 do
      {:error, unauthorized}
    else
      :ok
    end
  end

  # Extract imports from Python code
  defp extract_imports(code) do
    patterns = [
      ~r/^\s*import\s+([a-zA-Z_][a-zA-Z0-9_\.]*)/m,
      ~r/^\s*import\s+([a-zA-Z_][a-zA-Z0-9_\.]*)\s+as\s+/m,
      ~r/^\s*from\s+([a-zA-Z_][a-zA-Z0-9_\.]*)\s+import\s+/m
    ]

    patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, code)
      |> Enum.map(fn [_full, module_name] -> module_name end)
    end)
    |> Enum.uniq()
  end
end
