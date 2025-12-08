defmodule CodeAgentEx.Executor do
  @moduledoc """
  Exécuteur de code Elixir pour le CodeAgent.

  Utilise Code.eval_string pour l'exécution du code généré par le LLM.
  Inspiré de smolagents' local_python_executor.py.

  ## Utilisation

      Executor.execute_sandboxed(code, binding)

  Le code est exécuté avec accès aux tools via le binding.
  """

  require Logger

  @doc """
  Exécute du code Elixir avec Code.eval_string.

  Inspiré de smolagents' evaluate_python_code() qui utilise un AST walker.
  Ici on utilise Code.eval_string avec un binding préparé contenant tous les tools.

  ## Exemple de code attendu

      result = 25 * 4
      result = result + 10
      final_answer.(result)

  ## Paramètres

  - `code` - Le code Elixir à exécuter
  - `binding` - Keyword list contenant les tools disponibles

  ## Retourne

  - `{:ok, result, updated_binding}` - Exécution réussie avec binding mis à jour
  - `{:error, reason}` - Erreur d'exécution

  ## Final Answer

  Le binding est mis à jour avec `__final_answer__` uniquement si le code
  appelle `final_answer/1`, qui fait un `throw({:final_answer, value})`.
  Comme dans smolagents avec FinalAnswerException.
  """
  def execute_sandboxed(code, binding) do
    Logger.debug("🔒 [Executor] Executing code:\n#{code}")

    # Si le code utilise final_answer.( sans le préfixe tools., ajouter une ligne pour le définir
    code = maybe_add_final_answer_binding(code)

    # Préparer le binding pour Code.eval_string
    # Réutiliser les bindings précédents (variables définies dans les steps précédents)
    eval_binding = prepare_binding(binding)

    # Exécuter avec Code.eval_string (avec gestion du throw pour final_answer)
    try do
      {result, new_binding} = Code.eval_string(code, eval_binding)

      # Convertir les tuples {:image, path}, {:video, path}, {:audio, path} en AgentTypes
      converted_result = CodeAgentEx.AgentTypes.from_tuple(result)

      # Mettre à jour le binding avec les nouvelles variables créées
      # Cela permet de réutiliser les variables d'un step à l'autre
      updated_binding = merge_bindings(binding, new_binding)

      {:ok, converted_result, updated_binding}
    rescue
      e ->
        Logger.error("🔒 [Executor] Execution error: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    catch
      :throw, {:final_answer, answer} ->
        # Capturer le throw de final_answer (comme FinalAnswerException dans smolagents)
        # Convertir les tuples en AgentTypes
        converted_answer = CodeAgentEx.AgentTypes.from_tuple(answer)
        # Marquer le binding comme contenant une final_answer
        updated_binding = Map.put(binding, :__final_answer__, converted_answer)

        {:ok, converted_answer, updated_binding}
    end
  end

  # Ajoute automatiquement `final_answer = tools.final_answer` si le code utilise
  # final_answer.( sans le préfixe tools.
  defp maybe_add_final_answer_binding(code) do
    # Détecter si le code appelle final_answer.( sans le préfixe tools.
    has_final_answer = String.contains?(code, "final_answer.(")
    has_tools_prefix = String.contains?(code, "tools.final_answer.(")

    if has_final_answer and not has_tools_prefix do
      # Ajouter la ligne au début
      "final_answer = tools.final_answer\n" <> code
    else
      code
    end
  end

  # Prépare le binding pour Code.eval_string
  # On passe les tools ET les variables des steps précédents
  defp prepare_binding(binding) when is_map(binding) do
    # Récupérer les variables définies dans les steps précédents
    previous_vars = Map.get(binding, :__vars__, [])

    # Combiner tools, agents et variables précédentes
    [
      tools: Map.get(binding, :tools, %{}),
      agents: Map.get(binding, :agents, %{})
    ] ++ previous_vars
  end

  # Fusionne les bindings: garde tools/agents, ajoute les nouvelles variables
  defp merge_bindings(original_binding, new_binding) when is_map(original_binding) do
    # Filtrer pour garder uniquement les variables utilisateur (pas tools/agents)
    user_vars =
      new_binding
      |> Enum.filter(fn {key, _} ->
        key not in [:tools, :agents]
      end)

    # Mettre à jour le binding original avec les nouvelles variables
    original_binding
    |> Map.put(:__vars__, user_vars)
  end
end
