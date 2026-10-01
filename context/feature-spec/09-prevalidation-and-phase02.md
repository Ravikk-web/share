# Unit 09: Prevalidation Aggregator Role & Phase 02 (`02_Pre_upgrade_check.yaml`)

> **Revision 2026-10-01 (review remediation)** — Check 07 = admin-ack and removed-API usage for every minor hop; Check 14 = cgroup v2 for the highest hop (parsed with `split`, HARD); Check 15 = `olm.maxOpenShiftVersion` + OLM `Upgradeable`. Flow: scan → remediate → rollout wait → full re-scan → merge → report → gate (exit 10) → prevalidation mail only when the run continues to the upgrade.

## Goal

Build the `prevalidation` aggregator role and the Phase 02 playbook (`02_Pre_upgrade_check.yaml`) to orchestrate the complete **15-check prevalidation contract**, execute the auto-remediation pass via the `remediate` role for any failed auto-fixable checks, enforce the final HARD gate, and generate client-facing HTML prevalidation reports.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/prevalidation/` and `playbooks/02_Pre_upgrade_check.yaml`.
- **The 15-Check Contract**: Exactly 15 health and capacity checks (9 HARD gates, 6 WARN advisories).
- **One-Touch Remediation Pass**: If any HARD check fails initially and `auto_remediation_enabled: true`, the phase invokes `roles/remediate`, applies deterministic fixes, and re-evaluates the failed checks before evaluating the hard gate.
- **Fail-Safe Abort**: If residual HARD failures remain after remediation (or if auto-remediation is disabled), the chain halts immediately, logs failure, dispatches an alert email, and logs out.

---

## The 15-Check Prevalidation Contract

| # | Check Name | Role / Action | Gate Type | Rule / Success Criteria |
|---|---|---|---|---|
| **01** | ClusterOperators Health | `co` | **HARD** | All operators `Available=True`, `Degraded=False` |
| **02** | Node Readiness & Pressures | `node` | **HARD** | All nodes `Ready=True`; no Memory/Disk/PID pressures |
| **03** | MachineConfigPool Sync & Pause | `mcp` | **HARD** | `Updated=True`, `Degraded=False`, `spec.paused=false` *(Auto-Fixable)* |
| **04** | API Server Context | `api_check` | **HARD** | Active URL matches `desired_cluster_api_regex` |
| **05** | API Server Readiness | `api_readiness` | **HARD** | `/readyz` endpoint returns `ok` |
| **06** | etcd Quorum & Health | `etcd` | **HARD** | All etcd members healthy and raft leader established |
| **07** | Admin Acknowledgements | `oc get cv` | **HARD** | No pending `AdminAckRequired` blocking upgrade *(Auto-Fixable)* |
| **08** | Node Request Capacity Headroom | `utilization` | **HARD** | CPU & Memory requests < `max_cpu_percent` (90%) |
| **09** | Pending Node CSRs | `shell: oc get csr` | **WARN** | No unresolved certificates waiting for approval |
| **10** | PersistentVolume Health | `pv` | **WARN** | All PVs in `Bound` or `Available` phase |
| **11** | PersistentVolumeClaim Health | `pvc` | **WARN** | All PVCs in `Bound` phase |
| **12** | PodDisruptionBudgets (PDB) | `pdb` | **WARN** | Audit zero-disruption budgets (`disruptionsAllowed: 0`) |
| **13** | Critical Namespace Pod Health | `shell: oc get pods` | **WARN** | Core pods in `openshift-*` running without CrashLoop |
| **14** | **CGroup Mode Compatibility** | `shell: oc get nodes.config` | **HARD** | Cluster `cgroupMode == "v2"` if target >= 4.19 *(Auto-Fixable)* |
| **15** | **OLM Operator Upgrade Compatibility** | `operator_compat` | **HARD** | All installed OLM operators have compatible update channels for target OCP version |

---

## Prevalidation Workflow with Remediation Pass

```
Phase 02 Playbook
  │
  ├── 1. Run Initial 15 Checks (populates health_summary)
  │
  ├── 2. Any HARD checks failed?
  │     ├── NO  ──▶ Proceed to Step 4
  │     └── YES ──▶ Is auto_remediation_enabled: true?
  │           ├── NO  ──▶ Escalates to FAIL; aborts to rescue
  │           └── YES ──▶ Run `remediate` Role:
  │                 ├── Check 14 failed? ──▶ Run cgroup_v2.yml
  │                 ├── Check 07 failed? ──▶ Run admin_acks.yml
  │                 ├── Check 03 failed? ──▶ Run unpause_mcp.yml
  │                 └── Check 01 failed? ──▶ Run restart_operator.yml (if opted in)
  │
  ├── 3. Re-Evaluate Failed Checks:
  │     ├── Passed now? ──▶ Mark as AUTO-FIXED in health_summary
  │     └── Still failed? ──▶ Mark as FIX-FAILED in health_summary
  │
  ├── 4. Evaluate Residual HARD Gate:
  │     ├── Any check still marked FAIL / FIX-FAILED?
  │     │     └── Trigger `fail:` ──▶ rescue: error_handle + logout
  │     └── All checks PASS / WARN / AUTO-FIXED ──▶ Proceed
  │
  ├── 5. Generate Prevalidation Report:
  │     └── Call `report` role (writes output/<cluster>_prevalidation_<ts>.html)
  │
  └── 6. Dispatch Prevalidation Email Notification:
        └── Call `sendmail` role (dispatches HTML report with attachment to mail_to / preval_mail_to)
```

---

## Playbook Structure (`playbooks/02_Pre_upgrade_check.yaml`)

- Reuses existing authenticated session from Phase 01.
- Encapsulates checks in `block/rescue/always`.
- **`rescue:`**:
  1. Calls `error_handle` role to record failure facts and send failure alert email.
  2. Calls `logout` role to tear down cluster session immediately.
- **`always:`**:
  - Ensures clean teardown if an unhandled abort occurred.

---

## Verification Checklist

- [ ] All 15 checks are executed and mapped in `health_summary`.
- [ ] Check 14 validates cgroupMode for upgrades targeting `>= 4.19`.
- [ ] Auto-remediation executes when HARD checks fail and toggles are enabled.
- [ ] Successful remediations update check status to `AUTO-FIXED`.
- [ ] Residual HARD failures halt execution before Phase 03 begins.
- [ ] HTML prevalidation report is written to `output/`.
- [ ] Playbook passes `ansible-playbook --syntax-check`.
