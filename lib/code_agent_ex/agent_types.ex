defmodule CodeAgentEx.AgentTypes do
  @moduledoc """
  Types spéciaux pour les données binaires (images, audio) dans le CodeAgent.

  Ces types permettent de passer des fichiers binaires entre les tools et le code généré
  en utilisant des paths comme référence.

  Les fichiers sont sauvegardés dans un sous-dossier `code_agent` de tmp.

  ## Exemple

      # Un tool retourne une image
      image = AgentImage.from_binary(png_data, "png")

      # Dans le binding, l'image est accessible via son path
      # Le LLM peut faire: result = process_image.(image_path)
  """

  @agent_tmp_dir "code_agent"

  @doc """
  Retourne le dossier temporaire pour les fichiers de l'agent.
  Crée le dossier s'il n'existe pas.
  """
  def tmp_dir do
    dir = Path.join(System.tmp_dir!(), @agent_tmp_dir)
    File.mkdir_p!(dir)
    dir
  end

  defmodule AgentImage do
    @moduledoc """
    Type pour les images. Encapsule une image et la rend accessible via un path.
    """

    defstruct [:path, :binary, :format, :width, :height]

    @doc """
    Crée une AgentImage depuis un path existant.
    """
    def from_path(path) when is_binary(path) do
      if File.exists?(path) do
        %__MODULE__{path: path, format: Path.extname(path) |> String.trim_leading(".")}
      else
        {:error, "File not found: #{path}"}
      end
    end

    @doc """
    Crée une AgentImage depuis des données binaires.
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
    Crée une AgentImage depuis une URL (télécharge l'image).
    """
    def from_url(url) when is_list(url), do: from_url(List.to_string(url))

    def from_url(url) when is_binary(url) do
      case Req.get(url) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          # Deviner le format depuis l'URL ou Content-Type
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
    Retourne le path de l'image (pour utilisation dans le code généré).
    """
    def to_string(%__MODULE__{path: path}), do: path

    @doc """
    Retourne les données binaires de l'image.
    """
    def to_binary(%__MODULE__{binary: nil, path: path}) do
      File.read!(path)
    end

    def to_binary(%__MODULE__{binary: binary}), do: binary

    @doc """
    Nettoie le fichier temporaire.
    """
    def cleanup(%__MODULE__{path: path}) do
      if path && String.starts_with?(path, CodeAgentEx.AgentTypes.tmp_dir()) do
        File.rm(path)
      end
    end
  end

  defmodule AgentAudio do
    @moduledoc """
    Type pour les fichiers audio.
    """

    defstruct [:path, :binary, :format, :samplerate, :duration]

    @doc """
    Crée un AgentAudio depuis un path existant.
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
    Crée un AgentAudio depuis des données binaires.
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
    Retourne le path de l'audio.
    """
    def to_string(%__MODULE__{path: path}), do: path

    @doc """
    Retourne les données binaires.
    """
    def to_binary(%__MODULE__{binary: nil, path: path}) do
      File.read!(path)
    end

    def to_binary(%__MODULE__{binary: binary}), do: binary

    @doc """
    Nettoie le fichier temporaire.
    """
    def cleanup(%__MODULE__{path: path}) do
      if path && String.starts_with?(path, CodeAgentEx.AgentTypes.tmp_dir()) do
        File.rm(path)
      end
    end
  end

  defmodule AgentVideo do
    @moduledoc """
    Type pour les vidéos. Encapsule une vidéo et la rend accessible via un path.
    """

    defstruct [:path, :binary, :format, :duration, :width, :height]

    @doc """
    Crée un AgentVideo depuis un path existant.
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
    Crée un AgentVideo depuis des données binaires.
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
    Retourne le path de la vidéo.
    """
    def to_string(%__MODULE__{path: path}), do: path

    @doc """
    Retourne les données binaires.
    """
    def to_binary(%__MODULE__{binary: nil, path: path}) do
      File.read!(path)
    end

    def to_binary(%__MODULE__{binary: binary}), do: binary

    @doc """
    Nettoie le fichier temporaire.
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
