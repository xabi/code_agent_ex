defmodule CodeAgentMinimal.Tools.WikipediaTools do
  @moduledoc """
  Tools Wikipedia adaptés pour le CodeAgent.
  """

  @doc """
  Tool de recherche Wikipedia.
  """
  def wikipedia_search do
    %CodeAgentMinimal.Tool{
      name: :wikipedia_search,
      description: "Searches Wikipedia for page suggestions matching a query. Returns a list of matching page titles. Call with: wikipedia_search.(query) or wikipedia_search.(query, language, results)",
      inputs: %{
        "query" => %{type: "string", description: "Search term to find on Wikipedia"}
      },
      output_type: "string",
      function: &do_wikipedia_search/1
    }
  end

  defp do_wikipedia_search(query) do
    language = "en"
    results = 5

    python_code = """
    import wikipedia

    try:
        language = language.decode('utf-8')
        query = query.decode('utf-8')

        wikipedia.set_lang(language)
        suggestions = wikipedia.search(query, results=max_results)

        if suggestions:
            result = f"Wikipedia suggestions for '{query}':\\n"
            for i, suggestion in enumerate(suggestions, 1):
                result += f"{i}. {suggestion}\\n"
        else:
            result = f"No suggestions found for '{query}'"

        output = ("ok", str(result))
    except Exception as e:
        output = ("error", str(e))

    output
    """

    try do
      {result, _globals} = Pythonx.eval(python_code, %{
        "language" => language,
        "query" => query,
        "max_results" => results
      })

      case Pythonx.decode(result) do
        {"ok", message} -> message
        {"error", error_msg} -> "Error: #{error_msg}"
      end
    rescue
      error -> "Pythonx error: #{inspect(error)}"
    end
  end

  @doc """
  Tool de lecture de page Wikipedia.
  """
  def wikipedia_page do
    %CodeAgentMinimal.Tool{
      name: "wikipedia_page",
      description: "Reads the full content of a Wikipedia page and converts it to Markdown. Use wikipedia_search first to find the exact title.",
      inputs: %{
        "title" => %{type: "string", description: "Exact title of the Wikipedia page to read"}
      },
      output_type: "string",
      function: &do_wikipedia_page/1
    }
  end

  defp do_wikipedia_page(args) when is_map(args) do
    title = args["title"] || ""
    do_wikipedia_page_impl(title)
  end

  defp do_wikipedia_page(title) when is_binary(title) do
    do_wikipedia_page_impl(title)
  end

  defp do_wikipedia_page_impl(title) do
    language = "en"

    python_code = """
    import wikipedia
    from markdownify import markdownify as md

    try:
        language = language.decode('utf-8')
        page_title = page_title.decode('utf-8')

        wikipedia.set_lang(language)
        page = wikipedia.page(page_title)

        # Get full content and convert to Markdown
        content = page.content
        markdown_content = md(content, heading_style="ATX")

        result = f"# {page.title}\\n\\n"
        result += f"**URL:** {page.url}\\n\\n"
        result += markdown_content

        output = ("ok", str(result))

    except wikipedia.exceptions.DisambiguationError as e:
        options_str = ', '.join(e.options[:5])
        error_msg = f"Multiple pages match '{page_title}'. Options: {options_str}"
        output = ("error", str(error_msg))

    except wikipedia.exceptions.PageError:
        error_msg = f"No page found for '{page_title}'. Use wikipedia_search first."
        output = ("error", str(error_msg))

    except Exception as e:
        output = ("error", str(e))

    output
    """

    try do
      {result, _globals} = Pythonx.eval(python_code, %{
        "language" => language,
        "page_title" => title
      })

      case Pythonx.decode(result) do
        {"ok", message} -> message
        {"error", error_msg} -> "Error: #{error_msg}"
      end
    rescue
      error -> "Pythonx error: #{inspect(error)}"
    end
  end

  @doc """
  Retourne tous les tools Wikipedia + final_answer.
  """
  def all_tools do
    [
      wikipedia_search(),
      wikipedia_page(),
      CodeAgentMinimal.Tool.final_answer()
    ]
  end
end
