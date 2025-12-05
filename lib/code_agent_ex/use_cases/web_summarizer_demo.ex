defmodule CodeAgentEx.UseCases.WebSummarizerDemo do
  @moduledoc """
  Démonstrations et exemples d'utilisation du WebSummarizer.

  ## Utilisation dans IEx

      alias CodeAgentEx.UseCases.WebSummarizerDemo

      # Résumer une page simple
      WebSummarizerDemo.demo_single_page()

      # Résumer un site complet
      WebSummarizerDemo.demo_full_site()

      # Exemple personnalisé
      WebSummarizerDemo.summarize("https://your-url.com")
  """

  alias CodeAgentEx.UseCases.WebSummarizer
  require Logger

  @doc """
  Démo: résumer une seule page web.
  """
  def demo_single_page do
    Logger.info("🌐 Demo: Summarizing a single page (Elixir homepage)")

    case WebSummarizer.summarize_page("https://elixir-lang.org") do
      {:ok, summary} ->
        Logger.info("✅ Summary completed!")
        IO.puts("\n" <> String.duplicate("=", 80))
        IO.puts("SUMMARY")
        IO.puts(String.duplicate("=", 80))
        IO.puts(summary)
        IO.puts(String.duplicate("=", 80) <> "\n")
        {:ok, summary}

      {:error, error, _} ->
        Logger.error("❌ Failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Démo: résumer un site complet avec exploration de pages liées.
  """
  def demo_full_site do
    Logger.info("🌐 Demo: Analyzing full site (Elixir docs)")

    case WebSummarizer.summarize_site("https://hexdocs.pm/elixir", max_pages: 3) do
      {:ok, report} ->
        Logger.info("✅ Site analysis completed!")
        IO.puts("\n" <> String.duplicate("=", 80))
        IO.puts("SITE ANALYSIS REPORT")
        IO.puts(String.duplicate("=", 80))
        IO.puts(report)
        IO.puts(String.duplicate("=", 80) <> "\n")
        {:ok, report}

      {:error, error, _state} ->
        Logger.error("❌ Failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Résume une URL personnalisée.

  ## Exemples

      # Page simple
      summarize("https://example.com")

      # Site complet avec options
      summarize("https://example.com", type: :full_site, max_pages: 5)
  """
  def summarize(url, opts \\ []) do
    type = Keyword.get(opts, :type, :single_page)

    case type do
      :single_page ->
        Logger.info("📄 Summarizing single page: #{url}")
        WebSummarizer.summarize_page(url, Keyword.drop(opts, [:type]))

      :full_site ->
        Logger.info("🌐 Analyzing full site: #{url}")
        WebSummarizer.summarize_site(url, Keyword.drop(opts, [:type]))
    end
    |> handle_result()
  end

  @doc """
  Démo: comparer plusieurs pages.
  """
  def demo_compare_pages do
    Logger.info("📊 Demo: Comparing multiple pages")

    urls = [
      "https://elixir-lang.org",
      "https://www.phoenixframework.org",
      "https://hexdocs.pm/phoenix/overview.html"
    ]

    results =
      Enum.map(urls, fn url ->
        Logger.info("Fetching: #{url}")

        case WebSummarizer.summarize_page(url, max_steps: 3) do
          {:ok, summary} -> {url, summary}
          {:error, _, _} -> {url, "Failed to summarize"}
        end
      end)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("COMPARISON REPORT")
    IO.puts(String.duplicate("=", 80))

    Enum.each(results, fn {url, summary} ->
      IO.puts("\n## #{url}\n")
      IO.puts(String.slice(summary, 0, 300) <> "...\n")
    end)

    IO.puts(String.duplicate("=", 80) <> "\n")

    {:ok, results}
  end

  # Helpers

  defp handle_result({:ok, content}) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("RESULT")
    IO.puts(String.duplicate("=", 80))
    IO.puts(content)
    IO.puts(String.duplicate("=", 80) <> "\n")
    {:ok, content}
  end

  defp handle_result({:error, error, _} = result) do
    Logger.error("❌ Error: #{inspect(error)}")
    result
  end
end
