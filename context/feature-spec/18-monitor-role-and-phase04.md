# Unit 18: `monitor` Role + Phase 04 (`04_Live_monitoring_upgrade.yaml`)

## Goal

Build the `monitor` role and `04_Live_monitoring_upgrade.yaml` that polls cv/mcp/nodes every 2 minutes during each hop, enforces a 90-minute timeout guard, runs the settle-gate, and sends 20-minute heartbeat + immediate state-change emails.

## Design

- **System boundary:** `playbooks/roles/monitor` + phase file `04_Live_monitoring_upgrade.yaml` (called inside the hop).
- Deterministic polling loop; no detached daemon. Cadences from `vars` (2m poll, 20m heartbeat, 90m timeout).
- Settle-gate is hop N+1's entry condition. A stall past timeout → FAIL → alert → logout → stop.

## Implementation

### `monitor/tasks/main.yml`
Loop (bounded by `hop_timeout_minutes / poll_interval_minutes`): each iteration `oc get clusterversion|mcp|nodes -o json`, parse with `jq` (reuse mcp/node facts from Units 10/11), compute `% complete`, elapsed, current working node (draining/rebooting), degraded nodes. Detect **state change** vs previous poll; on change → send email immediately. Every `heartbeat_minutes` → send heartbeat email. `pause`/`wait_for` for the 2-min interval. `changed_when: false`.

### Timeout guard
If MCP not progressing/complete within `hop_timeout_minutes` → `fail:` (stall), triggering alert + logout via the hop's rescue.

### Settle-gate
After cv reaches target: assert cv at target, all ClusterOperators Available & not Progressing, MCP Updated=True. Pass → hop complete email; fail → `fail:`.

### `04_Live_monitoring_upgrade.yaml`
Thin phase that `include_role: monitor`; invoked per hop from `tasks/hop.yml`. Header + migration notes.

## Dependencies

- Unit 17 (`upgrade`/hop), Unit 05 (`sendmail`), Units 10/11 (mcp/node facts), Unit 04 (`progress-mail.j2`)
- Unit 01 (cadence vars)
- oc, jq

## Verify when done

- [ ] Polls cv/mcp/nodes every 2 min (bounded loop)
- [ ] Heartbeat email every 20 min; immediate email on state change
- [ ] Email shows MCP + current node + degraded-only, colour-coded, with hop x/y & % complete
- [ ] 90-min timeout → `fail:` → alert → logout
- [ ] Settle-gate asserts cv target + COs + MCP before next hop
- [ ] `changed_when: false`; cadences from `vars`
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
