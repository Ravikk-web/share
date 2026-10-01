# Unit 08: Capacity, Storage & Disruption Roles (`utilization`, `pv`, `pvc`, `pdb`)

## Goal

Build the four capacity, storage, and disruption roles: `utilization` (evaluating cluster-wide CPU and memory requests headroom), `pv` and `pvc` (verifying persistent storage bindings), and `pdb` (auditing PodDisruptionBudgets to ensure node draining will not deadlock during node reboots).

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/utilization`, `pv`, `pvc`, `pdb`.
- **Drain Headroom Invariant**: When nodes reboot during an upgrade, workloads must evacuate to remaining nodes. If CPU or memory requests exceed `max_cpu_percent` (default 90%), cluster draining risks workload starvation.
- **Disruption Deadlock Prevention**: PDBs configured with `maxUnavailable: 0` or `minAvailable: 100%` can permanently block node draining. The `pdb` role audits for zero-disruption budgets.
- **Read-Only**: All checks execute with `changed_when: false` and retry protection.

---

## Role Specifications

### 1. `roles/utilization/` (Node Capacity Headroom)
- **Purpose**: Calculate total cluster CPU and memory request allocations vs total allocatable capacity.
- **Command**:
  - `oc get nodes -o json` (allocatable capacity)
  - `oc get pods -A --field-selector=status.phase=Running -o json` (sum of resource requests)
- **Calculation (jq v1.5 compliant)**:
  - `total_cpu_requests / total_cpu_allocatable * 100`
  - `total_mem_requests / total_mem_allocatable * 100`
  - Formatted using custom `def rnd2: . * 100 | floor / 100;`
- **Thresholds**: Sourced from `vars/upgrade.yml` (`max_cpu_percent: 90`, `max_memory_percent: 90`).
- **Gate**: HARD. If requests exceed 90%, fail with detailed utilization metrics to prevent node eviction failures.

### 2. `roles/pv/` (PersistentVolumes)
- **Purpose**: Ensure all persistent storage volumes are healthy and bound.
- **Command**: `oc get pv -o json` | jq v1.5
- **Rule**: All PersistentVolumes must be in `Bound` or `Available` phase. No volumes in `Failed` or `Released` states.
- **Gate**: WARN. Surfaces problematic PVs in the prevalidation report without halting the chain.

### 3. `roles/pvc/` (PersistentVolumeClaims)
- **Purpose**: Ensure workload volume claims are satisfied across all namespaces.
- **Command**: `oc get pvc -A -o json` | jq v1.5
- **Rule**: All claims must be in `Bound` status. No claims in `Pending` or `Lost`.
- **Gate**: WARN. Surfaces unfulfilled claims in the prevalidation report.

### 4. `roles/pdb/` (PodDisruptionBudgets)
- **Purpose**: Detect restrictive disruption budgets that could prevent node evacuation during MCP rollout.
- **Command**: `oc get pdb -A -o json` | jq v1.5
- **Rule**: Detect any PDB where `status.disruptionsAllowed == 0` and `status.expectedPods > 0`.
- **Gate**: Configurable via `vars/upgrade.yml`:
  - Default: WARN (reports zero-disruption PDBs for operator awareness).
  - Strict: HARD if `fail_on_zero_disruption_pdb: true` is enabled.

---

## Verification Checklist

- [ ] `utilization` calculates CPU and memory percentages accurately using jq 1.5-safe expressions.
- [ ] Bracket notation `['items']` is used for parsing pod and node lists.
- [ ] `pv` and `pvc` roles cleanly capture volume phases without failing on empty clusters.
- [ ] `pdb` identifies zero-disruption budgets and surfaces namespace/name clearly.
- [ ] Each role appends structured status entries to `health_summary`.
- [ ] Roles pass `ansible-playbook --syntax-check`.
