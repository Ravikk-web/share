# Unit 07: `snapshot` Role + Phase 01 (`01_Policy_Check.yaml`)

## Goal

Build the `snapshot` role (writes `snapshots/<cluster>_<timestamp>_baseline.json`) and `01_Policy_Check.yaml`, which logs in once, captures the baseline, and validates every `upgrade_path` version as a real edge in `oc adm upgrade`.

## Design

- **System boundary:** `playbooks/roles/snapshot` + phase file `01_Policy_Check.yaml`.
- The baseline JSON is the **only** sanctioned cross-phase persistence; read later only by Phase 05.
- Edge validation is a HARD gate: an invalid target stops the run before any upgrade.
- Wrapped in `block/rescue/always`; `always:` logs out.

## Implementation

### `snapshot/tasks/main.yml`
Capture nodes, clusteroperators, routes, and clusterversion via `oc get ... -o json`, parse/assemble with `jq`, and write one JSON object to `snapshot_dir/<cluster>_<timestamp>_baseline.json` using `to_json`. `changed_when: false` on reads. `# MIGRATION 2.14:` note to retest `to_json/from_json` under Python 3.

### Edge validation (in phase or `upgrade` helper)
For each version in `upgrade_path`: run `oc adm upgrade -o json` (or parse text), `jq` the available edges, and `fail:` if the target is not a listed edge — message names the cluster and the missing version.

### `01_Policy_Check.yaml`
`pre_tasks: login` → `block:` [ `snapshot` role, edge validation ] → `rescue: error_handle` → `always: logout`. Loads `vars/` files. Header + migration comment.

## Dependencies

- Unit 03 (`login`/`logout`), Unit 06 (`error_handle`)
- Unit 01 (`vars/`, `snapshot_dir`)
- oc, jq

## Verify when done

- [ ] Baseline JSON written to `snapshots/<cluster>_<timestamp>_baseline.json`
- [ ] Snapshot captures nodes, operators, routes, version
- [ ] Every `upgrade_path` version validated as a real edge; invalid → `fail:`
- [ ] Phase wrapped in block/rescue/always; logout guaranteed
- [ ] `to_json/from_json` used; 2.14 retest note present
- [ ] Reads are `changed_when: false`; paths from `playbook_dir`
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
