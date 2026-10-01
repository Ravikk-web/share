# Unit 06: Snapshot Role & Phase 01 (`01_Policy_Check.yaml`)

> **Revision 2026-10-01 (review remediation)** — Phase 01 now validates the whole path (`tasks/validate_upgrade_path.yml`): update graph per hop channel, cluster offer for the first edge, reached hops skipped, running update resumed, conditional-update policy. The Phase 01 report has one row per edge. Exit code 5.

## Goal

Build the `snapshot` role to capture an immutable baseline JSON snapshot of the cluster, and the Phase 01 playbook (`01_Policy_Check.yaml`) to authenticate, capture baseline state, and validate that every target in `upgrade_path` is a confirmed, verified update edge before any upgrade begins.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/snapshot/` and `playbooks/01_Policy_Check.yaml`.
- **Single Persistence Contract**: The JSON snapshot written in this phase (`snapshots/<cluster>_<timestamp>_baseline.json`) is the **only** persisted cluster state artifact in the entire automation suite. It is read once by Phase 05 for postvalidation diffing.
- **Strict Edge Enforcement**: Phase 01 queries live available and conditional update edges from `ClusterVersion`. If `upgrade_path[0]` is not a valid edge from the current version, execution halts immediately with a HARD gate failure.
- **Fail-Safe Session Lifecycle**: `pre_tasks:` logs in; `rescue:` calls `error_handle` and alerts; `always:` guarantees `logout` on failure.

---

## Implementation Details

### 1. `roles/snapshot/`
- **`defaults/main.yml`**:
  ```yaml
  snapshot_dir: "{{ playbook_dir }}/snapshots"
  cluster_name: ""
  snapshot_file: "{{ snapshot_dir }}/{{ cluster_name }}_{{ run_timestamp }}_baseline.json"
  ```
- **`tasks/main.yml`**:
  1. Query live cluster state via `oc get` with `changed_when: false` and retry protection:
     - `oc get clusterversion version -o json`
     - `oc get clusteroperators -o json`
     - `oc get nodes -o json`
     - `oc get routes -A -o json`
  2. Parse results using jq v1.5-compatible expressions.
  3. Assemble structured baseline dictionary:
     - Cluster metadata: name, API server URL, current version, channel.
     - Node snapshot: node names, roles, kubelet versions, readiness conditions.
     - Operator snapshot: operator names, versions, Available/Progressing/Degraded conditions.
     - Route snapshot: route names, namespaces, hostnames.
  4. Write formatted JSON snapshot to `snapshot_file` using `copy:` with `content: "{{ baseline_dict | to_nice_json }}"`.
  5. Export `baseline_snapshot_file_path: "{{ snapshot_file }}"` fact for Phase 05.

### 2. Phase 01 Playbook (`playbooks/01_Policy_Check.yaml`)
- **Structure**:
  ```yaml
  - name: "Phase 01 — Policy Check & Baseline Capture"
    hosts: localhost
    connection: local
    gather_facts: true
    vars_files:
      - vars/upgrade.yml
      - vars/secrets.yml
      - vars/paths.yml
      - vars/smtp.yml
      - vars/report_vars.yml
      - vars/api_regex.yml
  ```
- **`pre_tasks:`**:
  - Authenticate once via `include_role: name=login`.
- **`block:`**:
  1. Capture baseline snapshot via `include_role: name=snapshot`.
  2. Query live ClusterVersion update graph:
     ```yaml
     - name: "Query live cluster available update edges"
       shell: "oc get clusterversion version -o json | jq -r '(.status.availableUpdates // [])[].version'"
       register: available_edges
       changed_when: false
     ```
  3. Validate target: assert that `upgrade_path[0]` is present in available edges (or valid conditional updates).
  4. HARD Gate: If target hop is not a valid edge, fail with clear error naming cluster, current version, target hop, and available edges.
  5. Log baseline capture confirmation to `.txt` and `.csv`.
- **`rescue:`**:
  - Extract sanitized error hierarchy.
  - Call `error_handle` role to log failure and send alert email.
  - Call `logout` role to tear down session.
- **`always:`**:
  - If the block failed, ensure session is logged out.

---

## Verification Checklist

- [ ] `01_Policy_Check.yaml` authenticates and writes custom kubeconfig.
- [ ] Baseline JSON snapshot is written to `snapshots/` with complete node, operator, and route data.
- [ ] Target hop is confirmed against live ClusterVersion available updates.
- [ ] Invalid target version triggers HARD gate `fail:` and cleans up session.
- [ ] Snapshot file path is exported as a host fact.
- [ ] Playbook passes `ansible-playbook --syntax-check`.
