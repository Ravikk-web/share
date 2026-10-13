# ARO Cluster Upgrade Automation

One command upgrades an Azure Red Hat OpenShift cluster through a sequence of minor versions (for example `4.14.40 -> 4.15.35 -> 4.16.18`). It then checks the result and finishes the operator updates. It runs on Ansible 2.7.17 (test) and 2.14.18 (prod) with `oc`, `jq`, `curl` and `python3`.

**To understand the flow, read [WORKFLOW.md](WORKFLOW.md).** It follows a run step by step in the same order as the files.

## How to run

```bash
cd playbooks
./00_Run.sh                                          # asks for cluster, mode and path
./00_Run.sh --cluster cluster_d01 --dry-run          # read-only rehearsal of every phase
./00_Run.sh --cluster cluster_d01 --pre-check        # prechecks + auto-fixes, no upgrade
./00_Run.sh --cluster cluster_d01                    # the full upgrade
./00_Run.sh --cluster cluster_d01 --post-check       # postchecks of the current version
./00_Run.sh --help
```

If a run stops, fix the cause and run the same command again: hops that are already done are skipped.

## The flow

```
00_Run.sh -> main.yml -> login
                      -> 01 policy check & baseline   (read-only, GATE: valid path)
                      -> 02 16 prechecks + auto-fix   (GATE: no HARD failure)
                      -> 03 hops, each watched by 04  (heartbeat / degradation mails)
                      -> 05 10 postchecks + diff      (GATE: no HARD failure)
                      -> 06 operators + dev console   (GATE: approved operators healthy)
                      -> report + summary mail
           any failure -> one handler: report + status file + one alert mail
           always      -> logout
```

## Files

| Path | What it is |
|---|---|
| `playbooks/00_Run.sh` | Start here: prompts, confirmation, lock, exit code |
| `playbooks/main.yml` | The whole flow on one page |
| `playbooks/01_*.yaml` … `06_*.yaml` | One file per phase, read top to bottom |
| `playbooks/steps/<phase>/` | The steps each phase uses (one file per check) |
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
- `logs/` is emptied at the start of every run, so it only holds the latest run. Logs of a run still active on another cluster are kept.

## Exit codes
`0` OK · `1` bad option, missing tool or cluster locked · `2` cancelled · `5` login or Phase 01 · `10` Phase 02 · `20` hop failed · `30` hop stopped progressing or timed out · `25` Phase 05 · `35` Phase 06 · `99` other.

## Current status
- **Phase:** Simplification (2026-10-13).
  - The flow is now one play with a single failure handler.
  - The 26 roles became `steps/`, there is one report per run, and the CLI is a single short script.
  - Prechecks gained Check 16 (installed operator health).
- **Removed on request:**
  - single-phase, skip-to and stop-after runs
  - the opt-in degraded-operator pod restart and machine-config-daemon force
  - the forced-image upgrade path
  - the decorated CLI menus and `--clean`
  - per-type mail lists and switches
  - the prevalidation mail
- **Verified offline only:**
  - YAML, Jinja and include paths
  - all 68 jq programs compiled, plus a jq 1.5 syntax scan
  - `bash -n` on every shell block
  - 35 behaviour tests on sample cluster data
- **Next:**
  1. On the jump host: `ansible-playbook --syntax-check main.yml` with Ansible 2.7.17 and 2.14.18.
  2. `./00_Run.sh --cluster <dev> --dry-run`.
  3. `--pre-check` on DEV.
  4. A one-hop DEV upgrade.
- Nothing is committed. Changes stay local until you ask.
