# Unit 11: Node Role (`node`) — HARD

## Goal

Build the `node` role that verifies all nodes are `Ready` and none are `SchedulingDisabled` (except those in `allowed_unschedulable_nodes`), recording a HARD PASS/FAIL into `health_summary`.

## Design

- **System boundary:** `playbooks/roles/node`.
- HARD gate. Kubelet-version parsing here is reused by postvalidation (Phase 05, check 4).
- Read-only, single concern.

## Implementation

### `node/tasks/main.yml`
`oc get nodes -o json` → `jq` each node's Ready condition, `spec.unschedulable`, and `status.nodeInfo.kubeletVersion`. Offenders = NotReady, or unschedulable and not in `allowed_unschedulable_nodes | default([])`. Non-empty → `fail:` naming cluster + nodes. Else PASS into `health_summary`. `changed_when: false`.

### Reusable facts
Expose per-node Ready + kubelet version as a fact for reuse by `monitor` and postvalidation.

### Defaults
`allowed_unschedulable_nodes: []` with `| default([])`.

## Dependencies

- Unit 03 (`login`), Unit 01 (`allowed_unschedulable_nodes`)
- oc, jq

## Verify when done

- [ ] Detects NotReady / SchedulingDisabled nodes (honouring allow-list)
- [ ] HARD `fail:` names cluster + offending nodes
- [ ] Per-node Ready + kubelet version exposed as a fact
- [ ] PASS recorded into `health_summary`
- [ ] `changed_when: false`; jq v1.5 syntax
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
