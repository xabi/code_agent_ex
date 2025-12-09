defmodule CodeAgentEx.AgentTypes do
  @moduledoc """
  Special types for binary data (images, audio) in CodeAgent.

  These types allow passing binary files between tools and generated code
  using paths as references.

  Files are saved in a `code_agent` subfolder of tmp.

  ## Example

      # A tool returns an image
      image = AgentImage.from_binary(png_data, "png")

      # In the binding, the image is accessible via its path
      # The LLM can do: result = process_image.(image_path)
  """

  @agent_tmp_dir "code_agent"

  @doc """
  Returns the temporary directory for agent files.
  Creates the directory if it doesn't exist.
  """
  def tmp_dir do
    dir = Path.join(System.tmp_dir!(), @agent_tmp_dir)
    File.mkdir_p!(dir)
    dir
  end

  defmodule AgentImage do
    @moduledoc """
    Type for images. Encapsulates an image and makes it accessible via a path.
    """

    defstruct [:path, :binary, :format, :width, :height]

    @doc """
    Creates an AgentImage from an existing path.
    """
    def from_path(path) when is_binary(path) do
      if File.exists?(path) do
        %__MODULE__{path: path, format: Path.extname(path) |> String.trim_leading(".")}
      else
        {:error, "File not found: #{path}"}
      end
    end

    @doc """
    Creates an AgentImage from binary data.
    """
    def from_binary(data, format \\ "png") when is_binary(data) do
      filename = "agent_image_#{:erlang.unique_integer([:positive])}.#{format}"
      path = Path.join(CodeAgentEx.AgentTypes.tmp_dir(), filename)

      case File.write(path, data) do
        :ok ->
          %__MODULE__{path: path, binary: data, format: format}

        {:error, reason} ->
          {:error, "Failed to write image: #{reason}"}
      end
    end

    @doc """
    Creates an AgentImage from a URL (downloads the image).
    """
    def from_url(url) when is_list(url), do: from_url(List.to_string(url))

    def from_url(url) when is_binary(url) do
      case Req.get(url) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          # Guess format from URL or Content-Type
          format =
            url
            |> URI.parse()
            |> Map.get(:path, "")
            |> Path.extname()
            |> String.trim_leading(".")
            |> case do
              "" -> "png"
              ext -> ext
            end

          from_binary(body, format)

        {:ok, %{status: status}} ->
          {:error, "HTTP error: #{status}"}

        {:error, reason} ->
          {:error, "Download failed: #{inspect(reason)}"}
      end
    end

    @doc """
    Returns the image path (for use in generated code).
    """
    def to_string(%__MODULE__{path: path}), do: path

    @doc """
    Returns the image binary data.
    """
    def to_binary(%__MODULE__{binary: nil, path: path}) do
      File.read!(path)
    end

    def to_binary(%__MODULE__{binary: binary}), do: binary

    @doc """
    Cleans up the temporary file.
    """
    def cleanup(%__MODULE__{path: path}) do
      if path && String.starts_with?(path, CodeAgentEx.AgentTypes.tmp_dir()) do
        File.rm(path)
      end
    end
  end

  defmodule AgentAudio do
    @moduledoc """
    Type for audio files.
    """

    defstruct [:path, :binary, :format, :samplerate, :duration]

    @doc """
    Creates an AgentAudio from an existing path.
    """
    def from_path(path, opts \\ []) when is_binary(path) do
      if File.exists?(path) do
        %__MODULE__{
          path: path,
          format: Path.extname(path) |> String.trim_leading("."),
          samplerate: Keyword.get(opts, :samplerate, 16_000)
        }
      else
        {:error, "File not found: #{path}"}
      end
    end

    @doc """
    Creates an AgentAudio from binary data.
    """
    def from_binary(data, format \\ "wav", opts \\ []) when is_binary(data) do
      filename = "agent_audio_#{:erlang.unique_integer([:positive])}.#{format}"
      path = Path.join(CodeAgentEx.AgentTypes.tmp_dir(), filename)

      case File.write(path, data) do
        :ok ->
          %__MODULE__{
            path: path,
            binary: data,
            format: format,
            samplerate: Keyword.get(opts, :samplerate, 16_000)
          }

        {:error, reason} ->
          {:error, "Failed to write audio: #{reason}"}
      end
    end

    @doc """
    Returns the audio path.
    """
    def to_string(%__MODULE__{path: path}), do: path

    @doc """
    Returns the binary data.
    """
    def to_binary(%__MODULE__{binary: nil, path: path}) do
      File.read!(path)
    end

    def to_binary(%__MODULE__{binary: binary}), do: binary

    @doc """
    Cleans up the temporary file.
    """
    def cleanup(%__MODULE__{path: path}) do
      if path && String.starts_with?(path, CodeAgentEx.AgentTypes.tmp_dir()) do
        File.rm(path)
      end
    end
  end

  defmodule AgentVideo do
    @moduledoc """
    Type for videos. Encapsulates a video and makes it accessible via a path.
    """

    defstruct [:path, :binary, :format, :duration, :width, :height]

    @doc """
    Creates an AgentVideo from an existing path.
    """
    def from_path(path, opts \\ []) when is_binary(path) do
      if File.exists?(path) do
        %__MODULE__{
          path: path,
          format: Path.extname(path) |> String.trim_leading("."),
          duration: Keyword.get(opts, :duration),
          width: Keyword.get(opts, :width),
          height: Keyword.get(opts, :height)
        }
      else
        {:error, "File not found: #{path}"}
      end
    end

    @doc """
    Creates an AgentVideo from binary data.
    """
    def from_binary(data, format \\ "mp4", opts \\ []) when is_binary(data) do
      filename = "agent_video_#{:erlang.unique_integer([:positive])}.#{format}"
      path = Path.join(CodeAgentEx.AgentTypes.tmp_dir(), filename)

      case File.write(path, data) do
        :ok ->
          %__MODULE__{
            path: path,
            binary: data,
            format: format,
            duration: Keyword.get(opts, :duration),
            width: Keyword.get(opts, :width),
            height: Keyword.get(opts, :height)
          }

        {:error, reason} ->
          {:error, "Failed to write video: #{reason}"}
      end
    end

    @doc """
    Returns the video path.
    """
    def to_string(%__MODULE__{path: path}), do: path

    @doc """
    Returns the binary data.
    """
    def to_binary(%__MODULE__{binary: nil, path: path}) do
      File.read!(path)
    end

    def to_binary(%__MODULE__{binary: binary}), do: binary

    @doc """
    Cleans up the temporary file.
    """
    def cleanup(%__MODULE__{path: path}) do
      if path && String.starts_with?(path, CodeAgentEx.AgentTypes.tmp_dir()) do
        File.rm(path)
      end
    end
  end

  @doc """
  Converts tuple results from external tools to AgentTypes.

  External tools (like code_agent_ex_tools) return tuples like:
  - {:image, path} → AgentImage
  - {:video, path} → AgentVideo
  - {:audio, path} → AgentAudio
  - other → unchanged
  """
  def from_tuple({:image, path}) when is_binary(path) do
    AgentImage.from_path(path)
  end

  def from_tuple({:video, path}) when is_binary(path) do
    AgentVideo.from_path(path)
  end

  def from_tuple({:audio, path}) when is_binary(path) do
    AgentAudio.from_path(path)
  end

  def from_tuple(value), do: value

  @doc """
  Convertit une valeur en sa représentation string pour le LLM.

  - AgentImage/AgentAudio/AgentVideo → path
  - Autres → inchangé
  """
  def to_llm_value(%AgentImage{} = img), do: AgentImage.to_string(img)
  def to_llm_value(%AgentAudio{} = audio), do: AgentAudio.to_string(audio)
  def to_llm_value(%AgentVideo{} = video), do: AgentVideo.to_string(video)
  def to_llm_value(value), do: value

  @doc """
  Vérifie si une valeur est un AgentType.
  """
  def agent_type?(%AgentImage{}), do: true
  def agent_type?(%AgentAudio{}), do: true
  def agent_type?(%AgentVideo{}), do: true
  def agent_type?(_), do: false
end

# Implement String.Chars for AgentImage so it can be interpolated
defimpl String.Chars, for: CodeAgentEx.AgentTypes.AgentImage do
  def to_string(%{path: path}), do: path
end

# Implement String.Chars for AgentAudio
defimpl String.Chars, for: CodeAgentEx.AgentTypes.AgentAudio do
  def to_string(%{path: path}), do: path
end

# Implement String.Chars for AgentVideo
defimpl String.Chars, for: CodeAgentEx.AgentTypes.AgentVideo do
  def to_string(%{path: path}), do: path
end
