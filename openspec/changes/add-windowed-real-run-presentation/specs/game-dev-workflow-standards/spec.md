## ADDED Requirements

### Requirement: Presentation-Aware Real-Run QA Workflow
AI development workflows SHALL use authoritative standalone GameAbility execution for functional and visual QA. Iterative MCP runs on HarmonyOS SHALL use the recommended `windowed` presentation policy so EditorAbility remains visible and controllable, while final Stage 4 release/fullscreen acceptance SHALL use an explicit `fullscreen` request. In-editor static inspection or any deprecated preview mechanism SHALL NOT be presented as real-run evidence.

#### Scenario: Iterate on a tablet without losing editor control
- **WHEN** an AI agent starts an iterative real run on the target tablet
- **THEN** it requests or accepts the MCP default `presentation: "windowed"`, verifies the actual floating or split presentation, and records matching GameAbility session evidence

#### Scenario: Do not treat 2-in-1 evidence as tablet acceptance
- **WHEN** a native-window real run passes on the currently connected HarmonyOS 2-in-1
- **THEN** the workflow records it as regression evidence and keeps tablet acceptance pending until the designated tablet is tested

#### Scenario: Complete final Stage 4 QA
- **WHEN** an agent presents final Stage 4 release/fullscreen results
- **THEN** the evidence includes an explicit fullscreen real-run session, an authoritative `source: "game"` capture, relevant diagnostics, and correlated terminal lifecycle outcome

#### Scenario: Reject non-authoritative preview evidence
- **WHEN** a static editor view, SubViewport preview, or system-composited screenshot is offered as proof of runtime scripts, input, audio, lifecycle, or final visuals
- **THEN** the workflow rejects it as non-authoritative and requires matching GameAbility evidence

### Requirement: Device Evidence and Blocker Reporting
AI development workflows SHALL report requested and actual presentation, detected device category, capability source, `session_id`, and capture provenance for presentation-sensitive acceptance. If the target tablet cannot automatically launch floating or split GameAbility through public application capabilities, the workflow SHALL report a platform blocker and SHALL NOT use manual system-toolbar conversion or silent fullscreen fallback to pass the change. Embedded Game View investigation SHALL be proposed separately rather than added to this change.

#### Scenario: Report a successful tablet run
- **WHEN** tablet acceptance succeeds
- **THEN** the evidence identifies the automatic presentation path, actual floating or split result, device and capability data, session correlation, and authoritative capture

#### Scenario: Report a platform limitation honestly
- **WHEN** automatic floating and split launch are both unavailable on the target tablet
- **THEN** the workflow records the platform limitation, leaves this acceptance incomplete, and may recommend a separate Embedded Game View research change

