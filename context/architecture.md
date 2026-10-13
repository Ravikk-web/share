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
  00_Run.sh                     entry point
  main.yml                      the flow: start -> block (login, phases, report, summary) -> rescue -> always (logout)
  01_Policy_Check.yaml          Phase 01  snapshot, path validation, GATE
  02_Pre_upgrade_check.yaml     Phase 02  16 prechecks, auto-fix, rollout wait, re-check, GATE
  03_Initiate_upgrade.yaml      Phase 03  hop loop (dry run: plan only)
  04_Live_monitoring_upgrade.yaml Phase 04 watch until settled (hop mode / rollout mode)
  05_post_Upgrade_Checks.yaml   Phase 05  10 postchecks, GATE
  06_Operator_Upgrade.yaml      Phase 06  operator approvals, validation, Developer perspective, GATE
  steps/common/                 login, logout, log_event, send_mail, write_report, handle_failure
  steps/01/                     snapshot, validate_path
  steps/02/                     run_all_checks, check_01..check_16, fix_cgroup_v2, fix_unpause_mcp
  steps/03/                     hop, start_hop, admin_ack, api_usage
  steps/04/                     poll_if_needed, poll
  steps/05/                     run_all_checks, check_01..check_10
  steps/06/                     approve_operators, validate_operators, developer_console
  templates/                    report.j2, email-summary.j2, progress-mail.j2, error-report.j2
  vars/                         upgrade.yml, smtp.yml, secrets.yml, paths.yml, report_vars.yml, api_regex.yml
  logs/ output/ snapshots/      run artifacts (git-ignored)
```

Boundaries:
- **Phase files** say *what* happens, in order.
- **`steps/`** files do the work: read the cluster, record a result, make one change.
- **Templates** only render facts.
- **`vars/`** holds every setting.

There are no Ansible roles and no role defaults.

---

## Run modes

| Mode | Phases | Writes |
|---|---|---|
| upgrade | 01 02 03(+04) 05 06 | all listed below |
| dry-run | 01 02 03 05 06 | none (`dry_run: true`; 03 prints the plan, 05 audits without enforcing, 06 reports) |
| pre-check | 01 02 | Phase 02 auto-fixes only |
| post-check | 05 | none |

`main.yml` picks the phases with `mode_phases[run_mode]`. That is the only place a phase is switched on or off.

---

## Failure handling

- Any failed task in any phase goes to the `rescue:` of `main.yml`, which runs `steps/common/handle_failure.yml`. There is one handler, so there is one alert and no need to deduplicate.
- The handler:
  - extracts the error (stderr, then the task's message)
  - works out the exit code: `phase_exit_codes[current_phase]`, or `failure_exit_code` when the monitor set 30 for a timeout
  - flags RBAC problems
  - writes `logs/<cluster>_<ts>.status` (`exit_code=`, `phase=`, `reason=` lines)
  - writes the report and sends one alert
- `always:` logs out and deletes the kubeconfig.
- Exit codes: 5 login / Phase 01, 10 Phase 02, 20 hop failed, 30 hop timeout / no progress, 25 Phase 05, 35 Phase 06, 99 other.

---

## State

- **Run facts** live only for the run: `run_phase_results`, `preval_checks`, `postval_checks`, `installed_operators`, `hop_results`, `admin_acks_applied`, `operator_checks`, `operators`, `path_validation`, and so on.
- **Snapshot:** `snapshots/<cluster>_<ts>_baseline.json` is the only state saved for later. Phase 05 Check 10 reads this run's snapshot, or in post-check mode the newest one for the cluster.
- **Logs:** `logs/<cluster>_<ts>.txt` holds the console plus events, and `.csv` holds the events. Only `steps/common/log_event.yml` writes them, and only by appending. `00_Run.sh` empties `logs/` before every run, after taking the lock; logs of a run still active on another cluster (lock held) are kept.
- **Lock:** `/tmp/aro-upgrade-<cluster>.lock` is a `flock` held by `00_Run.sh`. The kernel releases it when the script exits.
- **Kubeconfig:** `playbooks/.kubeconfig-<cluster>` is written at login and deleted at logout. `~/.kube/config` is never used.

---

## Cluster writes (complete list)

| Phase | Write | Condition |
|---|---|---|
| 02 | `nodes.config/cluster` `spec.cgroupMode: v2` | Check 14 FAIL, `auto_fix_cgroup_v2`, `auto_remediation_enabled`, not dry run |
| 02 | MachineConfigPool `spec.paused: false` | paused pool on `mcp_auto_unpause_list`, `auto_unpause_mcp`, `auto_remediation_enabled`, not dry run |
| 03 | ClusterVersion `spec.channel` | hop channel differs |
| 03 | `openshift-config/admin-acks` key(s) | minor hop, no removed-API callers, `auto_apply_admin_acks` |
| 03 | `oc adm upgrade --to=<hop>` (`--allow-not-recommended` only with `allow_conditional_updates`) | hop plan = start |
| 06 | InstallPlan `spec.approved: true` | `status.installPlanRef` of an UpgradePending subscription, not `skip_operator_upgrade`, not dry run |
| 06 | `oc rollout restart deployment -l olm.owner=<csv>` (once) | approved operator's CSV Failed, `operator_upgrade_auto_recover` |
| 06 | `consoles.operator.openshift.io/cluster` perspectives (`dev` -> Enabled) | Developer perspective Disabled, `enable_developer_perspective`, not dry run |

Phase 03 never runs in a dry run, and `start_hop.yml` refuses to run if `dry_run` is set.

---

## Invariants

1. **Deterministic.** No AI or heuristics: every decision is a `when:`, a `fail:` or a fixed `oc` command.
2. **Two Ansible versions.** The code runs unchanged on Ansible 2.7.17 and 2.14.18.
3. **One flow.** `main.yml` runs the phases in order 01 → 02 → 03(+04) → 05 → 06. Only `mode_phases` can leave a phase out.
4. **One failure handler.** No phase or step has its own rescue, apart from the small local ones that turn a non-critical problem into a WARN (mail, report rendering, Developer perspective).
5. **Whole path validated first.** Every remaining edge is checked before any change. Minor versions are never skipped, and each hop is verified on the cluster again before it starts.
6. **Gates.** HARD stops the run, WARN is reported only, and AUTO-FIXED is given only after a full re-check passes.
7. **Writes.** Only the writes in the table above happen, and none happen in a dry run. Any new write is added to that table, to `WORKFLOW.md` and to the `00_Run.sh` "Changes" line.
8. **Secrets.** No plaintext secrets: vault references, `no_log`, password on stdin.
9. **Lock.** One run per cluster at a time.
10. **Mails.** At most one alert per failed run and one summary per successful run.
