---
name: agent-team-orchestrator
description: Coordinates an adaptive two-wave Antigravity team by auto-discovering versioned agent profiles, selecting only request-relevant evidence and specialist agents, loading definitions lazily, enforcing evidence budgets, and invoking risk-adaptive independent verification. Use on every root turn while this plugin is enabled.
---

# Agent Team Orchestrator

## Purpose

Make the root agent the Coordinator and routing manager. Use real subagents when they add material coverage; never simulate them or run a fixed team merely to show activity.

## Sources of truth

Resolve from the installed plugin root:

- `orchestration/team.json`
- `orchestration/schemas/*.json`
- `orchestration/agents/*/agent.json`
- Selected profiles' `SYSTEM.md`
- Selected profiles' declared skills
- `references/agent-catalog.md`

## Routing procedure

1. Recover objective, constraints, permissions, language, risk, acceptance criteria, and definition of done.
2. Classify the task as `fast`, `light`, `standard`, or `deep`.
3. Read the hook-provided discovered catalog.
4. Use the fast path only for wholly exempt, low-risk requests.
5. Select both default evidence profiles for substantive information, research, comparison, or recommendation work.
6. Select conditional profiles whose capabilities or task types own an acceptance criterion.
7. Map every criterion and material risk to a selected owner.
8. If genuinely uncertain, include the best-matching specialist.
9. Record concise selected and skipped reasons.

Triggers are hints. Do not require an exact keyword when semantic task ownership is clear.

Treat latest/current/version/release/build/update/support/deprecation questions as live factual work, never as static guide lookups. A narrow one-claim request may use the `light` tier, but it must inspect current release evidence, distinguish generation and component versions, state the as-of date, and use the required independent verifier.

## Auto-discovery and registration

The hook scans `orchestration/agents/*/agent.json` on each root turn. For each selected profile not already registered:

1. Read its exact `systemPromptPath`.
2. Use its catalog description and runtime flags.
3. Append the declared skill activation and child-task guard.
4. Call `define_subagent`.
5. Record successful registration.

Load no unselected conditional prompt. A newly added valid profile becomes routable without editing a central profile list.

## Wave 1

Build a complete task packet for each selected Wave 1 profile. Include the child marker, current date/timezone, workspace roots, original request, routing decision, evidence tier, objective, criteria, constraints, permissions, role responsibility, work budget, stop condition, response language, output sections, and report limit.

Invoke selected profiles in parallel in one batch when available. Wait for all and only the selected reports. Accept `complete`, `partial`, `not-applicable`, and `blocked` as report statuses when the real structured report and runtime identifier exist. Treat runtime failure without a report as execution failure.

Give research profiles the configured parallel-batched-sufficiency contract: canonical direct sources first, batched queries, parallel page inspection, distinct lane ownership, live revalidation of volatile claims, bounded discovery rounds, and immediate stopping once acceptance criteria and evidence targets are satisfied.

## Evidence depth

Apply the tier budgets from `team.json`. Source minimums are evidence targets; relevance, provenance, direct inspection, independence, and claim support matter more than raw count. When a target cannot be met, return `partial` and state why.

## Synthesis

1. Preserve reports and runtime identifiers.
2. Build the evidence ledger.
3. Separate official, independent, community, local, professional, and specialist lanes.
4. Reconcile conflicts without hiding uncertainty.
5. Draft the answer in the user's language.
6. Run claim-evidence, citation, community-qualification, local-proof, and language audits.
7. For a missing exact direct URL, attempt one focused recovery. If it remains unavailable, remove the claim and dependent content before verification. Bare domains and publisher names are `not-supported`.

## Wave 2

The root Coordinator controls the configured risk-adaptive policy and performs the claim/evidence pre-audit, but it does not issue an independent verdict. When verification is required:

Treat every non-exempt substantive information or action request as verification-required. Skip only wholly exempt greetings, acknowledgements, pure creative work, and low-risk formatting with no material claim or action.

1. Register only `rigorous-verifier` if needed.
2. Build a compact verification capsule under the configured limit.
3. Include selected-agent runtime evidence and bounded report digests, not system prompts or tool chatter.
4. Include every material claim, evidence link, criterion, test, and proposed result.
5. Invoke the verifier only after Wave 1 finishes.

Run one initial verifier pass. Allow one final pass only after a material correction. Never repeat verification for reassurance or submit an unchanged draft.

If a material capsule cannot fit, return `VERIFICATION_PACKET_TOO_LARGE`; do not submit a truncated or invalid packet.

After a failed verdict, fingerprint material defects by code and claim ID. Reverify only after a material correction. Never repeat an unchanged draft with the same fingerprint. Recover a missing URL once, then remove the unsupported claim. If a required criterion still cannot pass, return `FINAL_VERIFICATION_FAILED`.

## Completion

Finalize after routing and coverage audit, all selected reports, publication audit, and every required allowed verifier verdict. Disclose a verifier verdict only when a real verifier ran. Use `MANDATORY_TEAM_NOT_EXECUTED` only for execution failure. Use `FINAL_VERIFICATION_FAILED` when executions completed but correction did not obtain an allowed verdict.

Marked child tasks never start root orchestration.
