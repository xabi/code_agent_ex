defmodule CodeAgentMinimal.Tools.ImageTools do
  @moduledoc """
  Tools pour manipuler des images dans le CodeAgent.
  """

  alias CodeAgentMinimal.AgentTypes.{AgentImage, AgentVideo}
  require Logger

  @doc """
  Tool pour générer une vidéo depuis un texte avec l'API Hugging Face Inference.
  """
  def text_to_video(opts \\ []) do
    model = Keyword.get(opts, :model, "Wan-AI/Wan2.1-T2V-14B")

    %CodeAgentMinimal.Tool{
      name: :text_to_video,
      description: """
      Generates a video from a text prompt using Hugging Face Inference API.
      Requires HF_TOKEN environment variable to be set.

      Usage:
        tools.text_to_video.("a cat walking on a sunny beach, photorealistic")

      The generated video will be saved in /tmp/code_agent/ and the function returns an AgentVideo object
      with a path property pointing to the saved MP4 file.

      Tips for better results:
      - Be descriptive and specific in your prompt
      - Mention camera movements like "camera panning", "slow motion"
      - Include style hints and lighting details
      """,
      inputs: %{
        "prompt" => %{type: "string", description: "Text description of the video to generate"}
      },
      output_type: "AgentVideo",
      function: fn prompt ->
        do_text_to_video_single_arg(prompt, model)
      end
    }
  end

  # Single argument handler - accepts just prompt as string
  defp do_text_to_video_single_arg(prompt, model) when is_binary(prompt) do
    do_text_to_video(prompt, %{}, model)
  end

  # If it's a charlist, convert it
  defp do_text_to_video_single_arg(prompt, model) when is_list(prompt) do
    prompt = to_string(prompt)
    do_text_to_video(prompt, %{}, model)
  rescue
    _ -> "Error: Could not convert prompt to string"
  end

  # Fallback
  defp do_text_to_video_single_arg(_prompt, _model) do
    "Error: Prompt must be a string"
  end

  defp do_text_to_video(prompt, _options, model) when is_binary(prompt) do
    token = System.get_env("HF_TOKEN")

    if is_nil(token) do
      "Error: HF_TOKEN environment variable not set. Get your token at https://huggingface.co/settings/tokens"
    else
      Logger.info("[ImageTools] Generating video with prompt: #{String.slice(prompt, 0, 50)}...")

      # Use Python with huggingface_hub library
      python_code = """
      import os
      from huggingface_hub import InferenceClient
      import base64

      try:
          # Convert bytes to str if needed
          prompt_str = prompt_text.decode('utf-8') if isinstance(prompt_text, bytes) else prompt_text
          model_str = model_name.decode('utf-8') if isinstance(model_name, bytes) else model_name

          client = InferenceClient(
              provider="replicate",
              api_key=os.environ.get("HF_TOKEN")
          )

          # Generate video - returns video bytes
          video_bytes = client.text_to_video(
              prompt_str,
              model=model_str
          )

          # Convert to base64
          video_base64 = base64.b64encode(video_bytes).decode('utf-8')

          output = ("ok", video_base64)
      except Exception as e:
          import traceback
          output = ("error", f"{str(e)}\\n\\nTraceback:\\n{traceback.format_exc()}")

      output
      """

      try do
        {result, _globals} =
          Pythonx.eval(python_code, %{
            "prompt_text" => prompt,
            "model_name" => model
          })

        case Pythonx.decode(result) do
          {"ok", video_base64} when is_binary(video_base64) ->
            case Base.decode64(video_base64) do
              {:ok, video_binary} ->
                Logger.info("[ImageTools] ✅ Video generated successfully")
                AgentVideo.from_binary(video_binary, "mp4")

              :error ->
                "Error: Failed to decode base64 video data"
            end

          {"error", error_msg} ->
            Logger.error("[ImageTools] Python error: #{error_msg}")
            "Error generating video: #{error_msg}"

          other ->
            "Unexpected result: #{inspect(other)}"
        end
      rescue
        error ->
          Logger.error("[ImageTools] Pythonx error: #{inspect(error)}")
          "Error: Failed to execute Python code - #{inspect(error)}"
      end
    end
  end

  @doc """
  Tool pour générer une image depuis un texte avec l'API Hugging Face Inference.
  """
  def text_to_image(opts \\ []) do
    model = Keyword.get(opts, :model, "black-forest-labs/FLUX.1-dev")

    %CodeAgentMinimal.Tool{
      name: :text_to_image,
      description: """
      Generates an image from a text prompt using Hugging Face Inference API.
      Requires HF_TOKEN environment variable to be set.

      Usage:
        tools.text_to_image.("a cute orange cat sitting on a sunny windowsill, photorealistic, warm tone")

      The generated image will be saved in /tmp/code_agent/ and the function returns an AgentImage object
      with a path property pointing to the saved PNG file.

      Tips for better results:
      - Be descriptive and specific in your prompt
      - Include style hints like "photorealistic", "artistic", "detailed"
      - Mention lighting, mood, and composition
      """,
      inputs: %{
        "prompt" => %{type: "string", description: "Text description of the image to generate"}
      },
      output_type: "AgentImage",
      function: fn prompt ->
        do_text_to_image_single_arg(prompt, model)
      end
    }
  end

  # Single argument handler - accepts just prompt as string
  defp do_text_to_image_single_arg(prompt, model) when is_binary(prompt) do
    do_text_to_image(prompt, %{}, model)
  end

  # If it's a charlist, convert it
  defp do_text_to_image_single_arg(prompt, model) when is_list(prompt) do
    prompt = to_string(prompt)
    do_text_to_image(prompt, %{}, model)
  rescue
    _ -> "Error: Could not convert prompt to string"
  end

  # Fallback
  defp do_text_to_image_single_arg(_prompt, _model) do
    "Error: Prompt must be a string"
  end

  defp do_text_to_image(prompt, _options, model) when is_binary(prompt) do
    token = System.get_env("HF_TOKEN")

    if is_nil(token) do
      "Error: HF_TOKEN environment variable not set. Get your token at https://huggingface.co/settings/tokens"
    else
      Logger.info("[ImageTools] Generating image with prompt: #{String.slice(prompt, 0, 50)}...")

      # Use Python with huggingface_hub library
      python_code = """
      import os
      from huggingface_hub import InferenceClient
      from io import BytesIO
      import base64

      try:
          # Convert bytes to str if needed
          prompt_str = prompt_text.decode('utf-8') if isinstance(prompt_text, bytes) else prompt_text
          model_str = model_name.decode('utf-8') if isinstance(model_name, bytes) else model_name

          client = InferenceClient(
              provider="replicate",
              api_key=os.environ.get("HF_TOKEN")
          )

          # Generate image - returns a PIL.Image object
          image = client.text_to_image(
              prompt_str,
              model=model_str
          )

          # Convert PIL Image to base64
          buffer = BytesIO()
          image.save(buffer, format='PNG')
          img_bytes = buffer.getvalue()
          image_base64 = base64.b64encode(img_bytes).decode('utf-8')

          output = ("ok", image_base64)
      except Exception as e:
          import traceback
          output = ("error", f"{str(e)}\\n\\nTraceback:\\n{traceback.format_exc()}")

      output
      """

      try do
        {result, _globals} =
          Pythonx.eval(python_code, %{
            "prompt_text" => prompt,
            "model_name" => model
          })

        case Pythonx.decode(result) do
          {"ok", image_base64} when is_binary(image_base64) ->
            case Base.decode64(image_base64) do
              {:ok, image_binary} ->
                Logger.info("[ImageTools] ✅ Image generated successfully")
                AgentImage.from_binary(image_binary, "png")

              :error ->
                "Error: Failed to decode base64 image data"
            end

          {"error", error_msg} ->
            Logger.error("[ImageTools] Python error: #{error_msg}")
            "Error generating image: #{error_msg}"

          other ->
            "Unexpected result: #{inspect(other)}"
        end
      rescue
        error ->
          Logger.error("[ImageTools] Pythonx error: #{inspect(error)}")
          "Error: Failed to execute Python code - #{inspect(error)}"
      end
    end
  end

  @doc """
  Tool pour télécharger une image depuis une URL.
  """
  def download_image do
    %CodeAgentMinimal.Tool{
      name: "download_image",
      description:
        "Downloads an image from a URL and returns it as an AgentImage. Call with: tools.download_image.(url)",
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
      description:
        "Loads an image from a local file path and returns it as an AgentImage. Call with: tools.load_image.(path)",
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
      description:
        "Returns information about an image (format, size). Call with: tools.image_info.(image_path)",
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
      description:
        "Saves an image to a specific location. Call with: tools.save_image.(source_path, destination_path)",
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
  Retourne tous les tools image/video + final_answer.
  """
  def all_tools(opts \\ []) do
    [
      text_to_image(opts),
      text_to_video(opts),
      download_image(),
      load_image(),
      image_info(),
      save_image(),
      CodeAgentMinimal.Tool.final_answer()
    ]
  end
end
