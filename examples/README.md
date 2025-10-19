# Claude Code SDK Examples

This directory contains comprehensive examples showcasing all major use cases of the Claude Code SDK for Elixir.

## 🚀 Quick Start Examples

Run any example with: `mix run examples/<example_name>.exs`

## 📂 Available Examples

### 🔄 Runtime Control (v0.5.0)

- [`runtime_control/model_switcher.exs`](runtime_control/model_switcher.exs) — demonstrates switching models mid-session with deterministic mock transport responses (`--live` enables CLI transport).
- [`runtime_control/transport_swap.exs`](runtime_control/transport_swap.exs) — compares custom mock transport configurations, including artificial latency, and prints raw control frames.
- [`runtime_control/subscriber_broadcast.exs`](runtime_control/subscriber_broadcast.exs) — shows how multiple subscribers receive assistant and control updates in lockstep.

Run them with:

```bash
mix run examples/runtime_control/model_switcher.exs
mix run examples/runtime_control/transport_swap.exs
mix run examples/runtime_control/subscriber_broadcast.exs
```

### 🔍 Code Analysis & Review

#### [`code_review_bot.exs`](code_review_bot.exs)
Automated code review for Git commits, pull requests, and individual files.

```bash
# Review latest commit
mix run examples/code_review_bot.exs

# Review specific file
mix run examples/code_review_bot.exs file lib/my_module.ex

# Review entire directory
mix run examples/code_review_bot.exs dir lib/

# Review pull request (requires gh CLI)
mix run examples/code_review_bot.exs pr 123
```

**Features:**
- Git commit diff analysis
- File-by-file code review
- Directory-wide quality assessment
- Pull request review integration
- Automated report generation

### 🧪 Test Generation

#### [`test_generator.exs`](test_generator.exs)
Comprehensive test suite generation for Elixir modules.

```bash
# Generate unit tests
mix run examples/test_generator.exs lib/my_module.ex

# Generate property-based tests
mix run examples/test_generator.exs lib/my_module.ex property

# Generate integration tests
mix run examples/test_generator.exs lib/my_module.ex integration

# Generate all test types
mix run examples/test_generator.exs lib/my_module.ex all
```

**Features:**
- ExUnit test generation
- Property-based testing with StreamData
- Integration test scaffolding
- Test fixing and optimization
- Coverage analysis suggestions

### 📚 Documentation Generation

#### [`doc_generator.exs`](doc_generator.exs)
Automated documentation generation for Elixir projects.

```bash
# Generate all documentation
mix run examples/doc_generator.exs lib/

# Generate module-specific docs
mix run examples/doc_generator.exs lib/ module lib/my_module.ex

# Generate changelog from git history
mix run examples/doc_generator.exs lib/ changelog

# Generate contributing guide
mix run examples/doc_generator.exs lib/ contributing
```

**Features:**
- API reference generation
- Getting started guides
- Architecture overviews
- Example collections
- Changelog generation
- Contributing guidelines

### 🤖 Interactive Development

#### [`project_assistant.exs`](project_assistant.exs)
Interactive development assistant with real-time code analysis.

```bash
# Start interactive session
mix run examples/project_assistant.exs
```

**Commands Available:**
- `analyze <file>` - Comprehensive code analysis
- `refactor <file>` - Refactoring suggestions
- `debug <file>` - Debug assistance
- `optimize <file>` - Performance optimization
- `test <file>` - Test generation suggestions
- `explain <file>` - Code explanation
- `compare <file1> <file2>` - File comparison
- `scaffold <type>` - Generate boilerplate code

**Scaffold Types:**
- `genserver` - GenServer boilerplate
- `supervisor` - Supervisor boilerplate
- `liveview` - Phoenix LiveView component
- `module` - Basic module template
- `test` - Test template

### 🏭 Batch Processing

#### [`batch_processor.exs`](batch_processor.exs)
Batch processing for multiple files and tasks.

```bash
# Process directory with code reviews
mix run examples/batch_processor.exs dir lib/ code_review

# Process with concurrency
mix run examples/batch_processor.exs dir src/ add_comments --concurrent 3

# Process task list
mix run examples/batch_processor.exs tasks my_tasks.txt
```

**Available Operations:**
- `code_review` - Perform code reviews
- `add_comments` - Add documentation and comments
- `generate_tests` - Generate test suites
- `refactor` - Refactor code for quality
- `security_audit` - Security vulnerability analysis
- `optimize` - Performance optimization
- `document` - Generate documentation

**Features:**
- Concurrent processing with rate limiting
- Progress tracking and reporting
- Error handling and recovery
- Summary report generation
- Task list processing

## 🛠️ Setup and Prerequisites

1. **Install dependencies:**
   ```bash
   mix deps.get
   ```

2. **Authenticate Claude CLI:**
   ```bash
   claude login
   ```

3. **Verify setup:**
   ```bash
   mix run final_test.exs
   ```

## 📋 Example Use Cases by Industry

### 🏢 Enterprise Development

```bash
# Code quality audit for enterprise codebase
mix run examples/batch_processor.exs dir lib/ security_audit

# Generate comprehensive documentation
mix run examples/doc_generator.exs lib/

# Automated code review for compliance
mix run examples/code_review_bot.exs dir lib/
```

### 🚀 Startup Development

```bash
# Rapid prototyping with scaffolding
mix run examples/project_assistant.exs
# > scaffold genserver
# > scaffold liveview

# Quick test generation for MVP
mix run examples/test_generator.exs lib/core_module.ex all

# Documentation for investors/stakeholders
mix run examples/doc_generator.exs lib/
```

### 🎓 Educational Projects

```bash
# Explain complex code to students
mix run examples/project_assistant.exs
# > explain lib/complex_algorithm.ex

# Generate learning materials
mix run examples/doc_generator.exs lib/

# Code review for learning
mix run examples/code_review_bot.exs file student_submission.ex
```

### 🔬 Research & Open Source

```bash
# Generate contributing guidelines
mix run examples/doc_generator.exs lib/ contributing

# Comprehensive documentation for community
mix run examples/doc_generator.exs lib/

# Code quality improvements
mix run examples/batch_processor.exs dir lib/ optimize
```

## 🔧 Customization

### Adding Custom Operations

Extend `batch_processor.exs` with custom operations:

```elixir
defp apply_operation(content, file_path, "custom_analysis") do
  """
  Perform custom analysis on this code:
  
  File: #{file_path}
  ```
  #{content}
  ```
  
  Custom requirements here...
  """
end
```

### Creating New Examples

1. Create new `.exs` file in `examples/`
2. Follow the pattern of existing examples
3. Add to this README
4. Include CLI interface and help text

## 🐛 Troubleshooting

### Common Issues

1. **Authentication errors:**
   ```bash
   claude auth status
   claude login
   ```

2. **Module not found:**
   ```bash
   # Use mix run instead of elixir
   mix run examples/example.exs
   ```

3. **Timeout issues:**
   - Reduce batch size
   - Increase timeout in options
   - Use sequential processing

### Debug Mode

Add debug output to any example:

```elixir
# In any example, add this before ClaudeAgentSDK.query:
IO.puts("🔧 Debug: Sending prompt: #{inspect(prompt)}")
```

## 📚 Further Reading

- [📋 Comprehensive Manual](../COMPREHENSIVE_MANUAL.md) - Complete SDK documentation
- [📖 Main README](../README.md) - Quick start and API reference
- [🏗️ Architecture Guide](../ARCHITECTURE.md) - Internal design and patterns

## 🤝 Contributing

To add new examples:

1. Follow existing patterns and naming conventions
2. Include comprehensive help text and CLI interface
3. Add error handling and validation
4. Update this README with usage instructions
5. Test thoroughly with different input types

## 📄 License

Apache License 2.0 - same as the main project.
