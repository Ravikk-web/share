# ARO Cluster Upgrade Automation — Project Overview

## Overview

This project is a **rule-based, deterministic Ansible automation suite** that performs **Y-stream (minor) upgrades** of Azure Red Hat OpenShift (ARO / OpenShift) clusters as **ordered, sequential version hops** (e.g. `4.18.09 → 4.19.15 → 4.20.08`), never skipping a minor version. It is built for cloud/platform engineers who upgrade production ARO clusters and need a repeatable, auditable, **no-AI-in-the-execution-path** workflow. The suite logs in once, runs a hard-gated 13-check prevalidation, drives each hop natively via `oc adm upgrade --to`, monitors ClusterVersion / MachineConfigPool / node state live, emails colour-coded HTML progress reports, and finishes with a 10-check postvalidation plus a baseline diff — all while running **unchanged on both Ansible 2.7.17 (test) and 2.14.18 (prod)** using only `oc`, `jq`, `sendmail`, and shell.

## Goals

1. Automate multi-version Y-stream ARO upgrades as ordered sequential hops that never skip a minor version.
2. Keep every decision **rule-based and deterministic** — no AI, no inference; all gates are hardcoded `when:` / `fail:` conditions.
3. Run the identical codebase on **Ansible 2.7.17 and 2.14.18** with no source changes, using short module names and inline `# MIGRATION 2.14:` notes.
4. Enforce a **13-check hard-gated prevalidation** before any upgrade and a **10-check postvalidation** after all hops complete.
5. Provide **live monitoring** (2-minute polling) with a 20-minute HTML heartbeat email plus immediate state-change alerts, all colour-coded green/amber/red.
6. Guarantee safe lifecycle handling: **login once, logout immediately on any failure** via `block/rescue/always`.
7. Keep secrets as **variable references only**, so migrating from a vars file to Conjur Vault is a source swap, not a code rewrite.
8. Produce client-presentable HTML reports and dual `.txt` + `.csv` logs for every run.
9. Keep the project structure simple: only **six main files (`00_Run.sh` + `01`–`05` playbooks)** drive the process; everything else is supporting scaffolding.

## Core User Flow

1. **Define the upgrade path.** The user supplies an ordered `upgrade_path` version list (each entry a real target version) in `vars/`.
2. **Run the CLI entrypoint.** The user executes `00_Run.sh`, which sets all dynamic paths from its own location, creates `logs/ output/ snapshots/` if missing, prompts for / accepts the cluster and `upgrade_path`, shows a confirmation summary, then invokes `main.yml` with live + logged output.
3. **Policy check & baseline (Phase 01 — `01_Policy_Check.yaml`).** A single `oc login` establishes the session and writes a kubeconfig under `playbook_dir`; a **baseline JSON snapshot** is written to `snapshots/<cluster>_<timestamp>_baseline.json`; each version in `upgrade_path` is confirmed as a real edge in `oc adm upgrade`.
4. **Prevalidation hard gate (Phase 02 — `02_Pre_upgrade_check.yaml`).** All 13 checks run once. Any HARD failure stops the chain and logs out; WARN items surface in the report only. A colour-coded HTML prevalidation report is written to `output/`.
5. **Execute hops (Phase 03 — `03_Initiate_upgrade.yaml`).** For each target version, `tasks/hop.yml` runs a `loop:` via `include_tasks:` (because `import_playbook` cannot loop on 2.7.17): set channel → verify edge → apply admin-ack if needed → `oc adm upgrade --to=<version>` → monitor → settle-gate.
6. **Monitor each hop (Phase 04 — `04_Live_monitoring_upgrade.yaml`).** `clusterversion`, `mcp`, and `nodes` are polled every 2 minutes and parsed with `jq`; an HTML heartbeat email is sent every 20 minutes plus immediate change alerts; a per-hop timeout guard (e.g. 90 min) fails, alerts, and logs out if the MCP stalls.
7. **Settle-gate between hops.** A lightweight check (cv at target, ClusterOperators Available & not Progressing, MCP Updated=True) becomes the entry condition for the next hop.
8. **Postvalidation (Phase 05 — `05_post_Upgrade_Checks.yaml`).** After the final hop, 10 checks run once and a baseline diff is produced against the Phase 01 snapshot. A colour-coded HTML postvalidation report is written to `output/`.
9. **Deliver & log out.** Reports land in `output/`, dual `.txt`/`.csv` logs in `logs/`, and the run logs out cleanly.

## Features

### Orchestration
- Single master playbook (`main.yml`) chaining fully isolated child playbooks.
- **Hybrid chaining:** `import_playbook` for once-only phases; a `loop:` play using `include_tasks: tasks/hop.yml` for per-hop upgrades (required because `import_playbook` cannot loop on 2.7.17).
- CLI entrypoint (`00_Run.sh`) provides a robust base interface: dynamic paths, input capture, confirmation summary, live + logged execution, sensible exit codes.
- Login once at start; logout immediately on any failure via `block/rescue/always`.

### Upgrade Execution
- Y-stream only, executed as ordered sequential hops that never skip a minor version.
- Manual `upgrade_path` input, with each version validated as a real edge before use.
- Native trigger: `oc adm upgrade --to=<version>` per hop (set channel → verify edge → admin-ack → apply → monitor → settle).
- `--to-image=<digest> --allow-not-recommended --force` available only as a **hard-gated, manual last resort** — never automatic.

### Validation
- **13-check prevalidation hard gate** (Phase 02), run once before any upgrade — HARD: ClusterOperators, nodes, MCP, etcd, admin-acks, valid edge, node capacity < 90% requests-based; WARN: pending CSRs, disk pressure, PDBs, drain headroom, critical-namespace pods, firing critical alerts.
- Lightweight **settle-gate** between hops.
- **10-check postvalidation** (Phase 05), run once after all hops, including a baseline diff vs the Phase 01 snapshot.

### Monitoring & Notifications
- Live polling of `clusterversion`, `mcp`, and `nodes` every 2 minutes, parsed with `jq`.
- HTML email via `sendmail` every 20 minutes (heartbeat) and immediately on any state change (node NotReady, MCP degraded, hop complete).
- Email content shows **MCP always, the current working node (draining/rebooting now), and degraded nodes only** — colour-coded green/amber/red with cluster, hop x/y, % complete, and elapsed time.
- Per-hop timeout guard that fails, alerts, and logs out on MCP stall.

### Reporting & Logging
- Colour-coded, client-facing HTML reports (prevalidation + postvalidation) with summary, collapsible detail, and copy button, written to `output/`.
- Dual `.txt` and `.csv` run logs in `logs/`.
- Baseline JSON snapshot in `snapshots/<cluster>_<timestamp>_baseline.json` — the only sanctioned cross-phase persistence.

### Compatibility & Portability
- Runs unchanged on Ansible 2.7.17 and 2.14.18 (short module names, `include_tasks`/`import_tasks`, no `warn:`, `| default('')` on optionals).
- All paths dynamic, derived from `playbook_dir`.
- No Python dependencies — only `oc`, `jq`, `sendmail`, and shell.
- Dual email implementation: active `sendmail` shell block plus a commented `community.general.mail` block for 2.14.

## In Scope

- Y-stream (minor) ARO/OpenShift upgrades executed as ordered sequential hops.
- Manual upgrade-path input with edge validation against `oc adm upgrade`.
- 13-check prevalidation, per-hop settle-gate, and 10-check postvalidation.
- Live monitoring with 2-minute polling, 20-minute HTML heartbeat, and change-triggered alerts.
- Colour-coded client-facing HTML reports, dual `.txt`/`.csv` logs, and a baseline JSON snapshot.
- Login-once / logout-on-failure lifecycle handling.
- Dual Ansible 2.7.17 / 2.14.18 compatibility with inline migration notes.
- Secrets as variable references, ready for a later Conjur Vault swap.
- Six-file process surface (`00_Run.sh` + `01`–`05` playbooks) plus supporting `vars/`, `roles/`, `tasks/`, `templates/`, `logs/`, `output/`, `snapshots/`.

## Out of Scope

- Any AI or non-deterministic decision-making in the execution path.
- **GitOps configuration and Argo/scheduling** — removed entirely from this project.
- Backup/restore of the cluster (backups are performed manually; etcd is only checked, never blocked, in prevalidation).
- Z-stream (patch) or X-stream (major) upgrade handling.
- Automatic use of `--to-image ... --force` (manual, hard-gated last resort only).
- Custom Python modules or any Python-based tooling.
- A graphical UI — the suite is CLI/Ansible driven (the only "UI" is HTML report/email output).
- Persisting cluster state between phases beyond the single baseline snapshot.
- Automated provisioning of new nodes or infrastructure changes.

## Success Criteria

- Running `00_Run.sh` → `main.yml` with a valid `upgrade_path` upgrades a cluster through every hop to the final target with no manual intervention beyond the initial input.
- Every version in `upgrade_path` is confirmed as a real edge before it is applied; an invalid edge stops the run at Phase 01/02.
- Any HARD prevalidation failure halts the chain and logs out cleanly, with no upgrade triggered.
- Each hop reaches the settle-gate (cv at target, ClusterOperators Available & not Progressing, MCP Updated=True) before the next hop begins.
- A stalled MCP beyond the per-hop timeout fails the run, sends an alert email, and logs out.
- Postvalidation confirms the final target version, healthy ClusterOperators/MCP/nodes with correct new kubelet versions, healthy etcd, and produces a baseline diff.
- The identical codebase runs successfully on both Ansible 2.7.17 and 2.14.18 without source edits.
- Every run produces colour-coded prevalidation and postvalidation HTML reports in `output/`, dual `.txt`/`.csv` logs in `logs/`, and a baseline snapshot in `snapshots/`.
- HTML heartbeat emails arrive every 20 minutes during a hop, with immediate alerts on any state change.
