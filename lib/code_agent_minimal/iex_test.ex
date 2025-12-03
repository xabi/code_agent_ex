defmodule CodeAgentMinimal.IexTest do
  @moduledoc """
  Module de tests interactifs pour le CodeAgent, utilisable depuis iex.

  ## Utilisation

  Dans iex:

      iex> CodeAgentMinimal.IexTest.test1()
      iex> CodeAgentMinimal.IexTest.test_all()
      iex> CodeAgentMinimal.IexTest.test_custom("Calculate 10 + 5")
  """

  alias CodeAgentMinimal.{CodeAgent, Tool, AgentConfig}
  require Logger

  @doc """
  Lance tous les tests de base.
  """
  def test_all do
    IO.puts("\n🤖 CodeAgent - Suite de tests complète\n")

    tests = [
      {"Test 1: Calcul arithmétique simple", &test1/0},
      {"Test 2: Manipulation de listes", &test2/0},
      {"Test 3: Tools personnalisés", &test3/0},
      {"Test 4: Logique conditionnelle", &test4/0},
      {"Test 5: Tools multiples", &test5/0},
      {"Test 6: Data processing", &test6/0},
      {"Test 7: Filtrage de données", &test7/0},
      {"Test 8: Managed agent Python", &test8/0},
      {"Test 9: Managed agent Wikipedia", &test9/0},
      {"Test 10: Managed agent Finance", &test10/0},
      {"Test 11: Managed agent Image FLUX", &test11/0},
      {"Test 12: Managed agent Moondream", &test12/0},
      {"Test 13: Nested managed agents", &test13/0},
      {"Test 14: Graphique équation du second degré", &test14/0},
      {"Test 15: Génération d'image avec HF Inference API", &test15/0},
      {"Test 16: Génération de vidéo avec HF Inference API", &test16/0}
      # Note: test17 n'est pas dans test_all car il nécessite une interaction manuelle
    ]

    results =
      Enum.map(tests, fn {name, test_fn} ->
        IO.puts("\n📝 #{name}")
        IO.puts(String.duplicate("=", 80))

        case test_fn.() do
          {:ok, result, state} ->
            IO.puts("✅ Résultat: #{inspect(result)}")
            IO.puts("   Steps: #{state.current_step}/#{state.config.max_steps}\n")
            :ok

          {:error, reason, _state} ->
            IO.puts("❌ Erreur: #{inspect(reason)}\n")
            :error
        end
      end)

    passed = Enum.count(results, &(&1 == :ok))
    total = length(results)

    IO.puts(String.duplicate("=", 80))
    IO.puts("📊 Résultats: #{passed}/#{total} tests réussis")

    if passed == total, do: :ok, else: :error
  end

  @doc """
  Test 1: Calcul arithmétique simple.
  """
  def test1 do
    task = "Calculate 25 * 4, then add 10 to the result"

    config =
      AgentConfig.new(
        tools: [],
        max_steps: 3
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 2: Manipulation de listes et moyenne.
  """
  def test2 do
    task = """
    Create a list of numbers from 1 to 10.
    Calculate the sum of all numbers.
    Then calculate and return the average as a float.
    """

    config =
      AgentConfig.new(
        tools: [],
        max_steps: 5
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 3: Tools personnalisés - Données utilisateur.
  """
  def test3 do
    user_data_tool = %Tool{
      name: :get_user_data,
      description: "Returns a map with user information including name, age, and test scores",
      inputs: %{},
      output_type: "map",
      function: fn ->
        %{
          name: "Alice",
          age: 30,
          scores: [85, 92, 78, 95, 88]
        }
      end
    }

    task = """
    Get the user data using get_user_data.
    Calculate the average of their test scores.
    Return a formatted string like: "Alice (30 years old) has an average score of X"
    """

    config =
      AgentConfig.new(
        tools: [user_data_tool],
        max_steps: 5
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 4: Logique conditionnelle.
  """
  def test4 do
    task = """
    Calculate 15 multiplied by 3.
    If the result is greater than 40, return the string "HIGH".
    Otherwise, return the string "LOW".
    """

    config =
      AgentConfig.new(
        tools: [],
        max_steps: 5
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 5: Combinaison de plusieurs tools.
  """
  def test5 do
    temperature_tool = %Tool{
      name: :get_temperature,
      description: "Returns the current temperature in Celsius",
      inputs: %{},
      output_type: "number",
      function: fn -> 25 end
    }

    convert_tool = %Tool{
      name: :celsius_to_fahrenheit,
      description:
        "Converts temperature from Celsius to Fahrenheit. Takes one argument: celsius (number)",
      inputs: %{
        "celsius" => %{type: "number", description: "Temperature in Celsius"}
      },
      output_type: "number",
      function: fn celsius -> celsius * 9 / 5 + 32 end
    }

    task = """
    Get the current temperature in Celsius using get_temperature.
    Convert it to Fahrenheit using celsius_to_fahrenheit.
    Return a formatted string like: "The temperature is X°C (Y°F)"
    """

    config =
      AgentConfig.new(
        tools: [temperature_tool, convert_tool],
        max_steps: 8
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 6: Traitement de données complexe - Analyse de ventes.
  """
  def test6 do
    sales_data_tool = %Tool{
      name: :get_sales_data,
      description: "Returns a list of sales data with product, quantity sold, and unit price",
      inputs: %{},
      output_type: "list",
      function: fn ->
        [
          %{product: "Laptop", quantity: 50, unit_price: 1200.0},
          %{product: "Mouse", quantity: 200, unit_price: 25.0},
          %{product: "Keyboard", quantity: 150, unit_price: 75.0},
          %{product: "Monitor", quantity: 80, unit_price: 300.0}
        ]
      end
    }

    task = """
    Get the sales data using get_sales_data.
    For each product, calculate the total revenue (quantity * unit_price).
    Find the product with the highest total revenue.
    Return a string like: "Product X generated the most revenue: $Y"
    """

    config =
      AgentConfig.new(
        tools: [sales_data_tool],
        max_steps: 8
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 7: Filtrage et transformation de données.
  """
  def test7 do
    employee_data_tool = %Tool{
      name: :get_employees,
      description: "Returns a list of employee records with name, department, and salary",
      inputs: %{},
      output_type: "list",
      function: fn ->
        [
          %{name: "Alice", department: "Engineering", salary: 85000},
          %{name: "Bob", department: "Sales", salary: 65000},
          %{name: "Charlie", department: "Engineering", salary: 95000},
          %{name: "Diana", department: "Marketing", salary: 70000},
          %{name: "Eve", department: "Engineering", salary: 78000}
        ]
      end
    }

    task = """
    Get the employee data using get_employees.
    Filter only employees from the Engineering department.
    Calculate the average salary for Engineering employees.
    Return a string like: "Engineering has X employees with average salary $Y"
    """

    config =
      AgentConfig.new(
        tools: [employee_data_tool],
        max_steps: 8
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 8: Managed agent avec Python interpreter.
  """
  def test8 do
    alias CodeAgentMinimal.{AgentConfig, Tools.PythonTools}

    # Créer un sous-agent spécialisé en calculs Python
    python_agent =
      AgentConfig.new(
        name: :python_calculator,
        instructions: "Specialized agent for performing calculations using Python",
        tools: [PythonTools.python_interpreter()],
        max_steps: 3
      )

    task = """
    Use the python_calculator agent to calculate the factorial of 10.
    Then format the result as: "The factorial of 10 is X"
    """

    config =
      AgentConfig.new(
        tools: [],
        managed_agents: [python_agent],
        max_steps: 5
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 9: Managed agent avec Wikipedia search.
  """
  def test9 do
    alias CodeAgentMinimal.{AgentConfig, Tools.WikipediaTools}

    # Créer un sous-agent spécialisé en recherche Wikipedia
    wiki_agent =
      AgentConfig.new(
        name: :wiki_researcher,
        instructions: "Specialized agent for searching Wikipedia articles",
        tools: [WikipediaTools.wikipedia_search()],
        max_steps: 3
      )

    task = """
    Use the wiki_researcher agent to search for information about "Elixir programming language" on Wikipedia.
    Then summarize the search results.
    """

    config =
      AgentConfig.new(
        tools: [],
        managed_agents: [wiki_agent],
        max_steps: 5
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 10: Managed agent avec Finance tools.
  """
  def test10 do
    alias CodeAgentMinimal.{AgentConfig, Tools.FinanceTools}

    # Créer un sous-agent spécialisé en données financières
    finance_agent =
      AgentConfig.new(
        name: :stock_analyst,
        instructions: "Specialized agent for analyzing stock prices",
        tools: [FinanceTools.stock_price()],
        max_steps: 4
      )

    task = """
    Use the stock_analyst agent to get the current stock prices for:
    - Apple (AAPL)
    - Microsoft (MSFT)

    Then provide a summary comparing the two prices.
    """

    config =
      AgentConfig.new(
        tools: [],
        managed_agents: [finance_agent],
        max_steps: 6
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 11: Managed agent avec génération d'image FLUX.
  """
  def test11 do
    alias CodeAgentMinimal.{AgentConfig, Tools.SmolAgentsTools}

    # Créer un sous-agent spécialisé en génération d'images
    image_agent =
      AgentConfig.new(
        name: :image_generator,
        instructions: "Specialized agent for generating images using FLUX",
        tools: [SmolAgentsTools.flux_image()],
        max_steps: 3
      )

    task = """
    Use the image_generator agent to create an image of a cute orange cat sitting on a windowsill.
    The image should be photorealistic and show the cat looking outside.
    Then describe what was generated.
    """

    config =
      AgentConfig.new(
        tools: [],
        managed_agents: [image_agent],
        max_steps: 5
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 12: Managed agent avec Moondream pour analyser une image.
  """
  def test12 do
    alias CodeAgentMinimal.{AgentConfig, Tools.MoondreamTools}

    # Tool pour lister les fichiers images dans un répertoire
    list_images_tool = %Tool{
      name: :list_images,
      description:
        "Lists all image files in a directory that start with a given prefix. Call with: tools.list_images.(directory_path, prefix)",
      inputs: %{
        "directory_path" => %{
          type: "string",
          description: "Path to the directory (e.g., '/tmp/code_agent')"
        },
        "prefix" => %{type: "string", description: "Prefix to filter files (e.g., 'agent_image')"}
      },
      output_type: "string",
      function: fn directory_path, prefix ->
        directory_path =
          if is_list(directory_path), do: List.to_string(directory_path), else: directory_path

        prefix = if is_list(prefix), do: List.to_string(prefix), else: prefix

        case File.ls(directory_path) do
          {:ok, files} ->
            images =
              files
              |> Enum.filter(&String.starts_with?(&1, prefix))
              |> Enum.filter(&String.ends_with?(&1, [".png", ".jpg", ".jpeg"]))

            if Enum.empty?(images) do
              "No images found in #{directory_path} with prefix '#{prefix}'"
            else
              "Available images in #{directory_path}:\n" <> Enum.join(images, "\n")
            end

          {:error, _} ->
            "Error: directory '#{directory_path}' not found or not accessible"
        end
      end
    }

    # Créer un sous-agent spécialisé en analyse d'images
    vision_agent =
      AgentConfig.new(
        name: :vision_analyst,
        instructions: """
        You are a specialized vision analysis agent with the following capabilities:
        - List available images in any directory using list_images tool (provide directory path and file prefix)
        - Generate captions for images using moondream_caption tool (provide full image path)
        - Answer questions about images using moondream_query tool (provide full image path and question)

        When asked to analyze images, you can:
        1. First list available images in a directory if needed (e.g., list_images.("/tmp/code_agent", "agent_image"))
        2. Select or use the specified image (use full path like "/tmp/code_agent/image.png")
        3. Generate captions and answer questions about the image
        """,
        tools: [list_images_tool, MoondreamTools.caption(), MoondreamTools.query()],
        max_steps: 5
      )

    task = """
    Use the vision_analyst agent to:
    1. List the available images in /tmp/code_agent that start with 'agent_image'
    2. If images are found, analyze a random one:
       - Generate a caption describing what's in the image
       - Ask a specific question about the image (e.g., "What colors are visible?")
    3. If no images are found, report that and suggest creating one first

    Hint: Enum.random select a random item in a List

    Provide a summary of the analysis.
    """

    config =
      AgentConfig.new(
        tools: [],
        managed_agents: [vision_agent],
        max_steps: 6
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test avec une tâche personnalisée.

  ## Exemples

      iex> CodeAgentMinimal.IexTest.test_custom("Calculate 10 + 5 * 2")
      iex> CodeAgentMinimal.IexTest.test_custom("Create a list [1,2,3,4,5] and sum it")
  """
  def test_custom(task, opts \\ []) do
    default_opts = [
      tools: [],
      max_steps: 5
    ]

    merged_opts = Keyword.merge(default_opts, opts)
    config = AgentConfig.new(merged_opts)

    IO.puts("\n📝 Test personnalisé")
    IO.puts(String.duplicate("=", 80))
    IO.puts("Tâche: #{task}\n")

    case CodeAgent.run(task, config) do
      {:ok, result, state} ->
        IO.puts("\n✅ Résultat: #{inspect(result)}")
        IO.puts("   Steps: #{state.current_step}/#{state.config.max_steps}")
        {:ok, result, state}

      {:error, reason, state} ->
        IO.puts("\n❌ Erreur: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  @doc """
  Test 13: Nested managed agents (agents imbriqués).

  Démontre la capacité d'un managed agent à utiliser d'autres managed agents.
  """
  def test13 do
    alias CodeAgentMinimal.{AgentConfig, Tools.PythonTools}

    # Niveau 2: Agent Python de base
    python_agent =
      AgentConfig.new(
        name: :python_executor,
        instructions: "Executes Python code for complex calculations",
        tools: [PythonTools.python_interpreter()],
        max_steps: 3
      )

    # Niveau 1: Agent mathématique qui peut utiliser Python
    math_agent =
      AgentConfig.new(
        name: :math_specialist,
        instructions:
          "Specialized in mathematical operations, can delegate complex calculations to Python",
        tools: [],
        managed_agents: [python_agent],
        max_steps: 5
      )

    task = """
    Use the math_specialist agent to calculate the sum of squares from 1 to 10.
    The math_specialist can delegate to python_executor if needed.
    Return the final result.
    """

    config =
      AgentConfig.new(
        tools: [],
        managed_agents: [math_agent],
        max_steps: 6
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 14: Génération d'un graphique pour une équation du second degré.

  Utilise Python pour tracer la courbe d'une équation ax² + bx + c et afficher ses racines.
  """
  def test14 do
    alias CodeAgentMinimal.{AgentConfig, Tools.PythonTools}

    # Créer le répertoire s'il n'existe pas
    File.mkdir_p!("/tmp/code_agent")

    # Créer un sous-agent spécialisé en Python avec matplotlib
    python_agent =
      AgentConfig.new(
        name: :python_plotter,
        instructions:
          "Specialized agent for creating mathematical plots using Python and matplotlib",
        tools: [PythonTools.python_interpreter()],
        max_steps: 5
      )

    task = """
    Use the python_plotter agent to create a graph for a quadratic equation (second degree equation).

    Equation: f(x) = x² - 4x + 3

    Requirements:
    1. Calculate the roots (solutions) of the equation using the quadratic formula: x = (-b ± √(b²-4ac)) / 2a
    2. Create a complete Python script that:
       - Imports numpy and matplotlib.pyplot
       - Calculates the discriminant and roots
       - Creates x values from -1 to 5 with numpy.linspace
       - Calculates y values: y = x**2 - 4*x + 3
       - Plots the parabola curve
       - Marks the roots with red dots ('ro', markersize=10, label='Roots')
       - Calculates and marks the vertex at x=-b/(2a) with a green dot ('go', markersize=10, label='Vertex')
       - Draws a horizontal line at y=0 (axhline(0, color='black', linewidth=0.5))
       - Adds grid (grid(True))
       - Labels axes (xlabel, ylabel)
       - Adds title "Quadratic Equation: f(x) = x² - 4x + 3"
       - Adds legend
       - Saves to '/tmp/code_agent/quadratic_equation.png' using plt.savefig()
       - Uses plt.close() after saving
    3. After running the code, verify the file exists and return its path with the roots and vertex coordinates

    IMPORTANT: Write the complete Python code in one execution. Make sure to use plt.savefig() before plt.close().
    """

    config =
      AgentConfig.new(
        tools: [],
        managed_agents: [python_agent],
        max_steps: 8
      )

    result = CodeAgent.run(task, config)

    # Vérifier si le fichier a été créé
    case result do
      {:ok, _result, _state} ->
        if File.exists?("/tmp/code_agent/quadratic_equation.png") do
          file_info = File.stat!("/tmp/code_agent/quadratic_equation.png")

          IO.puts(
            "\n✅ Image créée avec succès: /tmp/code_agent/quadratic_equation.png (#{file_info.size} bytes)"
          )
        else
          IO.puts("\n⚠️  L'agent a terminé mais le fichier n'a pas été trouvé")
        end

        result

      error ->
        error
    end
  end

  @doc """
  Test 15: Génération d'image avec l'API Hugging Face Inference.

  Utilise le nouveau tool text_to_image et response_format pour retourner un JSON structuré.
  """
  def test15 do
    alias CodeAgentMinimal.{AgentConfig, Tools.ImageTools}

    task = """
    Generate an image of a cute orange tabby cat sitting on a sunny windowsill, looking outside at birds.
    The image should be photorealistic and warm in tone.

    Use the text_to_image tool to generate the image.

    IMPORTANT: Return a JSON object with the following structure:
    {
      "success": true,
      "image_path": "/path/to/image.png",
      "prompt_used": "the prompt you used",
      "description": "brief description of what was generated"
    }

    If there was an error:
    {
      "success": false,
      "error": "error message"
    }
    """

    config =
      AgentConfig.new(
        tools: [ImageTools.text_to_image()],
        response_format: %{type: "json_object"},
        max_steps: 5
      )

    result = CodeAgent.run(task, config)

    # Afficher le résultat et parser le JSON
    case result do
      {:ok, final_result, _state} ->
        IO.puts("\n✅ Test terminé")
        IO.puts("Résultat brut: #{inspect(final_result)}")

        # Essayer de parser le JSON
        case Jason.decode(final_result) do
          {:ok, json_result} ->
            IO.puts("\n📋 JSON parsé:")
            IO.puts("  Success: #{json_result["success"]}")

            if json_result["success"] do
              IO.puts("  Image path: #{json_result["image_path"]}")
              IO.puts("  Prompt used: #{json_result["prompt_used"]}")
              IO.puts("  Description: #{json_result["description"]}")

              # Vérifier si le fichier existe
              if json_result["image_path"] && File.exists?(json_result["image_path"]) do
                file_info = File.stat!(json_result["image_path"])
                IO.puts("\n✅ Image vérifiée: #{file_info.size} bytes")
              else
                IO.puts("\n⚠️  Fichier image non trouvé à: #{json_result["image_path"]}")
              end
            else
              IO.puts("  Error: #{json_result["error"]}")
            end

          {:error, _reason} ->
            IO.puts("\n⚠️  Le résultat n'est pas un JSON valide")
            IO.puts("Résultat: #{final_result}")
        end

        result

      error ->
        IO.puts("\n❌ Erreur lors du test")
        error
    end
  end

  @doc """
  Test 16: Génération de vidéo avec l'API Hugging Face Inference.

  Utilise le tool text_to_video et response_format pour retourner un JSON structuré.
  """
  def test16 do
    alias CodeAgentMinimal.{AgentConfig, Tools.ImageTools}

    task = """
    Generate a short video of a cat walking on a sunny beach with waves in the background.
    The video should be photorealistic with smooth motion.

    Use the text_to_video tool to generate the video.

    IMPORTANT: Return a JSON object with the following structure:
    {
      "success": true,
      "video_path": "/path/to/video.mp4",
      "prompt_used": "the prompt you used",
      "description": "brief description of the video content",
      "duration": "estimated duration in seconds (if known)"
    }

    If there was an error:
    {
      "success": false,
      "error": "error message"
    }
    """

    config =
      AgentConfig.new(
        tools: [ImageTools.text_to_video()],
        response_format: %{type: "json_object"},
        max_steps: 5
      )

    result = CodeAgent.run(task, config)

    # Afficher le résultat et parser le JSON
    case result do
      {:ok, final_result, _state} ->
        IO.puts("\n✅ Test terminé")
        IO.puts("Résultat brut: #{inspect(final_result)}")

        # Essayer de parser le JSON
        case Jason.decode(final_result) do
          {:ok, json_result} ->
            IO.puts("\n📋 JSON parsé:")
            IO.puts("  Success: #{json_result["success"]}")

            if json_result["success"] do
              IO.puts("  Video path: #{json_result["video_path"]}")
              IO.puts("  Prompt used: #{json_result["prompt_used"]}")
              IO.puts("  Description: #{json_result["description"]}")

              if json_result["duration"] do
                IO.puts("  Duration: #{json_result["duration"]}s")
              end

              # Vérifier si le fichier existe
              if json_result["video_path"] && File.exists?(json_result["video_path"]) do
                file_info = File.stat!(json_result["video_path"])
                IO.puts("\n✅ Vidéo vérifiée: #{file_info.size} bytes")
              else
                IO.puts("\n⚠️  Fichier vidéo non trouvé à: #{json_result["video_path"]}")
              end
            else
              IO.puts("  Error: #{json_result["error"]}")
            end

          {:error, _reason} ->
            IO.puts("\n⚠️  Le résultat n'est pas un JSON valide")
            IO.puts("Résultat: #{final_result}")
        end

        result

      error ->
        IO.puts("\n❌ Erreur lors du test")
        error
    end
  end

  @doc """
  Test 17: Démonstration de continue_validation.

  Ce test montre comment utiliser le système de validation humaine (human-in-the-loop)
  avec require_validation: true sur l'agent principal.

  NOTE: Seul l'agent principal peut être validé. Les managed agents s'exécutent
  sans validation.

  ## Utilisation:

  1. Lancer le test:
     iex> {status, thought, code, state} = IexTest.test17()

  2. Le test retournera {:pending_validation, thought, code, state}

  3. Vous pouvez alors:
     - Approuver: CodeAgent.continue_validation(state, :approve)
     - Modifier: CodeAgent.continue_validation(state, {:modify, "nouveau_code"})
     - Donner feedback: CodeAgent.continue_validation(state, {:feedback, "suggestion"})
     - Rejeter: CodeAgent.continue_validation(state, :reject)

  ## Exemple complet:

      # Lancer le test
      iex> {status, thought, code, state} = IexTest.test17()
      # => {:pending_validation, "I need to...", "result = 10 + 20", %State{}}

      # Approuver l'exécution
      iex> CodeAgent.continue_validation(state, :approve)
      # => Continue et retourne {:ok, result, state} ou {:pending_validation, ...} si autre step

      # Ou modifier le code avant exécution
      iex> CodeAgent.continue_validation(state, {:modify, "result = 15 + 25"})
      # => Exécute le code modifié

      # Ou rejeter
      iex> CodeAgent.continue_validation(state, :reject)
      # => {:error, "Validation rejected by user", state}
  """
  def test17 do
    alias CodeAgentMinimal.{AgentConfig, Tools.PythonTools}

    IO.puts("""

    🔒 Test 17: Validation humaine (Human-in-the-loop)

    Ce test utilise require_validation sur l'agent principal.
    L'agent s'arrêtera et attendra votre validation avant d'exécuter du code.
    """)

    task = """
    Calculate the factorial of 5 using Python.

    Use the python_interpreter tool with Python's math.factorial function.

    Return the final result as a simple number.
    """

    config =
      AgentConfig.new(
        tools: [PythonTools.python_interpreter()],
        require_validation: true,
        max_steps: 5
      )

    IO.puts("\n📋 Task: Calculate factorial of 5 using Python")
    IO.puts("🔧 Config: require_validation = true on main agent\n")

    result = CodeAgent.run(task, config)

    case result do
      {:pending_validation, thought, code, state} ->
        IO.puts("""

        ⏸️  EXECUTION PAUSED - Validation Required

        Thought: #{thought}

        Code to execute:
        #{String.split(code, "\n") |> Enum.map(&("  " <> &1)) |> Enum.join("\n")}

        📝 To continue, use one of these commands:

        # Approve and execute
        CodeAgent.continue_validation(state, :approve)

        # Modify code before executing
        CodeAgent.continue_validation(state, {:modify, "your_modified_code"})

        # Give feedback without executing
        CodeAgent.continue_validation(state, {:feedback, "your feedback message"})

        # Reject and stop
        CodeAgent.continue_validation(state, :reject)

        The state variable is returned above: state = #{inspect(state |> Map.take([:current_step, :config]))}
        """)

        {:pending_validation, thought, code, state}

      {:ok, final_result, state} ->
        IO.puts("""

        ✅ Test completed without requiring validation
        Result: #{final_result}
        Steps: #{state.current_step}/#{state.config.max_steps}
        """)

        {:ok, final_result, state}

      {:error, reason, state} ->
        IO.puts("""

        ❌ Test failed
        Error: #{inspect(reason)}
        Steps: #{state.current_step}/#{state.config.max_steps}
        """)

        {:error, reason, state}
    end
  end

  @doc """
  Test rapide - alias pour test_custom.
  """
  def run(task, opts \\ []), do: test_custom(task, opts)

  @doc """
  Affiche les fonctions disponibles.
  """
  def help do
    IO.puts("""
    📚 CodeAgentMinimal.IexTest - Fonctions disponibles:

    ## Tests individuels (basiques)
    - test1()  - Calcul arithmétique simple
    - test2()  - Manipulation de listes
    - test3()  - Tools personnalisés
    - test4()  - Logique conditionnelle
    - test5()  - Tools multiples
    - test6()  - Data processing complexe
    - test7()  - Filtrage de données

    ## Tests avec managed agents
    - test8()   - Python interpreter
    - test9()   - Wikipedia search
    - test10()  - Finance tools
    - test11()  - FLUX image generation
    - test12()  - Moondream image analysis
    - test13()  - Nested managed agents (agents imbriqués)
    - test14()  - Graphique équation du second degré
    - test15()  - Génération d'image avec HF Inference API
    - test16()  - Génération de vidéo avec HF Inference API
    - test17()  - Validation humaine (Human-in-the-loop) sur agent principal

    ## Tests globaux
    - test_all()  - Lance tous les tests

    ## Tests personnalisés
    - test_custom("votre tâche")  - Test avec une tâche personnalisée
    - run("votre tâche")          - Alias pour test_custom

    ## Options pour test_custom
    - tools: [Tool.final_answer(), ...]
    - managed_agents: [agent1, agent2, ...]
    - max_steps: 10
    - model: "meta-llama/..."

    ## Exemples
        iex> IexTest.test1()
        iex> IexTest.test13()  # Agents imbriqués
        iex> IexTest.run("Calculate 5 * 5")
        iex> IexTest.test_custom("Sum [1,2,3]", max_steps: 3)
    """)
  end
end
