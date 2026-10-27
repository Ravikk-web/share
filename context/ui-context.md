# UI Context - ARO Cluster Upgrade Automation

There is no web UI. "UI" means:
1. **The run report:** `output/<cluster>_<ts>_report.html` from `templates/report.j2`.
2. **Mails:** `email-summary.j2` (summary), `progress-mail.j2` (heartbeat / degradation) and `error-report.j2` (alert), sent by `steps/common/send_mail.yml`.
3. **The terminal:** `00_Run.sh` (plain text prompts) and Ansible's console output.

Templates only render facts; statuses and colours are never decided inside a template.

## Colours and statuses (`vars/report_vars.yml`)
| Status | Text / background | Meaning |
|---|---|---|
| PASS | `#1a7f37` / `#e6f4ea` | check passed, hop complete |
| WARN | `#9a6700` / `#fff8e1` | reported, does not stop the run |
| FAIL | `#b42318` / `#fdecea` | HARD stop |
| AUTO-FIXED | `#1d4ed8` / `#eff6ff` | fixed automatically and passed the re-check |
| FIX-FAILED | `#c2410c` / `#ffedd5` | fix tried, re-check still fails (stops the run) |
| SKIPPED / INFO | `#344054` / `#f2f4f7` | not evaluated / information (a Phase 03 change whose switch is off) |

Page `#f8f9fb`, surface `#ffffff`, border `#e4e7ec`, heading `#101828`. System font stack; monospace for versions, names and errors.

## Run report (`report.j2`)
- Max width 1080px, self-contained (no external resources), and `<details>` expand when printed.
- **Header:**
  - cluster, mode and verdict pill
  - run ID, duration, path, start → final version
  - a dry-run note, and the one-line summary
- **"Why the run stopped":** shown on failure, with the reason, exit code and error text.
- **Node problems:** shown when the node diagnosis found something, or could not run. It has:
  - a note saying when and in which phase it was read, and that the automation only reports;
  - an amber line "The node diagnosis could not run: <reason>" when the nodes could not be read;
  - one row per node: the node, its role and pool, the problem with its details (Machine/VM state, load, PodDisruptionBudgets allowing 0 disruptions, a pool that cannot continue), the likely cause, and what to do;
  - the pods that cannot be scheduled, with the scheduler's message.
- **Phases table:** one row per phase that ran. A resumed run adds an "Upgrade hops - update already running" row right after 01; a dry run shows it as WARN "plan only".
- **01 Upgrade path:** one row per edge (status, channel, detail, risk links) and the baseline snapshot name.
- **02 Prechecks:**
  - the 17-row check table (titled "run again after the Phase 03 changes" when Phase 03 re-checked; a check Phase 03 fixed shows AUTO-FIXED)
  - the installed operators table: operator, namespace, version, channel, CSV phase, blocks upgrade, result, notes
  - "cgroup v2 on every node" (`<details>`, open when a node is not on v2), whenever the nodes were checked. One row per node: node, role, MCO configuration (v1/v2 and its name, "update not finished"), kernel (`cgroup2fs` / `tmpfs` / error), result pill, problem. A column `cgroup_check_method` leaves out reads "not checked"; the summary line names the method.
- **03 Pre-upgrade implementation:** one row per task (#, task, result pill, what was found and done, including the rollout watch), the changes made with documentation links, and the admin-acks applied in Phase 03. "(plan only)" in a dry run.
- **04 Upgrade hops:** hop table and the admin-acks applied right before a hop.
- **06 Postchecks:** the 10-row check table.
- **07 Operators:** the check table and the subscriptions table.
- **Footer:** run log path, time and host.

## Mails (max width 580px, inline CSS, no JavaScript, every cluster string escaped)
- **Summary (once, successful run):** verdict, summary line, versions, phases, hops, the changes made (Phase 03 changes, admin-acks, operators, Developer perspective). The report and logs are attached.
- **Heartbeat / degradation (while the cluster updates, or a Phase 03 node rollout runs):** label, target, current version, elapsed time, progress bar, new or open problems, hop timeline, pool table, nodes updating, nodes not Ready or under pressure. A degradation mail about a node or a pool that cannot continue adds an amber box, "What is wrong with the nodes, and what to do": per node the problem, details, likely cause and what to do, plus pods that cannot be scheduled. It ends with a note that the automation only reports and keeps watching.
- **Alert (once, failed run):**
  - the phase, exit code (a row of the Failure Details table) and error text
  - "Node problems" (amber box) when the node diagnosis found something: per node the problem, details, likely cause and what to do; pods that cannot be scheduled; or a line saying the diagnosis could not run
  - an RBAC callout with `oc auth can-i` and the grant command
  - a note that a started update or node rollout keeps running (Phase 03 and 04 failures)
  - next step: run the same command again (a running update is watched to the end first, then the prechecks; finished hops are skipped)

  The report and log are attached.

## Terminal (`00_Run.sh`)
- Numbered prompts (`select`), a four-line summary (cluster, mode, path, changes), and a confirmation prompt.
- At the end: RESULT, REASON (on failure), REPORT and LOG lines.
