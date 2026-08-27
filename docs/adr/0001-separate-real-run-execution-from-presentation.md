---
status: accepted
---

# Separate Real Run execution from Run Presentation

GDAI will keep Real Run as a complete, independently executing game session and treat floating, split-screen, and fullscreen as presentation choices rather than different execution modes. AI-driven debugging on HarmonyOS will prefer Windowed Real Run so the editor remains visible, using floating presentation first and split-screen second, and will fail rather than silently switch to fullscreen. SubViewport simulation and Embedded Game View are outside this decision: simulation cannot provide runtime parity, while true cross-process embedding requires a separate platform-level investigation.

## Consequences

Run lifecycle and session identity remain independent of window presentation. Tablet window capability must be detected and verified on-device; 2in1 keeps its native window behavior, phone keeps its fullscreen default, and final release QA still includes an explicit fullscreen Real Run.
