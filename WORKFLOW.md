# How a run works

This page follows one run from the command line to the summary mail, in the order the code runs. Each step names the file that does it, so you can open the files in the same order.

```
./00_Run.sh                     asks: cluster, mode, path -> confirm -> lock
   |
   v
main.yml                        ONE play, ONE block / rescue / always
   |-- Log in                      steps/common/login.yml
   |-- 01_Policy_Check.yaml        snapshot + validate the whole path      (read-only)
   |-- 02_Pre_upgrade_check.yaml   16 prechecks -> auto-fix -> re-check -> GATE
   |-- 03_Initiate_upgrade.yaml    for each hop: plan -> start -> watch (04)
   |      `-- 04_Live_monitoring_upgrade.yaml   poll until settled, heartbeat mails
   |-- 05_post_Upgrade_Checks.yaml 10 postchecks + baseline diff -> GATE
   |-- 06_Operator_Upgrade.yaml    approve operator updates, dev console -> GATE
   |-- write the report, send the summary mail
   |
   |-- rescue (any failure above): report + status file + ONE alert mail
   `-- always: log out
```

## The four run modes

| Mode | Command | Phases | Changes the cluster? |
|---|---|---|---|
| upgrade | `./00_Run.sh --cluster cluster_d01` | 01 02 03(+04) 05 06 | yes |
| dry-run | `./00_Run.sh --cluster cluster_d01 --dry-run` | 01 02 03 05 06 | **no** - the same steps, every write is skipped |
| pre-check | `./00_Run.sh --cluster cluster_d01 --pre-check` | 01 02 | only the Phase 02 auto-fixes (nodes may reboot) |
| post-check | `./00_Run.sh --cluster cluster_d01 --post-check` | 05 | no |

There is no separate "resume" mode. If a run stops, fix the cause and run the same command again: hops the cluster already finished are skipped, and an update that is still running is watched instead of being started again. (`--resume` is accepted but not needed.)

## Step by step

### 0. `00_Run.sh` (start here)
1. Checks that `ansible-playbook`, `oc`, `jq`, `curl`, `python3` and `flock` are installed. If the Ansible `mail` module is missing, it warns and turns mails off.
2. Reads the cluster list from `vars/secrets.yml` and the default path for each cluster from `vars/upgrade.yml`.
3. Takes the cluster, mode and path from the flags, or asks for them with numbered prompts.
4. Shows the cluster, mode, path and whether the cluster will change, then asks for confirmation. A PROD run that changes the cluster needs the word `UPGRADE` typed in; `--yes` never skips that.
5. Locks the cluster (`/tmp/aro-upgrade-<cluster>.lock`) so only one run can work on it.
6. Empties `logs/`, so it only ever holds the latest run. Logs of a run still active on another cluster are kept; reports and snapshots are never deleted.
7. Runs `main.yml`, copying the console into `logs/<cluster>_<timestamp>.txt`.
8. Exits with the code the playbook wrote to `logs/<cluster>_<timestamp>.status`, and prints the report path.

### 1. `main.yml`: start
- Checks the inputs and picks the phases for the mode.
- Sets `dry_run` (true only in dry-run mode).
- Names the run's files: one report, one `.txt` log, one `.csv` log and one `.status` file.
- Every `oc` command in the run uses the run's own kubeconfig (`KUBECONFIG` is set once for the whole play).

### 2. Log in: `steps/common/login.yml`
- `oc login` reads the password from stdin. Rejected credentials are not retried, so the account cannot be locked out.
- The login is accepted only if the session's API URL, the optional `cluster_id` pin and `desired_cluster_api_regex` all match.

### 3. Phase 01: `01_Policy_Check.yaml` (read-only)
1. `steps/01/snapshot.yml` saves `snapshots/<cluster>_<ts>_baseline.json`: version, nodes, operators and routes. Phase 05 compares against it.
2. `steps/01/validate_path.yml` splits the path into three groups:
   - hops already reached (skipped)
   - an update already running to the next hop (watched)
   - hops still to run

   It then checks:
   - the path shape: ascending, same major version, no skipped minor version
   - every remaining edge, against the OpenShift update graph of that hop's channel
   - the first edge, also against what the cluster itself offers
3. **GATE:** an invalid path stops the run before anything has changed.

### 4. Phase 02: `02_Pre_upgrade_check.yaml`
1. `steps/02/run_all_checks.yml` runs `check_01` … `check_16`. Each check reads the cluster and records PASS, WARN or FAIL. No check stops the run on its own.

   | # | Check | Gate |
   |---|---|---|
   | 01 | ClusterOperators healthy | HARD |
   | 02 | Nodes Ready, no pressure | HARD |
   | 03 | MachineConfigPools updated, not paused (auto-fix) | HARD |
   | 04 | API server URL | HARD |
   | 05 | API server `/readyz` | HARD |
   | 06 | etcd | HARD |
   | 07 | Admin-acks and removed APIs | HARD |
   | 08 | CPU / memory headroom | HARD |
   | 09 | Pending CSRs | WARN |
   | 10 | PersistentVolumes | WARN |
   | 11 | PersistentVolumeClaims | WARN |
   | 12 | PodDisruptionBudgets | WARN (HARD if `fail_on_zero_disruption_pdb`) |
   | 13 | Platform pods | WARN |
   | 14 | cgroup v2 for 4.19+ (auto-fix) | HARD |
   | 15 | Operator upgrade blockers (`olm.maxOpenShiftVersion`, OLM `Upgradeable=False`) | HARD |
   | 16 | Installed operator health (CSV phase, subscription problems, own upgrade blocked, channel) | WARN |

2. Auto-fixes. They never run in a dry run, and are turned off with `auto_remediation_enabled: false`.
   - **Check 14 fails:** `steps/02/fix_cgroup_v2.yml` sets `cgroupMode: v2`, and every node reboots.
   - **Check 03 has paused pools on `mcp_auto_unpause_list`:** `steps/02/fix_unpause_mcp.yml` unpauses them.
3. If a fix started a node rollout, `04_Live_monitoring_upgrade.yaml` waits for it in rollout mode.
4. All 16 checks run again. A check that was fixed is marked AUTO-FIXED if it now passes, and FIX-FAILED if not.
5. **GATE:** any HARD check that is FAIL or FIX-FAILED stops the run. No upgrade has started at this point.

### 5. Phase 03: `03_Initiate_upgrade.yaml`, one `steps/03/hop.yml` per hop
1. **Plan from the live cluster:** skip the hop if it is already done, watch it if it is already running, start it otherwise. If an update to a different version is running, the run stops.
2. **Wait for a stable cluster:** up to `prehop_settle_wait_minutes`.
3. **`steps/03/start_hop.yml`:**
   - set the channel
   - wait until the cluster offers the target
   - refuse conditional-update risks unless `allow_conditional_updates` is true
   - on a minor hop, run `steps/03/admin_ack.yml`: check removed-API usage, set the admin-ack, wait for `Upgradeable=True`
   - run `oc adm upgrade --to=<hop>` and confirm the cluster accepted it
4. **Watch the hop:** `04_Live_monitoring_upgrade.yaml`.

A dry run only prints the plan for each hop.

### 6. Phase 04: `04_Live_monitoring_upgrade.yaml` and `steps/04/poll.yml`
- Every `poll_interval_minutes`, reads ClusterVersion, ClusterOperators, MachineConfigPools and Nodes in one call.
- Sends a heartbeat mail every `heartbeat_minutes`, and one degradation mail per new problem (after its grace period).
- Logs in again if the session token expired.
- **Settled** means the cluster is at the target, Available, not Progressing or Failing, operators are settled, every unpaused pool is updated and every node is done. This must hold for `settle_consecutive_polls` polls in a row.
- **Fails** if:
  - nothing progresses for `hop_timeout_minutes` (exit 30)
  - the hop runs longer than `hop_max_minutes` (exit 30)
  - the API is unreadable for `monitor_api_outage_minutes` (exit 30)
  - the release is not accepted (exit 20)
  - ClusterVersion stays Failing too long (exit 20)

### 7. Phase 05: `05_post_Upgrade_Checks.yaml`
1. `steps/05/run_all_checks.yml` runs 10 checks:
   - ClusterVersion, ClusterOperators (waits for them to settle), pools, nodes and kubelet version, node pressure, etcd (HARD)
   - PVs, platform pods, critical alerts, baseline diff (WARN)
2. **GATE:** a HARD failure stops the run. In a dry run the gate is reported, not enforced.

### 8. Phase 06: `06_Operator_Upgrade.yaml`
1. `steps/06/approve_operators.yml` approves only the current InstallPlan of each subscription that has a pending upgrade, then waits for those operators. A Failed operator gets its Deployments restarted once.
2. `steps/06/validate_operators.yml`:
   - HARD: approved upgrades that did not finish, and operators that regressed
   - WARN: operators that were already unhealthy, and plans left unapproved
3. `steps/06/developer_console.yml` enables the Developer perspective if it is Disabled. A problem here is only a WARN.
4. **GATE:** approved operators must be healthy. The cluster upgrade itself is never rolled back.

### 9. Finish
- `steps/common/write_report.yml` writes `output/<cluster>_<ts>_report.html` (one section per phase that ran).
- `steps/common/send_mail.yml` sends the summary mail with the report and logs attached.

### When something fails
Every failing task, in any phase, jumps to the `rescue:` in `main.yml`, which runs `steps/common/handle_failure.yml`:
1. Works out the error (stderr first, then the task message), the phase and the exit code, and flags permission (RBAC) problems.
2. Writes the `.status` file, which `00_Run.sh` turns into the exit code.
3. Writes the report with a "Why the run stopped" section.
4. Sends one alert mail.

Then `always:` logs out.

## Exit codes
`0` OK · `1` bad option, missing tool or cluster locked · `2` cancelled · `5` login or Phase 01 · `10` Phase 02 · `20` hop failed · `30` hop stopped progressing or timed out · `25` Phase 05 · `35` Phase 06 · `99` other.

## Mails
| Mail | When | To |
|---|---|---|
| heartbeat | every `heartbeat_minutes` while the cluster updates | `mail_to` |
| degradation | once per new problem during an update | `alert_mail_to` + `mail_to` |
| summary | once, at the end of a successful run | `mail_to` |
| alert | once, when a run fails | `alert_mail_to` + `mail_to` |

Templates: summary `email-summary.j2`, alert `error-report.j2`, heartbeat and degradation `progress-mail.j2`.
`--mail-to` replaces `mail_to` for one run. `send_email: false` in `vars/smtp.yml` turns all mails off.

## Every change the automation can make to the cluster
| Phase | Change | Only when |
|---|---|---|
| 02 | `nodes.config/cluster` `cgroupMode: v2` | Check 14 failed, `auto_fix_cgroup_v2` |
| 02 | MachineConfigPool `spec.paused: false` | paused pool on `mcp_auto_unpause_list`, `auto_unpause_mcp` |
| 03 | ClusterVersion `spec.channel` | the hop's channel differs |
| 03 | `openshift-config/admin-acks` key(s) | minor hop, no removed-API callers, `auto_apply_admin_acks` |
| 03 | `oc adm upgrade --to=<hop>` | hop plan is "start" |
| 06 | InstallPlan `spec.approved: true` | current plan of an UpgradePending subscription, not `skip_operator_upgrade` |
| 06 | `oc rollout restart` of a Failed operator's Deployments (once) | `operator_upgrade_auto_recover` |
| 06 | console perspectives (`dev` -> Enabled) | it is Disabled, `enable_developer_perspective` |

A dry run makes none of these changes. A pre-check makes only the Phase 02 ones.

## Where things are
```
playbooks/
  00_Run.sh, main.yml, 01..06       the flow (read in this order)
  steps/common/                     login, logout, log, mail, report, failure handler
  steps/01 .. steps/06/             the steps of each phase (one file per check)
  templates/                        report.j2, email-summary.j2, progress-mail.j2, error-report.j2
  vars/                             all settings (upgrade.yml, smtp.yml, secrets.yml, ...)
  logs/ output/ snapshots/          what each run writes
```
