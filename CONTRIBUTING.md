# Contributing to Antigravity Adaptive Two-Wave Team

Thank you for helping improve the project. This repository is an experimental Antigravity plugin, so a contribution must preserve execution truth, evidence quality, least privilege, and bounded orchestration--not only make the happy path appear successful.

> [!NOTE]
> An explicit open-source license has not yet been selected. The repository owner should add a `LICENSE` file before accepting external contributions.

## Development environment

The current implementation and validation target is Windows:

- Windows PowerShell 5.1 (`powershell.exe`)
- Git
- A current Antigravity Desktop, IDE, or CLI build for manual integration testing

Fork or clone the repository, create a focused branch, and run the baseline suite before editing:

```powershell
git checkout -b feat/short-description
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

Do not develop directly inside Antigravity's installed plugin directory. Keep the repository as the source of truth, validate it, then copy or install that revision into the target surface.

## Architecture invariants

All changes must preserve these properties unless an approved design change explicitly replaces them:

1. The root Antigravity agent is the Coordinator and routing manager.
2. A marked child task never starts another root team.
3. The hook activates once after each latest explicit root-user message.
4. Profiles are discovered from `orchestration/agents/*/agent.json`; there is no hardcoded agent registry.
5. Fast-path requests may avoid subagents, while substantive factual tasks use the default evidence lanes.
6. Conditional profiles run only when they own an acceptance criterion or material risk.
7. Selected Wave 1 profiles execute in parallel when the runtime supports it.
8. Research starts from direct sources, batches discovery, avoids cross-lane duplication, and stops at evidence sufficiency.
9. The root manager controls verification policy but never replaces the independent Wave 2 verdict.
10. Verification receives a bounded capsule rather than complete prompts and transcripts.
11. Every profile remains read-only and non-delegating.
12. Missing execution, missing evidence, and failed verification remain visible; never simulate success.

## Sources of truth

- `plugin.json`: package identity and description.
- `hooks.json`: hook registration.
- `orchestration/team.json`: activation, discovery, routing, waves, budgets, performance, publication, failure, and final-gate policies.
- `orchestration/schemas/*.json`: machine-readable configuration contracts.
- `orchestration/agents/<id>/agent.json`: discoverable profile and routing metadata.
- `orchestration/agents/<id>/SYSTEM.md`: profile-specific behavior.
- `rules/*.md`: global coordinator and evidence policies.
- `skills/*/SKILL.md`: reusable workflows loaded through progressive disclosure.
- `scripts/mandatory-agent-reminder.ps1`: runtime discovery and root-turn injection.
- `tests/run-tests.ps1`: executable project contract.

Avoid defining the same policy independently in several places. When duplication is necessary for runtime injection, add a test that proves the representations remain aligned.

## Add a new agent

### 1. Define a clear responsibility

Add a specialist only when it owns a reusable category of work that existing profiles cannot cover cleanly. A narrow keyword is not enough. Define:

- What acceptance criteria the profile can own.
- Which tasks should activate it.
- Which tasks should explicitly exclude it.
- What evidence or artifacts it must return.
- Why a dedicated skill or profile is preferable to a coordinator instruction.

### 2. Create the profile directory

```text
orchestration/agents/<agent-id>/agent.json
orchestration/agents/<agent-id>/SYSTEM.md
```

Use a lowercase kebab-case directory and profile ID.

### 3. Implement `agent.json`

Follow `orchestration/schemas/agent.schema.json` and the existing profiles. Required design points include:

- `schemaVersion: 2`
- A unique stable `id`
- An accurate `description`
- `systemPrompt: "SYSTEM.md"`
- Existing skill IDs, or a separately implemented reusable skill
- `routing.stage`, `activation`, `priority`, and `cost`
- Specific `capabilities`, `taskTypes`, `triggers`, and `exclusions`
- `runtime.kind: "custom"`
- `runtime.enableWriteTools: false`
- `runtime.enableSubagentTools: false`
- A structured `outputContract`

Enable MCP tools only when the role materially needs them. Tool availability is not permission to use every tool.

### 4. Write `SYSTEM.md`

Keep the prompt scoped to the profile's responsibility. It should define:

- Role and boundaries.
- Required inputs.
- Evidence or inspection method.
- Stop conditions.
- Required output sections.
- Honest `complete`, `partial`, `not-applicable`, and `blocked` semantics.
- Prohibition on delegation and simulated execution.

Do not copy the entire coordinator policy into every profile.

### 5. Add or reuse a skill

Reuse an existing skill when the workflow is already represented. Add `skills/<skill-id>/SKILL.md` only for reusable expertise or a reusable procedure. A skill is a progressively disclosed instruction package; it is not an independently executing agent.

Each skill must have valid frontmatter:

```yaml
---
name: skill-id
description: A precise explanation of when Antigravity should use this skill.
---
```

The `name` must match the folder name.

### 6. Update documentation and tests

- Add the profile to the catalog table in `README.md` and `skills/agent-team-orchestrator/references/agent-catalog.md`.
- Update the expected profile count and routing composition in `tests/run-tests.ps1`.
- Add a focused assertion for new safety or routing behavior.
- Do not add a hardcoded runtime registry; the hook must continue to auto-discover profiles.

## Change routing or verification

Routing changes can alter cost, latency, and answer quality. A pull request should explain:

- The misrouting or missing coverage observed.
- A representative user request.
- Old and proposed selected profiles.
- Effect on fast, light, standard, and deep tiers.
- Whether token, source, report, or verifier budgets change.
- How false negatives and unnecessary agent launches are prevented.

Verification policy belongs to the root manager configuration and coordinator rules. The verdict must remain owned by the independent `rigorous-verifier` profile. Do not merge the verifier into the manager merely to reduce latency; reduce packet duplication, avoid irrelevant profiles, or improve pre-audit instead.

## Change research behavior

Preserve the lane boundaries:

- Official Documentation Analyst: first-party sources and attributable maintainer statements.
- RSH: genuinely independent research and technical reporting.
- Community Intelligence: original developer reports and community signals.
- Codebase Analysis: local project evidence.
- Senior Mentor: professional synthesis of principles, constraints, and trade-offs.

Material external claims require exact page URLs. Search snippets, publisher names, and bare domains are discovery evidence, not final citations. Community evidence must remain qualified and cannot override official support statements by popularity alone.

For current or volatile facts, use the actual execution date and perform live revalidation. Never hardcode a product version as current.

## Change the hook

`scripts/mandatory-agent-reminder.ps1` is security- and reliability-sensitive. Hook changes must preserve:

- JSON input/output behavior.
- Explicit fail-closed packets for invalid configuration or input.
- Latest-user-message activation and same-turn deduplication.
- Child recursion prevention.
- Path containment and safe profile discovery.
- Payload and profile limits.
- UTF-8 output.
- No personal absolute paths or fixed product versions.

Add a fixture under `tests/fixtures/` for every new transcript-state behavior.

## Testing

Run the complete suite from the repository root:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

The suite validates JSON parsing, PowerShell syntax, schemas, profile safety, skill metadata, rule limits, runtime auto-discovery, routing composition, injected policies, hook markers, transcript behavior, recursion guards, fail-closed errors, and portability.

After automated tests pass, perform a manual smoke test on the surfaces affected by the change:

### Desktop or IDE

1. Install the tested repository revision in a global or workspace plugin directory.
2. Start a new conversation.
3. Verify a fast-path request does not start unnecessary research.
4. Verify a current factual request starts the appropriate evidence lanes and verifier.
5. Inspect all direct citations and reported limitations.

### CLI

1. Run `agy plugin install <repository-path>`.
2. Confirm the revision with `agy plugin list`.
3. Inspect `/hooks` in a new CLI session.
4. Run the same fast-path and substantive smoke tests.

Manual success messages are not a substitute for the automated suite or runtime execution evidence.

## Coding and documentation style

- Use UTF-8 and preserve existing line-ending conventions.
- Format JSON with two-space indentation.
- Use lowercase kebab-case IDs.
- Keep PowerShell compatible with Windows PowerShell 5.1 unless the compatibility target changes explicitly.
- Prefer descriptive names and bounded functions over duplicated inline logic.
- Use relative repository links in Markdown.
- Keep public documentation free of personal paths, credentials, local IDs, and fixed "current" versions.
- Document limitations and unsupported surfaces directly.

## Pull request checklist

- [ ] The change has one clear objective.
- [ ] The repository remains the source of truth; generated or installed copies are not committed.
- [ ] No secrets, personal paths, runtime transcripts, or private `.gemini` data are included.
- [ ] Agent permissions remain least-privilege.
- [ ] Routing and evidence-lane ownership remain explicit.
- [ ] Current facts are not hardcoded.
- [ ] New or changed behavior has an automated assertion.
- [ ] `tests/run-tests.ps1` finishes with `FAILED=0`.
- [ ] Affected Desktop, IDE, or CLI surfaces were smoke-tested and identified in the PR.
- [ ] README and maintainer documentation were updated.
- [ ] Known limitations and migration impact are disclosed.

## Reporting issues

Include enough evidence to reproduce the problem without sharing secrets:

- Antigravity surface: Desktop, IDE, or CLI.
- Operating system and PowerShell version.
- Plugin revision or commit.
- Global, workspace, or CLI installation method.
- Minimal user prompt.
- Selected profiles and visible runtime IDs, if available.
- Hook status and exact failure marker.
- Sanitized test output.
- Expected and actual behavior.

Do not attach credentials, complete private transcripts, `.gemini` runtime state, or proprietary source code unless you are authorized to publish it.
