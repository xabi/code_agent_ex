defmodule CodeAgentMinimal.Test do
  @moduledoc """
  Tests pour le CodeAgent.

  Utilisation dans iex:

      CodeAgentMinimal.Test.run_all()
      CodeAgentMinimal.Test.test_simple_calc()
      CodeAgentMinimal.Test.test_with_tool()
      CodeAgentMinimal.Test.test_list_manipulation()
  """

  alias CodeAgentMinimal.CodeAgent
  alias CodeAgentMinimal.Tool
  alias CodeAgentMinimal.Tools.WikipediaTools
  alias CodeAgentMinimal.Tools.ImageTools
  alias CodeAgentMinimal.Tools.MoondreamTools
  alias CodeAgentMinimal.AgentConfig
  require Logger

  @doc """
  Lance tous les tests.
  """
  def run_all do
    IO.puts("🤖 CodeAgent Tests\n")

    tests = [
      {"Simple calculation", &test_simple_calc/0},
      {"With calculator tool", &test_with_tool/0},
      {"List manipulation", &test_list_manipulation/0}
    ]

    results =
      Enum.map(tests, fn {name, test_fn} ->
        IO.puts("📝 #{name}")
        IO.puts(String.duplicate("=", 60))

        result = test_fn.()

        case result do
          {:ok, value, _state} ->
            IO.puts("✅ Résultat: #{inspect(value)}\n")
            :ok

          {:error, reason, _state} ->
            IO.puts("❌ Erreur: #{inspect(reason)}\n")
            :error
        end
      end)

    passed = Enum.count(results, &(&1 == :ok))
    total = length(results)

    IO.puts("#{String.duplicate("=", 60)}")
    IO.puts("📊 Résultat: #{passed}/#{total} tests passés")

    if passed == total, do: :ok, else: :error
  end

  @doc """
  Test: Calcul simple avec persistance de variables.
  """
  def test_simple_calc do
    task = "Calculate 25 * 4, then add 10 to the result."

    config = AgentConfig.new(
      tools: [Tool.final_answer()],
      max_steps: 5
    )

    CodeAgent.run(task, config)
  end

  @doc """
  Test: Calcul multi-étapes en Elixir natif.
  """
  def test_with_tool do
    task = "Compute 123 + 456, then multiply that result by 2"

    config = AgentConfig.new(
      tools: [Tool.final_answer()],
      max_steps: 5
    )

    CodeAgent.run(task, config)
  end

  @doc """
  Test: Manipulation de listes.
  """
  def test_list_manipulation do
    task = "Create a list of numbers from 1 to 5, calculate their sum, and return the average"

    config = AgentConfig.new(
      tools: [Tool.final_answer()],
      max_steps: 5
    )

    CodeAgent.run(task, config)
  end

  @doc """
  Test: Vérifie que le code dangereux est bloqué.
  """
  def test_security do
    task = "Execute the shell command 'ls -la' using System.cmd"

    config = AgentConfig.new(
      tools: [Tool.final_answer()],
      max_steps: 3
    )

    case CodeAgent.run(task, config) do
      {:error, "Code contains potentially dangerous operations", _state} ->
        IO.puts("✅ Sécurité OK: code dangereux bloqué")
        :ok

      {:ok, _, _state} ->
        IO.puts("❌ Sécurité FAIL: code dangereux exécuté!")
        :error

      {:error, _, _state} ->
        IO.puts("✅ Sécurité OK: exécution échouée")
        :ok
    end
  end

  @doc """
  Test: Recherche Wikipedia.
  """
  def test_wikipedia do
    task = "Search Wikipedia for 'Elixir programming language' and give me a brief summary of what you find"

    config = AgentConfig.new(
      tools: WikipediaTools.all_tools(),
      max_steps: 6
    )

    CodeAgent.run(task, config)
  end

  @doc """
  Test: Téléchargement et info d'une image.
  """
  def test_image do
    task = "Download the image from 'https://httpbin.org/image/png' and get its info"

    config = AgentConfig.new(
      tools: ImageTools.all_tools(),
      max_steps: 6
    )

    CodeAgent.run(task, config)
  end

  @doc """
  Test: Téléchargement et description d'une image avec Moondream.
  """
  def test_moondream do
    task = "Download the image from 'https://httpbin.org/image/jpeg' and use moondream_caption to describe what you see in the image"

    # Combiner ImageTools (pour download) et MoondreamTools (pour caption)
    tools =
      [ImageTools.download_image()] ++
      MoondreamTools.basic_tools()

    config = AgentConfig.new(
      tools: tools,
      max_steps: 6
    )

    CodeAgent.run(task, config)
  end

  @doc """
  Test: Recherche Wikipedia, récupération d'images et description avec Moondream.
  """
  def test_wikipedia_images(subject \\ "Eiffel Tower") do
    task = """
    1. Search Wikipedia for '#{subject}' and get the page content
    2. Use web_get_images to find image URLs from the Wikipedia page
    3. Download the first image found using download_image
    4. Use moondream_caption to describe what you see in the image
    5. Return a summary with the Wikipedia info and the image description
    """

    tools =
      WikipediaTools.all_tools() ++
      [web_get_images_tool()] ++
      [ImageTools.download_image()] ++
      [MoondreamTools.caption()] ++
      [Tool.final_answer()]

    config = AgentConfig.new(
      tools: tools,
      max_steps: 10
    )

    CodeAgent.run(task, config)
  end

  # Tool pour extraire les URLs d'images d'une page web
  defp web_get_images_tool do
    %CodeAgentMinimal.Tool{
      name: "web_get_images",
      description: "Fetches a webpage and extracts all image URLs from it. Call with: web_get_images.(url)",
      inputs: %{
        "url" => %{type: "string", description: "URL of the webpage to extract images from"}
      },
      output_type: "string",
      function: &do_web_get_images/1
    }
  end

  defp do_web_get_images(url) do
    url = if is_list(url), do: List.to_string(url), else: url

    case Req.get(url) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        # Extraire les URLs d'images avec regex
        image_regex = ~r/(?:src|href)=["']([^"']+\.(?:jpg|jpeg|png|gif|webp|svg))["']/i

        images =
          Regex.scan(image_regex, body)
          |> Enum.map(fn [_, img_url] ->
            # Convertir les URLs relatives en absolues
            if String.starts_with?(img_url, "//") do
              "https:" <> img_url
            else if String.starts_with?(img_url, "/") do
              uri = URI.parse(url)
              "#{uri.scheme}://#{uri.host}#{img_url}"
            else
              img_url
            end
            end
          end)
          |> Enum.uniq()
          |> Enum.take(10)

        if Enum.empty?(images) do
          "No images found on the page"
        else
          "Found #{length(images)} images:\n" <> Enum.join(images, "\n")
        end

      {:ok, %{status: status}} ->
        "Error fetching page: HTTP #{status}"

      {:error, reason} ->
        "Error: #{inspect(reason)}"
    end
  end

  @doc """
  Test: Utilisation de managed agents.

  Un agent principal délègue la recherche Wikipedia à un sous-agent spécialisé.
  """
  def test_managed_agents do
    # Créer un agent spécialisé pour la recherche Wikipedia
    wiki_agent = AgentConfig.new(
      name: "wiki_researcher",
      instructions: "Specialized agent for searching and reading Wikipedia articles",
      tools: WikipediaTools.all_tools(),
      max_steps: 4
    )

    # Tâche pour l'agent principal
    task = "Use the wiki_researcher agent to find information about 'Elixir programming language' and summarize the key points"

    config = AgentConfig.new(
      tools: [Tool.final_answer()],
      managed_agents: [wiki_agent],
      max_steps: 6
    )

    CodeAgent.run(task, config)
  end

  @doc """
  Test: Multiple managed agents.

  Un agent principal orchestre plusieurs sous-agents spécialisés.
  """
  def test_multi_agents do
    # Agent pour la recherche Wikipedia
    wiki_agent = AgentConfig.new(
      name: "wiki_researcher",
      instructions: "Searches and reads Wikipedia articles",
      tools: WikipediaTools.all_tools(),
      max_steps: 4
    )

    # Agent pour le calcul
    calc_agent = AgentConfig.new(
      name: "calculator",
      instructions: "Performs mathematical calculations using Elixir",
      tools: [Tool.final_answer()],
      max_steps: 3
    )

    task = """
    1. Use wiki_researcher to find the height of the Eiffel Tower in meters
    2. Use calculator to convert that height to feet (multiply by 3.28084)
    3. Return both values
    """

    config = AgentConfig.new(
      tools: [Tool.final_answer()],
      managed_agents: [wiki_agent, calc_agent],
      max_steps: 8
    )

    CodeAgent.run(task, config)
  end

  @doc """
  Test custom avec une tâche personnalisée.
  """
  def test_custom(task, opts \\ []) do
    default_opts = [
      tools: [Tool.final_answer()],
      max_steps: 5
    ]

    merged_opts = Keyword.merge(default_opts, opts)
    config = AgentConfig.new(merged_opts)
    CodeAgent.run(task, config)
  end
end
