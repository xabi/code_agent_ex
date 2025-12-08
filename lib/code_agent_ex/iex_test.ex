defmodule CodeAgentEx.IexTest do
  @moduledoc """
  Module de tests interactifs pour le CodeAgent, utilisable depuis iex.

  Tests basiques sans dépendances Python. Les tests utilisant Python, Wikipedia,
  Finance, Images, etc. ont été déplacés vers le projet code_agent_ex_tools séparé.

  ## Utilisation

  Dans iex:

      iex> CodeAgentEx.IexTest.test1()
      iex> CodeAgentEx.IexTest.test_all()
      iex> CodeAgentEx.IexTest.test_custom("Calculate 10 + 5")
  """

  alias CodeAgentEx.{CodeAgent, Tool, AgentConfig}
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
      {"Test 8: Managed agents", &test8/0},
      {"Test 9: AI-powered validation", &test9/0}
    ]

    results =
      Enum.map(tests, fn {name, test_fn} ->
        IO.puts("\n📝 #{name}")
        IO.puts(String.duplicate("=", 80))

        case test_fn.() do
          {:ok, result} ->
            IO.puts("✅ Résultat: #{inspect(result)}")
            :ok

          {:error, reason} ->
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
  Test 8: Managed agents (hierarchical delegation).
  """
  def test8 do
    # Create a specialized calculator sub-agent
    calculator = AgentConfig.new(
      name: :calculator,
      instructions: "You are a specialized calculator agent. Perform mathematical calculations accurately.",
      tools: [],
      max_steps: 3
    )

    # Create a specialized data processor sub-agent
    data_processor = AgentConfig.new(
      name: :data_processor,
      instructions: "You are a specialized data processing agent. Filter, transform, and analyze data.",
      tools: [],
      max_steps: 3
    )

    task = """
    Use the calculator agent to compute the sum of: 25, 48, 33, 67, 12.
    Then use the data_processor agent to find the largest number in that same list.
    Finally, return a string like: "Sum is X and largest number is Y"
    """

    config =
      AgentConfig.new(
        tools: [],
        managed_agents: [calculator, data_processor],
        max_steps: 8
      )

    CodeAgent.run(task, config)
  end

  @doc """
  Test 9: AI-powered validation (requires HF_TOKEN).

  Demonstrates AIValidator analyzing code before execution for:
  - Safety (no destructive operations)
  - Correctness (matches agent's intention)
  - Quality (clean, readable code)
  """
  def test9 do
    alias CodeAgentEx.{AIValidator, AgentOrchestrator}

    api_key = System.get_env("HF_TOKEN")

    if !api_key do
      IO.puts("\n❌ HF_TOKEN environment variable not set!")
      IO.puts("   Export your HuggingFace token to use AI validation.\n")
      {:error, :missing_api_key}
    else
      # Create AI validation handler (verbose mode to see decisions)
      validation_handler =
        AIValidator.create_handler(
          verbose: true,
          auto_approve_threshold: 70,
          api_key: api_key
        )

      config =
        AgentConfig.new(
          tools: [],
          max_steps: 5
        )

      task = """
      Calculate the average of the numbers: 15, 28, 42, 33, 19.
      Return the result as a formatted string like: "The average is X"
      """

      IO.puts("\n🤖 AI Validator will analyze each code execution\n")

      # Start orchestrator with AI validation
      {:ok, orch} = AgentOrchestrator.start_link(config, validation_handler: validation_handler)

      case AgentOrchestrator.run_task(orch, task) do
        {:ok, result} ->
          IO.puts("\n✅ Final Result: #{result}")
          IO.puts("\nThe AI validator analyzed all code executions for safety and correctness!\n")
          {:ok, result}

        {:error, reason} ->
          IO.puts("\n❌ Error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Test custom avec une tâche personnalisée.
  """
  def test_custom(task, opts \\ []) do
    default_opts = [
      tools: [],
      max_steps: 5
    ]

    merged_opts = Keyword.merge(default_opts, opts)
    config = AgentConfig.new(merged_opts)
    CodeAgent.run(task, config)
  end

  @doc """
  Helper pour exécuter une tâche simple.
  """
  def run(task, opts \\ []) do
    test_custom(task, opts)
  end
end
