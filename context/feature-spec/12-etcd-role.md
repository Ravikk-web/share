# Unit 12: etcd Role (`etcd`) — HARD (non-blocking rule)

## Goal

Build the `etcd` role that checks etcd member health and records a HARD PASS/FAIL into `health_summary`, per the spec: etcd is checked but its state must not, by itself, block the upgrade beyond the defined HARD rule.

## Design

- **System boundary:** `playbooks/roles/etcd`.
- HARD gate on member health as defined; backup is out of scope (manual).
- Read-only, single concern.

## Implementation

### `etcd/tasks/main.yml`
Query etcd health via the etcd operator / pods (`oc get pods -n openshift-etcd -o json` and/or `oc get etcd -o json`), `jq` member/condition status. Determine unhealthy members. If unhealthy per the HARD rule → `fail:` naming the cluster and members; else PASS into `health_summary`. `changed_when: false`.

### Defaults
Optional namespace/selector overrides with `| default('')`.

## Dependencies

- Unit 03 (`login`)
- oc, jq

## Verify when done

- [ ] Reports etcd member health accurately
- [ ] HARD rule enforced with clear `fail:` message
- [ ] Backup NOT attempted (out of scope)
- [ ] PASS recorded into `health_summary`
- [ ] `changed_when: false`; jq v1.5 syntax
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
