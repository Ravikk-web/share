# Unit 07: Health Check Roles (`api_check`, `api_readiness`, `co`, `mcp`, `node`, `etcd`)

## Goal

Build the six core health check roles responsible for evaluating foundational cluster health: API context verification, API server readiness, ClusterOperators, MachineConfigPools, Nodes, and etcd. Each role enforces HARD gate evaluation, implements transient command retry, and records structured records to `health_summary`.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/api_check`, `api_readiness`, `co`, `mcp`, `node`, `etcd`.
- **Single Concern per Role**: Each role queries exactly one subsystem. No cross-contamination of queries.
- **Read-Only**: Every task sets `changed_when: false`. Zero mutations occur in health roles.
- **Resilient Querying**: All `oc` CLI commands implement transient failure retries: `retries: 3 / delay: 10 / until: rc == 0`.
- **Structured Recording**: Each role appends its evaluation result (`PASS`, `WARN`, `FAIL`) to the shared `health_summary` fact list.

---

## Role Specifications

### 1. `roles/api_check/`
- **Purpose**: Verify that the active cluster API URL matches the intended cluster pattern, preventing operations on the wrong cluster.
- **Command**: `oc whoami --show-server`
- **Rule**: Server URL must match `desired_cluster_api_regex` from `vars/api_regex.yml`.
- **Gate**: HARD. If regex match fails, fail immediately naming observed vs expected.

### 2. `roles/api_readiness/`
- **Purpose**: Confirm API server endpoints are responding with healthy readiness status.
- **Command**: `oc get --raw='/readyz'`
- **Rule**: Output must equal `ok` and exit code must be `0`.
- **Gate**: HARD. If not `ok`, fail naming observed payload.

### 3. `roles/co/` (ClusterOperators)
- **Purpose**: Ensure all OpenShift platform operators are fully functional before upgrading.
- **Command**: `oc get clusteroperators -o json` | jq v1.5
- **Rule**:
  - `Available == 'True'` across all operators.
  - `Degraded == 'False'` across all operators.
  - Optional `co_allow_list` can whitelist non-critical operators if configured.
- **Gate**: HARD. Fails naming all degraded or unavailable operators.

### 4. `roles/mcp/` (MachineConfigPools)
- **Purpose**: Verify that node configuration pools are synchronized and unpaused.
- **Command**: `oc get mcp -o json` | jq v1.5
- **Rule**:
  - `Updated == 'True'` and `Degraded == 'False'`.
  - `spec.paused == false` (paused pools block rollouts).
- **Facts Exposed**: Exports `mcp_parsed_data` and `mcp_all_pools` for direct consumption by the `monitor` and `remediate` roles.
- **Gate**: HARD. Fails naming offending pools and conditions.

### 5. `roles/node/` (Node Health)
- **Purpose**: Ensure all cluster nodes are in `Ready` status with no kernel or disk pressures.
- **Command**: `oc get nodes -o json` | jq v1.5
- **Rule**:
  - `Ready == 'True'` across all nodes.
  - `DiskPressure == 'False'`, `MemoryPressure == 'False'`, `PIDPressure == 'False'`.
  - No unschedulable nodes (unless within `allowed_unschedulable_nodes` count).
- **Gate**: HARD. Fails naming unready or pressured nodes.

### 6. `roles/etcd/` (etcd Database Health)
- **Purpose**: Verify etcd member quorum and raft leader stability before cluster mutation.
- **Command**:
  - `oc get pods -n openshift-etcd -l app=etcd -o json`
  - `oc exec -n openshift-etcd <etcd-pod> -c etcd -- etcdctl endpoint health` (or synthetic check via ClusterOperator etcd).
- **Rule**: All control-plane etcd pods must be running and reporting healthy endpoint status.
- **Gate**: HARD. Fails if etcd reports degraded quorum.

---

## Verification Checklist

- [ ] All 6 roles implement `retries: 3 / delay: 10 / until: rc == 0` on `oc` commands.
- [ ] All shell tasks with `jq` specify `args: executable: /bin/bash`.
- [ ] All condition comparisons apply `| string | trim`.
- [ ] Every role records a clean dictionary into `health_summary` via `set_fact`.
- [ ] Each role has complete `defaults/main.yml` documenting input parameters.
- [ ] Roles pass `ansible-playbook --syntax-check`.
