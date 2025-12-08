# CodeAgentEx 🤖

> A code-generating agent framework for Elixir, inspired by [smolagents](https://github.com/huggingface/smolagents)

CodeAgentEx is a lightweight implementation of an agentic AI system that **writes and executes Elixir code** to solve tasks. Using a ReAct (Reasoning + Acting) loop, the agent iteratively generates code, executes it in a sandbox, and uses the results to progress toward a solution.

## ✨ Features

### 🧠 Intelligent Code Generation
- **ReAct Loop**: Think → Code → Execute → Observe → Repeat
- **Variable Persistence**: Variables carry over between steps for complex multi-step reasoning
- **LLM-Powered**: Uses state-of-the-art language models via OpenAI-compatible APIs

### 🔧 Flexible Tool System
- **Custom Tools**: Define your own tools with typed inputs/outputs
- **Built-in Tools**: Wikipedia, stock prices, web search, Python execution, image generation (FLUX), vision analysis (Moondream)
- **Parameterized Tools**: Tools can accept arguments for maximum flexibility

### 🏗️ Hierarchical Agents
- **Managed Agents**: Agents can delegate to specialized sub-agents
- **Nested Delegation**: Sub-agents can have their own sub-agents
- **Capability Discovery**: Explicit instructions help agents discover each other's capabilities

### 🔒 Safe Execution
- **Sandboxed**: Code runs via `Code.eval_string` with restricted access
- **Whitelisted Modules**: Only safe modules (Map, String, Enum, etc.) are available
- **No Filesystem/Network**: External operations only through tools

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd code_agent_ex

# Install dependencies
mix deps.get

# Compile
mix compile
```

### Configuration

CodeAgentEx is a **library**, not an application. It does not impose configuration on your project.

**Option 1: Pass API keys directly to functions**

```elixir
# LLM Client (HuggingFace or OpenAI-compatible)
alias CodeAgentEx.LLM.Client

Client.chat_completion(
  model,
  messages,
  response_schema,
  api_key: "hf_your_token_here"
)

# Moondream
{:ok, client} = CodeAgentEx.MoondreamApi.new("your_moondream_key")
```

**Option 2: Use environment variables in your project**

```bash
# Set environment variables
export HF_TOKEN=hf_your_token_here
export MOONDREAM_API_KEY=your_token_here
```

Most functions accept an `api_key` option, so you can manage credentials however you prefer.

**Python Dependencies (for Python-based tools)**

If you use tools that require Python (Wikipedia, Finance, SmolAgents, etc.), initialize PythonX in your application:

```elixir
# In your application.ex start/2 or at runtime
CodeAgentEx.PythonEnv.init()
```

Or use custom dependencies:

```elixir
CodeAgentEx.PythonEnv.init_custom("""
[project]
name = "my_project"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = [
  "wikipedia==1.4.0",
  "my_custom_package>=1.0.0"
]
""")
```

To see the default dependencies, check `CodeAgentEx.PythonEnv.default_config()`.

### Basic Usage

```elixir
# Start an IEx session
iex -S mix

# Run a simple calculation
alias CodeAgentEx.{CodeAgent, AgentConfig}

config = AgentConfig.new(
  model: "Qwen/Qwen3-Coder-30B-A3B-Instruct",
  max_steps: 5
)

{:ok, result, _state} = CodeAgent.run(
  "Calculate the factorial of 10 and format it nicely",
  config
)
```

### Running Tests

The project includes 13 comprehensive tests:

```elixir
# In IEx
alias CodeAgentEx.IexTest

# Run individual tests
IexTest.test1()   # Simple arithmetic
IexTest.test3()   # Custom tools
IexTest.test8()   # Python interpreter
IexTest.test11()  # FLUX image generation
IexTest.test12()  # Moondream vision analysis

# Run all tests
IexTest.test_all()

# Custom task
IexTest.run("Calculate the sum of squares from 1 to 100")
```

## 📖 Examples

### Example 1: Simple Calculation

```elixir
config = AgentConfig.new(max_steps: 3)

CodeAgent.run(
  "Calculate 25 * 4, then add 10 to the result",
  config
)
# => {:ok, "110", state}
```

### Example 2: Using Tools

```elixir
alias CodeAgentEx.Tools.WikipediaTools

config = AgentConfig.new(
  tools: [WikipediaTools.wikipedia_search()],
  max_steps: 5
)

CodeAgent.run(
  "Search Wikipedia for information about Elixir programming language and summarize it",
  config
)
```

### Example 3: Managed Agents (Hierarchical)

```elixir
alias CodeAgentEx.{AgentConfig, Tools.PythonTools, Tools.WikipediaTools}

# Create a specialized research agent
researcher = AgentConfig.new(
  name: :researcher,
  instructions: "Specialized agent for finding and summarizing information",
  tools: [WikipediaTools.wikipedia_search()],
  max_steps: 3
)

# Create a specialized calculator agent
calculator = AgentConfig.new(
  name: :calculator,
  instructions: "Specialized agent for complex calculations",
  tools: [PythonTools.python_interpreter()],
  max_steps: 3
)

# Main agent can delegate to both
config = AgentConfig.new(
  managed_agents: [researcher, calculator],
  max_steps: 8
)

CodeAgent.run(
  """
  Use the researcher to find the population of France.
  Then use the calculator to compute the population density
  if the area is 643,801 km².
  """,
  config
)
```

### Example 4: Image Generation with FLUX

```elixir
alias CodeAgentEx.Tools.SmolAgentsTools

config = AgentConfig.new(
  tools: SmolAgentsTools.image_tools(),
  max_steps: 3
)

CodeAgent.run(
  "Generate an image of a sunset over the ocean with vibrant colors",
  config
)
# => Returns an AgentImage struct with path to generated image
```

### Example 5: Vision Analysis with Moondream

```elixir
alias CodeAgentEx.Tools.MoondreamTools

config = AgentConfig.new(
  tools: MoondreamTools.basic_tools(),
  max_steps: 5
)

CodeAgent.run(
  "Generate a caption for the image at /path/to/image.png and tell me what colors are visible",
  config
)
```

## 🏛️ Architecture

```
CodeAgent (main ReAct loop)
├── AgentConfig (configuration)
│   ├── tools: List of available tools
│   ├── managed_agents: Sub-agents for delegation
│   ├── model: LLM model to use
│   ├── max_steps: Maximum iteration limit
│   └── instructions: Custom agent behavior
│
├── Executor (sandboxed code execution)
│   └── Code.eval_string with persistent bindings
│
├── Memory (conversation history)
│   └── Stores messages for context
│
├── Prompts (system prompts)
│   └── Guides LLM behavior
│
└── Tools (available functions)
    ├── PythonTools (execute Python code)
    ├── WikipediaTools (search Wikipedia)
    ├── FinanceTools (stock prices via Yahoo Finance)
    ├── SmolAgentsTools (FLUX, web search via smolagents)
    ├── MoondreamTools (vision: caption, query, detect, point)
    └── Custom tools (define your own!)
```

## 🛠️ Creating Custom Tools

Tools are simple structs with a function:

```elixir
alias CodeAgentEx.Tool

temperature_tool = %Tool{
  name: :get_temperature,
  description: "Returns the current temperature in Celsius for a city. Call with: get_temperature.(city_name)",
  inputs: %{
    "city_name" => %{type: "string", description: "Name of the city"}
  },
  output_type: "number",
  function: fn city ->
    # Your implementation here
    # Could call an API, database, etc.
    case city do
      "Paris" -> 15.5
      "Tokyo" -> 22.0
      _ -> 20.0
    end
  end
}

config = AgentConfig.new(
  tools: [temperature_tool],
  max_steps: 3
)

CodeAgent.run("What's the temperature in Paris?", config)
```

## 🧪 Available Tools

### Core Tools
- **final_answer**: Mark completion and return result (required for all agents)

### Python Integration
- **python_interpreter**: Execute Python code via Pythonx

### Information Retrieval
- **wikipedia_search**: Search Wikipedia articles
- **web_search**: Search the web via DuckDuckGo

### Finance
- **stock_price**: Get current stock prices from Yahoo Finance

### Vision (Moondream API)
- **moondream_caption**: Generate image captions
- **moondream_query**: Answer questions about images
- **moondream_detect**: Detect and locate objects in images
- **moondream_point**: Find points of interest in images

### Image Generation
- **generate_flux_image**: Generate images using FLUX.1-schnell via HuggingFace Spaces

## ⚙️ Configuration Options

```elixir
AgentConfig.new(
  # Agent identity
  name: :my_agent,                    # Agent name (atom)

  # Behavior
  instructions: "Custom instructions", # How agent should behave

  # Tools and delegation
  tools: [tool1, tool2],               # Available tools
  managed_agents: [agent1, agent2],    # Sub-agents for delegation

  # LLM settings
  model: "Qwen/Qwen3-Coder-30B-A3B-Instruct",  # Model to use
  llm_opts: [                          # Additional LLM options
    temperature: 0.7,
    max_tokens: 4000,
    tool_choice: "none"
  ],

  # Execution limits
  max_steps: 10,                       # Maximum iterations

  # Advanced
  backend: :hf,                        # LLM backend (:hf or :openai)
  listener_pid: self(),                # Event listener
  require_validation: false            # User validation before tool use
)
```

## 🎯 Supported Models

The agent works with any OpenAI-compatible API. Tested models:

### Recommended
- **Qwen/Qwen3-Coder-30B-A3B-Instruct** (default) - Best results for code generation

### Also Compatible
- OpenAI models (gpt-4, gpt-3.5-turbo, etc.)
- Any model via HuggingFace Router
- Local models via compatible APIs

## 📚 Dependencies

```elixir
# Core
{:instructor_lite, "~> 1.1.2"}  # Structured LLM outputs with Ecto schemas
{:req, "~> 0.5"}                # HTTP client
{:jason, "~> 1.2"}              # JSON encoding/decoding

# Code execution
{:mini_elixir, github: "sequinstream/mini_elixir"}  # Sandboxed code execution

# Python integration
{:pythonx, "~> 0.4"}            # Python interop for smolagents tools
```

## 🤝 Contributing

Contributions are welcome! Areas for improvement:

- Additional tools (filesystem, database, etc.)
- More LLM providers
- Streaming support for real-time output
- Better error handling and recovery
- Performance optimizations
- Documentation improvements

## 📝 License

MIT

## 🙏 Acknowledgments

- Inspired by [smolagents](https://github.com/huggingface/smolagents) by HuggingFace
- Uses [instructor_lite](https://github.com/martosaur/instructor_lite) for structured LLM outputs
- Vision capabilities powered by [Moondream](https://moondream.ai/)
- Image generation via [FLUX.1-schnell](https://huggingface.co/black-forest-labs/FLUX.1-schnell)

## 🔗 Related Projects

- [smolagents](https://github.com/huggingface/smolagents) - Original Python implementation
- [Langchain](https://github.com/langchain-ai/langchain) - Comprehensive agent framework
- [AutoGPT](https://github.com/Significant-Gravitas/AutoGPT) - Autonomous GPT-4 agent
