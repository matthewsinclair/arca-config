# Arca Config Development Guidelines

## Build & Run Commands
- Build project: `mix compile`
- Run IEx with project: `./scripts/iex`
- Run CLI: `./scripts/cli`
- Format code: `mix format`
- Run all tests: `./scripts/test`
- Run single test: `./scripts/test test/config/cfg_test.exs:LINE_NUMBER`
- Generate docs: `mix docs`

## Code Style Guidelines
- Follow standard Elixir style (2 space indentation, no trailing whitespace)
- Prefer pipe operator (`|>`) for sequential operations
- Use atoms for keys in internal maps, strings for user-facing maps
- Document functions with clear `@doc` comments and doctests
- Return `{:ok, result}` or `{:error, reason}` for functions that can fail
- Provide bang variants (`function!`) for functions with error handling
- Use proper typespec annotations for all public functions
- Prefer pattern matching over conditionals where applicable
- Keep functions small and focused on a single responsibility
- Use existing project modules/patterns when extending functionality

## Error Handling
- Never silence errors, always handle or propagate them
- Use `with` statements for complex error handling flows
- Meaningful error messages should be returned rather than generic ones