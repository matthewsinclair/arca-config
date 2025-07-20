---
verblock: "23 Mar 2025:v0.2: Claude-assisted - Marked as completed"
stp_version: 1.0.0
status: Completed
created: 20250322
completed: 20250323
---
# ST0001: Reconciling Arca.Config with Elixir Registry

## Overview

This steel thread successfully integrated Arca.Config with Elixir Registry and implemented additional features like file watching and callbacks for configuration changes.

## Requirements

Arca.Config needed to meet these requirements:

1. Provide a unified way to store and retrieve runtime configuration params in a file that is automatically loaded at runtime.
2. Allow an app to easily write back config changes that persist to the config file and are available on subsequent app invocations.
3. Provide an easy-to-use lookup mechanism to access configuration data via a simple API.

Additionally, we wanted to:
4. Detect changes to configuration files made externally and reload appropriately
5. Provide notifications when configuration changes through a subscription system
6. Allow components to register callbacks to react to configuration changes
7. Support asynchronous file operations to avoid blocking
8. Prevent notification loops when the application itself changes the config

## Implementation Summary

We successfully implemented all requirements by:

1. **Integration with Elixir Registry**:
   - Used Registry with duplicate keys for subscription management
   - Created a separate CallbackRegistry for change callbacks
   - Implemented proper message passing for notifications

2. **File Watching**:
   - Created a FileWatcher GenServer to monitor config file changes
   - Used file timestamps to detect external modifications
   - Implemented a token system to prevent notification loops for self-initiated changes

3. **Callback System**:
   - Added a callback registration system for external code
   - Implemented process isolation for callbacks to prevent cascading failures
   - Added proper error handling for callback execution

4. **Asynchronous Operations**:
   - Implemented asynchronous file writes using Task.start
   - Made notification dispatching asynchronous to avoid blocking
   - Added proper cleanup to prevent resource leaks

5. **Caching Improvements**:
   - Enhanced the ETS-based cache system for better resilience
   - Implemented proper invalidation for nested keys
   - Added cache rebuilding on configuration reload

6. **API Improvements**:
   - Maintained backward compatibility with existing API
   - Added new functions for subscription and callback management
   - Used railway-oriented programming with {:ok, result}/{:error, reason} tuples

## Documentation

Comprehensive documentation has been created:

1. Technical Product Design (TPD) in `stp/eng/tpd/technical_product_design.md`
2. User Guide in `stp/usr/user_guide.md`
3. Reference Guide in `stp/usr/reference_guide.md`
4. Deployment Guide in `stp/usr/deployment_guide.md`
5. Upgrade Prompt in `stp/prj/st/ST0001_upgrade_prompt.md`

## Upgrade Path

For existing applications using Arca.Config, an upgrade path was defined:

1. Update dependency to the latest version
2. Update supervision tree if manually starting Arca.Config
3. Migrate any custom change detection to use the new callback system
4. Update components to use the subscription system if needed

A detailed upgrade prompt for Claude Code is available in `ST0001_upgrade_prompt.md`.

## Conclusion

The implementation successfully modernized Arca.Config with idiomatic Elixir patterns, integrated with Registry, and added important new features like file watching and callbacks. All tests are passing, and the code is now more robust, functional, and maintainable.