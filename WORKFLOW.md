# How a run works

This page follows one run from the command line to the summary mail, in the order the code runs. Each step names the file that does it, so you can open the files in the same order.

```
./00_Run.sh                          asks: cluster, mode, path -> confirm -> lock
   |
   v
main.yml                             ONE play, ONE block / rescue / always
   |-- Log in                           steps/common/login.yml
   |-- 01_Policy_Check.yaml             snapshot + validate the whole path            (read-only)
   |-- 02_Pre_upgrade_check.yaml        16 prechecks -> GATE                          (read-only)
   |-- 03_Pre_upgrade_Implementation    4 tasks: check -> change -> watch rollout (05) -> verify
   |                                    -> re-run the 16 prechecks -> GATE
   |-- 04_Initiate_upgrade.yaml         for each hop: plan -> start -> watch (05)
   |      `-- 05_Live_monitoring_upgrade.yaml   poll until settled, heartbeat mails
   |-- 06_post_Upgrade_Checks.yaml      10 postchecks + baseline diff -> GATE
   |-- 07_Operator_Upgrade.yaml         approve operator updates, dev console -> GATE
   |-- write the report, send the summary mail
   |
   |-- rescue (any failure above): report + status file + ONE alert mail
   `-- always: log out
```

## The four run modes

| Mode | Command | Phases | Changes the cluster? |
|---|---|---|---|
| upgrade | `./00_Run.sh --cluster cluster_d01` | 01 02 03 04 06 07 (05 inside 03 and 04) | yes |
| dry-run | `./00_Run.sh --cluster cluster_d01 --dry-run` | 01 02 03 04 06 07 | **no** - the same steps, every write is skipped |
| pre-check | `./00_Run.sh --cluster cluster_d01 --pre-check` | 01 02 03 | only the Phase 03 changes (nodes may reboot), no cluster update |
| post-check | `./00_Run.sh --cluster cluster_d01 --post-check` | 06 | no |

There is no separate "resume" mode. If a run stops, fix the cause and run the same command again: hops the cluster already finished are skipped, and an update that is still running is watched instead of being started again. (`--resume` is accepted but not needed.)

While testing, any phase include in `main.yml` (or any task include in `03_Pre_upgrade_Implementation.yaml`) can be commented out. Each phase reads what it needs from the cluster itself.

## Step by step

### 0. `00_Run.sh` (start here)
1. Checks that `ansible-playbook`, `oc`, `jq`, `curl`, `python3` and `flock` are installed. If the Ansible `mail` module is missing, it warns and turns mails off.
2. Reads the cluster list from `vars/secrets.yml` and the default path for each cluster from `vars/upgrade.yml`.
3. Takes the cluster, mode and path from the flags, or asks for them with numbered prompts.
4. Shows the cluster, mode, path and whether the cluster will change, then asks for confirmation. A PROD run that changes the cluster (upgrade or pre-check) needs the word `UPGRADE` typed in; `--yes` never skips that.
5. Locks the cluster (`/tmp/aro-upgrade-<cluster>.lock`) so only one run can work on it.
6. Empties `logs/`, so it only ever holds the latest run. Logs of a run still active on another cluster are kept; reports and snapshots are never deleted.
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
1. `steps/01/snapshot.yml` saves `snapshots/<cluster>_<ts>_baseline.json`: version, nodes, operators and routes. Phase 06 compares against it.
2. `steps/01/validate_path.yml` splits the path into three groups:
   - hops already reached (skipped)
   - an update already running to the next hop (watched)
   - hops still to run

   It then checks:
   - the path shape: ascending, same major version, no skipped minor version
   - every remaining edge, against the OpenShift update graph of that hop's channel
   - the first edge, also against what the cluster itself offers
3. **GATE:** an invalid path stops the run before anything has changed.

### 4. Phase 02: `02_Pre_upgrade_check.yaml` (read-only)
1. `steps/02/run_all_checks.yml` runs `check_01` … `check_16`. Each check reads the cluster and records PASS, WARN or FAIL. No check stops the run on its own, and nothing on the cluster is changed.

   | # | Check | Gate |
   |---|---|---|
   | 01 | ClusterOperators healthy | HARD |
   | 02 | Nodes Ready, no pressure | HARD |
   | 03 | MachineConfigPools updated, not paused (Phase 03 task 1) | HARD |
   | 04 | API server URL | HARD |
   | 05 | API server `/readyz` | HARD |
   | 06 | etcd | HARD |
   | 07 | Admin-acks and removed APIs (Phase 03 task 4) | HARD |
   | 08 | CPU / memory headroom | HARD |
   | 09 | Pending CSRs | WARN |
   | 10 | PersistentVolumes | WARN |
   | 11 | PersistentVolumeClaims | WARN |
   | 12 | PodDisruptionBudgets | WARN (HARD if `fail_on_zero_disruption_pdb`) |
   | 13 | Platform pods | WARN |
   | 14 | cgroup v2 for 4.19+ (Phase 03 task 2) | HARD |
   | 15 | Operator upgrade blockers (`olm.maxOpenShiftVersion`, OLM `Upgradeable=False`) (Phase 03 task 3) | HARD |
   | 16 | Installed operator health (CSV phase, subscription problems, own upgrade blocked, channel) | WARN |

2. **Left to Phase 03.** When Phase 03 is part of the run and the fix is switched on, a problem Phase 03 fixes is recorded as WARN ("Phase 03 will ...") instead of FAIL:
   - Check 03: every failing pool is paused and on `mcp_auto_unpause_list`, and none is Degraded.
   - Check 14: cgroup v1 on a path that reaches 4.19+.
   - Check 15: every blocking operator has an upgrade pending.

   A blocking operator with nothing pending, a Degraded pool or a paused pool that is not on the list stays FAIL.
3. **GATE:** any HARD check that is FAIL stops the run. Nothing has been changed at this point.

### 5. Phase 03: `03_Pre_upgrade_Implementation.yaml`
Makes the changes the cluster needs before the first hop. Each task is one file in `steps/03/` and works the same way:

**check → change if needed → watch the node rollout it started → verify → record one row → stop the run if the change did not work.**

| # | Task | Change | Watch |
|---|---|---|---|
| 1 | `task_1_unpause_pools.yml` | unpause paused pools on `mcp_auto_unpause_list` | watched at once when the pool had configuration held back |
| 2 | `task_2_cgroup_v2.yml` | `cgroupMode: v2` when a hop reaches 4.19+ | always watched (every node reboots) |
| 3 | `task_3_operator_upgrades.yml` | approve the current InstallPlan of every subscription with an upgrade pending (`steps/07/approve_operators.yml`, the same step Phase 07 uses), wait for Succeeded; stop if an operator still blocks the target version | looked for, watched if a pool starts updating |
| 4 | `task_4_admin_ack.yml` | removed-API check (APIRequestCount), then the admin-ack keys for the minor the cluster is on, then wait for `Upgradeable=True` when the first hop is a minor hop | looked for, watched if a pool starts updating |

- **Watching** is `steps/03/watch_rollout.yml`. For a change that may or may not roll out, it looks for up to `rollout_detect_seconds` for a pool that starts updating. If one does, Phase 05 watches it in rollout mode, with heartbeat and degradation mails, until every pool has settled. The next task only starts after that.
- **The order matters:** a paused pool would not take the cgroup change, and the admin-ack step waits for `Upgradeable=True`, which a blocking operator keeps False.
- **Results:** each task records one row: PASS (nothing needed), AUTO-FIXED (changed and verified), WARN (a dry run would change it), SKIPPED (its switch is off), FAIL or FIX-FAILED (the run stops here).
- **Re-check:** if any task changed the cluster, all 16 prechecks run again, with nothing left to Phase 03. A check a task worked on becomes AUTO-FIXED if it now passes and FIX-FAILED if not.
- **GATE:** any HARD check that is FAIL or FIX-FAILED stops the run. No hop has started.
- **During an update:** if a cluster update is already running (a re-run that resumes a hop), nothing is changed and every task is SKIPPED.
- **Dry run:** each task reports what it would change.

### 6. Phase 04: `04_Initiate_upgrade.yaml`, one `steps/04/hop.yml` per hop
1. **Plan from the live cluster:** skip the hop if it is already done, watch it if it is already running, start it otherwise. If an update to a different version is running, the run stops.
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
Never runs on its own. Phase 04 includes it for each hop (hop mode), and Phase 03 for each node rollout (rollout mode).
- Every `poll_interval_minutes`, reads ClusterVersion, ClusterOperators, MachineConfigPools and Nodes in one call.
- Sends a heartbeat mail every `heartbeat_minutes`, and one degradation mail per new problem (after its grace period).
- Logs in again if the session token expired.
- **Settled** means every unpaused pool is updated, every node is done and operators are settled; in hop mode the cluster must also be at the target, Available, and not Progressing or Failing. This must hold for `settle_consecutive_polls` polls in a row.
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
2. **GATE:** a HARD failure stops the run. In a dry run the gate is reported, not enforced.

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
2. Adds a FAIL row for a Phase 03 task that stopped part-way, for example during its rollout watch.
3. Writes the `.status` file, which `00_Run.sh` turns into the exit code.
4. Writes the report with a "Why the run stopped" section.
5. Sends one alert mail.

Then `always:` logs out.

## Exit codes
`0` OK · `1` bad option, missing tool or cluster locked · `2` cancelled · `5` login or Phase 01 · `10` Phase 02 · `15` Phase 03 · `20` hop failed (Phase 04) · `30` hop stopped progressing or timed out (Phase 05) · `25` Phase 06 · `35` Phase 07 · `99` other.

## Mails
| Mail | When | To |
|---|---|---|
| heartbeat | every `heartbeat_minutes` while the cluster updates or a Phase 03 rollout runs | `mail_to` |
| degradation | once per new problem during an update or a Phase 03 rollout | `alert_mail_to` + `mail_to` |
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
