# Unit 11: Monitor Role & Phase 04 (`04_Live_monitoring_upgrade.yaml`)

> **Revision 2026-10-01 (review remediation)** — `roles/monitor` rewritten (`main.yml`, `poll_iteration.yml` wrapper, `poll_body.yml`): real clock, one API call per poll, outage tolerance and re-login, no-progress / hard-limit / release / Failing aborts, settle after consecutive polls, heartbeat and one-per-condition degradation alerts, rollout mode for Phase 02, Tier 2 daemon force only for daemon-Degraded nodes.

## Goal

Build the `monitor` role and Phase 04 task playbook (`04_Live_monitoring_upgrade.yaml`) to poll cluster status (`clusterversion`, `mcp`, `nodes`) every 2 minutes during an active upgrade hop, enforce a 90-minute timeout guard, detect state changes and send immediate alerts, send 20-minute heartbeat progress emails, provide optional node stall recovery, and execute the settle-gate between hops.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/monitor/` and `playbooks/04_Live_monitoring_upgrade.yaml`.
- **Inline Bounded Loop**: Monitoring executes directly within the Ansible task thread using a bounded loop calculated from `hop_timeout_minutes / poll_interval_minutes` (e.g. 90m / 2m = 45 iterations). No detached background daemons.
- **Heartbeat vs State-Change Logic**:
  - State change (e.g. node becomes `NotReady`, MCP reports degraded, active node switches) triggers an immediate notification email.
  - Every 20 minutes (configurable via `heartbeat_minutes`), an HTML progress heartbeat is dispatched even if state has not changed.
- **Settle-Gate Contract**: Settle-gate executes at the conclusion of monitoring. It asserts that ClusterVersion is at target, all ClusterOperators are `Available=True` and `Progressing=False`, and all MCPs report `Updated=True`. Passing settle-gate is the mandatory entry condition for hop N+1.

---

## Implementation Details

### 1. `roles/monitor/`
- **`defaults/main.yml`**:
  ```yaml
  poll_interval_minutes: 2
  hop_timeout_minutes: 90
  heartbeat_minutes: 20
  auto_force_stalled_node: false
  node_stall_threshold_minutes: 30
  ```
- **`tasks/main.yml`**:
  1. Initialize monitoring metrics: record `monitor_start_epoch`, loop index counter, and initial state signature.
  2. Execute bounded polling loop (`until:` settle condition met or timeout reached):
     - Query live `clusterversion`, `mcp`, and `nodes` via `oc get ... -o json` with retry protection.
     - Parse MCP progress: ready machine count / total machine count, updated, updating, degraded.
     - Parse active working node: identify node currently in `SchedulingDisabled` / rebooting.
     - Detect state change vs previous poll. If state changed, set `state_changed: true`.
     - Calculate elapsed time and next scheduled heartbeat.
     - If `state_changed` or `heartbeat_due`, invoke `sendmail` role with `mail_template: "progress-mail.j2"`.
     - Node Stall Detection: If a single node remains the active updating node for more than `node_stall_threshold_minutes` and `auto_force_stalled_node: true`, execute `oc debug node/<node> -- chroot /host touch /run/machine-config-daemon-force`.
     - Sleep `poll_interval_minutes * 60` seconds between iterations using `pause:`.
  3. **Timeout Guard**: If loop reaches maximum iterations without settling, fail explicitly with:
     ```yaml
     - name: "Enforce hop timeout guard"
       fail:
         msg: "CRITICAL: Upgrade hop exceeded {{ hop_timeout_minutes }}m timeout without settling. MCP or ClusterVersion stalled."
       when: not (hop_settled | default(false) | bool)
     ```
  4. **Settle-Gate Verification**:
     - Confirm `ClusterVersion.status.history[0].state == "Completed"` and version matches target.
     - Confirm all ClusterOperators report `Available == "True"` and `Progressing == "False"`.
     - Confirm all MachineConfigPools report `Updated == "True"` and `Degraded == "False"`.
     - On pass, record settle-gate success and log duration.

### 2. Phase 04 Playbook (`playbooks/04_Live_monitoring_upgrade.yaml`)
- Thin task playbook included per hop from `playbooks/tasks/hop.yml`.
- Invokes `roles/monitor` with hop context variables (`hop_target_version`, `hop_label`, `hop_number`, `hop_total`).

---

## Verification Checklist

- [ ] Polling loop executes every 2 minutes with zero task mutations (`changed_when: false`).
- [ ] Heartbeat emails arrive every 20 minutes; state changes trigger immediate email.
- [ ] Working node (draining/rebooting) is detected and surfaced in email.
- [ ] Stalled rollout triggers 90-minute timeout guard and halts via rescue block.
- [ ] Settle-gate rigorously verifies cv target + COs + MCP before declaring hop complete.
- [ ] Playbook passes `ansible-playbook --syntax-check`.
