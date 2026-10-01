# Unit 12: Postvalidation Role & Phase 05 (`05_post_Upgrade_Checks.yaml`)

> **Revision 2026-10-01 (review remediation)** — Kubelet prefix parsed with `split` (was always `v1.13.`), `Ready=Unknown` not ready, bounded operator settle loop, alerts query failure = WARN not checked, baseline from `baseline_snapshot_file_path`. Phase 05 writes the report before the gate, enforces it on live runs only (exit 25) and mails only when run on its own.

## Goal

Build the `postvalidation` role and Phase 05 playbook (`05_post_Upgrade_Checks.yaml`) to execute the **10-check postvalidation contract**, compute a structural baseline diff against the Phase 01 JSON snapshot, generate the client-facing HTML postvalidation report, and hand off the preserved authenticated session to Phase 06 for operator upgrades.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/postvalidation/` and `playbooks/05_post_Upgrade_Checks.yaml`.
- **The 10-Check Contract**: Post-upgrade health evaluation auditing cluster version, nodes, kubelet versions, operators, storage, and critical workloads.
- **Baseline Diff Engine**: Compares post-upgrade cluster state directly against the Phase 01 baseline snapshot (`snapshots/<cluster>_<ts>_baseline.json`), identifying node count parity, operator health shifts, and route availability.
- **Session Preservation**: Unlike previous designs that logged out at the end of postvalidation, Phase 05 deliberately preserves the authenticated session so Phase 06 can perform operator compatibility checks and upgrades without re-authenticating.

---

## The 10-Check Postvalidation Contract

| # | Check Name | Evaluation Criteria | Gate |
|---|---|---|---|
| **01** | Final ClusterVersion | `cv` matches final target version in `upgrade_path` | **HARD** |
| **02** | ClusterOperators Status | All operators `Available=True`, `Degraded=False`, `Progressing=False` | **HARD** |
| **03** | MachineConfigPool Status | All pools `Updated=True`, `Degraded=False` | **HARD** |
| **04** | Node Readiness & Version | All nodes `Ready=True`; kubelet versions match target minor version | **HARD** |
| **05** | Node Pressures | Zero `DiskPressure`, `MemoryPressure`, or `PIDPressure` | **HARD** |
| **06** | etcd Cluster Health | Member quorum healthy, raft leader stable | **HARD** |
| **07** | PersistentVolume Status | Storage volumes remain in `Bound` / `Available` state | **WARN** |
| **08** | Core Namespace Pods | Control plane and ingress pods running without crash loops | **WARN** |
| **09** | Firing Critical Alerts | Query Prometheus alerts API; report any active critical alerts | **WARN** |
| **10** | **Baseline Diff Audit** | Node count, active operators, and routes match or exceed baseline | **WARN** |

---

## Implementation Details

### 1. `roles/postvalidation/`
- **`defaults/main.yml`**:
  ```yaml
  baseline_snapshot_file: "{{ baseline_snapshot_file_path | default('') }}"
  final_target_version: "{{ upgrade_path[-1] | default('') }}"
  ```
- **`tasks/main.yml`**:
  1. Verify `ClusterVersion` is at `final_target_version`.
  2. Evaluate `co`, `mcp`, and `node` health checks.
  3. Validate node kubelet versions: confirm all nodes run the target minor version kubelet.
  4. Load Phase 01 baseline snapshot from `baseline_snapshot_file` using `slurp` / `from_json`.
  5. Compute Baseline Diff:
     - Compare baseline node count vs live node count.
     - Compare baseline operator versions vs live operator versions.
     - Verify all baseline routes remain bound and accessible.
  6. Assemble results and populate `postval_summary` facts.
  7. Call `report` role with `report_type: "postvalidation"` to write `output/<cluster>_postvalidation_<ts>.html`.

### 2. Phase 05 Playbook (`playbooks/05_post_Upgrade_Checks.yaml`)
- Runs on `localhost` reusing existing session.
- Wraps execution in `block/rescue/always`.
- **`block:`**:
  - Executes `roles/postvalidation`.
  - Enforces HARD gate `fail:` if any check 01–06 fails.
  - Generates HTML postvalidation report.
  - Logs postvalidation success.
  - **Does NOT log out on success**: session remains open for Phase 06.
- **`rescue:`**:
  - Calls `error_handle` role to alert platform team.
  - Calls `logout` role to tear down session immediately.
- **`always:`**:
  - Cleans up temporary postvalidation facts.

---

## Verification Checklist

- [ ] All 10 postvalidation checks execute and record to facts.
- [ ] Baseline snapshot is successfully slurped and parsed via `from_json`.
- [ ] Baseline diff identifies node count and route discrepancies.
- [ ] HTML postvalidation report is written to `output/`.
- [ ] Session is NOT destroyed on success; preserved cleanly for Phase 06.
- [ ] Playbook passes `ansible-playbook --syntax-check`.
