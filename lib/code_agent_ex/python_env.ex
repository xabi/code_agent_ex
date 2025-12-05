defmodule CodeAgentEx.PythonEnv do
  @moduledoc """
  Gère l'initialisation de l'environnement Python avec PythonX.

  Ce module fournit les configurations par défaut pour les dépendances Python
  nécessaires aux tools de CodeAgentEx.

  ## Usage

  Dans votre application, appelez `init()` au démarrage :

      # Dans votre application.ex ou au démarrage
      CodeAgentEx.PythonEnv.init()

  Pour utiliser des dépendances Python personnalisées :

      CodeAgentEx.PythonEnv.init_custom(\"\"\"
      [project]
      name = "my_project"
      version = "0.1.0"
      requires-python = ">=3.10"
      dependencies = [
        "wikipedia==1.4.0",
        "my_custom_package>=1.0.0"
      ]
      \"\"\")
  """

  @pyproject_toml """
  [project]
  name = "code_agent_minimal_tools"
  version = "0.1.0"
  requires-python = ">=3.10"
  dependencies = [
    "wikipedia==1.4.0",
    "markdownify>=0.11.6",
    "yfinance>=0.2.0",
    "matplotlib>=3.7.0",
    "smolagents>=0.1.0",
    "huggingface_hub>=0.36.0",
    "gradio_client>=0.10.0",
    "ddgs>=1.0.0"
  ]

  [tool.uv]
  python-downloads = "automatic"
  """

  @doc """
  Initialise PythonX avec les dépendances par défaut de CodeAgentEx.
  """
  def init do
    Pythonx.uv_init(@pyproject_toml)
  end

  @doc """
  Initialise PythonX avec une configuration personnalisée.

  ## Exemple

      CodeAgentEx.PythonEnv.init_custom(\"\"\"
      [project]
      name = "my_project"
      version = "0.1.0"
      requires-python = ">=3.10"
      dependencies = [
        "wikipedia==1.4.0",
        "my_package>=1.0.0"
      ]
      \"\"\")
  """
  def init_custom(pyproject_toml) when is_binary(pyproject_toml) do
    Pythonx.uv_init(pyproject_toml)
  end

  @doc """
  Retourne la configuration pyproject.toml par défaut.

  Utile si vous voulez merger avec vos propres dépendances.
  """
  def default_config do
    @pyproject_toml
  end
end
