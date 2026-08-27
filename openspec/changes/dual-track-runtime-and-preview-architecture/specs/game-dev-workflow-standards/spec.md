## ADDED Requirements

### Requirement: Dual-Track Verification Workflow
AI development workflows SHALL treat viewport preview as an optional static visual-iteration aid and SHALL use standalone real run as the authoritative source for functional, physics, input, audio, multi-scene, lifecycle, and Stage 4 visual QA acceptance.

#### Scenario: Use preview during scene iteration
- **WHEN** an agent needs to check serialized scene composition, framing, material appearance, or static layout
- **THEN** the agent may invoke `simulate_*`, records preview limitations, and does not claim that preview evidence validates gameplay

#### Scenario: Pass the Stage 4 QA gate
- **WHEN** an agent presents Stage 4 functional or visual QA results
- **THEN** the evidence includes a matching real-run session, `GameAbility` screenshot provenance, relevant logs or errors, explicit stop/exit acknowledgement, and no silent fallback source

#### Scenario: Validate multi-scene behavior
- **WHEN** the feature uses SceneTree replacement, level transitions, project Autoloads, audio, physics, or OS lifecycle events
- **THEN** the agent validates the behavior only through `run_project`, `run_scene`, or `run_current_scene`

