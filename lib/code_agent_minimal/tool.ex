defmodule CodeAgentMinimal.Tool do
  @moduledoc """
  Définition des tools pour le CodeAgent.

  Un tool est une fonction que l'agent peut appeler dans son code généré.
  Les tools sont injectés dans le binding lors de l'exécution.

  ## Structure d'un tool

      %Tool{
        name: :calculator,
        description: "Effectue des calculs mathématiques",
        inputs: %{
          "expression" => %{type: "string", description: "Expression mathématique"}
        },
        output_type: "number",
        function: fn expression -> ... end
      }
  """

  defstruct [:name, :description, :inputs, :output_type, :function]

  @doc """
  Crée un binding Elixir avec tous les tools disponibles.

  Chaque tool devient une fonction dans le binding que le code peut appeler.
  Les noms des tools doivent être des atoms.
  """
  def create_binding(tools) do
    tools
    |> Enum.map(fn tool ->
      # Le nom doit déjà être un atom
      {tool.name, tool.function}
    end)
    |> Keyword.new()
  end

  @doc """
  Génère la documentation des tools pour le prompt système.
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

    """
    ### #{tool.name}
    #{tool.description}

    **Inputs:**
    #{inputs_doc}

    **Output:** #{tool.output_type}
    """
  end

  # ==================== TOOLS PRÉDÉFINIS ====================

  @doc """
  Tool obligatoire pour terminer l'exécution avec une réponse.
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
      function: fn answer ->
        # Marque spéciale pour signaler la fin
        throw({:final_answer, answer})
      end
    }
  end

  @doc """
  Tool pour lire un fichier.
  """
  def read_file do
    %__MODULE__{
      name: :read_file,
      description: "Reads the content of a file.",
      inputs: %{
        "path" => %{type: "string", description: "Path to the file to read"}
      },
      output_type: "string",
      function: fn path ->
        case File.read(path) do
          {:ok, content} -> content
          {:error, reason} -> "Error reading file: #{reason}"
        end
      end
    }
  end

  @doc """
  Tool pour écrire dans un fichier.
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
      function: fn path, content ->
        case File.write(path, content) do
          :ok -> "File written successfully: #{path}"
          {:error, reason} -> "Error writing file: #{reason}"
        end
      end
    }
  end

  @doc """
  Tool pour exécuter une commande shell.
  """
  def shell_command do
    %__MODULE__{
      name: :shell,
      description: "Executes a shell command and returns the output.",
      inputs: %{
        "command" => %{type: "string", description: "Shell command to execute"}
      },
      output_type: "string",
      function: fn command ->
        case System.cmd("sh", ["-c", command], stderr_to_stdout: true) do
          {output, 0} -> output
          {output, code} -> "Command failed (exit code #{code}):\n#{output}"
        end
      end
    }
  end

  @doc """
  Tool pour faire une requête HTTP GET.
  """
  def http_get do
    %__MODULE__{
      name: :http_get,
      description: "Makes an HTTP GET request to a URL.",
      inputs: %{
        "url" => %{type: "string", description: "URL to fetch"}
      },
      output_type: "string",
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

  @doc """
  Tool pour afficher/logger une valeur (utile pour debug).
  """
  def print do
    %__MODULE__{
      name: :print,
      description: "Prints a value to the output log.",
      inputs: %{
        "value" => %{type: "any", description: "Value to print"}
      },
      output_type: "nil",
      function: fn value ->
        IO.puts(inspect(value))
        nil
      end
    }
  end
end
