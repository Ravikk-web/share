# Unit 09: ClusterOperators Role (`co`) — HARD

## Goal

Build the `co` role that verifies every ClusterOperator reports `Available=True` and `Degraded=False`, recording a HARD PASS/FAIL into `health_summary`.

## Design

- **System boundary:** `playbooks/roles/co`.
- HARD gate: any operator not Available or any Degraded → `fail:`.
- Read-only; single concern (operators only, never nodes/MCP).

## Implementation

### `co/tasks/main.yml`
`oc get clusteroperators -o json` → `jq` to extract each operator's `Available`/`Degraded` conditions. Build a list of offenders. If offenders non-empty → `fail:` with a message naming the cluster and the failing operators. Else `set_fact` PASS into `health_summary`. `changed_when: false`.

### Defaults
Optional allow-list override (empty) with `| default([])`.

## Dependencies

- Unit 03 (`login`)
- oc, jq

## Verify when done

- [ ] Detects any operator with Available≠True or Degraded=True
- [ ] HARD `fail:` names cluster + offending operators
- [ ] PASS recorded into `health_summary`
- [ ] `changed_when: false`; explicit `failed_when:`
- [ ] jq v1.5-compatible syntax
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
