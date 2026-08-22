# Domain Documentation

This repository uses a **single-context** domain documentation layout.

## Layout

- **Domain Model**: CONTEXT.md at the repository root.
- **Architectural Decision Records (ADRs)**: docs/adr/ at the repository root.

## Consumer Rules

1. **Read on Start**: When entering a task that touches core system architecture or domain terminology, consult CONTEXT.md.
2. **Consult ADRs**: Before making architectural decisions, check docs/adr/ to understand existing decisions and constraints.
3. **Record Changes**: When introducing new domain concepts or significant architectural patterns, update CONTEXT.md or propose a new ADR in docs/adr/.
