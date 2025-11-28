import Config

# Configure Pythonx with required dependencies
config :pythonx, :uv_init,
  pyproject_toml: """
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
