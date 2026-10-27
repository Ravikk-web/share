# ARO Cluster Upgrade Automation

One command upgrades an Azure Red Hat OpenShift cluster through a sequence of minor versions (for example `4.14.40 -> 4.15.35 -> 4.16.18`). It then checks the result and finishes the operator updates. It runs on Ansible 2.7.17 (test) and 2.14.18 (prod) with `oc`, `jq`, `curl` and `python3`.

**To understand the flow, read [WORKFLOW.md](WORKFLOW.md).** It follows a run step by step in the same order as the files.

## How to run

```bash
cd playbooks
./00_Run.sh                                          # asks for cluster, mode and path
./00_Run.sh --cluster cluster_d01 --dry-run          # read-only rehearsal of every phase
./00_Run.sh --cluster cluster_d01 --pre-check        # prechecks + pre-upgrade changes, no upgrade
./00_Run.sh --cluster cluster_d01                    # the full upgrade
./00_Run.sh --cluster cluster_d01 --post-check       # postchecks of the current version
./00_Run.sh --help
```

If a run stops, fix the cause and run the same command again:
- an update that is still running (or whose worker nodes are still updating) is watched to the end first;
- then the prechecks run;
- hops that are already done are skipped.

## The flow

```
00_Run.sh -> main.yml -> login
                      -> 01 policy check & baseline       (read-only, GATE: valid path)
                      -> resume: an update still running is watched to the end by 05
                      -> 02 17 prechecks                  (read-only, GATE: no HARD failure Phase 03 can't fix)
                      -> 03 pre-upgrade implementation    (unpause pools, cgroup v2 checked on every node,
                                                           operator upgrades, admin-ack; each rollout watched by 05;
                                                           re-check, GATE)
                      -> 04 hops, each watched by 05      (heartbeat / degradation mails, node diagnosis)
                      -> 06 10 postchecks + diff          (GATE: no HARD failure)
                      -> 07 operators + dev console       (GATE: approved operators healthy)
                      -> report + summary mail
           any failure -> one handler: node diagnosis + report + status file + one alert mail
           always      -> logout
```

## Files

| Path | What it is |
|---|---|
| `playbooks/00_Run.sh` | Start here: prompts, confirmation, lock, exit code |
| `playbooks/main.yml` | The whole flow on one page |
| `playbooks/01_*.yaml` … `07_*.yaml` | One file per phase, read top to bottom (05 is included by 03, 04 and the resume step after 01) |
| `playbooks/steps/<phase>/` | The steps each phase uses (one file per check or Phase 03 task) |
| `playbooks/steps/common/` | Login, logout, run log, mail, report, failure handler |
| `playbooks/templates/` | `report.j2` (one report per run) and the mail templates `email-summary.j2`, `progress-mail.j2`, `error-report.j2` |
| `playbooks/vars/` | All settings: `upgrade.yml`, `smtp.yml`, `secrets.yml`, `paths.yml`, `report_vars.yml`, `api_regex.yml` |
| `playbooks/logs/`, `output/`, `snapshots/` | What each run writes |
| `context/` | Architecture, standards and progress notes for developers |
| `Documentation.md` | Running record of the project and its decisions |

## Outputs of a run
- `output/<cluster>_<ts>_report.html`: one report with a section per phase.
- `logs/<cluster>_<ts>.txt` and `.csv`: the console log and the events. On failure there is also `.status`, which holds the exit code.
- `snapshots/<cluster>_<ts>_baseline.json`: the Phase 01 baseline.
- `logs/` keeps the last 5 runs of each cluster (`log_keep_runs`), so the log of a failed run is still there after the run that resumes it.

## Exit codes
`0` OK · `1` bad option, missing tool or cluster locked · `2` cancelled · `5` login or Phase 01 · `10` Phase 02 · `15` Phase 03 · `20` hop failed · `30` hop stopped progressing or timed out · `25` Phase 06 · `35` Phase 07 · `99` other.

## Current status
- **Phase:** Live-run fixes (2026-10-26), after the first live run on arod01. That run stopped with the worker pool at "0 of 3" behind one cordoned worker, and the resume then stopped in the prechecks.
  - **Resume:** running the same command again first watches an update that is still running to the end. That includes a hop whose control plane is done while its workers are still updating. Then the prechecks run.
  - **cgroup v2 is checked on every node.** `cgroup_check_method` in `vars/upgrade.yml` chooses how:
    - `config` (default): the MCO configuration the node runs;
    - `kernel`: its kernel (`stat -c %T -f /sys/fs/cgroup` through the node's machine-config-daemon pod, needs `pods/exec`);
    - `both`.

    AUTO-FIXED only when every node is on v2.
  - **Node problems** are reported with the likely cause and what to do, in Check 02, the degradation mails and the alert. The automation never repairs a node.
  - **"Pool cannot continue" alert:** no node updating while unavailable nodes use up `maxUnavailable`.
  - **New checks:** Check 08 now checks drain headroom per pool (HARD), and the new Check 17 checks router headroom (WARN).
  - **Logs:** the last 5 runs per cluster are kept.
  - **Settings:** `log_keep_runs`, `cgroup_check_method`, `cgroup_render_wait_minutes`, `cgroup_node_check_wait_minutes`, `degradation_pool_blocked_minutes`, `node_overcommit_memory_usage_percent`, `node_overcommit_memory_limits_percent`. No new cluster writes.
- **Verified offline only** (no Ansible on the workstation). After an independent review whose findings were all fixed, and including the `cgroup_check_method` switch: static checks 0 problems, unit checks 62/62, flow scenarios 33/33 (147 checks, 0 failed).
  - Static checks: YAML, Jinja, include paths, the jq programs compiled plus a jq 1.5 scan, `bash -n`.
  - Unit checks of each new shell step against a fake cluster.
  - End-to-end flow scenarios: the real `main.yml` run by a small Ansible emulator against a fake `oc` cluster.
- **Next:**
  1. arod01: free the cordoned worker (runbook in `Documentation.md`), let the worker pool finish, then run the same command again.
  2. On the jump host: `ansible-playbook --syntax-check main.yml` with Ansible 2.7.17 and 2.14.18.
  3. Check the new reads on a real cluster: `oc get machines.machine.openshift.io`, `oc adm top nodes` and, before using `cgroup_check_method` `kernel` or `both`, the `oc exec ... stat` kernel check.
  4. `--dry-run`, `--pre-check`, then a one-hop upgrade on DEV.
- The live-run fixes are committed (`de65045`). The `cgroup_check_method` switch is not committed yet. Nothing is pushed.
