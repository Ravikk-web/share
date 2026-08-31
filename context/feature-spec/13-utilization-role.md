# Unit 13: Utilization Role (`utilization`) — HARD

## Goal

Build the `utilization` role that verifies per-node and cluster-wide CPU and memory are **< 90% requests-based**, recording a HARD PASS/FAIL into `health_summary`.

## Design

- **System boundary:** `playbooks/roles/utilization`.
- HARD gate. Threshold sourced from `vars` (`max_cpu_percent`, `max_memory_percent` = 90) — never a literal.
- Requests-based (not live usage): sum pod requests vs allocatable.
- Read-only, single concern.

## Implementation

### `utilization/tasks/main.yml`
`oc get nodes -o json` (allocatable) and `oc get pods --all-namespaces -o json` (requests) → `jq` to sum CPU/mem requests per node and cluster-wide, compute percentages vs allocatable. Offenders = any node or cluster total ≥ threshold. Non-empty → `fail:` naming cluster + node + observed %. Else PASS into `health_summary`. `changed_when: false`.

### Reusable facts
Expose per-node headroom for the WARN "spare capacity to tolerate 1 node draining" check in prevalidation.

### Defaults
`max_cpu_percent: 90`, `max_memory_percent: 90` with `| default(90)`.

## Dependencies

- Unit 03 (`login`), Unit 01 (thresholds)
- oc, jq

## Verify when done

- [ ] Computes requests-based CPU/mem per-node and cluster-wide
- [ ] HARD `fail:` when ≥ threshold, naming node + observed %
- [ ] Threshold read from `vars`, not hardcoded
- [ ] Per-node headroom exposed as a fact
- [ ] `changed_when: false`; jq v1.5 syntax
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
