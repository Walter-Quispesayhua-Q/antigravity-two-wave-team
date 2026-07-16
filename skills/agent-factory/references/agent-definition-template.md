# Agent Definition Template

Use this template with `agent.schema.json`.

## Directory

```text
orchestration/agents/<directory-name>/
├── agent.json
└── SYSTEM.md
```

When specialized reusable knowledge is required:

```text
skills/<skill-name>/
└── SKILL.md
```

## Profile template

```json
{
  "$schema": "../../schemas/agent.schema.json",
  "schemaVersion": 2,
  "id": "<agent-id>",
  "displayName": "<Display Name>",
  "description": "<One precise responsibility>",
  "systemPrompt": "SYSTEM.md",
  "skills": [
    "<skill-name>"
  ],
  "routing": {
    "stage": "wave-1",
    "activation": "conditional",
    "priority": 50,
    "cost": "medium",
    "capabilities": [
      "<owned-capability>"
    ],
    "taskTypes": [
      "<task-type>"
    ],
    "triggers": [
      "<routing-hint>"
    ],
    "exclusions": [
      "greeting"
    ]
  },
  "runtime": {
    "kind": "custom",
    "enableMcpTools": false,
    "enableWriteTools": false,
    "enableSubagentTools": false
  },
  "outputContract": {
    "format": "markdown",
    "requiredSections": [
      "Status",
      "Findings",
      "Evidence",
      "Uncertainty",
      "Recommendation"
    ],
    "evidenceRequired": true
  }
}
```

Replace every placeholder before validation.

## SYSTEM.md skeleton

```markdown
# <Display Name>

## Role

State one primary responsibility and the agent's wave or conditional activation.

## Expected input

List every required task-packet field.

## Procedure

Provide a bounded step-by-step method and stop condition.

## Evidence rules

Define what counts as evidence and what must remain uncertain.

## Permission boundaries

Define read, write, MCP, command, and delegation limits.

## Completion rules

Define complete, partial, not-applicable, blocked, or role-specific verdicts.

## Output contract

Define exact top-level headings and required fields.
```

## Auto-discovery checklist

When adding an agent:

- Place `agent.json` and `SYSTEM.md` together under `orchestration/agents/<directory>/`.
- Use a unique ID and schema version 2.
- Declare `wave-1` with `default-evidence` or `conditional`, or `wave-2` with `verifier`.
- Describe capabilities and task types semantically; triggers are hints only.
- Use exclusions to avoid obvious false positives.
- Keep write and delegation tools disabled unless the global design is explicitly revised.
- Reference only installed skills.
- Do not edit a central profile map; the hook discovers the directory.
- Update catalog and routing tests.

## Validation cases

At minimum test:

1. Valid profile.
2. Missing `SYSTEM.md`.
3. Missing skill.
4. Duplicate ID.
5. Invalid permission field.
6. Discovery of a newly added valid directory.
7. Invalid stage and activation combination.
8. Child task recursion attempt.
9. Incomplete task packet.
10. Tool unavailable.
11. Agent timeout or failure.
12. Output missing a required section.
13. Personal path or secret detected.
14. Relevant profile selected and irrelevant profile skipped.
15. Real invocation visible in the agent manager.
