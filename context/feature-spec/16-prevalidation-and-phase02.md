# Unit 16: `prevalidation` Aggregator + Phase 02 (`02_Pre_upgrade_check.yaml`)

## Goal

Build the `prevalidation` aggregation and `02_Pre_upgrade_check.yaml` that runs all 13 checks once, records HARD/WARN results, hard-fails on any HARD failure, and emits the HTML prevalidation report.

## Design

- **System boundary:** `playbooks/roles/prevalidation` (orchestrates check roles) + phase file `02_Pre_upgrade_check.yaml`.
- 13-check contract: HARD (1 CO, 2 nodes, 3 MCP, 4 etcd, 5 admin-acks, 6 valid edge, 7 capacity <90%); WARN (8 CSRs, 9 disk pressure, 10 PDB, 11 drain headroom, 12 critical-namespace pods, 13 firing alerts).
- Any HARD → `fail:` → chain halts → logout. WARN surfaces in report only.

## Implementation

### `prevalidation/tasks/main.yml`
Sequentially `include_role` each check (co, node, mcp, etcd, admin-ack, edge, utilization, then WARN checks). Admin-acks: `jq` required `admin-ack` gates for the target API removals. CSRs/disk-pressure/critical-pods/alerts: read-only WARN checks appended to `health_summary`. Drain-headroom: reuse utilization per-node headroom fact.

### `02_Pre_upgrade_check.yaml`
`pre_tasks: login` (session reused) → `block:` prevalidation → mark HARD/WARN → `rescue: error_handle` (alert + logout) → `always: logout`. After checks, `include_role: report` (prevalidation HTML). Gate: `fail:` if any HARD entry present.

### New WARN check details
Pending CSRs (`oc get csr`), disk pressure (node conditions), critical-namespace failing/pending pods, firing critical alerts (`oc get ...`/alertmanager) — all `failed_when: false`.

## Dependencies

- Units 08–14 (check roles), Unit 15 (`report`), Unit 06 (`error_handle`), Unit 07 (edge validation)
- oc, jq

## Verify when done

- [ ] All 13 checks run once in order
- [ ] HARD 1–7 can halt via `fail:`; WARN 8–13 only report
- [ ] Admin-ack check evaluates required gates for the target
- [ ] Prevalidation HTML report written to `output/`
- [ ] Phase wrapped block/rescue/always; logout guaranteed
- [ ] Runs on 2.7.17 and 2.14.18; `--syntax-check` passes
- [ ] progress-tracker.md updated
