defmodule CodeAgentMinimal.Tools.MoondreamTools do
  @moduledoc """
  Outils d'analyse d'images utilisant l'API Moondream pour le CodeAgent.

  Ces outils utilisent des paths de fichiers images directement.
  """

  require Logger

  @doc """
  Tool de génération de légende pour une image.
  """
  def caption do
    %CodeAgentMinimal.Tool{
      name: :moondream_caption,
      description: "Generates a descriptive caption for an image. Call with: moondream_caption.(image_path)",
      inputs: %{
        "image_path" => %{type: "string", description: "Path to the image file"}
      },
      output_type: "string",
      function: fn image_path -> do_caption(image_path, "normal") end
    }
  end

  defp do_caption(image_path, length) do
    image_path = normalize_arg(image_path)
    length = normalize_arg(length)

    case read_image_as_base64(image_path) do
      {:ok, image_base64} ->
        with {:ok, client} <- CodeAgentMinimal.MoondreamApi.new(),
             {:ok, image_binary} <- Base.decode64(image_base64),
             {:ok, image_url} <- CodeAgentMinimal.MoondreamApi.binary_to_image_url(image_binary),
             {:ok, result} <- CodeAgentMinimal.MoondreamApi.caption(client, image_url, length: length) do
          caption = Map.get(result, "caption", "No caption generated")
          Logger.info("[MoondreamTools] ✅ Caption generated")
          "Caption: #{caption}"
        else
          {:error, :missing_api_key} ->
            "Error: Moondream API key missing. Set MOONDREAM_API_KEY environment variable."

          {:error, reason} ->
            "Error generating caption: #{inspect(reason)}"
        end

      {:error, reason} ->
        "Error: #{reason}"
    end
  end

  @doc """
  Tool de question-réponse sur une image.
  """
  def query do
    %CodeAgentMinimal.Tool{
      name: :moondream_query,
      description: "Answers a specific question about an image. Call with: moondream_query.(image_path, question)",
      inputs: %{
        "image_path" => %{type: "string", description: "Path to the image file"},
        "question" => %{type: "string", description: "Question to ask about the image"}
      },
      output_type: "string",
      function: &do_query/2
    }
  end

  defp do_query(image_path, question) do
    image_path = normalize_arg(image_path)
    question = normalize_arg(question)

    case read_image_as_base64(image_path) do
      {:ok, image_base64} ->
        with {:ok, client} <- CodeAgentMinimal.MoondreamApi.new(),
             {:ok, image_binary} <- Base.decode64(image_base64),
             {:ok, image_url} <- CodeAgentMinimal.MoondreamApi.binary_to_image_url(image_binary),
             {:ok, result} <- CodeAgentMinimal.MoondreamApi.query(client, image_url, question) do
          answer = Map.get(result, "answer", "No answer available")
          Logger.info("[MoondreamTools] ✅ Query answered")
          "Question: #{question}\nAnswer: #{answer}"
        else
          {:error, :missing_api_key} ->
            "Error: Moondream API key missing. Set MOONDREAM_API_KEY environment variable."

          {:error, reason} ->
            "Error querying image: #{inspect(reason)}"
        end

      {:error, reason} ->
        "Error: #{reason}"
    end
  end

  @doc """
  Tool de détection d'objets dans une image.
  """
  def detect do
    %CodeAgentMinimal.Tool{
      name: "moondream_detect",
      description: "Detects and locates specific objects in an image with bounding boxes. Call with: moondream_detect.(image_path, object)",
      inputs: %{
        "image_path" => %{type: "string", description: "Path to the image file"},
        "object" => %{type: "string", description: "Object to detect (e.g., 'person', 'car', 'dog')"}
      },
      output_type: "string",
      function: &do_detect/2
    }
  end

  defp do_detect(image_path, object) do
    image_path = normalize_arg(image_path)
    object = normalize_arg(object)

    case read_image_as_base64(image_path) do
      {:ok, image_base64} ->
        with {:ok, client} <- CodeAgentMinimal.MoondreamApi.new(),
             {:ok, image_binary} <- Base.decode64(image_base64),
             {:ok, image_url} <- CodeAgentMinimal.MoondreamApi.binary_to_image_url(image_binary),
             {:ok, result} <- CodeAgentMinimal.MoondreamApi.detect(client, image_url, object) do
          objects = Map.get(result, "objects", [])
          Logger.info("[MoondreamTools] ✅ Detect completed - #{length(objects)} object(s) found")

          if Enum.empty?(objects) do
            "No '#{object}' detected in the image"
          else
            detections =
              objects
              |> Enum.with_index(1)
              |> Enum.map(fn {obj, idx} ->
                x_min = Map.get(obj, "x_min", 0)
                y_min = Map.get(obj, "y_min", 0)
                x_max = Map.get(obj, "x_max", 0)
                y_max = Map.get(obj, "y_max", 0)
                "#{idx}. Bounding box: x_min=#{Float.round(x_min, 3)}, y_min=#{Float.round(y_min, 3)}, x_max=#{Float.round(x_max, 3)}, y_max=#{Float.round(y_max, 3)}"
              end)
              |> Enum.join("\n")

            "Objects '#{object}' detected - #{length(objects)} occurrence(s):\n#{detections}"
          end
        else
          {:error, :missing_api_key} ->
            "Error: Moondream API key missing. Set MOONDREAM_API_KEY environment variable."

          {:error, reason} ->
            "Error detecting objects: #{inspect(reason)}"
        end

      {:error, reason} ->
        "Error: #{reason}"
    end
  end

  @doc """
  Tool de localisation de points d'intérêt dans une image.
  """
  def point do
    %CodeAgentMinimal.Tool{
      name: "moondream_point",
      description: "Locates a specific point of interest in an image (returns x, y coordinates). Call with: moondream_point.(image_path, object)",
      inputs: %{
        "image_path" => %{type: "string", description: "Path to the image file"},
        "object" => %{type: "string", description: "Element to locate (e.g., 'face', 'text', 'logo')"}
      },
      output_type: "string",
      function: &do_point/2
    }
  end

  defp do_point(image_path, object) do
    image_path = normalize_arg(image_path)
    object = normalize_arg(object)

    case read_image_as_base64(image_path) do
      {:ok, image_base64} ->
        with {:ok, client} <- CodeAgentMinimal.MoondreamApi.new(),
             {:ok, image_binary} <- Base.decode64(image_base64),
             {:ok, image_url} <- CodeAgentMinimal.MoondreamApi.binary_to_image_url(image_binary),
             {:ok, result} <- CodeAgentMinimal.MoondreamApi.point(client, image_url, object) do
          points = Map.get(result, "points", [])
          Logger.info("[MoondreamTools] ✅ Point completed - #{length(points)} point(s) found")

          if Enum.empty?(points) do
            "No point of interest '#{object}' located in the image"
          else
            locations =
              points
              |> Enum.with_index(1)
              |> Enum.map(fn {point, idx} ->
                x = Map.get(point, "x", 0)
                y = Map.get(point, "y", 0)
                "#{idx}. Coordinates: (x: #{x}, y: #{y})"
              end)
              |> Enum.join("\n")

            "Points '#{object}' located - #{length(points)} point(s):\n#{locations}"
          end
        else
          {:error, :missing_api_key} ->
            "Error: Moondream API key missing. Set MOONDREAM_API_KEY environment variable."

          {:error, reason} ->
            "Error locating points: #{inspect(reason)}"
        end

      {:error, reason} ->
        "Error: #{reason}"
    end
  end

  @doc """
  Retourne tous les tools Moondream + final_answer.
  """
  def all_tools do
    [
      caption(),
      query(),
      detect(),
      point(),
      CodeAgentMinimal.Tool.final_answer()
    ]
  end

  @doc """
  Retourne les tools de base (caption et query) + final_answer.
  """
  def basic_tools do
    [
      caption(),
      query(),
      CodeAgentMinimal.Tool.final_answer()
    ]
  end

  # ================= HELPERS PRIVÉS ==================

  # Normalise un argument (charlist -> binary)
  defp normalize_arg(arg) when is_list(arg), do: List.to_string(arg)
  defp normalize_arg(arg), do: arg

  # Lit une image et la convertit en base64
  defp read_image_as_base64(image_path) do
    if File.exists?(image_path) do
      case File.read(image_path) do
        {:ok, binary} ->
          {:ok, Base.encode64(binary)}

        {:error, reason} ->
          {:error, "Failed to read image: #{reason}"}
      end
    else
      {:error, "Image file not found: #{image_path}"}
    end
  end
end
