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
- **Core Library**: Lightweight with no external dependencies beyond LLM client
- **Parameterized Tools**: Tools can accept arguments for maximum flexibility
- **Extended Tools**: Python-based tools (Wikipedia, Finance, Images, etc.) available in separate `code_agent_ex_tools` project

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
```

**Option 2: Use environment variables in your project**

```bash
# Set environment variables
export HF_TOKEN=hf_your_token_here
```

Most functions accept an `api_key` option, so you can manage credentials however you prefer.

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

The project includes 9 basic tests:

```elixir
# In IEx
alias CodeAgentEx.IexTest

# Run individual tests
IexTest.test1()   # Simple arithmetic
IexTest.test2()   # List manipulation
IexTest.test3()   # Custom tools
IexTest.test4()   # Conditional logic
IexTest.test5()   # Multiple tools
IexTest.test6()   # Data processing
IexTest.test7()   # Data filtering
IexTest.test8()   # Managed agents (hierarchical)
IexTest.test9()   # AI-powered validation (requires HF_TOKEN)

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

### Example 2: Custom Tools

```elixir
alias CodeAgentEx.Tool

# Define a custom tool
user_data_tool = %Tool{
  name: :get_user_data,
  description: "Returns a map with user information including name, age, and test scores",
  inputs: %{},
  output_type: "map",
  function: fn ->
    %{
      name: "Alice",
      age: 30,
      scores: [85, 92, 78, 95, 88]
    }
  end
}

config = AgentConfig.new(
  tools: [user_data_tool],
  max_steps: 5
)

CodeAgent.run(
  "Get the user data and calculate their average test score",
  config
)
```

### Example 3: Managed Agents (Hierarchical)

```elixir
alias CodeAgentEx.{AgentConfig, Tool}

# Create a specialized data processor agent
processor = AgentConfig.new(
  name: :data_processor,
  instructions: "Specialized agent for processing and analyzing data",
  tools: [],
  max_steps: 3
)

# Main agent can delegate to the processor
config = AgentConfig.new(
  managed_agents: [processor],
  max_steps: 8
)

CodeAgent.run(
  "Use the data_processor to analyze a list of numbers and find statistics",
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
    └── Custom tools (define your own!)

Note: Python-based tools (Wikipedia, Finance, Images, Moondream, etc.)
have been moved to the separate `code_agent_ex_tools` project.
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

## 🧪 Tool System

### Core Library

CodeAgentEx core is **lightweight** with **zero external dependencies** beyond the LLM client. The agent can:

- Execute Elixir code with persistent bindings
- Use custom tools you define
- Delegate to managed sub-agents

### Custom Tools

Define tools as simple structs:

```elixir
alias CodeAgentEx.Tool

%Tool{
  name: :my_tool,
  description: "Description of what the tool does",
  inputs: %{"param" => %{type: "string", description: "Parameter description"}},
  output_type: "string",
  function: fn param -> "result" end
}
```

### Extended Tools (Separate Project)

Python-based tools have been moved to the `code_agent_ex_tools` project:

- **Wikipedia**: Search and retrieve Wikipedia articles
- **Finance**: Stock prices via Yahoo Finance
- **Web Search**: DuckDuckGo web search
- **Python Interpreter**: Execute arbitrary Python code
- **Image Generation**: FLUX.1-schnell via HuggingFace
- **Vision**: Moondream API for image analysis

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
  adapter: InstructorLite.Adapters.ChatCompletionsCompatible,  # InstructorLite adapter
  llm_opts: [                          # Additional LLM options
    temperature: 0.7,
    max_tokens: 4000,
    tool_choice: "none"
  ],

  # Execution limits
  max_steps: 10,                       # Maximum iterations

  # Advanced
  listener_pid: self(),                # Event listener
  response_schema: MyCustomSchema      # Custom Ecto schema for final response
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

CodeAgentEx core has **minimal dependencies**:

```elixir
{:instructor_lite, "~> 1.1.2"}  # Structured LLM outputs with Ecto schemas
{:req, "~> 0.5"}                # HTTP client
{:jason, "~> 1.2"}              # JSON encoding/decoding
```

That's it! No Python, no external services, just pure Elixir.

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

## 🔗 Related Projects

- [smolagents](https://github.com/huggingface/smolagents) - Original Python implementation
- [Langchain](https://github.com/langchain-ai/langchain) - Comprehensive agent framework
- [AutoGPT](https://github.com/Significant-Gravitas/AutoGPT) - Autonomous GPT-4 agent
