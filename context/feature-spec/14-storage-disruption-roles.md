# Unit 14: Storage & Disruption Roles (`pv`, `pvc`, `pdb`) — WARN

## Goal

Build the `pv`, `pvc`, and `pdb` roles as the WARN storage-and-disruption set: PV status, PVC status, and PDB configuration (`maxUnavailable:0` / `minAvailable=replicas`), each recording a WARN result into `health_summary` without blocking.

## Design

- **System boundary:** `playbooks/roles/pv`, `playbooks/roles/pvc`, `playbooks/roles/pdb`.
- WARN model: `failed_when: false` + recorded status; never `fail:`, never auto-remediate.
- Built together because they are the WARN storage cluster and always verified in one session.

## Implementation

### `pv/tasks/main.yml`
`oc get pv -o json` → `jq` phase (Bound/Available/Released/Failed); flag non-healthy PVs as WARN into `health_summary`. `changed_when: false`.

### `pvc/tasks/main.yml`
`oc get pvc --all-namespaces -o json` → `jq` phase; flag Pending/Lost as WARN. `changed_when: false`.

### `pdb/tasks/main.yml`
`oc get pdb --all-namespaces -o json` → `jq` for `maxUnavailable:0` or `minAvailable == replicas` (blocking-drain risk). Behaviour governed by `fail_on_zero_disruption_pdb` var: when true it may escalate per spec, else WARN only. Record status. `changed_when: false`.

### Defaults
`fail_on_zero_disruption_pdb` with `| default(false)`.

## Dependencies

- Unit 03 (`login`), Unit 01 (`fail_on_zero_disruption_pdb`)
- oc, jq

## Verify when done

- [ ] PV/PVC/PDB states parsed and recorded as WARN
- [ ] WARN items never block (`failed_when: false`), never auto-remediate
- [ ] PDB risk detection (`maxUnavailable:0` / `minAvailable=replicas`) works
- [ ] `fail_on_zero_disruption_pdb` behaviour honoured
- [ ] `changed_when: false`; jq v1.5 syntax
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
