# Unit 10: MCP Role (`mcp`) — HARD

## Goal

Build the `mcp` role that verifies every MachineConfigPool is `Updated=True`, not `Degraded`, and not paused, recording a HARD PASS/FAIL into `health_summary`.

## Design

- **System boundary:** `playbooks/roles/mcp`.
- HARD gate. Also reused by the monitor/settle-gate later, so parsing must be clean and reusable.
- Read-only, single concern.

## Implementation

### `mcp/tasks/main.yml`
`oc get mcp -o json` → `jq` each pool's `Updated`, `Degraded`, and `spec.paused`. Offenders = any not Updated, or Degraded=True, or paused=true. Non-empty → `fail:` naming cluster + pools. Else PASS into `health_summary`. `changed_when: false`.

### Reusable facts
Expose parsed MCP state as a fact so the `monitor`/settle-gate can reuse the same jq logic without duplication.

### Defaults
Optional ignore rules carry `| default('')` / `| default([])`.

## Dependencies

- Unit 03 (`login`)
- oc, jq

## Verify when done

- [ ] Detects not-Updated / Degraded / paused pools
- [ ] HARD `fail:` names cluster + offending pools
- [ ] Parsed MCP state exposed as a reusable fact
- [ ] PASS recorded into `health_summary`
- [ ] `changed_when: false`; jq v1.5 syntax
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
