# Arca Config Development Guidelines

# Arca.Config Project Guidelines

## Project Documentation

- **IMPORTANT**: Always read `stp/eng/tpd/technical_product_design.md` at the start of a new session
- This document contains comprehensive information about the project vision, architecture, and current state
- The "Preamble to Claude" section at the top is specifically designed to give Claude sessions a complete understanding of the project
- When making significant changes, update this document to keep it in sync with the implementation
- When suggesting improvements, reference and respect the architectural patterns described in this document

- **NEXT**: Work is coordinated through _STEEL THREADS_
- The Steel Threads document `stp/prj/st/steel_threads.md` contains details of each self-contained piece of work.
- Review the Steel Threads document at the start of each session to determine the current state of the project and what is next to be worked on.

- **THEN**: The scratch doc `stp/prj/wip.md` contains the current tasks in progress for each day.
- Use this document to keep track of WIP.

### Configuration File Format

The configuration file uses JSON format:

```json
{
  "key1": "value1",
  "key2": "value2"
}
```

## Code Style Guidelines

- Use `@moduledoc` and `@doc` with examples for all modules and public functions
- Add type specs for public functions with `@spec`
- Format with: `mix format`
- Use snake_case for variables, functions, and modules
- Use 2-space indentation (standard Elixir style)
- Group related functions together; public functions first, private after
- Handle errors with pattern matching or explicit `{:ok, result}` / `{:error, reason}` tuples
- Use descriptive variable names - avoid single-letter names except in very short callbacks
- All functions should have clear, defined purposes with no side effects
- Prefer pipe operators (`|>`) for data transformations
- Use doctest examples in documentation to provide test coverage
- When possible, make functions pure and stateless
- Follow the "sense/infer/act" pipeline pattern and data flow described in the technical design document
- Use the scripts in scripts/* to run Elixir binaries (where they exist)
- DO NOT ADD: "🤖 Generated with [Claude Code](https://claude.ai/code)" or "Co-Authored-By: Claude <noreply@anthropic.com>")" to git commit messages
- Write functional, idiomatic Elixir:
  - Use functional composition with the pipe operator (|>)
  - Use Enum functions directly rather than manually building accumulators
  - Leverage pattern matching instead of conditionals where possible
  - Avoid imperative-style if/then/else constructs in favor of functional approaches
  - Prefer case/with expressions for clear control flow
  - Use pure functional implementations whenever possible
  - Avoid unnecessary reversing lists
  - Write concise, expressive code that embraces functional programming principles

## Backwards Compatibility

- Do not worry about backwards compatability, ather write new code, update, and fail-forward
- We are building new code, so just roll forward with the changes and bring everything up to date with the latest version as we go
- There is no legacy to interact with at this point so backwards compatibility is not necessary
