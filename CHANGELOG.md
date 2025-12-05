# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- AI-powered code validation using Instructor.Lite with HuggingFace
- AIValidator module with configurable prompt functions
- Test24: AI validation with sub-agents demonstration
- AgentOrchestrator for centralized agent communication and validation
- Reusable orchestrator with state preservation between tasks
- Custom validation handlers (interactive, AI-powered, logging)
- Support for managed agents (sub-agents) with automatic validation propagation

### Changed
- Refactored validation system from `auto_approve` boolean to flexible `validation_handler` function
- Updated API: removed `require_validation` from agent configs (now handled by orchestrator)
- Return values: `{:ok, result, state}` → `{:ok, result}` (state managed internally)
- Validation flow: agents send validation requests to orchestrator instead of direct send/receive

### Fixed
- GenServer-based agent communication using call/reply instead of send/receive
- Proper cleanup of agent processes via supervision tree
- Context preservation between multiple tasks on same orchestrator

## [0.1.0] - 2025-01-05

### Added
- Initial release
- Core agent system with code generation capabilities
- Tool system for extending agent capabilities
- Python integration via PythonX
- HuggingFace LLM integration
- OpenAI LLM integration
- Multi-agent support (agents can delegate to other agents)
- Interactive testing suite (IexTest module)
- Examples for various use cases (calculations, data processing, image generation)

[Unreleased]: https://github.com/yourusername/code_agent_minimal/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourusername/code_agent_minimal/releases/tag/v0.1.0
