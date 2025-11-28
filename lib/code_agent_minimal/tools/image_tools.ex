defmodule CodeAgentMinimal.Tools.ImageTools do
  @moduledoc """
  Tools pour manipuler des images dans le CodeAgent.
  """

  alias CodeAgentMinimal.AgentTypes.AgentImage

  @doc """
  Tool pour télécharger une image depuis une URL.
  """
  def download_image do
    %CodeAgentMinimal.Tool{
      name: "download_image",
      description: "Downloads an image from a URL and returns it as an AgentImage. Call with: download_image.(url)",
      inputs: %{
        "url" => %{type: "string", description: "URL of the image to download"}
      },
      output_type: "AgentImage",
      function: &do_download_image/1
    }
  end

  defp do_download_image(url) do
    case AgentImage.from_url(url) do
      %AgentImage{} = image -> image
      {:error, reason} -> "Error downloading image: #{reason}"
    end
  end

  @doc """
  Tool pour lire une image depuis un fichier local.
  """
  def load_image do
    %CodeAgentMinimal.Tool{
      name: "load_image",
      description: "Loads an image from a local file path and returns it as an AgentImage. Call with: load_image.(path)",
      inputs: %{
        "path" => %{type: "string", description: "Local file path of the image"}
      },
      output_type: "AgentImage",
      function: &do_load_image/1
    }
  end

  defp do_load_image(path) do
    case AgentImage.from_path(path) do
      %AgentImage{} = image -> image
      {:error, reason} -> "Error loading image: #{reason}"
    end
  end

  @doc """
  Tool pour obtenir les informations d'une image.
  """
  def image_info do
    %CodeAgentMinimal.Tool{
      name: "image_info",
      description: "Returns information about an image (format, size). Call with: image_info.(image_path)",
      inputs: %{
        "image_path" => %{type: "string", description: "Path to the image file"}
      },
      output_type: "string",
      function: &do_image_info/1
    }
  end

  defp do_image_info(path) do
    if File.exists?(path) do
      case File.stat(path) do
        {:ok, stat} ->
          format = Path.extname(path) |> String.trim_leading(".")
          size_kb = Float.round(stat.size / 1024, 2)
          "Image: #{Path.basename(path)}, Format: #{format}, Size: #{size_kb} KB"

        {:error, reason} ->
          "Error getting image info: #{reason}"
      end
    else
      "Error: File not found at #{path}"
    end
  end

  @doc """
  Tool pour sauvegarder une image à un emplacement spécifique.
  """
  def save_image do
    %CodeAgentMinimal.Tool{
      name: "save_image",
      description: "Saves an image to a specific location. Call with: save_image.(source_path, destination_path)",
      inputs: %{
        "source_path" => %{type: "string", description: "Path to the source image"},
        "destination_path" => %{type: "string", description: "Path where to save the image"}
      },
      output_type: "string",
      function: fn source_path, dest_path ->
        do_save_image(source_path, dest_path)
      end
    }
  end

  defp do_save_image(source_path, dest_path) do
    case File.copy(source_path, dest_path) do
      {:ok, _bytes} -> "Image saved to #{dest_path}"
      {:error, reason} -> "Error saving image: #{reason}"
    end
  end

  @doc """
  Retourne tous les tools image + final_answer.
  """
  def all_tools do
    [
      download_image(),
      load_image(),
      image_info(),
      save_image(),
      CodeAgentMinimal.Tool.final_answer()
    ]
  end
end
