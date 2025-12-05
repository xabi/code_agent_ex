defmodule CodeAgentEx.UseCases.WebSummarizer do
  @moduledoc """
  Agent spécialisé pour explorer et résumer un site web et ses pages.

  Cet agent peut:
  - Récupérer le contenu d'une URL
  - Extraire les liens depuis une page
  - Résumer le contenu de plusieurs pages
  - Générer un rapport structuré sur un site web

  ## Exemple

      alias CodeAgentEx.UseCases.WebSummarizer

      # Résumer une seule page
      {:ok, summary} = WebSummarizer.summarize_page("https://example.com")

      # Résumer un site (page principale + liens)
      {:ok, report} = WebSummarizer.summarize_site("https://example.com", max_pages: 5)
  """

  alias CodeAgentEx.{CodeAgent, AgentConfig, Tool}
  alias CodeAgentEx.UseCases.UrlTracker

  @doc """
  Résume le contenu d'une seule page web.

  ## Arguments
  - `url` - L'URL de la page à résumer
  - `opts` - Options pour l'agent (model, max_steps, etc.)

  ## Exemple

      WebSummarizer.summarize_page("https://elixir-lang.org")
  """
  def summarize_page(url, opts \\ []) do
    tools = [
      fetch_url_tool(),
      Tool.final_answer()
    ]

    config =
      AgentConfig.new(
        Keyword.merge(
          [
            name: :page_summarizer,
            tools: tools,
            max_steps: 5,
            instructions: """
            You are a web content summarizer. Your task is to:
            1. Fetch the content from the given URL
            2. Analyze and summarize the main points
            3. Extract key information (title, main topics, important details)
            4. Format the summary in clear markdown
            """
          ],
          opts
        )
      )

    task = """
    Please fetch and summarize the content from this URL: #{url}

    Your summary should include:
    - The page title
    - Main topics or sections
    - Key information or takeaways
    - A brief conclusion (2-3 sentences)

    Format your answer in markdown.
    """

    case CodeAgent.run(task, config) do
      {:ok, result, _state} -> {:ok, result}
      error -> error
    end
  end

  @doc """
  Résume un site web complet (page principale + pages liées).

  ## Arguments
  - `url` - L'URL du site à explorer
  - `opts` - Options:
    - `:max_pages` - Nombre maximum de pages à explorer (défaut: 5)
    - `:model` - Modèle LLM à utiliser
    - `:max_steps` - Nombre maximum d'étapes (défaut: 15)

  ## Exemple

      WebSummarizer.summarize_site("https://elixir-lang.org", max_pages: 3)
  """
  def summarize_site(url, opts \\ []) do
    max_pages = Keyword.get(opts, :max_pages, 5)
    max_steps = Keyword.get(opts, :max_steps, 15)

    # Créer une session de tracking pour cette exploration
    session_id = UrlTracker.new_session()

    tools = [
      fetch_url_tool(session_id),
      extract_links_tool(),
      check_visited_tool(session_id),
      list_visited_tool(session_id),
      Tool.final_answer()
    ]

    config =
      AgentConfig.new(
        Keyword.merge(
          [
            name: :site_summarizer,
            tools: tools,
            max_steps: max_steps,
            instructions: """
            You are a comprehensive web site analyzer. Your task is to:
            1. Start with the main page
            2. Extract important links from the page
            3. Use check_visited to avoid visiting the same URL twice
            4. Fetch content from the most relevant unvisited linked pages
            5. Create a structured summary of the entire site

            IMPORTANT: Before fetching any URL, always check if it was already visited using check_visited.(url)

            Tools available:
            - fetch_url(url) - Fetches content and marks URL as visited
            - extract_links(url) - Extracts links from a page
            - check_visited(url) - Returns "true" if already visited, "false" otherwise
            - list_visited() - Lists all visited URLs

            Be strategic about which links to follow - prioritize:
            - Documentation pages
            - About/Features pages
            - Getting started guides
            - Main content sections

            Avoid:
            - URLs already visited (check with check_visited first!)
            - External links to other domains
            - Login/signup pages
            - Social media links
            """
          ],
          Keyword.drop(opts, [:max_pages])
        )
      )

    task = """
    Please analyze this website: #{url}

    Your task:
    1. Fetch the main page content
    2. Extract up to #{max_pages} most relevant internal links
    3. Fetch and analyze those linked pages
    4. Create a comprehensive summary report

    Your final report should include:
    ## Site Overview
    - Site name/title
    - Main purpose/description

    ## Main Page Summary
    - Key topics and information

    ## Linked Pages
    For each important page you explored:
    - Page title and URL
    - Brief summary of content
    - Key information

    ## Overall Insights
    - What is this site about?
    - Who is the target audience?
    - What are the main features/offerings?

    Format everything in clear markdown.
    """

    result =
      case CodeAgent.run(task, config) do
        {:ok, result, _state} -> {:ok, result}
        error -> error
      end

    # Nettoyer la session après utilisation
    UrlTracker.cleanup(session_id)

    result
  end

  # Tool pour récupérer le contenu d'une URL
  defp fetch_url_tool(session_id \\ nil) do
    %Tool{
      name: :fetch_url,
      description: """
      Fetches the content from a URL and returns the text content.
      Call with: fetch_url.(url)

      The content is cleaned and converted to markdown format for easy reading.
      """,
      inputs: %{
        "url" => %{type: "string", description: "The URL to fetch"}
      },
      output_type: "string",
      function: fn url ->
        url = normalize_string(url)

        # Marquer comme visitée si session active
        if session_id, do: UrlTracker.mark_visited(session_id, url)

        case Req.get(url, receive_timeout: 30_000) do
          {:ok, %{status: 200, body: body}} ->
            # Extraire le texte brut (simplification - pourrait utiliser Floki pour mieux parser)
            cleaned =
              body
              |> remove_html_tags()
              |> clean_whitespace()
              |> String.slice(0, 10_000)

            "✅ Content fetched from #{url} (marked as visited):\n\n#{cleaned}"

          {:ok, %{status: status}} ->
            "❌ Failed to fetch #{url}: HTTP #{status}"

          {:error, error} ->
            "❌ Error fetching #{url}: #{inspect(error)}"
        end
      end
    }
  end

  # Tool pour extraire les liens d'une page
  defp extract_links_tool do
    %Tool{
      name: :extract_links,
      description: """
      Extracts all internal links from a webpage.
      Call with: extract_links.(url)

      Returns a list of URLs found on the page (only same-domain links).
      """,
      inputs: %{
        "url" => %{type: "string", description: "The URL to extract links from"}
      },
      output_type: "string",
      function: fn url ->
        url = normalize_string(url)

        case Req.get(url, receive_timeout: 30_000) do
          {:ok, %{status: 200, body: body}} ->
            base_uri = URI.parse(url)

            links =
              body
              |> extract_href_attributes()
              |> Enum.map(&build_absolute_url(&1, base_uri))
              |> Enum.filter(&same_domain?(&1, base_uri))
              |> Enum.uniq()
              |> Enum.take(20)

            if Enum.empty?(links) do
              "No internal links found on #{url}"
            else
              "✅ Found #{length(links)} internal links on #{url}:\n\n" <>
                Enum.map_join(links, "\n", fn link -> "- #{link}" end)
            end

          {:ok, %{status: status}} ->
            "❌ Failed to fetch #{url}: HTTP #{status}"

          {:error, error} ->
            "❌ Error fetching #{url}: #{inspect(error)}"
        end
      end
    }
  end

  # Tool pour vérifier si une URL a déjà été visitée
  defp check_visited_tool(session_id) do
    %Tool{
      name: :check_visited,
      description: """
      Checks if a URL has already been visited in this session.
      Call with: check_visited.(url)

      Returns "true" if the URL was already visited, "false" otherwise.
      Use this BEFORE fetching a URL to avoid duplicate visits.
      """,
      inputs: %{
        "url" => %{type: "string", description: "The URL to check"}
      },
      output_type: "string",
      function: fn url ->
        url = normalize_string(url)

        if UrlTracker.visited?(session_id, url) do
          "true - URL #{url} was already visited"
        else
          "false - URL #{url} has not been visited yet"
        end
      end
    }
  end

  # Tool pour lister toutes les URLs visitées
  defp list_visited_tool(session_id) do
    %Tool{
      name: :list_visited,
      description: """
      Lists all URLs that have been visited in this session.
      Call with: list_visited.()

      Returns a formatted list of all visited URLs with count.
      """,
      inputs: %{},
      output_type: "string",
      function: fn ->
        visited = UrlTracker.list_visited(session_id)
        count = length(visited)

        if count == 0 do
          "No URLs visited yet in this session."
        else
          "✅ Visited #{count} URLs so far:\n\n" <>
            Enum.map_join(visited, "\n", fn url -> "- #{url}" end)
        end
      end
    }
  end

  # Helpers

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value) when is_list(value), do: List.to_string(value) |> String.trim()
  defp normalize_string(value), do: to_string(value) |> String.trim()

  defp remove_html_tags(html) do
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/s, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/s, "")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/&nbsp;/, " ")
    |> String.replace(~r/&amp;/, "&")
    |> String.replace(~r/&lt;/, "<")
    |> String.replace(~r/&gt;/, ">")
  end

  defp clean_whitespace(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp extract_href_attributes(html) do
    ~r/href=["']([^"']+)["']/
    |> Regex.scan(html)
    |> Enum.map(fn [_, href] -> href end)
  end

  defp build_absolute_url(href, base_uri) do
    case URI.parse(href) do
      %URI{scheme: nil, host: nil, path: path} when not is_nil(path) ->
        # Relative URL
        base_url = "#{base_uri.scheme}://#{base_uri.host}"
        base_url = if base_uri.port, do: "#{base_url}:#{base_uri.port}", else: base_url

        cond do
          String.starts_with?(path, "/") -> "#{base_url}#{path}"
          true -> "#{base_url}/#{path}"
        end

      %URI{scheme: scheme, host: host} when not is_nil(scheme) and not is_nil(host) ->
        # Absolute URL
        href

      _ ->
        nil
    end
  end

  defp same_domain?(nil, _base_uri), do: false

  defp same_domain?(url, base_uri) do
    %URI{host: host} = URI.parse(url)
    host == base_uri.host
  end
end
