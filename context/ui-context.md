# UI Context - ARO Cluster Upgrade Automation

There is no web UI. "UI" means:
1. **The run report:** `output/<cluster>_<ts>_report.html` from `templates/report.j2`.
2. **Mails:** `mail-summary.j2`, `mail-progress.j2` (heartbeat / degradation) and `mail-alert.j2`, sent by `steps/common/send_mail.yml`.
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
| SKIPPED / INFO | `#344054` / `#f2f4f7` | not evaluated / information |

Page `#f8f9fb`, surface `#ffffff`, border `#e4e7ec`, heading `#101828`. System font stack; monospace for versions, names and errors.

## Run report (`report.j2`)
- Max width 1080px, self-contained (no external resources), and `<details>` expand when printed.
- **Header:**
  - cluster, mode and verdict pill
  - run ID, duration, path, start → final version
  - a dry-run note, and the one-line summary
- **"Why the run stopped":** shown on failure, with the reason, exit code and error text.
- **Phases table:** one row per phase that ran.
- **01 Upgrade path:** one row per edge (status, channel, detail, risk links) and the baseline snapshot name.
- **02 Prechecks:**
  - the 16-row check table
  - the auto-fixes applied, with documentation links
  - the installed operators table: operator, namespace, version, channel, CSV phase, blocks upgrade, result, notes
- **03 Upgrade hops:** hop table and the admin-acks applied.
- **05 Postchecks:** the 10-row check table.
- **06 Operators:** the check table and the subscriptions table.
- **Footer:** run log path, time and host.

## Mails (max width 580px, inline CSS, no JavaScript, every cluster string escaped)
- **Summary (once, successful run):** verdict, summary line, versions, phases, hops, the changes made (auto-fixes, admin-acks, operators, Developer perspective). The report and logs are attached.
- **Heartbeat / degradation (while the cluster updates):** label, target, current version, elapsed time, progress bar, new or open problems, hop timeline, pool table, nodes updating, nodes not Ready or under pressure.
- **Alert (once, failed run):**
  - the phase, exit code and error text
  - an RBAC callout with `oc auth can-i` and the grant command
  - a note that a started update keeps running
  - next step: run the same command again

  The report and log are attached.

## Terminal (`00_Run.sh`)
- Numbered prompts (`select`), a four-line summary (cluster, mode, path, changes), and a confirmation prompt.
- At the end: RESULT, REASON (on failure), REPORT and LOG lines.
