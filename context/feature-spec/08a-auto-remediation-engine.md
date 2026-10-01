# Unit 08a: Auto-Remediation Engine (`remediate` Role)

> **Revision 2026-10-01 (review remediation)** — Remediations no longer edit `health_summary`; they record attempts and Phase 02 re-runs the full scan (AUTO-FIXED / FIX-FAILED). Admin-acks moved to Phase 03 (per minor hop, after the removed-API usage check in `roles/api_usage`). Node rollouts are monitored before the re-scan. Phase 06 recovery restarts operator Deployments once; CSVs are never deleted. See `architecture.md` → Cluster Writes.

## Goal

Build the dedicated `remediate` role to centralize the automated resolution of known, safe-to-remediate OpenShift upgrade blockers (including cgroup v1→v2 migration, dynamic admin-acknowledgements, paused MachineConfigPools, and degraded operator recovery), transforming the suite into a true one-touch automation.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/remediate/` (`tasks/main.yml`, `tasks/cgroup_v2.yml`, `tasks/admin_acks.yml`, `tasks/unpause_mcp.yml`, `tasks/restart_operator.yml`).
- **Tiered Handling Model**:
  - **Tier 1 (Auto-Fix, Default ON)**: Safe, zero-risk, official Red Hat remediation procedures (cgroup v2 patch, admin-ack ConfigMap, unpausing permitted MCPs, transient command retry).
  - **Tier 2 (Guided, Default OFF)**: Non-destructive recovery attempts (degraded operator pod restart, stalled node MCD force re-apply, operator CSV re-creation). Must be opted into via `vars/upgrade.yml`.
  - **Tier 3 (Hard-Stop)**: Complex or destructive issues (e.g. Gateway API CRD conflicts) halt immediately with actionable diagnostics.
- **Strict Verification Cycle**: Every remediation task executes:
  1. Detect condition.
  2. Verify toggle is enabled (`auto_remediation_enabled` and specific flag).
  3. Apply deterministic `oc patch` / command.
  4. Re-verify condition.
  5. Update `health_summary` with `AUTO-FIXED` (if re-verification passed) or `FIX-FAILED` (if still failing).
- **Audit Logging**: Every automated fix logs a prominent `[AUTO-FIX]` entry to console, `.txt`, and `.csv`.

---

## Implementation Details

### 1. Structure of `roles/remediate/`

```
playbooks/roles/remediate/
├── defaults/main.yml
└── tasks/
    ├── main.yml               # Dispatcher routing based on failed checks
    ├── cgroup_v2.yml          # Blocker 1: CGroup v1 → v2 migration
    ├── admin_acks.yml         # Blocker 2: Auto-apply admin-ack ConfigMap
    ├── unpause_mcp.yml        # Blocker 3: Unpause paused MachineConfigPools
    └── restart_operator.yml   # Blocker 4: Restart degraded operator pods
```

### 2. `defaults/main.yml`
```yaml
# Master toggle for automatic remediation
auto_remediation_enabled: true

# Tier 1 toggles (Auto-Fix)
auto_fix_cgroup_v2: true
auto_apply_admin_acks: true
auto_unpause_mcp: true
mcp_auto_unpause_list:
  - "worker"
  - "master"

# Tier 2 toggles (Guided recovery)
auto_restart_degraded_operators: false
operator_restart_grace_seconds: 180
auto_force_stalled_node: false
node_stall_threshold_minutes: 30

# Specific remediation dispatch triggers
trigger_cgroup_remediation: false
trigger_admin_ack_remediation: false
trigger_unpause_mcp_remediation: false
trigger_co_restart_remediation: false
```

### 3. Task Implementations

#### `tasks/cgroup_v2.yml` (CGroup Mode Migration)
- **Problem**: OpenShift 4.19+ deprecates and removes cgroup v1. Clusters reporting `cgroupMode: "v1"` block upgrades with `Upgradeable=False`.
- **Remediation Task**:
  ```yaml
  - name: "[AUTO-FIX] Patch cluster cgroupMode to v2"
    shell: "oc patch nodes.config/cluster -p '{\"spec\":{\"cgroupMode\":\"v2\"}}' --type=merge"
    register: cgroup_patch_result
    changed_when: true
    args:
      executable: /bin/bash

  - name: "Verify cgroupMode configuration updated"
    shell: "oc get nodes.config/cluster -o jsonpath='{.spec.cgroupMode}'"
    register: verified_cgroup
    failed_when: verified_cgroup.stdout != "v2"
    changed_when: false
  ```
- **Result**: Records `AUTO-FIXED` for Check 14 (CGroup Mode). Node reboots roll out naturally during subsequent MCP updates.

#### `tasks/admin_acks.yml` (Dynamic Administrator Acknowledgements)
- **Problem**: Upgrades across minor versions removing Kubernetes APIs block with `Upgradeable=False` and `reason: AdminAckRequired`.
- **Remediation Task**:
  1. Inspect `ClusterVersion` conditions and dynamically extract the required ack key matching `ack-.*-api-removals-in-.*`.
  2. If detected, apply acknowledgement:
     ```yaml
     - name: "[AUTO-FIX] Apply required admin-ack ConfigMap"
       shell: >-
         oc -n openshift-config patch cm admin-acks
         --patch '{"data":{"{{ detected_ack_key }}":"true"}}' --type=merge
       register: ack_patch_result
       changed_when: true
       args:
         executable: /bin/bash
     ```
  3. Re-query `ClusterVersion` to confirm `AdminAckRequired` condition is cleared.

#### `tasks/unpause_mcp.yml` (MachineConfigPool Unpausing)
- **Problem**: Paused pools block configuration rollouts and node updates.
- **Remediation Task**:
  1. Iterate over paused pools that are present in `mcp_auto_unpause_list`.
  2. Unpause each:
     ```yaml
     - name: "[AUTO-FIX] Unpause MachineConfigPool {{ item }}"
       shell: "oc patch mcp {{ item }} --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/paused\",\"value\":false}]'"
       register: unpause_result
       changed_when: true
     ```
  3. Re-verify `spec.paused == false`.

#### `tasks/restart_operator.yml` (Degraded Operator Recovery)
- **Problem**: Transient operator deadlocks or leader election stalls cause `Degraded=True`.
- **Remediation Task**:
  1. Identify degraded operator pod names.
  2. Delete degraded operator pod to trigger controller-manager recreation:
     ```yaml
     - name: "[GUIDED] Delete degraded operator pod to force restart"
       shell: "oc delete pod -n {{ operator_namespace }} -l app={{ operator_name }}"
       changed_when: true
     ```
  3. Wait up to `operator_restart_grace_seconds` (default 180s).
  4. Re-check `Available` and `Degraded` conditions.

---

## Integration Points

- **Phase 02 (`02_Pre_upgrade_check.yaml`)**: Runs after initial 14-check scan if any HARD check failed. If remediable, invokes `remediate`, then re-runs failed checks.
- **Phase 03 (`03_Initiate_upgrade.yaml`)**: Invokes `admin_acks.yml` dynamically for each hop target version prior to running `oc adm upgrade --to`.
- **Phase 04 (`04_Live_monitoring_upgrade.yaml`)**: If a node exceeds `node_stall_threshold_minutes` in updating, can optionally invoke MCD force re-apply.
- **Phase 06 (`06_Operator_Upgrade.yaml`)**: If a CSV rollout stalls, deletes the CSV pod once to let OLM reconcile from subscription.

---

## Verification Checklist

- [ ] All remediation actions respect `auto_remediation_enabled` and specific toggles.
- [ ] CGroup v2 patch verified against `nodes.config/cluster`.
- [ ] Dynamic admin-ack extraction parses keys accurately from `ClusterVersion`.
- [ ] Paused MCP unpausing honors `mcp_auto_unpause_list`.
- [ ] Failed remediations record `FIX-FAILED` and cleanly trigger HARD gate halts.
- [ ] Successful remediations record `AUTO-FIXED` and allow the chain to continue.
- [ ] Dual-version headers present in all task files.
