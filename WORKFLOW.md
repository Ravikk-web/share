# How a run works

This page follows one run from the command line to the summary mail, in the order the code runs. Each step names the file that does it, so you can open the files in the same order.

```
./00_Run.sh                          asks: cluster, mode, path -> confirm -> lock
   |
   v
main.yml                             ONE play, ONE block / rescue / always
   |-- Log in                           steps/common/login.yml
   |-- 01_Policy_Check.yaml             snapshot + validate the whole path            (read-only)
   |-- resume                           an update still running? watch it to the end (05)
   |                                    (steps/04/finish_running_update.yml)
   |-- 02_Pre_upgrade_check.yaml        17 prechecks -> GATE                          (read-only)
   |-- 03_Pre_upgrade_Implementation    4 tasks: check -> change -> watch rollout (05) -> verify
   |                                    -> re-run the 17 prechecks -> GATE
   |-- 04_Initiate_upgrade.yaml         for each hop: plan -> start -> watch (05)
   |      `-- 05_Live_monitoring_upgrade.yaml   poll until settled, heartbeat mails
   |-- 06_post_Upgrade_Checks.yaml      10 postchecks + baseline diff -> GATE
   |-- 07_Operator_Upgrade.yaml         approve operator updates, dev console -> GATE
   |-- write the report, send the summary mail
   |
   |-- rescue (any failure above): node diagnosis + report + status file + ONE alert mail
   `-- always: log out
```

## The four run modes

| Mode | Command | Phases | Changes the cluster? |
|---|---|---|---|
| upgrade | `./00_Run.sh --cluster cluster_d01` | 01 02 03 04 06 07 (05 inside 03, 04 and the resume step) | yes |
| dry-run | `./00_Run.sh --cluster cluster_d01 --dry-run` | 01 02 03 04 06 07 | **no** - the same steps, every write is skipped |
| pre-check | `./00_Run.sh --cluster cluster_d01 --pre-check` | 01 02 03 | only the Phase 03 changes (nodes may reboot), no cluster update |
| post-check | `./00_Run.sh --cluster cluster_d01 --post-check` | 06 | no |

There is no separate "resume" mode. If a run stops, fix the cause and run the same command again:
- an update that is still running is watched to the end first: the control plane updating to a hop, or a hop that ClusterVersion already reports Completed while its nodes are still updating (pools rolling);
- then the prechecks judge a settled cluster, with every gate;
- hops the cluster already finished are skipped.

`--resume` is accepted but not needed. A dry run only reports what a live run would watch; a post-check checks the cluster as it is and says that an update is still running.

While testing, any phase include in `main.yml` (or any task include in `03_Pre_upgrade_Implementation.yaml`) can be commented out. Each phase reads what it needs from the cluster itself.

## Step by step

### 0. `00_Run.sh` (start here)
1. Checks that `ansible-playbook`, `oc`, `jq`, `curl`, `python3` and `flock` are installed. If the Ansible `mail` module is missing, it warns and turns mails off.
2. Reads the cluster list from `vars/secrets.yml` and the default path for each cluster from `vars/upgrade.yml`.
3. Takes the cluster, mode and path from the flags, or asks for them with numbered prompts.
4. Shows the cluster, mode, path and whether the cluster will change, then asks for confirmation. A PROD run that changes the cluster (upgrade or pre-check) needs the word `UPGRADE` typed in; `--yes` never skips that.
5. Locks the cluster (`/tmp/aro-upgrade-<cluster>.lock`) so only one run can work on it.
6. Keeps the logs of the cluster's last `log_keep_runs` runs (default 5, this run included) in `logs/` and deletes its older ones, so the log of a failed run is still there after the run that resumes it. Other clusters' logs are left alone; reports and snapshots are never deleted.
7. Runs `main.yml`, copying the console into `logs/<cluster>_<timestamp>.txt`.
8. Exits with the code the playbook wrote to `logs/<cluster>_<timestamp>.status`, and prints the report path.

### 1. `main.yml`: start
- Checks the inputs and picks the phases for the mode.
- Sets `dry_run` (true only in dry-run mode) and `target_max_version` (the highest hop of the path).
- Names the run's files: one report, one `.txt` log, one `.csv` log and one `.status` file.
- Every `oc` command in the run uses the run's own kubeconfig (`KUBECONFIG` is set once for the whole play).

### 2. Log in: `steps/common/login.yml`
- `oc login` reads the password from stdin. Rejected credentials are not retried, so the account cannot be locked out.
- The login is accepted only if the session's API URL, the optional `cluster_id` pin and `desired_cluster_api_regex` all match.

### 3. Phase 01: `01_Policy_Check.yaml` (read-only)
1. `steps/01/snapshot.yml` saves `snapshots/<cluster>_<ts>_baseline.json`: version, nodes, operators and routes. Phase 06 compares against it. The snapshot also records whether an update was still running when it was taken (`update_running`).
2. `steps/01/validate_path.yml` splits the path into three groups:
   - hops already reached (skipped)
   - an update already running to the next hop (watched)
   - hops still to run

   It then checks:
   - the path shape: ascending, same major version, no skipped minor version
   - every remaining edge, against the OpenShift update graph of that hop's channel
   - the first edge, also against what the cluster itself offers
3. **GATE:** an invalid path stops the run before anything has changed.

### 3a. Resume: `steps/04/finish_running_update.yml` (upgrade, pre-check; a dry run only reports)
`steps/04/read_update_state.yml` reads ClusterVersion and the MachineConfigPools. An update is still running when:
- the control plane is updating (ClusterVersion `Progressing=True` and desired ≠ completed), or
- ClusterVersion reports the version Completed but an unpaused pool still has machines that are not on its target configuration (`updatedMachineCount` < `machineCount`). ClusterVersion reports Completed once the control plane is done; the worker nodes of that hop follow afterwards through their pool.

A pool whose machines all run the target, but which still reports `Updating=True`, is not a running update. The MCO reports that while one node is unavailable, NotReady or cordoned. That is a node problem, and Check 02 diagnoses it.

Such an update is watched to the end by Phase 05 in hop mode, with the heartbeat and degradation mails and the hop exit codes (20 / 30), and recorded as `COMPLETE (resumed)` for its hop. Only then do the prechecks run, so a resumed run is not stopped by the cordoned and rebooting nodes of its own update. An update to a version outside the path stops the run.

### 4. Phase 02: `02_Pre_upgrade_check.yaml` (read-only)
1. `steps/02/run_all_checks.yml` runs `check_01` … `check_17`. Each check reads the cluster and records PASS, WARN or FAIL. No check stops the run on its own, and nothing on the cluster is changed.

   | # | Check | Gate |
   |---|---|---|
   | 01 | ClusterOperators healthy | HARD |
   | 02 | Nodes Ready, no pressure, not cordoned (a failure is diagnosed: see below) | HARD |
   | 03 | MachineConfigPools updated, not paused (Phase 03 task 1) | HARD |
   | 04 | API server URL | HARD |
   | 05 | API server `/readyz` | HARD |
   | 06 | etcd | HARD |
   | 07 | Admin-acks and removed APIs (Phase 03 task 4) | HARD |
   | 08 | Drain headroom: per pool (not master), the pods of the largest `maxUnavailable` nodes fit on the other nodes | HARD |
   | 09 | Pending CSRs | WARN |
   | 10 | PersistentVolumes | WARN |
   | 11 | PersistentVolumeClaims | WARN |
   | 12 | PodDisruptionBudgets | WARN (HARD if `fail_on_zero_disruption_pdb`) |
   | 13 | Platform pods | WARN |
   | 14 | cgroup v2 for 4.19+: the setting AND every node (MCO configuration and/or kernel, `cgroup_check_method`) (Phase 03 task 2) | HARD |
   | 15 | Operator upgrade blockers (`olm.maxOpenShiftVersion`, OLM `Upgradeable=False`) (Phase 03 task 3) | HARD |
   | 16 | Installed operator health (CSV phase, subscription problems, own upgrade blocked, channel) | WARN |
   | 17 | Router drain headroom: eligible nodes ≥ router replicas + `maxUnavailable` | WARN |

   - **Check 08** models the node drain. For each pool except master, it drains the pool's largest `maxUnavailable` nodes. The requests of the pods that have to move (all but DaemonSet and static pods) must then stay within `max_cpu_percent` / `max_memory_percent` of what the pool's other Ready, schedulable nodes can still allocate. Pods that do not fit stay Pending, their PodDisruptionBudgets then block the drain, and the pool never finishes. The master pool is skipped; a pool with one node is listed, not judged. A failed read fails the check and is retried; it never passes on missing data.
   - **Check 14** checks every node with `steps/03/cgroup_nodes.yml` whenever the path reaches 4.19+. The MCO must have finished the node. Then `cgroup_check_method` in `vars/upgrade.yml` decides what proves the node runs v2:
     - `config` (default): the rendered configuration it runs has no `systemd.unified_cgroup_hierarchy=0`. No exec.
     - `kernel`: `stat -c %T -f /sys/fs/cgroup` on the node prints `cgroup2fs` (`oc exec` into the node's machine-config-daemon pod, read-only; needs `pods/exec`). MachineConfigs are not read, so a finished node on a v1 kernel cannot be told from one the rollout has not reached yet: it counts as still to roll out.
     - `both`: the configuration, then the kernel of every node that runs a v2 configuration.

     Any other value stops the run at the start. The nodes decide, not the setting. An empty `cgroupMode` is fine when every node runs v2: the MCO renders an empty setting as v2 on OpenShift 4.14+. An explicit `v1` is always a problem. A node that cannot be checked counts as not on v2. With `skip_cgroup_check` the nodes are not checked and the check is a WARN.
   - **Check 17** warns when a router deployment has fewer eligible nodes (Ready, schedulable, matching its nodeSelector and taints) than replicas + `maxUnavailable`. Router pods of the same version must run on different nodes, so every drain then leaves one router Pending until the node is back: ingress is Progressing meanwhile, and Degraded after 60 minutes. Not a blocker.
   - **Node diagnosis.** When Check 02 fails, `steps/common/diagnose_nodes.yml` says for each node what is wrong, the likely cause and what to do (see "Node problems" below).

2. **Left to Phase 03.** When Phase 03 is part of the run and the fix is switched on, a problem Phase 03 fixes is recorded as WARN ("Phase 03 will ...") instead of FAIL:
   - Check 03: every failing pool is paused and on `mcp_auto_unpause_list`, and none is Degraded.
   - Check 14, on a path that reaches 4.19+:
     - the setting is not v2 and nodes are not on v2 (needs `auto_fix_cgroup_v2` and `auto_remediation_enabled`): Phase 03 sets v2;
     - the setting is v2 but nodes still run a v1 configuration (with `kernel`: a v1 kernel): they have not finished, or not started, rolling it out, and Phase 03 watches the rollout.

     In both cases Phase 03 then checks every node. If the MCO never renders a v2 configuration (for example a custom MachineConfig that forces v1), Phase 03 stops after `cgroup_render_wait_minutes`.
   - Check 15: every blocking operator has an upgrade pending.

   The following stay FAIL:
   - a blocking operator with nothing pending;
   - a Degraded pool, or a paused pool that is not on the list;
   - for Check 14: the nodes cannot be read; or a node the MCO has finished runs a configuration that cannot be read; or it runs a v2 configuration but its kernel is not on cgroup v2 (`both`); or its kernel cannot be checked (`kernel`, `both`).

3. **GATE:** any HARD check that is FAIL stops the run. Nothing has been changed at this point.

### 5. Phase 03: `03_Pre_upgrade_Implementation.yaml`
Makes the changes the cluster needs before the first hop. Each task is one file in `steps/03/` and works the same way:

**check → change if needed → watch the node rollout it started → verify → record one row → stop the run if the change did not work.**

| # | Task | Change | Watch |
|---|---|---|---|
| 1 | `task_1_unpause_pools.yml` | unpause paused pools on `mcp_auto_unpause_list` | watched at once when the pool had configuration held back |
| 2 | `task_2_cgroup_v2.yml` | `cgroupMode: v2` when a hop reaches 4.19+; then wait (up to `cgroup_render_wait_minutes`) until the MCO has rendered a v2 configuration for every pool | always watched (every node reboots, one at a time per pool); then every node is checked (`steps/03/cgroup_nodes.yml`, up to `cgroup_node_check_wait_minutes` for the last one). AUTO-FIXED only when every node is on v2. When the setting is already v2 but nodes have not finished, the rollout is watched and checked without a change (PASS) |
| 3 | `task_3_operator_upgrades.yml` | approve the current InstallPlan of every subscription with an upgrade pending (`steps/07/approve_operators.yml`, the same step Phase 07 uses), wait for Succeeded; stop if an operator still blocks the target version | looked for, watched if a pool starts updating |
| 4 | `task_4_admin_ack.yml` | removed-API check (APIRequestCount), then the admin-ack keys for the minor the cluster is on, then wait for `Upgradeable=True` when the first hop is a minor hop | looked for, watched if a pool starts updating |

- **Watching** is `steps/03/watch_rollout.yml`. For a change that may or may not roll out, it looks for up to `rollout_detect_seconds` for a pool that starts updating. If one does, Phase 05 watches it in rollout mode, with heartbeat and degradation mails, until every pool has settled. The next task only starts after that.
- **The order matters:** a paused pool would not take the cgroup change, and the admin-ack step waits for `Upgradeable=True`, which a blocking operator keeps False.
- **Results:** each task records one row: PASS (nothing needed), AUTO-FIXED (changed and verified), WARN (a dry run would change it), SKIPPED (its switch is off), FAIL or FIX-FAILED (the run stops here).
- **Re-check:** if any task changed the cluster (or watched nodes reboot), all 17 prechecks run again, with nothing left to Phase 03. A check a task changed something for becomes AUTO-FIXED if it now passes and FIX-FAILED if not.
- **GATE:** any HARD check that is FAIL or FIX-FAILED stops the run. No hop has started.
- **During an update:** if a cluster update is still running (normally the resume step has watched it to the end before), nothing is changed and every task is SKIPPED.
- **Dry run:** each task reports what it would change.

### 6. Phase 04: `04_Initiate_upgrade.yaml`, one `steps/04/hop.yml` per hop
1. **Plan from the live cluster** (`steps/04/read_update_state.yml`):
   - skip the hop if it is already done: the cluster completed it, and no pool is still rolling out its nodes;
   - watch it if it is still running: the control plane is updating to it, or ClusterVersion reports it Completed while pools still roll out its nodes;
   - start it otherwise.

   If an update to a different version is running, the run stops. A hop the resume step already watched keeps its `COMPLETE (resumed)` row.
2. **Wait for a stable cluster:** up to `prehop_settle_wait_minutes`.
3. **`steps/04/start_hop.yml`:**
   - set the channel
   - wait until the cluster offers the target
   - refuse conditional-update risks unless `allow_conditional_updates` is true
   - on a minor hop, run `steps/03/admin_ack.yml` again (the Phase 03 task 4 step): check removed-API usage, set any admin-ack still pending, wait for `Upgradeable=True`. Phase 03 already applied the first minor hop's ack. A later minor hop's key only appears once the cluster is on that minor, so it is applied here.
   - run `oc adm upgrade --to=<hop>` and confirm the cluster accepted it
4. **Watch the hop:** `05_Live_monitoring_upgrade.yaml`.

A dry run only prints the plan for each hop.

### 7. Phase 05: `05_Live_monitoring_upgrade.yaml` and `steps/05/poll.yml`
Never runs on its own. Phase 04 includes it for each hop (hop mode), Phase 03 for each node rollout (rollout mode), and the resume step for an update that was already running (hop mode).
- Every `poll_interval_minutes`, reads ClusterVersion, ClusterOperators, MachineConfigPools and Nodes in one call.
- Sends a heartbeat mail every `heartbeat_minutes`, and one degradation mail per new problem (after its grace period). A mail about a node or a blocked pool carries the node diagnosis: what is wrong, the likely cause and what to do.
- **A pool that cannot continue** is a degradation (after `degradation_pool_blocked_minutes`):
  - the pool has configuration to roll out;
  - no node of the pool is updating;
  - its unavailable nodes (NotReady or cordoned) use up `maxUnavailable`, default 1.

  The MCO then updates no other node of the pool, and the pool never finishes, without ever going Degraded: the console shows "Worker Nodes 0 of 3".

  Unavailable is the MCO's own test: not Ready, disk pressure, network unavailable, or cordoned. The same mail also fires when every node still waiting is unavailable (the MCO never picks such a node, whatever `maxUnavailable` is). It also fires when every node runs the target but an unavailable node keeps the pool from reporting Updated ("cannot finish").

  The watch keeps going: if the node is back within `hop_timeout_minutes` (90) of the last progress, the update continues by itself. Otherwise the hop stops with exit 30, and running the same command again resumes the watch.
- Logs in again if the session token expired.
- **Settled** means every unpaused pool is updated, every node is done, operators are settled, and ClusterVersion is Available and not Progressing or Failing; in hop mode the cluster must also be at the target. This must hold for `settle_consecutive_polls` polls in a row.
- **Fails** if:
  - nothing progresses for `hop_timeout_minutes` (exit 30 for a hop)
  - the watch runs longer than `hop_max_minutes` (exit 30 for a hop)
  - the API is unreadable for `monitor_api_outage_minutes` (exit 30 for a hop)
  - the release is not accepted (exit 20)
  - ClusterVersion stays Failing too long (exit 20)

  A rollout watch that fails keeps Phase 03's exit code (15).

### 8. Phase 06: `06_post_Upgrade_Checks.yaml`
1. `steps/06/run_all_checks.yml` runs 10 checks:
   - ClusterVersion, ClusterOperators (waits for them to settle), pools, nodes and kubelet version, node pressure, etcd (HARD)
   - PVs, platform pods, critical alerts, baseline diff (WARN)

   The baseline diff prefers a snapshot taken on a settled cluster: this run's, else the newest earlier one. A resumed run takes its own snapshot mid-update.
2. A post-check (or a dry run) never waits for an update that is still running. It checks the cluster as it is, and the result and the gate message say that an update is running.
3. **GATE:** a HARD failure stops the run. In a dry run the gate is reported, not enforced.

### 9. Phase 07: `07_Operator_Upgrade.yaml`
1. `steps/07/approve_operators.yml` approves only the current InstallPlan of each subscription that has a pending upgrade (new versions often appear after the cluster upgrade), then waits for those operators. A Failed operator gets its Deployments restarted once.
2. `steps/07/validate_operators.yml`:
   - HARD: approved upgrades that did not finish, and operators that regressed
   - WARN: operators that were already unhealthy, and plans left unapproved
3. `steps/07/developer_console.yml` enables the Developer perspective if it is Disabled. A problem here is only a WARN.
4. **GATE:** approved operators must be healthy. The cluster upgrade itself is never rolled back.

### 10. Finish
- `steps/common/write_report.yml` writes `output/<cluster>_<ts>_report.html` (one section per phase that ran).
- `steps/common/send_mail.yml` sends the summary mail with the report and logs attached.

### When something fails
Every failing task, in any phase, jumps to the `rescue:` in `main.yml`, which runs `steps/common/handle_failure.yml`:
1. Works out the error (stderr first, then the task message), the phase, the Phase 03 task or hop, and the exit code. It also flags permission (RBAC) problems.
2. Looks at the nodes (after login and Phase 01): a node that is not Ready, cordoned, under pressure or stuck in its update goes into the alert and the report with the likely cause and what to do. A problem here never stops the alert.
3. Adds a FAIL row for a Phase 03 task that stopped part-way, for example during its rollout watch.
4. Writes the `.status` file, which `00_Run.sh` turns into the exit code.
5. Writes the report with a "Why the run stopped" section.
6. Sends one alert mail.

Then `always:` logs out.

### Node problems (report only)
`steps/common/diagnose_nodes.yml` is used by Check 02, Phase 05 (before a degradation mail about a node or a blocked pool) and the failure handler. It reads nodes, pools, Machines, PodDisruptionBudgets, the pods on the problem nodes, Pending pods and, when the metrics API answers, `oc adm top nodes`. Fixed rules name the problem, the likely cause and what to do:

| Node | Likely cause | What to do (reported, never done by the automation) |
|---|---|---|
| NotReady, Ready=Unknown | VM stopped or hung, network lost, kubelet starved | check the Machine / Azure VM, restart a hung VM; replace a worker's Machine; never delete a master (ARO support) |
| NotReady, network plugin message | OVN-Kubernetes pod on the node not running | look at that pod in `openshift-ovn-kubernetes` |
| NotReady, PLEG message | node overloaded or CRI-O hung | `oc adm top node`, CRI-O log, restart a VM that does not recover |
| machine-config daemon Degraded | the MCD could not apply its configuration | the MCD log names it |
| machine-config daemon Unreconcilable | the configuration cannot be applied to this node at all | fix or revert the MachineConfig the reason names |
| Memory / Disk / PID pressure | node short of resources | move or scale down workloads, free disk |
| network unavailable (`NetworkUnavailable=True`) | the node network is not set up | look at the OVN-Kubernetes pod on the node |
| cordoned, MCO update open | the drain cannot evict a pod: a PodDisruptionBudget allowing 0 disruptions, or no room for the evicted pods | the machine-config-controller log names the pod; with its owner, get the app healthy or delete that one pod; do not uncordon |
| cordoned, MCO done | cordoned outside the update (maintenance left over); counts as unavailable for the MCO | `oc adm uncordon <node>` when nobody is working on it |

Each row also shows:
- the node's Machine and VM state;
- its load: requests, memory limits and usage. The node is flagged as overcommitted at `node_overcommit_memory_usage_percent` (90) memory usage, or at memory limits above `node_overcommit_memory_limits_percent` (150) of allocatable;
- the PodDisruptionBudgets allowing 0 disruptions whose selector matches a pod on the node that a drain has to evict (DaemonSet pods are left out);
- when its pool cannot continue or finish, that too.

Pods that cannot be scheduled are listed with the scheduler's message, for example the third router of 3 on 3 workers while a worker is out. When the nodes cannot be read at all, the diagnosis says so ("could not run"), never "no problems".

## Exit codes
`0` OK · `1` bad option, missing tool or cluster locked · `2` cancelled · `5` login or Phase 01 · `10` Phase 02 · `15` Phase 03 · `20` hop failed (Phase 04) · `30` hop stopped progressing or timed out (Phase 05) · `25` Phase 06 · `35` Phase 07 · `99` other.

## Mails
| Mail | When | To |
|---|---|---|
| heartbeat | every `heartbeat_minutes` while the cluster updates or a Phase 03 rollout runs | `mail_to` |
| degradation | once per new problem during an update or a Phase 03 rollout (with the node diagnosis for a node or a blocked pool) | `alert_mail_to` + `mail_to` |
| summary | once, at the end of a successful run | `mail_to` |
| alert | once, when a run fails | `alert_mail_to` + `mail_to` |

Templates: summary `email-summary.j2`, alert `error-report.j2`, heartbeat and degradation `progress-mail.j2`.
`--mail-to` replaces `mail_to` for one run. `send_email: false` in `vars/smtp.yml` turns all mails off.

## Every change the automation can make to the cluster
| Phase | Change | Only when |
|---|---|---|
| 03 | MachineConfigPool `spec.paused: false` | paused pool on `mcp_auto_unpause_list`, `auto_unpause_mcp` |
| 03 | `nodes.config/cluster` `cgroupMode: v2` | a hop reaches 4.19+, cluster on v1, `auto_fix_cgroup_v2` |
| 03 | InstallPlan `spec.approved: true` | current plan of an UpgradePending subscription, `preupgrade_operator_upgrades`, not `skip_operator_upgrade` |
| 03 | `oc rollout restart` of a Failed operator's Deployments (once) | an operator approved in Phase 03 failed, `operator_upgrade_auto_recover` |
| 03 | `openshift-config/admin-acks` key(s) | a minor hop in the path, key pending for the current minor, no removed-API callers, `auto_apply_admin_acks` |
| 04 | ClusterVersion `spec.channel` | the hop's channel differs |
| 04 | `openshift-config/admin-acks` key(s) | minor hop, key still pending (a later hop's), no removed-API callers, `auto_apply_admin_acks` |
| 04 | `oc adm upgrade --to=<hop>` | hop plan is "start" |
| 07 | InstallPlan `spec.approved: true` | current plan of an UpgradePending subscription, not `skip_operator_upgrade` |
| 07 | `oc rollout restart` of a Failed operator's Deployments (once) | `operator_upgrade_auto_recover` |
| 07 | console perspectives (`dev` -> Enabled) | it is Disabled, `enable_developer_perspective` |

The unpause and cgroup changes also need `auto_remediation_enabled`. A dry run makes none of these changes. A pre-check makes only the Phase 03 ones.

Nothing else is changed. In particular, nodes are never patched, cordoned, uncordoned, drained, rebooted or deleted: the MCO applies the cgroup setting to the nodes itself, and node problems are only reported. The one action that runs inside the cluster without changing it is `oc exec` into the existing machine-config-daemon pod of each node, for the read-only kernel check of Check 14 and Phase 03 task 2 (only with `cgroup_check_method` `kernel` or `both`).

## Where things are
```
playbooks/
  00_Run.sh, main.yml, 01..07       the flow (read in this order)
  steps/common/                     login, logout, log, mail, report, failure handler
  steps/01 .. steps/07/             the steps of each phase (one file per check / task)
  templates/                        report.j2, email-summary.j2, progress-mail.j2, error-report.j2
  vars/                             all settings (upgrade.yml, smtp.yml, secrets.yml, ...)
  logs/ output/ snapshots/          what each run writes
```
