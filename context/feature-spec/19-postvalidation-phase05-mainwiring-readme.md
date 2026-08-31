# Unit 19: `postvalidation` + Phase 05 + `main.yml` Final Wiring + README

## Goal

Build the `postvalidation` set and `05_post_Upgrade_Checks.yaml` (10 checks + baseline diff vs the Phase 01 snapshot + HTML report), complete the `main.yml` master chain (`01 → 02 → 03/04 looped → 05`), and write the `README.md`.

## Design

- **System boundary:** `playbooks/roles/postvalidation` + phase file `05_post_Upgrade_Checks.yaml` + `main.yml` + `README.md`.
- 10-check contract: HARD (1 version=final target & Progressing=False, 2 COs Available/not Degraded/not Progressing, 3 MCP Updated/not Degraded, 4 nodes Ready + correct new kubelet, 5 etcd healthy); WARN (6 no critical alerts, 7 critical-namespace pods, 8 baseline diff, 9 stuck CSRs, 10 smoke test).
- HARD failure halts + logs out; WARN reports only. Reuses check roles + facts from earlier units.

## Implementation

### `postvalidation/tasks/main.yml`
Reuse `co`, `mcp`, `node` (kubelet-version fact), `etcd` for HARD checks; add version-at-target check (`oc get clusterversion -o json` + `jq`). WARN: alerts, critical pods, CSRs, plus a **baseline diff** — `from_json` the Phase 01 snapshot and compare nodes/operators/routes, and a sample route/workload reachability smoke test.

### `05_post_Upgrade_Checks.yaml`
`pre_tasks: login` (reuse) → `block:` postvalidation → `rescue: error_handle` → `always: logout`. Then `include_role: report` (postvalidation HTML). `fail:` on any HARD.

### `main.yml` final wiring
`import_playbook: 01_Policy_Check.yaml` → `import_playbook: 02_Pre_upgrade_check.yaml` → play looping `include_tasks: tasks/hop.yml` (which invokes 03/04) → `import_playbook: 05_post_Upgrade_Checks.yaml`. Fixed order; header + migration notes. Loads `vars/`.

### `README.md`
Setup (oc/jq/sendmail prereqs, RHEL 8), how to define `upgrade_path`, how to run via `00_Run.sh`, output locations (`logs/ output/ snapshots/`), and the full **2.7 → 2.14 migration checklist** (FQCN optional, email switch, no `warn:`, `include_tasks`/`import_tasks`, `| default('')`, Python 3 snapshot retest, full-chain retest).

## Dependencies

- Unit 07 (snapshot for diff), Unit 15 (`report`), Unit 16 (prevalidation), Unit 18 (monitor)
- Reuses Units 09–12 check roles
- oc, jq, sendmail

## Verify when done

- [ ] All 10 postvalidation checks run once; HARD can halt, WARN reports
- [ ] Version confirmed = final target; kubelet versions correct on all nodes
- [ ] Baseline diff vs Phase 01 snapshot produced (nodes/operators/routes)
- [ ] Postvalidation HTML report written to `output/`
- [ ] `main.yml` chains `01 → 02 → 03/04 looped → 05` in fixed order
- [ ] README covers setup, `upgrade_path`, run, and 2.7→2.14 migration
- [ ] Full chain `--syntax-check` passes on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
