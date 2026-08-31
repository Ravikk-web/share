# Architecture Context — ARO Cluster Upgrade Automation

This document defines the system structure, boundaries, storage model, and invariants. Read `project-overview.md` first for the product definition, then this file before making any architectural decision.

## Stack

| Layer | Technology | Role |
|---|---|---|
| Orchestration engine | Ansible (**2.7.17 test / 2.14.18 prod**, single codebase) | Runs `main.yml`, chains isolated phases, drives the per-hop loop. Written to 2.7.17 syntax with inline `# MIGRATION 2.14:` notes. |
| CLI entrypoint | Bash (`00_Run.sh`) | Robust control surface: derives dynamic paths, creates output dirs, captures cluster + `upgrade_path`, confirms, runs `main.yml` with live + logged output, returns sensible exit codes. |
| Cluster interface | `oc` CLI (OpenShift client) | All cluster reads and the upgrade trigger (`oc adm upgrade --to`). Live queries only; no API SDK. |
| Data parsing | `jq` (v1.5) | Parses `oc ... -o json` output for clusterversion, MCP, nodes, operators, etc. |
| Scripting glue | Bash / POSIX shell (via `shell`/`command`) | Inline logic inside tasks; no custom binaries. |
| Notifications | `sendmail` (active) / `community.general.mail` (commented, 2.14) | Sends colour-coded HTML heartbeat + change-alert emails. |
| Reporting | Jinja2 templates (`.j2`) | Renders prevalidation/postvalidation HTML reports and progress emails. |
| Secrets source | Ansible vars file now → **Conjur Vault** later | Supplies cluster credentials as variable references only. |
| Host platform | RHEL 8 jump server | Execution environment where the playbooks and `oc`/`jq`/`sendmail` run. |

## Process Surface (Six Main Files)

Only six files drive the entire process. Everything else is supporting scaffolding these files lean on.

| File | Responsibility | Chain type |
|---|---|---|
| `00_Run.sh` | CLI base — dynamic paths, input capture, confirmation, live+logged run of `main.yml`, exit codes | Bash wrapper |
| `main.yml` | Master orchestrator — chains phases in fixed order | Hybrid (`import_playbook` + loop play) |
| `01_Policy_Check.yaml` | Login once + baseline JSON snapshot + policy/version/edge validation | `import_playbook` |
| `02_Pre_upgrade_check.yaml` | 13-check prevalidation hard gate → HTML report | `import_playbook` |
| `03_Initiate_upgrade.yaml` | Per-hop upgrade loop via `include_tasks: tasks/hop.yml` with `loop:` | `include_tasks` + `loop` |
| `04_Live_monitoring_upgrade.yaml` | 2-min polling, settle-gate, timeout guard, heartbeat + change-alert email | `include_tasks` (per hop) |
| `05_post_Upgrade_Checks.yaml` | 10-check postvalidation + baseline diff vs Phase 01 snapshot → HTML report | `import_playbook` |

## System Boundaries

- `playbooks/` — Root of the automation; holds `00_Run.sh`, `main.yml`, and the phase playbooks `01_Policy_Check` → `05_post_Upgrade_Checks`. Owns orchestration and the master flow only.
- `playbooks/tasks/` — Owns `hop.yml`, the single per-hop upgrade sequence (set channel → edge-check → admin-ack → `oc adm upgrade --to` → monitor → settle-gate), wrapped in `block/rescue`.
- `playbooks/roles/` — Owns all reusable units of work (`login`, `logout`, `co`, `mcp`/`node`/`pdb`/`pv`/`pvc` health, `utilization`, `etcd`, `api_readiness`/`api_check`, `sendmail`, `report`, `error_handle`, `prevalidation`, `upgrade`, `monitor`, `snapshot`). Each role owns exactly one concern.
- `playbooks/vars/` — Owns all inputs: secrets, SMTP details, HTML vars, log paths, API regex, and the `upgrade_path` list. No logic lives here.
- `playbooks/templates/` — Owns presentation only: `health-overview.j2`, `error-report.j2`, `progress-mail.j2`. No cluster logic.
- `playbooks/logs/` — Owns run logs in both `.txt` and `.csv`. Write-only output boundary.
- `playbooks/output/` — Owns client-facing HTML reports (prevalidation + postvalidation). Write-only output boundary.
- `playbooks/snapshots/` — Owns the single baseline JSON snapshot per run (`<cluster>_<timestamp>_baseline.json`). The only persisted cluster state.

## Storage Model

- **Baseline snapshot (JSON file, `snapshots/`)**: The single source of persisted cluster state — nodes, operators, routes, version captured at **Phase 01**. Read once during **Phase 05** for the baseline diff. This is the *only* sanctioned cross-phase persistence.
- **Reports (HTML files, `output/`)**: Client-facing prevalidation and postvalidation output, colour-coded, with summary + collapsible detail + copy button. Write-only artifacts; never read back by the automation.
- **Logs (`.txt` + `.csv` files, `logs/`)**: Full run history in two formats for human review and audit. Write-only artifacts.
- **Live cluster state (in-memory, ephemeral)**: All operational decisions read fresh from `oc` at execution time and held only in play variables/registers. Never persisted between phases (baseline snapshot excepted).
- **Secrets (vars file → Conjur later)**: Credentials sourced as variable references at runtime. Never written to logs, reports, or snapshots.

## Auth and Access Model

- **Authentication**: A single `oc login` in **Phase 01** establishes the session and writes a kubeconfig derived from `playbook_dir`. All subsequent phases reuse that session — no re-login per phase.
- **Credential source**: Cluster username/password come from `vars/` as variable references (`password: "{{ vault_cluster_d01_password }}"`), designed so the later switch to a Conjur Vault lookup is a variable-source swap only, with no code change.
- **Ownership**: The service account defined in secrets (e.g. `svc-aro-upgrade`) is the sole identity performing all reads and the upgrade trigger. One cluster is targeted per run.
- **Session teardown**: Logout is mandatory on any failure and is enforced via `block/rescue/always`, so a failed run never leaves an authenticated session open on the jump server.

## Background Task & Monitoring Model

- **No AI anywhere in execution.** Every decision is a hardcoded rule — `when:` conditions and `fail:` gates. There is no inference, scoring, or agentic behaviour in the path.
- **Monitoring loop (`monitor` role, Phase 04)**: During each hop, the play polls `oc get clusterversion`, `oc get mcp`, and `oc get nodes` every 2 minutes, parsing with `jq`. This runs inline within the hop play (not a detached daemon).
- **Timeout guard**: Each hop carries a bounded poll count (e.g. 90 min). If the MCP stalls past the limit, the hop fails → alert email → logout → stop.
- **Email cadence**: HTML email via `sendmail` every 20 minutes (heartbeat) and immediately on any state change (node NotReady, MCP degraded, hop complete).
- **Settle-gate**: A lightweight between-hops check (cv at target, ClusterOperators Available & not Progressing, MCP Updated=True) acts as hop N+1's entry condition.

## Invariants

- **No AI in the execution path.** All decisions must be deterministic rules (`when:`/`fail:`); nothing may introduce inference or non-deterministic branching.
- **The codebase must run unchanged on both Ansible 2.7.17 and 2.14.18.** Only short module names, always `include_tasks`/`import_tasks` (never bare `include:`), never the `warn:` param on shell/command, and `| default('')` on every optional variable.
- **Login once, logout on any failure.** Every phase that can fail is wrapped in `block/rescue/always` so no run ever leaves an authenticated session open.
- **oc live queries only; no cross-phase state persistence** — with the single exception of the **Phase 01 baseline JSON snapshot**. No phase may read another phase's derived cluster state from disk.
- **Minor versions are never skipped.** Multi-version jumps must execute as ordered sequential hops, and every target must be validated as a real edge in `oc adm upgrade` before it is applied.
- **HARD gates halt the chain.** Any HARD prevalidation, settle-gate, or postvalidation failure must stop execution and log out; WARN items may only surface in the report, never block or auto-remediate.
- **`--to-image ... --force` is never automatic.** It exists only as a manual, hard-gated last-resort path.
- **All paths derive from `playbook_dir`.** Nothing may be hardcoded to a specific machine, and secrets must never be written into logs, reports, or snapshots.
- **Master flow ordering is fixed.** `main.yml` chains phases `01 → 02 → 03/04 (looped) → 05`; phases are not reordered or removed without explicit instruction.
- **GitOps and Argo/scheduling are out of the system.** No phase reads config from Git and no scheduler triggers runs; the operator invokes `00_Run.sh` manually.
