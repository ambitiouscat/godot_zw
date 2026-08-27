## MODIFIED Requirements

### Requirement: Stage 4 Uses Authoritative GameAbility Evidence

Stage 4 functional and visual QA SHALL execute the game through `run_project`, `run_scene`, or `run_current_scene`, wait for the matching `REAL_RUNNING` session, capture with `take_screenshot(source="game")`, inspect errors and runtime behavior through correlated GameAbility capabilities, and stop with `stop_project`.

#### Scenario: Functional acceptance

- **WHEN** an agent validates gameplay, physics, input, audio, dynamic scene content, Autoload behavior, or scene transitions
- **THEN** it uses standalone `GameAbility`
- **AND** it does not treat the editor viewport as runtime evidence

#### Scenario: Visual acceptance

- **WHEN** an agent presents Stage 4 visual QA evidence
- **THEN** the screenshot reports `actual_source="game_ability"`, a matching active session, a GameAbility-only backend, and verified artifact metadata

### Requirement: Editor Screenshots Are Static Inspection Only

`take_screenshot(source="editor")` MAY be used to inspect editor UI, scene composition, camera placement, and serialized assets. It SHALL NOT satisfy gameplay or final runtime acceptance.

#### Scenario: Editor inspection

- **WHEN** an editor screenshot is captured
- **THEN** the report labels it as editor/static inspection evidence
- **AND** does not infer script execution or runtime parity from it

### Requirement: Simulation Is Not Part of the Workflow

Active protocols, skills, examples, and method discovery SHALL NOT instruct agents to use `simulate_*`, `stop_simulation`, or `source="preview"`.

#### Scenario: Workflow discovery

- **WHEN** an agent reads the active development protocol or MCP documentation
- **THEN** only the authoritative GameAbility run track and editor static-inspection source are described
