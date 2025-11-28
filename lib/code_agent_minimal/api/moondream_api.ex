defmodule CodeAgentMinimal.MoondreamApi do
  @moduledoc """
  Client pour l'API Moondream.

  Ce module fournit une interface pour interagir avec l'API Moondream,
  incluant les endpoints Caption, Query, Detect et Point.
  """

  require Logger

  @base_url "https://api.moondream.ai"

  defstruct [:api_key]

  @doc """
  Convertit le contenu d'un fichier image en image_url (base64 avec data URI)

  ## Examples

      iex> {:ok, image_url} = CodeAgentMinimal.MoondreamApi.file_to_image_url("/path/to/image.jpg")
      {:ok, "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQ..."}

  """
  def file_to_image_url(file_path) do
    Logger.info("[MoondreamApi] 📁 Lecture du fichier image: #{file_path}")

    case File.read(file_path) do
      {:ok, binary} ->
        mime_type = get_mime_type(file_path)
        size_kb = byte_size(binary) / 1024

        Logger.info(
          "[MoondreamApi] ✅ Fichier lu avec succès: #{Float.round(size_kb, 2)} KB, type: #{mime_type}"
        )

        base64_content = Base.encode64(binary)
        base64_preview = String.slice(base64_content, 0, 50)
        Logger.debug("[MoondreamApi] 🔐 Base64 généré (preview): #{base64_preview}...")
        {:ok, "data:#{mime_type};base64,#{base64_content}"}

      {:error, reason} ->
        Logger.error("[MoondreamApi] ❌ Erreur lors de la lecture du fichier: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Convertit du contenu binaire d'image en image_url (base64 avec data URI)

  ## Examples

      iex> binary = File.read!("image.jpg")
      iex> {:ok, image_url} = CodeAgentMinimal.MoondreamApi.binary_to_image_url(binary, "image/jpeg")
      {:ok, "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQ..."}

  """
  def binary_to_image_url(binary, mime_type \\ "image/jpeg") do
    base64_content = Base.encode64(binary)
    {:ok, "data:#{mime_type};base64,#{base64_content}"}
  end

  defp get_mime_type(file_path) do
    case Path.extname(file_path) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "image/jpeg"
    end
  end

  @type t :: %__MODULE__{
          api_key: String.t()
        }

  def new(api_key \\ nil) do
    Logger.debug("[MoondreamApi] 🔑 Initialisation du client Moondream")
    api_key = api_key || Application.get_env(:code_agent_minimal, :moondream)[:api_key]

    if is_nil(api_key) or api_key == "" do
      Logger.error("[MoondreamApi] ❌ Clé API Moondream manquante")
      {:error, :missing_api_key}
    else
      key_preview = String.slice(api_key, 0, 20)
      Logger.info("[MoondreamApi] ✅ Client Moondream initialisé (clé: #{key_preview}...)")
      {:ok, %__MODULE__{api_key: api_key}}
    end
  end

  def caption(%__MODULE__{} = client, image_url, options \\ []) do
    Logger.info("[MoondreamApi] 📸 Appel API caption avec options: #{inspect(options)}")
    payload = %{image_url: image_url}

    # Add optional parameters
    payload = if options[:length], do: Map.put(payload, :length, options[:length]), else: payload
    payload = if options[:stream], do: Map.put(payload, :stream, options[:stream]), else: payload

    make_request(client, "/v1/caption", payload, options)
  end

  def query(%__MODULE__{} = client, image_url, question, options \\ []) do
    Logger.info("[MoondreamApi] ❓ Appel API query - question: #{question}")
    payload = %{image_url: image_url, question: question}

    # Add optional stream parameter
    payload = if options[:stream], do: Map.put(payload, :stream, options[:stream]), else: payload

    make_request(client, "/v1/query", payload, options)
  end

  def detect(%__MODULE__{} = client, image_url, object, options \\ []) do
    Logger.info("[MoondreamApi] 🔍 Appel API detect - objet: #{object}")
    payload = %{image_url: image_url, object: object}
    make_request(client, "/v1/detect", payload, options)
  end

  def point(%__MODULE__{} = client, image_url, object, options \\ []) do
    Logger.info("[MoondreamApi] 📍 Appel API point - objet: #{object}")
    payload = %{image_url: image_url, object: object}
    make_request(client, "/v1/point", payload, options)
  end

  defp make_request(%__MODULE__{api_key: api_key}, endpoint, payload, _options) do
    url = @base_url <> endpoint
    Logger.info("[MoondreamApi] 🌐 Requête HTTP POST vers: #{url}")

    headers = [
      {"Content-Type", "application/json"},
      {"X-Moondream-Auth", api_key}
    ]

    encoded_payload = Jason.encode!(payload)
    payload_size_kb = byte_size(encoded_payload) / 1024
    Logger.debug("[MoondreamApi] 📊 Taille du payload: #{Float.round(payload_size_kb, 2)} KB")

    case Finch.build(:post, url, headers, encoded_payload)
         |> Finch.request(CodeAgentMinimal.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        Logger.info("[MoondreamApi] ✅ Réponse HTTP 200 OK")
        Logger.debug("[MoondreamApi] 📥 Body: #{String.slice(body, 0, 200)}...")

        case Jason.decode(body) do
          {:ok, response} ->
            Logger.info("[MoondreamApi] ✅ JSON décodé avec succès")
            {:ok, response}

          {:error, error} ->
            Logger.error("[MoondreamApi] ❌ Erreur de décodage JSON: #{inspect(error)}")
            {:error, error}
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[MoondreamApi] ❌ Erreur HTTP #{status}")
        Logger.error("[MoondreamApi] 📥 Body: #{body}")
        {:error, %{status: status, body: body}}

      {:error, error} ->
        Logger.error("[MoondreamApi] ❌ Erreur de connexion: #{inspect(error)}")
        {:error, error}
    end
  end
end
