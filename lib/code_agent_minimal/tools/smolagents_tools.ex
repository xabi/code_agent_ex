defmodule CodeAgentMinimal.Tools.SmolAgentsTools do
  @moduledoc """
  Tools utilisant smolagents via Pythonx pour le CodeAgent.

  Permet d'accéder à DuckDuckGo search et aux Hugging Face Spaces.
  """

  require Logger
  alias CodeAgentMinimal.AgentTypes.AgentImage

  @doc """
  Tool de recherche web avec DuckDuckGo.
  """
  def web_search do
    %CodeAgentMinimal.Tool{
      name: :web_search,
      description: "Searches the web using DuckDuckGo and returns relevant results. Call with: tools.web_search.(query) or web_search.(query, max_results)",
      inputs: %{
        "query" => %{type: "string", description: "Search query"}
      },
      output_type: "string",
      function: &do_web_search/1
    }
  end

  defp do_web_search(query) do
    query = normalize_arg(query)
    max_results = 10

    python_code = """
    from smolagents import WebSearchTool

    try:
        query_str = query.decode('utf-8') if isinstance(query, bytes) else query
        search_tool = WebSearchTool(max_results=max_results)
        results = search_tool(query_str)
        output = ("ok", results)
    except Exception as e:
        output = ("error", str(e))

    output
    """

    try do
      {result, _globals} = Pythonx.eval(python_code, %{
        "query" => query,
        "max_results" => max_results
      })

      case Pythonx.decode(result) do
        {"ok", results} ->
          Logger.info("[SmolAgentsTools] ✅ Web search completed")
          results

        {"error", error_msg} ->
          "Error searching: #{error_msg}"
      end
    rescue
      error -> "Pythonx error: #{inspect(error)}"
    end
  end

  @doc """
  Tool de génération d'images avec FLUX.
  """
  def flux_image do
    %CodeAgentMinimal.Tool{
      name: :generate_flux_image,
      description: "Generates an image using FLUX.1-schnell via HF Space. Call with: tools.generate_flux_image.(prompt)",
      inputs: %{
        "prompt" => %{type: "string", description: "Description of the image to generate"}
      },
      output_type: "AgentImage",
      function: &do_generate_flux/1
    }
  end

  defp do_generate_flux(prompt) do
    prompt = normalize_arg(prompt)

    python_code = """
    from gradio_client import Client
    import base64
    from io import BytesIO

    try:
        prompt_str = prompt.decode('utf-8')

        # Utiliser directement gradio_client sans smolagents
        client = Client("black-forest-labs/FLUX.1-schnell")
        result = client.predict(
            prompt=prompt_str,
            api_name="/infer"
        )

        # L'API retourne un tuple (image_path, seed) - on prend le premier élément
        image_path = result[0] if isinstance(result, tuple) else result

        if image_path:
            # Lire le fichier image
            from PIL import Image
            pil_image = Image.open(image_path)

            buffer = BytesIO()
            pil_image.save(buffer, format='PNG')
            img_bytes = buffer.getvalue()

            output = ("ok", img_bytes)
        else:
            output = ("error", "No image generated")

    except Exception as e:
        output = ("error", str(e))

    output
    """

    try do
      {result, _globals} = Pythonx.eval(python_code, %{"prompt" => prompt})

      case Pythonx.decode(result) do
        {"ok", image_bytes} when is_binary(image_bytes) ->
          Logger.info("[SmolAgentsTools] ✅ FLUX image generated")
          # Créer un AgentImage
          case AgentImage.from_binary(image_bytes, "png") do
            %AgentImage{} = img ->
              img
            {:error, reason} ->
              "Error saving image: #{reason}"
          end

        {"error", error_msg} ->
          "Error generating image: #{error_msg}"

        other ->
          "Unexpected result: #{inspect(other)}"
      end
    rescue
      error -> "Pythonx error: #{inspect(error)}"
    end
  end

  @doc """
  Tool générique pour créer un tool depuis un HF Space.
  """
  def from_space(space_id, name \\ nil, description \\ nil) do
    actual_name = name || "space_#{String.replace(space_id, "/", "_")}"
    actual_desc = description || "Tool from HF Space #{space_id}"

    %CodeAgentMinimal.Tool{
      name: actual_name,
      description: "#{actual_desc}. Call with: #{actual_name}.(input)",
      inputs: %{
        "input" => %{type: "string", description: "Input for the Space"}
      },
      output_type: "string",
      function: fn input ->
        do_call_space(space_id, actual_name, actual_desc, input)
      end
    }
  end

  defp do_call_space(space_id, tool_name, tool_desc, input) do
    input = normalize_arg(input)

    python_code = """
    from smolagents import Tool
    import json

    try:
        input_str = input_data.decode('utf-8')

        space_tool = Tool.from_space(
            space_id=space_id,
            name=tool_name,
            description=tool_description
        )

        # Try to parse as JSON, else use as text
        try:
            inputs_data = json.loads(input_str)
            if isinstance(inputs_data, dict):
                result = space_tool(**inputs_data)
            else:
                result = space_tool(inputs_data)
        except json.JSONDecodeError:
            result = space_tool(input_str)

        output = ("ok", str(result))

    except Exception as e:
        output = ("error", str(e))

    output
    """

    try do
      {result, _globals} = Pythonx.eval(python_code, %{
        "space_id" => space_id,
        "tool_name" => tool_name,
        "tool_description" => tool_desc,
        "input_data" => input
      })

      case Pythonx.decode(result) do
        {"ok", message} ->
          Logger.info("[SmolAgentsTools] ✅ Space #{space_id} executed")
          message

        {"error", error_msg} ->
          "Error from Space: #{error_msg}"
      end
    rescue
      error -> "Pythonx error: #{inspect(error)}"
    end
  end

  @doc """
  Tool pour visiter une page web et retourner son contenu en markdown.
  """
  def visit_webpage do
    %CodeAgentMinimal.Tool{
      name: "visit_webpage",
      description: "Visits a webpage at the given URL and returns its content as markdown. Call with: tools.visit_webpage.(url)",
      inputs: %{
        "url" => %{type: "string", description: "The URL of the webpage to visit"}
      },
      output_type: "string",
      function: &do_visit_webpage/1
    }
  end

  defp do_visit_webpage(url) do
    url = normalize_arg(url)

    python_code = """
    import re
    import requests
    from markdownify import markdownify
    from requests.exceptions import RequestException

    try:
        url_str = url.decode('utf-8') if isinstance(url, bytes) else url

        # Send a GET request to the URL
        response = requests.get(url_str, timeout=30)
        response.raise_for_status()

        # Convert the HTML content to Markdown
        markdown_content = markdownify(response.text).strip()

        # Remove multiple line breaks
        markdown_content = re.sub(r"\\n{3,}", "\\n\\n", markdown_content)

        # Limit content length to avoid huge responses
        if len(markdown_content) > 10000:
            markdown_content = markdown_content[:10000] + "\\n\\n... (content truncated)"

        output = ("ok", markdown_content)
    except RequestException as e:
        output = ("error", f"Error fetching the webpage: {str(e)}")
    except Exception as e:
        output = ("error", f"An unexpected error occurred: {str(e)}")

    output
    """

    try do
      {result, _globals} = Pythonx.eval(python_code, %{"url" => url})

      case Pythonx.decode(result) do
        {"ok", content} ->
          Logger.info("[SmolAgentsTools] ✅ Webpage fetched: #{String.slice(url, 0, 50)}...")
          content

        {"error", error_msg} ->
          "Error: #{error_msg}"
      end
    rescue
      error -> "Pythonx error: #{inspect(error)}"
    end
  end

  @doc """
  Retourne les tools de recherche.
  """
  def search_tools do
    [
      web_search(),
      visit_webpage()
    ]
  end

  @doc """
  Retourne les tools d'image + final_answer.
  """
  def image_tools do
    [
      flux_image(),
      CodeAgentMinimal.Tool.final_answer()
    ]
  end

  @doc """
  Retourne tous les tools smolagents + final_answer.
  """
  def all_tools do
    [
      web_search(),
      flux_image(),
      CodeAgentMinimal.Tool.final_answer()
    ]
  end

  # Normalise les charlists en binaries
  defp normalize_arg(arg) when is_list(arg), do: List.to_string(arg)
  defp normalize_arg(arg), do: arg
end
