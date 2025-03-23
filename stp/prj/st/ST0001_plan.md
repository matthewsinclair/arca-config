---
verblock: "23 Mar 2025:v0.1: Claude - Initial implementation plan"
---
# ST0001: Arca.Config Implementation Plan

This document outlines the implementation plan for modernizing Arca.Config to align with idiomatic, functional Elixir practices and integrate with the Elixir Registry for runtime configuration management.

## Implementation Approach

The implementation will be completed in phases, each building upon the previous one:

1. **Foundation**: Establish a proper Application and GenServer architecture
2. **Registry Integration**: Implement Registry-based configuration state
3. **API Enhancement**: Redesign the API for modern functional Elixir
4. **CLI Improvements**: Update CLI to work with the new architecture
5. **Testing & Documentation**: Ensure comprehensive test coverage and documentation

## Phase 1: Foundation (Application Architecture)

### Checkpoints

- [ ] Design a proper supervision tree for Arca.Config
- [ ] Implement a ConfigServer GenServer for state management
- [ ] Set up Application start/stop callbacks
- [ ] Create an ETS table for caching configuration values
- [ ] Implement basic state management functions

### Technical Details

1. **Supervision Tree**:
   - Create a dynamic supervisor for config subscribers
   - Initialize the ConfigServer under the main supervisor
   - Set up proper restart strategies

2. **ConfigServer Implementation**:
   - GenServer to maintain the current configuration state
   - Initialize from the configuration file on startup
   - Provide synchronized file access for reads/writes
   - Implement caching with ETS

3. **Runtime State Management**:
   - Track configuration file path and loaded state
   - Synchronize file operations to prevent corruption
   - Maintain in-memory representation of configuration

## Phase 2: Registry Integration

### Checkpoints

- [ ] Set up Registry for config key registration
- [ ] Implement publisher-subscriber pattern for config changes
- [ ] Create subscription/watch API for config keys
- [ ] Add notification system for configuration changes
- [ ] Test Registry behavior with multiple processes

### Technical Details

1. **Registry Setup**:
   - Create a Registry for subscribing to specific config keys
   - Register processes interested in particular config values
   - Implement key lookup via Registry

2. **Change Notifications**:
   - Dispatch notifications when config values change
   - Allow subscribing to specific keys or key patterns
   - Support wildcard subscriptions

3. **Key Tracking**:
   - Track active subscribers for each key
   - Optimize notifications to only relevant processes

## Phase 3: API Enhancement

### Checkpoints

- [ ] Redesign the API to be more functional
- [ ] Implement improved error handling
- [ ] Create type validation system
- [ ] Add helper functions for common patterns
- [ ] Establish key/path module for nested access
- [ ] Ensure backward compatibility with existing API

### Technical Details

1. **Functional API Design**:
   - Use pipe operators for data transformations
   - Implement `with` statements for cleaner error handling
   - Create pure functions where possible
   - Extract side effects into dedicated functions

2. **Enhanced Error Handling**:
   - Implement detailed error structs with context
   - Add validation for configuration values
   - Improve error reporting

3. **Type System**:
   - Support explicit type definitions for config values
   - Add schema validation
   - Implement type coercion for common patterns

## Phase 4: CLI Improvements

### Checkpoints

- [ ] Update the CLI to use the new API
- [ ] Add commands for watching config changes
- [ ] Implement configuration import/export
- [ ] Add environment-specific commands
- [ ] Enhance output formatting

### Technical Details

1. **Command Updates**:
   - Adapt existing get/set/list commands
   - Add watch command for monitoring changes
   - Support importing/exporting configuration

2. **Output Formatting**:
   - Improve JSON output formatting
   - Add support for different output formats
   - Enhance error reporting

## Phase 5: Testing & Documentation

### Checkpoints

- [ ] Write comprehensive tests for new modules
- [ ] Update existing tests
- [ ] Create property-based tests for complex behaviors
- [ ] Add doctests and examples
- [ ] Update module and function documentation
- [ ] Create user guide and examples

### Technical Details

1. **Test Coverage**:
   - Unit tests for core functionality
   - Integration tests for the full system
   - Performance tests for concurrent operations

2. **Documentation**:
   - Update all @moduledoc and @doc strings
   - Add examples to all public functions
   - Create a user guide

## Implementation Timeline

1. **Phase 1**: 2 days
2. **Phase 2**: 2 days
3. **Phase 3**: 2 days
4. **Phase 4**: 1 day
5. **Phase 5**: 1 day

**Total Estimated Time**: 8 days

## Detailed Prompt for Claude Code

```
# Arca.Config Modernization Task

I need to modernize the Arca.Config library to follow idiomatic functional Elixir practices and integrate with Elixir Registry for runtime configuration management. The current implementation is too imperative and doesn't make use of proper process architecture.

## Current Implementation Issues

1. The code uses imperative-style control flow instead of functional composition
2. All operations read/write directly to files with no caching
3. No proper Application supervision tree
4. No use of Registry for config state management
5. No way to subscribe to configuration changes
6. Inefficient for frequent access patterns

## Requirements for the New Implementation

1. Create a proper Application with supervision tree
2. Implement a ConfigServer GenServer for state management
3. Use Registry for runtime configuration state
4. Maintain file-based persistence as a backing store
5. Provide notification mechanisms for config changes
6. Follow functional programming principles:
   - Use pipe operators for data transformations
   - Implement with statements for error handling
   - Create pure functions where possible
   - Isolate side effects

## Key Features to Implement

1. In-memory caching of configuration values
2. Ability to subscribe to specific config keys
3. Notifications when config values change
4. Proper error handling with context
5. Type validation and coercion
6. Improved CLI with watch capabilities

Please help me implement this modernization while ensuring compatibility with existing API users.
```

This prompt can guide Claude through the process of modernizing Arca.Config, focusing on idiomatic Elixir practices and integrating with Registry for improved runtime configuration management.
