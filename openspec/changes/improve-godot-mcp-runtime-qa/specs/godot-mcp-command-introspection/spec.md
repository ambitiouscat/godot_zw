## Purpose

Enables dynamic MCP method discovery, reflection, and backward-compatible alias resolution for all Godot MCP client integrations.

## ADDED Requirements

### Requirement: Input Action Command Alias
The Godot MCP Server SHALL accept dd_input_action as a direct alias for set_input_action without raising method not found errors.

#### Scenario: Calling add_input_action
- **WHEN** client invokes dd_input_action with ction_name (or ction) and event definitions
- **THEN** system configures the project InputMap action and returns a success response.

### Requirement: Dynamic Method Listing and Introspection
The Godot MCP Server SHALL provide reflection commands allowing clients to query available methods and signatures dynamically.

#### Scenario: Listing Registered Commands
- **WHEN** client invokes list_methods
- **THEN** system returns the list of all registered MCP command names and the total count.

#### Scenario: Checking Method Documentation
- **WHEN** client invokes get_documentation with a target method name
- **THEN** system returns whether the method is available and its parameter structure.
