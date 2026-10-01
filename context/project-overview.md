# ARO Cluster Upgrade Automation — Project Overview

## Overview

This project is a **rule-based, deterministic, one-touch Ansible automation suite** that performs **Y-stream (minor) upgrades** of Azure Red Hat OpenShift (ARO / OpenShift) clusters across **ordered, sequential version hops** (e.g. `4.18.09 → 4.19.15 → 4.20.08`), followed by **automated OLM operator upgrades, validation and closeout**.

It runs from an isolated RHEL jump server with an automation account (NPID) that has cluster-admin. A single CLI command performs pre-flight checks, captures the cluster baseline, validates the **whole upgrade path** against the OpenShift update graph, runs a 15-check prevalidation with an **auto-remediation engine** (cgroup v1→v2 migration, paused MachineConfigPools, optional operator restart) that re-checks every fix, provides the **OpenShift administrator acknowledgement before every minor hop** (after verifying that no workload still calls an API the next release removes), executes the hops with live monitoring, verifies post-upgrade health with a baseline diff, approves pending operator upgrades, **enables the web console Developer perspective** when it is disabled, and delivers HTML reports and a small, predictable set of emails.

The codebase executes **unchanged on Ansible 2.7.17 (test) and 2.14.18 (production)** using native modules, `oc`, `jq` 1.5, `curl`, Python and shell. **No AI or non-deterministic heuristic exists in the execution path.**

---

## Goals

1. **True One-Touch Automation**: one CLI invocation drives the cluster and operator upgrade end to end.
2. **Automated Blocker Remediation, Verified**: safe, documented fixes (cgroup v2 for OpenShift 4.19+, paused MCPs, optional degraded-operator restart) are applied, their node rollout is waited for, and the full check list is re-run; a check is AUTO-FIXED only if it then passes.
3. **Hop Acknowledgements Handled**: before each minor hop the admin-ack the cluster asks for is applied automatically, but only after APIRequestCount shows no remaining callers of the removed APIs; otherwise the hop stops with the callers listed.
4. **Sequential Minor-Version Compliance**: minor versions are never skipped; every edge of the path is validated up front (update graph per hop channel + cluster offer) and again on the cluster right before the hop.
5. **Deterministic & Auditable**: every gate, threshold and fix is a fixed rule; every cluster write is listed in `architecture.md`.
6. **Dual-Version Compatibility**: one codebase for Ansible 2.7.17 and 2.14.18.
7. **Multi-Phase Gates**: 15-check prevalidation (Phase 02), per-hop settle gate (Phase 04), 10-check postvalidation with baseline diff (Phase 05), operator validation (Phase 06).
8. **Quiet, Useful Notifications**: a 20-minute heartbeat and one alert per degradation during hops, exactly one alert when a run fails, one prevalidation mail before a full upgrade, and exactly one closing summary per run — no duplicate mails.
9. **Fail-Safe Lifecycle**: identity-checked login, session reuse across phases, logout on every path via `block/rescue/always`.
10. **Vault-Ready Secrets**: variable references with `no_log: true`; the password is passed on stdin.

---

## Core User Flow

1. **Launch (`00_Run.sh`)**
   - Pre-flight dependency checks; Vault-tolerant validation of `vars/*.yml`; static path validation (X.Y.Z, ascending, same major, no skipped minor).
   - Menus for cluster, path and run mode (Full Upgrade, Dry Run, Pre-check, isolated phase, partial run); visual hop journey; change-scope box listing every change the selected phases can make.
   - PROD runs that can change the cluster require typing `UPGRADE` (never bypassed by `--yes`).
   - Per-cluster run lock (flock); the exit code comes from the run status file.

2. **Phase 01 — Policy Check & Baseline**
   - Logs in (password on stdin, no retry on bad credentials) and verifies the API URL, optional cluster ID pin and server regex.
   - Captures the baseline snapshot used by Phase 05.
   - Validates the whole path: hops already reached are skipped (safe `--resume`), an update already running to the next hop is monitored, every remaining edge is checked against the OpenShift Update Service graph of that hop's channel (`stable-<major.minor>`), the first edge also against the cluster's own offer. Conditional edges with risks that apply are refused unless `allow_conditional_updates`. If the graph cannot be reached the check becomes a WARN and each hop is verified on the cluster before it starts.

3. **Phase 02 — Prevalidation & Auto-Remediation**
   - Runs 15 checks (Check 07 = admin-ack and removed-API usage for every minor hop of the path, Check 14 = cgroup v2 for the highest hop, Check 15 = operator `olm.maxOpenShiftVersion` and OLM `Upgradeable`).
   - Applies the enabled remediations for failed checks it can act on, waits for any node rollout they start (with heartbeats and degradation alerts), re-runs all 15 checks, and marks remediated checks AUTO-FIXED or FIX-FAILED.
   - Writes the prevalidation report; any HARD FAIL / FIX-FAILED stops the run (one alert, exit 10). In a full run, sends the prevalidation mail before the first hop.

4. **Phase 03 — Upgrade Hops**
   - For each hop: plan from the live cluster (skip / resume / trigger) → wait for a stable cluster → set the hop channel → wait until the cluster offers the target → minor hop: removed-API check, admin-ack, wait for `Upgradeable=True` → `oc adm upgrade --to=<hop>` → confirm the cluster accepted it → Phase 04.
   - A dry run prints this plan for every hop and changes nothing.

5. **Phase 04 — Live Monitoring & Settle Gate**
   - Polls ClusterVersion, ClusterOperators, MachineConfigPools and Nodes every 2 minutes in one call, with the real clock.
   - Heartbeat mail every 20 minutes; one degradation alert per condition after its grace period (node NotReady, pressure, stalled node update, degraded operator / pool, ClusterVersion Failing).
   - Tolerates API outages up to 10 minutes and logs in again on an expired token; fails the hop on no progress for 90 minutes, 8 hours in total, release not accepted, or ClusterVersion Failing for 30 minutes.
   - Settled = ClusterVersion completed at the target, Available, not Progressing / Failing; no degraded, progressing or unavailable operator; every unpaused pool updated; no node updating or NotReady — for 2 polls in a row.

6. **Phase 05 — Postvalidation & Baseline Diff**
   - 10 checks (final version, operators after a settle wait, pools, node readiness and kubelet version, pressure, etcd, PVs, core pods, critical alerts — "not checked" if the alerts API cannot be read, baseline diff).
   - Writes the report, then enforces the HARD gate on live runs (exit 25).

7. **Phase 06 — Operators, Developer Perspective & Closeout**
   - Reports operator compatibility with the reached version.
   - Approves only the current InstallPlan of each subscription with a pending upgrade and waits for those CSVs; one operator restart if a CSV fails.
   - Gates on the approved operators and on regressions (exit 35); pre-existing problems and unapproved plans are warnings.
   - Enables the web console **Developer perspective** if it is Disabled (default from OpenShift 4.19), preserving the other perspective settings; dry runs and post-checks only report it.
   - Writes the operators report.

8. **Close-out**
   - One closing summary mail with every report and the run logs attached, then logout. The CLI prints the post-run summary and the exit code.

---

## Features

### CLI & Operator Experience (`00_Run.sh` + `scripts/cli_helpers.sh`)
- Pre-flight dependency validation and Vault-tolerant config validation.
- Interactive cluster, path and run-mode menus; `--phase NN` isolated phases (01, 02, 03, 05, 06; 04 is part of 03); `--skip-to-phase` / `--stop-after-phase`; `--pre-check`; `--dry-run`; `--resume` (hops already reached are skipped automatically).
- Change-scope display derived from the selected phases; PROD `UPGRADE` confirmation.
- Per-cluster flock run lock; `--clean` refuses while a run is active.
- Structured post-run summary and exit codes: 0 OK, 1 lock conflict, 2 aborted / invalid input, 5 / 10 / 20 / 25 / 30 / 35 by phase, 99 other.

### Auto-Remediation Engine
- **CGroup v1 → v2** (Phase 02): when any hop reaches 4.19+; all nodes reboot; the rollout is monitored before the re-check.
- **MCP unpause** (Phase 02): only pools on `mcp_auto_unpause_list`.
- **Degraded operator restart** (Phase 02, opt-in): the operator's own ReplicaSet pods in its namespace.
- **Admin-ack** (Phase 03, per minor hop): after the removed-API usage check.
- **Machine-config daemon force** (Phase 04, opt-in): nodes whose daemon is Degraded for 30 minutes.
- **Operator restart** (Phase 06): once per approved operator whose CSV is Failed.
- Every fix is behind `auto_remediation_enabled` (Phase 02) and its own toggle, and is logged as AUTO-FIX / FIX-FAILED.

### Reporting, Notifications & Audit
- Mails: prevalidation (full runs), heartbeat (20 min), degradation (once per condition), failure alert (once per run, RBAC guidance, exact attachments), closing summary (once per run, notification ledger, every report attached). Routing per mail type; `--mail-to` never removes the on-call list from alerts.
- Reports: Phase 01 (one row per path edge), Phase 02 (15-check table and data-driven cards), Phase 05, Phase 06 (operators and Developer perspective).
- Logs: append-only `.txt` / `.csv` events plus the tee'd console log; `.status` on failure.

---

## In Scope

- One-touch sequential Y-stream upgrades of ARO / OpenShift clusters.
- Whole-path validation against the OpenShift Update Service (internet access from the jump server; TLS verification skipped by configuration).
- Automatic admin-acks per minor hop, gated by removed-API usage.
- Phase 02 auto-remediation with rollout wait and full re-check.
- Live monitoring with heartbeat and degradation alerts, outage tolerance and progress-based timeouts.
- Postvalidation with baseline diff.
- OLM operator upgrades (current InstallPlan per subscription) and validation.
- Enabling the web console Developer perspective after the upgrade.
- Ansible 2.7.17 and 2.14.18.

---

## Out of Scope

- Any AI, machine-learning, or non-deterministic decision logic in the execution path.
- Provisioning of cloud infrastructure.
- Skipping minor versions or major-version jumps.
- Automatic `--to-image … --force` (a guarded manual override only).
- Accepting conditional-update risks automatically (requires `allow_conditional_updates: true`).
- GitOps / ArgoCD synchronisation; git operations.
- etcd backup / restore (etcd health is validated; backups are out of band).

---

## Success Criteria

1. **One-Touch Completion**: `./00_Run.sh` runs pre-flight → path validation → prevalidation → hops → postvalidation → operators → summary without manual steps.
2. **Verified Auto-Remediation**: a remediated check is AUTO-FIXED only after the full re-scan passes; node rollouts finish before the first hop.
3. **Hop Acknowledgement**: every minor hop that needs an admin-ack gets it automatically, and never while removed APIs are still in use.
4. **Path Enforcement**: no hop starts unless the cluster offers it in the hop's channel; an invalid path stops the run in Phase 01 with zero cluster changes.
5. **Hard Gate Integrity**: residual HARD failures stop the run with one alert and a clean logout.
6. **No Duplicate Mails**: one alert per failed run, one summary per successful run, no per-node or hop-complete mails.
7. **Zero Token Orphanage**: every run ends with logout and kubeconfig removal.
8. **Dual Runtime Execution**: identical code on Ansible 2.7.17 and 2.14.18.
9. **Complete Artifacts**: reports in `output/`, `.txt` / `.csv` logs in `logs/`, baseline snapshot in `snapshots/`.
10. **Developer Perspective**: enabled after a live upgrade when it was disabled; reported otherwise.
