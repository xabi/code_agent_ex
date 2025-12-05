defmodule CodeAgentMinimal.UseCases.UrlTracker do
  @moduledoc """
  Module pour tracker les URLs visitées en utilisant ETS.

  Permet de:
  - Marquer une URL comme visitée
  - Vérifier si une URL a déjà été visitée
  - Lister toutes les URLs visitées
  - Réinitialiser le tracker

  ## Utilisation

      # Créer une nouvelle session de tracking
      session_id = UrlTracker.new_session()

      # Marquer une URL comme visitée
      UrlTracker.mark_visited(session_id, "https://example.com")

      # Vérifier si visitée
      UrlTracker.visited?(session_id, "https://example.com")  # => true

      # Lister toutes les URLs visitées
      UrlTracker.list_visited(session_id)

      # Nettoyer la session
      UrlTracker.cleanup(session_id)
  """

  @table_name :url_tracker_sessions

  @doc """
  Initialise le système de tracking (appelé au démarrage de l'application).
  """
  def init do
    case :ets.info(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:named_table, :public, :set])
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Crée une nouvelle session de tracking et retourne son ID.

  ## Exemple

      session_id = UrlTracker.new_session()
      # => "session_1234567890"
  """
  def new_session do
    init()
    session_id = "session_#{System.system_time(:millisecond)}_#{:rand.uniform(10000)}"
    :ets.insert(@table_name, {session_id, []})
    session_id
  end

  @doc """
  Marque une URL comme visitée dans une session.

  ## Exemple

      UrlTracker.mark_visited(session_id, "https://example.com")
  """
  def mark_visited(session_id, url) do
    init()
    url = normalize_url(url)

    case :ets.lookup(@table_name, session_id) do
      [{^session_id, visited_urls}] ->
        unless url in visited_urls do
          :ets.insert(@table_name, {session_id, [url | visited_urls]})
        end

        :ok

      [] ->
        :ets.insert(@table_name, {session_id, [url]})
        :ok
    end
  end

  @doc """
  Vérifie si une URL a déjà été visitée dans une session.

  ## Exemple

      UrlTracker.visited?(session_id, "https://example.com")
      # => true ou false
  """
  def visited?(session_id, url) do
    init()
    url = normalize_url(url)

    case :ets.lookup(@table_name, session_id) do
      [{^session_id, visited_urls}] -> url in visited_urls
      [] -> false
    end
  end

  @doc """
  Liste toutes les URLs visitées dans une session.

  ## Exemple

      UrlTracker.list_visited(session_id)
      # => ["https://example.com", "https://example.com/page1"]
  """
  def list_visited(session_id) do
    init()

    case :ets.lookup(@table_name, session_id) do
      [{^session_id, visited_urls}] -> visited_urls
      [] -> []
    end
  end

  @doc """
  Nettoie une session (supprime toutes les URLs trackées).

  ## Exemple

      UrlTracker.cleanup(session_id)
  """
  def cleanup(session_id) do
    init()
    :ets.delete(@table_name, session_id)
    :ok
  end

  @doc """
  Nettoie toutes les sessions.
  """
  def cleanup_all do
    init()
    :ets.delete_all_objects(@table_name)
    :ok
  end

  # Normalise une URL pour la comparaison (retire le trailing slash, etc.)
  defp normalize_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> String.trim_trailing("/")
  end

  defp normalize_url(url) when is_list(url) do
    url |> List.to_string() |> normalize_url()
  end

  defp normalize_url(url), do: to_string(url) |> normalize_url()
end
