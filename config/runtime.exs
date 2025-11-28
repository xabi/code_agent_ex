import Config

# Configuration runtime pour CodeAgentMinimal
# Ce fichier est chargé au démarrage de l'application et permet
# de configurer l'application avec des variables d'environnement

# Configuration Moondream API
# Définir MOONDREAM_API_KEY dans l'environnement pour activer l'API
if moondream_api_key = System.get_env("MOONDREAM_API_KEY") do
  config :code_agent_minimal, :moondream,
    api_key: moondream_api_key
end

# Configuration Hugging Face API
# Définir HF_TOKEN dans l'environnement pour accéder aux modèles HF
if hf_token = System.get_env("HF_TOKEN") do
  config :code_agent_minimal, :hugging_face,
    token: hf_token
end
