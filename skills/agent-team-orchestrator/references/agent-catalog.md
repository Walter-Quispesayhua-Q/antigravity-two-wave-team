# Agent Catalog and Routing Contract

The runtime catalog is generated from `orchestration/agents/*/agent.json`. This file is a maintainer guide, not a second registry.

## Current profiles

| Profile ID | Activation | Primary ownership |
|---|---|---|
| `official-documentation-analyst` | Default evidence | Current first-party documentation, releases, support, standards, advisories |
| `rsh-current-research` | Default evidence | Independent technical research and cross-source verification |
| `community-intelligence-hunter` | Conditional | Developer reports, emerging failures, workarounds, adoption, disagreement |
| `codebase-analysis` | Conditional | Workspace, code, configuration, dependencies, tests, and local state |
| `senior-mentor` | Conditional | Architecture, current practices, risks, trade-offs, recommendations |
| `rigorous-verifier` | Risk-adaptive Wave 2 | Independent falsification and acceptance audit |

## Selection rules

- Fast exemptions may use no subagents.
- Substantive information, research, comparison, and recommendation requests use both default evidence profiles.
- Latest/current/version/release requests are live research, use at least the light tier, and require independent verification; a static product guide is insufficient.
- Conditional profiles run only when materially relevant.
- Every acceptance criterion and risk needs an owner.
- Uncertain routing includes the best match.
- Skipped profiles do not block completion.
- The verifier never runs in Wave 1.

## Performance contract

- Start with canonical direct sources.
- Batch lane-specific discovery queries and independent page inspection when tools support it.
- Do not duplicate the same source across official, independent, and community lanes.
- Revalidate volatile claims live.
- Stop when acceptance criteria, tier targets, direct-link requirements, and contradiction checks are satisfied.
- Keep broad serial page-by-page browsing for genuinely deep or unresolved work.

## Adding a future specialist

Create only:

```text
orchestration/agents/<directory>/agent.json
orchestration/agents/<directory>/SYSTEM.md
```

Declare one or more existing skills, or add a dedicated skill when reusable expertise is needed. Populate `routing` with accurate stage, activation, priority, cost, capabilities, task types, trigger hints, and exclusions. The hook discovers the profile automatically.

Update this guide and tests for maintainability, but do not add a hardcoded profile map.

## Routing safety

Auto-discovery is fail-closed. Every discovered profile must:

- Use schema version 2.
- Have a unique valid ID.
- Resolve inside the plugin root.
- Have a valid UTF-8 `SYSTEM.md`.
- Reference installed skills.
- Be custom, read-only, and non-delegating.
- Declare complete routing and output metadata.
- Respect catalog and payload limits.

An invalid profile blocks orchestration instead of being silently ignored.

## Verification capsule

Include the selected-agent execution ledger, bounded evidence digests, evidence ledger, claim matrix, citation audit, language, pre-audit, criteria, proposed answer, and material links/paths/tests. Exclude raw prompts, duplicate report prose, and progress chatter.

The root Coordinator controls the verification decision and performs the pre-audit. The separate `rigorous-verifier` owns the independent verdict. Use one initial pass and at most one materially corrected final pass.

## Report, citation, and failure semantics

- Every selected profile must execute and return a structured report with a runtime identity.
- `complete`, `partial`, `not-applicable`, and `blocked` are honest report statuses; they do not excuse a missing execution.
- A domain, publisher name, search snippet, or inaccessible result is not a direct citation.
- Recover a missing exact URL once. If recovery fails, remove the unsupported claim and every dependent conclusion or recommendation before verification.
- Fingerprint verifier defects by code and claim ID. Never reverify an unchanged draft for the same defect.
- `MANDATORY_TEAM_NOT_EXECUTED` means a selected agent or required verifier did not execute.
- `FINAL_VERIFICATION_FAILED` means execution completed, but the corrected result did not obtain an allowed verifier verdict.
