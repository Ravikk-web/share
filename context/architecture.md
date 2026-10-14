# Architecture - ARO Cluster Upgrade Automation

How the code is laid out, what it stores, and the rules every change must keep. For a step-by-step walkthrough of one run, see `WORKFLOW.md`.

---

## Stack

| Layer | Technology | Role |
|---|---|---|
| Entry point | Bash (`00_Run.sh`) | Prompts, confirmation (PROD: type `UPGRADE`), flock run lock, tee'd log, exit code from the status file |
| Orchestration | Ansible 2.7.17 / 2.14.18, one codebase | `main.yml`: one play, one `block / rescue / always` |
| Cluster access | `oc` | Every read and write; `KUBECONFIG` set once on the play |
| Parsing | `jq` 1.5 | Every `oc ... -o json` result |
| Update graph | OpenShift Update Service via `curl` | Phase 01 path validation (TLS verification skipped by configuration) |
| Mail | Ansible `mail` module (community.general on 2.14) | `steps/common/send_mail.yml` only |
| Report | Jinja2 | `templates/report.j2`, one HTML report per run |
| Secrets | `vars/secrets.yml` vault references | Password passed to `oc login` on stdin, `no_log: true` |

---

## Layout

```
playbooks/
  00_Run.sh                          entry point
  main.yml                           the flow: start -> block (login, phases, report, summary) -> rescue -> always (logout)
  01_Policy_Check.yaml               Phase 01  snapshot, path validation, GATE
  02_Pre_upgrade_check.yaml          Phase 02  16 prechecks (read-only), GATE
  03_Pre_upgrade_Implementation.yaml Phase 03  pre-upgrade changes, each followed by a rollout watch; re-check, GATE
  04_Initiate_upgrade.yaml           Phase 04  hop loop (dry run: plan only)
  05_Live_monitoring_upgrade.yaml    Phase 05  watch until settled (hop mode / rollout mode); included by 03 and 04
  06_post_Upgrade_Checks.yaml        Phase 06  10 postchecks, GATE
  07_Operator_Upgrade.yaml           Phase 07  operator approvals, validation, Developer perspective, GATE
  steps/common/                      login, logout, log_event, send_mail, write_report, handle_failure
  steps/01/                          snapshot, validate_path
  steps/02/                          run_all_checks, check_01..check_16, read_operators
  steps/03/                          task_1..task_4, watch_rollout, record_task, admin_ack, api_usage
  steps/04/                          hop, start_hop
  steps/05/                          poll_if_needed, poll
  steps/06/                          run_all_checks, check_01..check_10
  steps/07/                          approve_operators, validate_operators, developer_console
  templates/                         report.j2, email-summary.j2, progress-mail.j2, error-report.j2
  vars/                              upgrade.yml, smtp.yml, secrets.yml, paths.yml, report_vars.yml, api_regex.yml
  logs/ output/ snapshots/           run artifacts (git-ignored)
```

Boundaries:
- **Phase files** say *what* happens, in order.
- **`steps/`** files do the work: read the cluster, record a result, make one change.
- **Templates** only render facts.
- **`vars/`** holds every setting.

Shared steps live in the folder of the phase that owns the change, and other phases include them from there:
- `steps/03/admin_ack.yml` (with `api_usage.yml`): Precheck 07 evaluates with it, Phase 03 applies, and `steps/04/start_hop.yml` applies again before each later minor hop.
- `steps/02/read_operators.yml`: Precheck 15 and Phase 03 task 3 read the installed operators with it.
- `steps/07/approve_operators.yml`: Phase 03 task 3 (before the first hop) and Phase 07 (after the cluster upgrade) approve operator upgrades with it.

There are no Ansible roles and no role defaults.

---

## Run modes

| Mode | Phases | Writes |
|---|---|---|
| upgrade | 01 02 03(+05) 04(+05) 06 07 | all listed below |
| dry-run | 01 02 03 04 06 07 | none (`dry_run: true`; 03 and 04 print the plan, 06 audits without enforcing, 07 reports) |
| pre-check | 01 02 03(+05) | Phase 03 changes only |
| post-check | 06 | none |

`main.yml` picks the phases with `mode_phases[run_mode]`. That is the only place a phase is switched on or off. Phase 05 is never listed: Phase 03 and Phase 04 include it.

While testing, a phase include in `main.yml` can be commented out. Each phase reads what it needs from the cluster itself, and facts that a later phase may read (for example `run_start_version`, `path_validation`) are used with defaults.

---

## Phase 02 -> Phase 03 hand-off

Phase 02 never changes the cluster. A precheck whose problem Phase 03 will fix is recorded as **WARN** ("Phase 03 will ...") instead of FAIL, so the Phase 02 gate only stops on problems nothing in the run fixes. This happens only when Phase 03 is part of the run (`preval_defer_fixes`) and the fix is switched on:

| Check | Deferred to Phase 03 when |
|---|---|
| 03 MachineConfigPools | every failing pool is paused and on `mcp_auto_unpause_list`, none is Degraded |
| 14 cgroup mode | cgroup v1 on a path that reaches 4.19+, `auto_fix_cgroup_v2`, not `skip_cgroup_check` |
| 15 Operator upgrade blockers | every blocking operator has an upgrade pending (`UpgradePending`), operator approvals switched on |

Check 07 already passes when the only thing missing is the admin-ack (Phase 03 applies it).

When Phase 03 changed anything, it re-runs all 16 prechecks with deferral off. A check it worked on becomes AUTO-FIXED if it now passes and FIX-FAILED if not, and the same HARD gate applies.

---

## Phase 03 tasks

Each task is one file, `steps/03/task_<n>_<name>.yml`, and works the same way:

1. **Check** the cluster.
2. **Change** it only if needed, behind its switches and `not dry_run`.
3. **Watch** any MachineConfigPool rollout it started (`steps/03/watch_rollout.yml` -> Phase 05 in rollout mode, with the heartbeat and degradation mails). A change that always rolls out (cgroup v2) is watched at once. For any other change, the step looks for `rollout_detect_seconds` and watches only if a pool starts updating.
4. **Verify** the change.
5. **Record** one row in `preimpl_tasks` (`steps/03/record_task.yml`). A row that is FAIL or FIX-FAILED stops the run there.

| # | Task | Change | Re-checked by |
|---|---|---|---|
| 1 | MachineConfigPools | unpause paused pools on `mcp_auto_unpause_list` | Check 03 |
| 2 | cgroup v2 | `cgroupMode: v2` when a hop reaches 4.19+ (all nodes reboot) | Check 14 |
| 3 | Operator upgrades | approve the current InstallPlan of every `UpgradePending` subscription; stop if an operator still blocks the target | Check 15 |
| 4 | Admin-ack | removed-API check, then the keys the next minor hop needs | Check 07 |

The order matters: a paused pool would not take the cgroup change, and the admin-ack step waits for `Upgradeable=True`, which a blocking operator keeps False.

No Phase 03 change is made while a cluster update is running, for example when a re-run resumes a hop. All tasks are then recorded as SKIPPED.

---

## Failure handling

- Any failed task in any phase goes to the `rescue:` of `main.yml`, which runs `steps/common/handle_failure.yml`. There is one handler, so there is one alert and no need to deduplicate.
- The handler:
  - extracts the error (stderr, then the task's message)
  - works out the exit code: `phase_exit_codes[current_phase]`, or `failure_exit_code` when the monitor set 30 for a hop timeout
  - flags RBAC problems
  - adds a FAIL row for a Phase 03 task that stopped part-way (for example during its rollout watch)
  - writes `logs/<cluster>_<ts>.status` (`exit_code=`, `phase=`, `reason=` lines)
  - writes the report and sends one alert
- `always:` logs out and deletes the kubeconfig.
- Exit codes: 5 login / Phase 01, 10 Phase 02, 15 Phase 03, 20 hop failed (Phase 04), 30 hop timeout / no progress (Phase 05 watching a hop), 25 Phase 06, 35 Phase 07, 99 other. A Phase 05 rollout watch that fails keeps Phase 03's code (15).

---

## State

- **Run facts** live only for the run: `run_phase_results`, `preval_checks`, `preval_deferred`, `preimpl_tasks`, `postval_checks`, `installed_operators`, `hop_results`, `admin_acks_applied`, `preval_autofix_items`, `operator_checks`, `operators`, `path_validation`, and so on.
- **Snapshot:** `snapshots/<cluster>_<ts>_baseline.json` is the only state saved for later. Phase 06 Check 10 reads this run's snapshot, or in post-check mode the newest one for the cluster.
- **Logs:** `logs/<cluster>_<ts>.txt` holds the console plus events, and `.csv` holds the events. Only `steps/common/log_event.yml` writes them, and only by appending. `00_Run.sh` empties `logs/` before every run, after taking the lock; logs of a run still active on another cluster (lock held) are kept.
- **Lock:** `/tmp/aro-upgrade-<cluster>.lock` is a `flock` held by `00_Run.sh`. The kernel releases it when the script exits.
- **Kubeconfig:** `playbooks/.kubeconfig-<cluster>` is written at login and deleted at logout. `~/.kube/config` is never used.

---

## Cluster writes (complete list)

| Phase | Write | Condition |
|---|---|---|
| 03 | MachineConfigPool `spec.paused: false` | paused pool on `mcp_auto_unpause_list`, `auto_unpause_mcp`, `auto_remediation_enabled`, not dry run |
| 03 | `nodes.config/cluster` `spec.cgroupMode: v2` | a hop reaches 4.19+, cluster on v1, `auto_fix_cgroup_v2`, `auto_remediation_enabled`, not `skip_cgroup_check`, not dry run |
| 03 | InstallPlan `spec.approved: true` | `status.installPlanRef` of an UpgradePending subscription, `preupgrade_operator_upgrades`, not `skip_operator_upgrade`, not dry run |
| 03 | `oc rollout restart deployment -l olm.owner=<csv>` (once) | an operator approved in Phase 03 has a Failed CSV, `operator_upgrade_auto_recover` |
| 03 | `openshift-config/admin-acks` key(s) | a minor hop in the path, a key pending for the current minor, no removed-API callers, `auto_apply_admin_acks`, not dry run |
| 04 | ClusterVersion `spec.channel` | hop channel differs |
| 04 | `openshift-config/admin-acks` key(s) | minor hop, a key still pending (normally a later hop's, which only appears on that minor), no removed-API callers, `auto_apply_admin_acks` |
| 04 | `oc adm upgrade --to=<hop>` (`--allow-not-recommended` only with `allow_conditional_updates`) | hop plan = start |
| 07 | InstallPlan `spec.approved: true` | `status.installPlanRef` of an UpgradePending subscription, not `skip_operator_upgrade`, not dry run |
| 07 | `oc rollout restart deployment -l olm.owner=<csv>` (once) | approved operator's CSV Failed, `operator_upgrade_auto_recover` |
| 07 | `consoles.operator.openshift.io/cluster` perspectives (`dev` -> Enabled) | Developer perspective Disabled, `enable_developer_perspective`, not dry run |

Phase 04 never runs in a dry run, and `start_hop.yml` refuses to run if `dry_run` is set. In a dry run Phase 03 evaluates only, and `admin_ack.yml` refuses apply mode.

---

## Invariants

1. **Deterministic.** No AI or heuristics: every decision is a `when:`, a `fail:` or a fixed `oc` command.
2. **Two Ansible versions.** The code runs unchanged on Ansible 2.7.17 and 2.14.18.
3. **One flow.** `main.yml` runs the phases in order 01 → 02 → 03(+05) → 04(+05) → 06 → 07. Only `mode_phases` can leave a phase out.
4. **One failure handler.** No phase or step has its own rescue, apart from the small local ones that turn a non-critical problem into a WARN (mail, report rendering, Developer perspective).
5. **Whole path validated first.** Every remaining edge is checked before any change. Minor versions are never skipped, and each hop is verified on the cluster again before it starts.
6. **Checks before changes.** Phase 02 only reads. Every pre-upgrade change happens in Phase 03, after the Phase 02 gate. Each change is verified, and any node rollout it starts is watched to the end before the next task.
7. **Gates.** HARD stops the run, WARN is reported only, and AUTO-FIXED is given only after a full re-check passes.
8. **Writes.** Only the writes in the table above happen, and none happen in a dry run. Any new write is added to that table, to `WORKFLOW.md` and to the `00_Run.sh` "Changes" line.
9. **Secrets.** No plaintext secrets: vault references, `no_log`, password on stdin.
10. **Lock.** One run per cluster at a time.
11. **Mails.** At most one alert per failed run and one summary per successful run.
