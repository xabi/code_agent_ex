#!/usr/bin/env elixir

# Test du CodeAgent minimal avec cas d'usage réels

Application.ensure_all_started(:code_agent_minimal)

alias CodeAgentMinimal.CodeAgent
alias CodeAgentMinimal.Tool

IO.puts("🤖 Test CodeAgent Minimal - Suite de tests complète\n")

# ============================================================================
# Test 1: Calcul mathématique simple
# ============================================================================
IO.puts("📝 Test 1: Calcul arithmétique simple")
IO.puts("=" |> String.duplicate(80))

task1 = "Calculate 25 * 4, then add 10 to the result"

case CodeAgent.run(task1, tools: [Tool.final_answer()], max_steps: 5) do
  {:ok, result} ->
    IO.puts("✅ Résultat: #{inspect(result)}")

  {:error, reason} ->
    IO.puts("❌ Erreur: #{inspect(reason)}")
end

# ============================================================================
# Test 2: Manipulation de listes
# ============================================================================
IO.puts("\n📝 Test 2: Manipulation de listes et moyenne")
IO.puts("=" |> String.duplicate(80))

task2 = """
Create a list of numbers from 1 to 10.
Calculate the sum of all numbers.
Then calculate and return the average as a float.
"""

case CodeAgent.run(task2, tools: [Tool.final_answer()], max_steps: 5) do
  {:ok, result} ->
    IO.puts("✅ Résultat: #{inspect(result)} (attendu: 5.5)")

  {:error, reason} ->
    IO.puts("❌ Erreur: #{inspect(reason)}")
end

# ============================================================================
# Test 3: Utilisation de tools personnalisés
# ============================================================================
IO.puts("\n📝 Test 3: Tools personnalisés - Données utilisateur")
IO.puts("=" |> String.duplicate(80))

# Définir un tool qui fournit des données
user_data_tool = %{
  name: "get_user_data",
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

task3 = """
Get the user data using get_user_data.
Calculate the average of their test scores.
Return a formatted string like: "Alice (30 years old) has an average score of X"
"""

case CodeAgent.run(task3, tools: [user_data_tool, Tool.final_answer()], max_steps: 5) do
  {:ok, result} ->
    IO.puts("✅ Résultat: #{result}")

  {:error, reason} ->
    IO.puts("❌ Erreur: #{inspect(reason)}")
end

# ============================================================================
# Test 4: Logique conditionnelle
# ============================================================================
IO.puts("\n📝 Test 4: Logique conditionnelle")
IO.puts("=" |> String.duplicate(80))

task4 = """
Calculate 15 multiplied by 3.
If the result is greater than 40, return the string "HIGH".
Otherwise, return the string "LOW".
"""

case CodeAgent.run(task4, tools: [Tool.final_answer()], max_steps: 5) do
  {:ok, result} ->
    IO.puts("✅ Résultat: #{inspect(result)} (attendu: \"HIGH\" car 15*3=45>40)")

  {:error, reason} ->
    IO.puts("❌ Erreur: #{inspect(reason)}")
end

# ============================================================================
# Test 5: Tools multiples - Conversion de température
# ============================================================================
IO.puts("\n📝 Test 5: Combinaison de plusieurs tools")
IO.puts("=" |> String.duplicate(80))

temperature_tool = %{
  name: "get_temperature",
  description: "Returns the current temperature in Celsius",
  inputs: %{},
  output_type: "number",
  function: fn -> 25 end
}

convert_tool = %{
  name: "celsius_to_fahrenheit",
  description: "Converts temperature from Celsius to Fahrenheit. Takes one argument: celsius (number)",
  inputs: %{
    "celsius" => %{type: "number", description: "Temperature in Celsius"}
  },
  output_type: "number",
  function: fn celsius -> celsius * 9 / 5 + 32 end
}

task5 = """
Get the current temperature in Celsius using get_temperature.
Convert it to Fahrenheit using celsius_to_fahrenheit.
Return a formatted string like: "The temperature is X°C (Y°F)"
"""

case CodeAgent.run(task5, tools: [temperature_tool, convert_tool, Tool.final_answer()], max_steps: 8) do
  {:ok, result} ->
    IO.puts("✅ Résultat: #{result}")

  {:error, reason} ->
    IO.puts("❌ Erreur: #{inspect(reason)}")
end

# ============================================================================
# Test 6: Data processing complexe
# ============================================================================
IO.puts("\n📝 Test 6: Traitement de données complexe - Analyse de ventes")
IO.puts("=" |> String.duplicate(80))

sales_data_tool = %{
  name: "get_sales_data",
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

task6 = """
Get the sales data using get_sales_data.
For each product, calculate the total revenue (quantity * unit_price).
Find the product with the highest total revenue.
Return a string like: "Product X generated the most revenue: $Y"
"""

case CodeAgent.run(task6, tools: [sales_data_tool, Tool.final_answer()], max_steps: 8) do
  {:ok, result} ->
    IO.puts("✅ Résultat: #{result}")
    IO.puts("   (attendu: Laptop avec $60000)")

  {:error, reason} ->
    IO.puts("❌ Erreur: #{inspect(reason)}")
end

# ============================================================================
# Test 7: Continuation de conversation
# ============================================================================
IO.puts("\n📝 Test 7: Continuation de conversation avec contexte")
IO.puts("=" |> String.duplicate(80))

task7a = "Calculate 10 + 5 and return the result"

case CodeAgent.run(task7a, tools: [Tool.final_answer()], max_steps: 5) do
  {:ok, result1, state1} ->
    IO.puts("✅ Première tâche: #{inspect(result1)}")

    # Continuer avec le contexte
    task7b = "Now multiply the previous result by 3"

    case CodeAgent.run(task7b, tools: [Tool.final_answer()], state: state1, max_steps: 5) do
      {:ok, result2, state2} ->
        IO.puts("✅ Deuxième tâche: #{inspect(result2)}")
        IO.puts("   Total steps dans la conversation: #{CodeAgentMinimal.Memory.count(state2.memory)}")

      {:error, reason, _} ->
        IO.puts("❌ Erreur dans la continuation: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("❌ Erreur: #{inspect(reason)}")
end

# ============================================================================
# Test 8: Filtrage et transformation de données
# ============================================================================
IO.puts("\n📝 Test 8: Filtrage et transformation de données")
IO.puts("=" |> String.duplicate(80))

employee_data_tool = %{
  name: "get_employees",
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

task8 = """
Get the employee data using get_employees.
Filter only employees from the Engineering department.
Calculate the average salary for Engineering employees.
Return a string like: "Engineering has X employees with average salary $Y"
"""

case CodeAgent.run(task8, tools: [employee_data_tool, Tool.final_answer()], max_steps: 8) do
  {:ok, result} ->
    IO.puts("✅ Résultat: #{result}")
    IO.puts("   (attendu: 3 employés avec salaire moyen $86000)")

  {:error, reason} ->
    IO.puts("❌ Erreur: #{inspect(reason)}")
end

# ============================================================================
# Résumé final
# ============================================================================
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("✅ Suite de tests complète terminée!")
IO.puts("\nPour lancer ces tests:")
IO.puts("  export HF_TOKEN=your_huggingface_token")
IO.puts("  ./test_code_agent.exs")
IO.puts(String.duplicate("=", 80))
