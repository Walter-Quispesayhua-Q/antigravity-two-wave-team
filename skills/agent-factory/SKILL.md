---
name: agent-factory
description: Creates or revises auto-discovered versioned custom-agent profiles, routing metadata, system prompts, skill mappings, permissions, output contracts, and validation cases for this Antigravity plugin. Use only when adding or changing agents.
---

# Agent Factory

## Purpose

Add or revise agents without weakening orchestration, security, portability, or validation.

Use the project-owned schemas and templates. Do not invent incompatible profile structures.

## Sources of truth

Read:

- `<plugin-root>/orchestration/schemas/agent.schema.json`
- `<plugin-root>/orchestration/schemas/team.schema.json`
- `<plugin-root>/orchestration/team.json`
- `references/agent-definition-template.md`
- `agent-team-orchestrator/references/agent-catalog.md`

## Procedure

1. Define the missing responsibility.
2. Confirm an existing agent or skill cannot handle it.
3. Decide whether the agent is `default-evidence`, `conditional`, or the single `verifier`.
4. Define precise inputs and stop conditions.
5. Select least-privilege tools.
6. Define the output contract.
7. Create:
    - Agent directory.
    - `agent.json`.
    - `SYSTEM.md`.
    - Dedicated skill when necessary.
8. Declare accurate routing capabilities, task types, trigger hints, exclusions, priority, and cost.
9. Let directory auto-discovery register the profile; edit `team.json` only when changing global routing or budgets.
10. Add or update the maintainer catalog.
11. Add positive, negative, discovery, selection, failure, and recursion tests.
12. Validate all references.
13. Document compatibility and migration impact.

## Design rules

A good agent has:

- One primary responsibility.
- Clear activation criteria.
- Explicit non-goals.
- Bounded inputs.
- Least privilege.
- A deterministic output contract.
- Accurate semantic routing metadata.
- Honest failure states.
- A clear Coordinator handoff.
- No hidden dependency on a user-specific path.
- No hardcoded current date or current version.

## Permission rules

Default to:

- MCP tools disabled unless evidence access is necessary.
- Write tools disabled for research, analysis, mentorship, and verification.
- Subagent tools disabled unless nested delegation is explicitly justified.
- User and parent safety permissions always inherited.

Do not enable a capability merely because it may be convenient.

## Orchestration rules

- Do not create a Coordinator subagent.
- Do not create a second Coordinator or routing-manager agent.
- Do not place the verifier in Wave 1.
- Do not let a child task recursively start root orchestration.
- Do not classify a specialist as default evidence merely to force execution.
- Keep the dependency graph acyclic.
- Define how failures affect finalization.
- Keep prompt loading lazy so catalog growth does not inflate every root turn.

## Prompt rules

`SYSTEM.md` must define:

- Role.
- Expected input.
- Procedure.
- Evidence rules.
- Permission boundaries.
- Completion rules.
- Exact output contract.

Keep shared methodology in skills rather than duplicating it across every system prompt.

## Validation

For every new or revised agent verify:

- JSON syntax.
- Schema compliance.
- Profile ID uniqueness.
- Profile-map consistency.
- Auto-discovery from a single agent directory.
- Routing metadata completeness and semantic selection cases.
- `SYSTEM.md` existence.
- Skill existence.
- Permission policy.
- Required output headings.
- Stage and activation compatibility.
- Dependency correctness.
- Child-marker recursion prevention.
- Missing-input behavior.
- Failure behavior.
- No secrets or personal paths.
- Cross-platform text encoding.

## Guardrails

- Do not edit the user's working global `.gemini` configuration during plugin development.
- Do not publish transcripts, brain data, credentials, logs, or local paths.
- Do not claim an agent works until a real invocation test passes.
- Do not use role-play headings as evidence of subagent execution.
- Do not add unsupported official-schema fields.

## Output

When creating or revising an agent, return:

- Responsibility.
- Files added or changed.
- Permissions.
- Team integration.
- Output contract.
- Tests required.
- Compatibility impact.
- Remaining uncertainty.
