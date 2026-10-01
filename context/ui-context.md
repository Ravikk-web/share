# UI Context — ARO Cluster Upgrade Automation

This project has **no web UI**. "UI" in this architecture refers to:
1. **Client-Facing HTML Reports** (`output/`) rendered from Jinja2 templates (`phase01-policy-check.j2`, `phase02-prevalidation.j2`, `health-overview.j2`).
2. **Emails** dispatched through `tasks/notify.yml` → `roles/sendmail` (native `mail` module) using `email-summary.j2`, `progress-mail.j2` and `error-report.j2`.
3. **CLI Terminal Interface** (`00_Run.sh` + `scripts/cli_helpers.sh`) using ANSI box-drawing and formatted terminal tiles.

**Golden Rule:** All colour and status coding is driven by **variables passed into the template** (or shell functions) — never computed inside the template. Templates only *render* status; roles and playbooks evaluate state via `set_fact`.

---

## Theme & Layout Philosophy

Light, clean, modern, and print-friendly. Designed for enterprise platform engineering:
- **Email Compatibility**: Single `<style>` blocks in `<head>` and inline CSS for email templates (`progress-mail.j2`, `error-report.j2`). External stylesheets and complex CSS variables do not survive enterprise mail clients (Outlook, Thunderbird).
- **Responsive Width**: Email templates must be constrained to a max-width container (`≤ 580px`) with zero horizontal overflow on mobile mail clients. Standalone HTML reports use a flexible container (`max-width: 1080px`).
- **No JavaScript in Emails**: Copy-to-clipboard buttons and interactive scripts are strictly confined to standalone HTML reports in `output/`.
- **Print / PDF Hand-Off**: Reports in `output/` must include `@media print` rules expanding `<details>` elements so printed or PDF-exported reports contain complete diagnostic details without truncation.

---

## Color Tokens & Status Conventions

Status colors are strictly defined. Every color is paired with an alphanumeric label and a symbolic icon glyph to ensure accessibility and grayscale/print legibility. Row and pill precedence: `AUTO-FIXED` → `FIX-FAILED` → `FAIL` → `WARN` → `SKIPPED` → `PASS` (`FIX-FAILED` is checked before `FAIL` because its label contains "FAIL"). A value that was not measured is displayed as `n/a` — never a placeholder number.

| Token / Status | Hex Color (Text / BG) | Icon | Meaning |
|---|---|---|---|
| `PASS` | `#1a7f37` on `#e6f4ea` | `✔` | Healthy / check passed / hop complete / settle-gate passed |
| `WARN` | `#9a6700` on `#fff8e1` | `!` | Non-blocking advisory / node draining / pending CSRs |
| `FAIL` | `#b42318` on `#fdecea` | `✖` | Hard blocker / degraded operator / timeout exceeded / NotReady |
| `AUTO-FIXED` | `#1d4ed8` on `#eff6ff` | `⚙` | **Auto-Remediated**: Check failed initially, automated fix applied, re-check passed |
| `FIX-FAILED` | `#c2410c` on `#ffedd5` | `⚠` | Remediation attempted but re-verification failed; escalated to FAIL |
| `SKIPPED` | `#667085` on `#f2f4f7` | `–` | Not evaluated (the phase stopped at an earlier check) |
| `INFO` / Neutral | `#344054` on `#f2f4f7` | `ℹ` | Informational item / N/A / not applicable |
| `--surface` | `#ffffff` | — | Card and container background |
| `--page-bg` | `#f8f9fb` | — | Outer report page background |
| `--border` | `#e4e7ec` | — | Card, table, and divider borders |
| `--heading` | `#101828` | — | High-contrast heading text |

---

## Typography

- **System Font Stack**: `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`. Never import remote Google Fonts or external web fonts in emails or reports.
- **Sizes**: Base body `14px`, line-height `1.5`; report title `20–22px` bold; section headings `16px` semibold; table cells `13px`.
- **Monospace Stack**: `"SFMono-Regular", Consolas, "Liberation Mono", Menlo, Courier, monospace` for node names, version strings, API paths, and error traces.
- **Contrast**: Maintain WCAG AA compliance across all status combinations.

---

## Report Components (`health-overview.j2`)

All client-facing HTML reports (Prevalidation, Postvalidation, Operator Validation) follow a uniform, structured anatomy:

1. **Header Band**: Report title, cluster name, execution timestamp, target upgrade path, and overall run verdict badge (`PASS ✔`, `WARN !`, `FAIL ✖`, or `AUTO-FIXED ⚙`).
2. **Summary Metric Tiles**: At-a-glance metric boxes showing counts for total checks, passed, warnings, auto-fixed, and failed items.
3. **Structured Status Table**: Columns for `#`, `Check Name`, `Observed State / Output`, `Gate Type (HARD/WARN/AUTO)`, and `Verdict Pill`. Rows are subtly tinted by the evaluated status.
4. **Auto-Remediation Callout (Conditional)**: Appears whenever `AUTO-FIXED` items exist, summarizing the automated actions taken (e.g. cgroup v2 patch, admin-ack applied) and referencing the official Red Hat guidance.
5. **Collapsible Details (`<details>`)**: Deep inspection sections containing raw `oc`/`jq` JSON outputs, node capacity tables, and PVC allocations (collapsed by default for readability).
6. **Copy-to-Clipboard Action**: Clean inline JavaScript button copying run IDs, cluster API URLs, and failed resource names. (Excluded from emails).
7. **Footer**: Generation timestamp, execution host, jump server user, and explicit links to run logs in `logs/`.

### Operator Validation Report Specifics
When rendering Phase 06 results, `health-overview.j2` displays:
- Six summary checks: approved operator upgrades (HARD), health regressions (HARD), operators already unhealthy before Phase 06 (WARN), pending upgrades not approved (WARN), operator compatibility with the reached version (WARN), web console Developer perspective (WARN / AUTO-FIXED).
- One row per Subscription: name, namespace, what happened (`Upgraded a.v1 -> a.v2`, `was Succeeded before Phase 06 and is now Failed`, …), installed CSV, channel, approval mode, CSV phase pill.
- The auto-fix callout lists the Developer perspective change and any one-time operator restart.

### Postvalidation Report Specifics
- The header shows the upgrade path and the version the cluster reached (`run_final_version`).
- Check 09 (critical alerts) reads "Alerts could not be queried … not checked" (WARN) when the alerts API is unreachable — never PASS.

### Phase 01 Policy Check Report Specifics (`phase01-policy-check.j2`)
Phase 01 uses a dedicated template because its content differs structurally from health-check tables:
- **Planned Upgrade Journey**: Visual hop-by-hop bar showing current version → target versions.
- **Step-by-Step Execution Table**: session and identity, baseline snapshot, current version / update state, path format, then **one row per hop**: `Hop to X` (already reached) or `Edge A -> B (stable-4.N)` with PASS / WARN / FAIL, the source (cluster offer or update graph) and any conditional-update risks.
- **Baseline Snapshot Grid**: Four metric cards showing Nodes, Cluster Operators, Routes counts, and snapshot artifact status.
- **Update Edge Validation Detail**: Visual display of available edges (with target highlighted) and conditional edges, showing current → target version on channel.
- **Session & Safety Lifecycle**: Three cards documenting authentication status, server identity verification, and `block/rescue/always` fail-safe teardown pattern.
- **Artifacts Produced Table**: Lists all Phase 01 output files (baseline JSON snapshot, `.txt` log, `.csv` log, scoped kubeconfig).

### Phase 02 Prevalidation Report Specifics (`phase02-prevalidation.j2`)
Phase 02 uses a dedicated, highly structured template implementing the full 15-check prevalidation contract:
- **Header Band**: Phase 02 badge (`Phase 02 of 06`), cluster name, full upgrade path, run timestamp, and overall verdict pill (`PASS ✔`, `WARN !`, `FAIL ✖`, `AUTO-FIXED ⚙`).
- **6 Summary Metric Tiles**: At-a-glance counters for Total Contract Checks (15), Passed, Auto-Fixed, Warnings, Failed, and Skipped.
- **Planned Upgrade Journey**: Hop-by-hop progression bar matching the sequential upgrade path.
- **Auto-Remediation Summary**: Conditional callouts for the fixes applied in Phase 02 (cgroup v2, unpaused MCPs, operator restarts) with direct Red Hat documentation links. Admin-acks are applied per hop in Phase 03 and appear in the closing summary.
- **Master 15-Check Contract Checklist Table**: Complete 15-row contract (#01 to #15) with Check Name, Role/Inline implementation, Gate Type (HARD/WARN), Observed Output, and Status Badge. Guaranteed to show all 15 rows without truncation even on early abort (unreached rows marked `SKIPPED ⏸`).
- **15 Check Detail Cards** (one `card()` macro): every stat comes from the facts the check roles set in this run (`n/a` if not measured) and the footer shows that check's own status and observed text. Cards:
  1. *ClusterOperators*: Total, available, degraded, and progressing counts with unhealthy operator breakdown table.
  2. *Nodes*: Ready/total counts, unschedulable tally, and disk/memory/PID pressure indicators.
  3. *MachineConfigPools*: Updated, updating, degraded, and paused pool counts with machine totals.
  4. *API Context*: Active server URL and pattern match against `desired_cluster_api_regex`.
  5. *API Readiness*: `/readyz` probe status and response validation.
  6. *etcd Quorum*: Control plane pod counts, HA quorum verification, and CO health.
  7. *Admin-ack and removed APIs*: admin-ack keys pending, removed-API callers in the last 24 h, ClusterVersion `Upgradeable`.
  8. *Capacity Headroom*: CPU and memory request % (`utilization_*_percent`) against `max_cpu_percent` / `max_memory_percent`.
  9. *Pending CSRs*: Pending node/client certificate signing requests.
  10. *PersistentVolumes*: Bound, available, released, and failed volume counts.
  11. *PersistentVolumeClaims*: Bound, pending, and lost claim counts.
  12. *PodDisruptionBudgets*: Zero-disruption budget scan with system namespace exclusions (`openshift-*`, `kube-*`).
  13. *Critical Pods*: Platform pod readiness across core namespaces.
  14. *CGroup Mode*: Cluster cgroup mode detection (v1 vs v2) and target version compatibility.
  15. *OLM Operator Compatibility*: Subscription scan, channel compatibility, and manual InstallPlan detection.
- **OLM Subscription Compatibility Table**: Dedicated breakdown of installed operators, channels, and CSV states.
- **Session Lifecycle Cards**: Active kubeconfig isolation, authentication method, and zero-mutation pre-flight safety.
- **Collapsible Diagnostics (`<details>`)**: Deep inspection logs for unhealthy operators, degraded pools, and PDB violations, with `@media print` expansion.
- **Fail-Safe Generation**: Built on both normal exit and in `rescue:` on failure, attaching `output/<cluster>_prevalidation_<ts>.html` to `error-report.j2` alerts.

---

## Email Templates

Every mail is composed by `tasks/notify.yml`: subject `[ARO Upgrade][<cluster>][<TAG>] <headline> (run <ts>)` (ASCII only), recipients by mail type (alerts and degradation always include `alert_mail_to`), only attachments that exist. Container max width `580px`, inline CSS, no JavaScript, every cluster-provided string escaped.

### 1. Heartbeat & Degradation (`progress-mail.j2`)
- `HEARTBEAT` every `heartbeat_minutes` (20) during a hop or a Phase 02 node rollout; `DEGRADED` once per condition after its grace period (it also counts as the heartbeat).
- Header: `UPGRADE IN PROGRESS ℹ` or `DEGRADATION DETECTED ⚠`, hop label, target, current version, elapsed time, progress bar.
- New-problem callout (degradation) or open-issues callout (heartbeat), ClusterVersion status message, hop timeline from `upgrade_path` + `hop_results`, MachineConfigPool table (`updated / total`), nodes updating now, nodes NotReady or under pressure.
- There are no hop-started, hop-completed or per-node mails.

### 2. Failure Alert (`error-report.j2`) — `ALERT`
- Exactly one per failed run (`failure_alert_sent`), sent by the innermost handler.
- `UPGRADE HALTED ✖` badge, RBAC callout with the `oc auth can-i …` check and the grant command, a truthful session note (plus "the upgrade keeps running on the cluster" for Phase 03/04 failures), failure details, error output (truncated, escaped), exact attachments, next steps (`--resume`).

### 3. Summary (`email-summary.j2`)
Used for three kinds of mail, all compact cards with a verdict, run facts, phase results, hops, check counts and the non-PASS rows (max 20):
- `PREVALIDATION` — full runs only, before the first hop ("Prevalidation Passed - Upgrade Starting"); attachments: Phase 01 and prevalidation reports, run logs.
- Standalone phase mails — `PHASE-01`, `PREVALIDATION`, `PHASE-03`, `POSTVALIDATION`, `PHASE-06`.
- The closing summary — `COMPLETE`, `DRY-RUN`, `PRE-CHECK`, `PARTIAL-RUN` — exactly one per successful orchestrated run, with a "Changes" list (remediations, admin-acks applied per hop, operator upgrades, Developer perspective), every report and log of the run attached, and the notification ledger.

---

## CLI Terminal Formatting (`scripts/cli_helpers.sh`)

Terminal interactions via `00_Run.sh` must maintain an equally polished, professional presentation:
- **Box-Drawing Characters**: Use clean UTF-8 box characters (`╭`, `╮`, `│`, `├`, `┤`, `╰`, `╯`, `─`).
- **Standard Width**: Menus and confirmation summaries use a fixed 72-column box.
- **Color Coding**: Cyan for structure/prompts, Green for success/active defaults, Amber for warnings/intermediate hops, Red for errors/production warnings, Magenta for banners.
- **Visual Journey Diagrams**: Format upgrade sequences clearly:
  ```
  Current version: 4.14.12
  Upgrade Journey: 4.14.12 ──▶ 4.14.40 ──▶ 4.15.35 ──▶ 4.16.18
  ```
- **Post-Run Summary**: A structured terminal box detailing phase-by-phase execution times, check counts, and output artifact paths.
