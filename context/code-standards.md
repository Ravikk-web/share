# Code Standards — ARO Cluster Upgrade Automation

These standards are **mandatory** for all playbooks, roles, tasks, templates, and vars in this project. The suite is **production-grade** and must run **unchanged on Ansible 2.7.17 (test) and 2.14.18 (prod)** using only `oc`, `jq`, `sendmail`, and shell. When in doubt, favour **determinism, explicit failure, and readability** over cleverness.

## General

- Keep each role single-purpose. One role owns exactly one concern (e.g. `mcp` health check never queries nodes). If a role grows a second responsibility, split it.
- Fix root causes, never layer workarounds. Do not paper over a failing gate with `ignore_errors` or a retry that masks a real problem.
- **No AI, no inference, no non-determinism** anywhere in the execution path. Every branch is a hardcoded `when:` or `fail:` rule.
- Every task must be idempotent-safe or explicitly read-only. Cluster reads must never mutate state; the only write to the cluster is `oc adm upgrade`.
- Prefer many small, verifiable tasks over one large opaque task. Each task should be understandable and testable in isolation.
- Never hardcode machine-specific paths. Everything derives from `playbook_dir`.
- Keep the project simple: only the six main files (`00_Run.sh`, `01`–`05`) drive the process; all heavy lifting lives in roles/tasks/templates so the main files stay thin and readable.

## Ansible & YAML

- **Write to 2.7.17 syntax.** Use **short module names** (`shell`, `command`, `template`, `copy`, `set_fact`, `fail`, etc.). Add `# MIGRATION 2.14:` inline notes wherever 2.14 behaviour differs.
- **Never use bare `include:`.** Always use `include_tasks:` (dynamic, for loops/conditionals) or `import_tasks:` (static). Choose deliberately and comment why.
- **Never use `import_playbook` inside a loop** — it cannot loop on 2.7.17. Per-hop iteration must use a play with `include_tasks:` + `loop:`.
- **Add `| default('')`** (or a sensible typed default) to every optional variable. 2.14 Jinja2 is stricter and undefined vars must not break the run.
- Every YAML file starts with a header comment stating it targets 2.7.17 and listing any 2.14 migration notes.
- Name every task with a clear, action-oriented `name:`. Unnamed tasks are not allowed.
- Use `changed_when:` and `failed_when:` explicitly on shell/command tasks — never rely on Ansible's default exit-code interpretation for gate logic.
- Use `block/rescue/always` for any phase that can fail; the `always` block must guarantee logout.
- Keep booleans, gates, and thresholds in `vars/` — never buried as literals inside tasks.

## Shell & Command Modules

- **Never use the `warn:` parameter** on shell/command — it was removed in 2.14 and breaks the dual-version contract.
- Prefer `command` over `shell` unless you need pipes, redirection, or heredocs (e.g. `sendmail`, `oc ... | jq ...`). Comment why `shell` was chosen.
- Always set `changed_when: false` on read-only `oc`/`jq` queries so reporting stays honest.
- Capture output with `register:` and validate `rc` / `stdout` explicitly before acting on it.
- Pipe `oc` JSON output through `jq` (v1.5-compatible syntax only) for parsing — do not parse JSON with fragile string/regex hacks.
- Quote all variable interpolations inside shell blocks to survive empty or spaced values.
- Minimise terminal noise: surface only meaningful status lines; suppress verbose success chatter.

## Jinja2 & Templates

- Templates (`.j2`) are **presentation-only**. No cluster queries or decision logic in a template.
- Guard every optional value with `| default('')` (or `| default('N/A')` for display) so a missing field never renders `Undefined`.
- All colour-coding (green/amber/red) is driven by **status variables passed in**, not computed in the template.
- HTML reports must include: a summary section, colour-coded status, collapsible detail, and a copy button — consistent across `health-overview.j2`, `error-report.j2`, and `progress-mail.j2`.
- Keep template logic flat and readable; move any non-trivial computation into a `set_fact` before rendering.

## Gates & Error Handling

- **HARD gates use `fail:`** with a clear, specific message naming the check, the cluster, and the observed value. A HARD failure halts the chain and triggers logout.
- **WARN items never block.** They are recorded and surfaced in the report only — never auto-remediated.
- **Prevalidation (13 checks) runs once** as a hard gate before any hop (**Phase 02**). **Postvalidation (10 checks) runs once** after the final hop (**Phase 05**). The **settle-gate** runs between hops (**Phase 04**).
- Timeout guards are mandatory on monitoring loops (e.g. 90 min/hop). A stall must fail → alert → logout, never hang indefinitely.
- Do not use `ignore_errors: true` to bypass a gate. If a step is genuinely non-fatal, model it explicitly as a WARN with `failed_when: false` and a recorded status.
- Every failure path must emit an alert email and log the reason before logout.
- **Error Extraction & RBAC Awareness**: In rescue blocks, always extract `stderr` and `stderr_lines` before falling back to generic `msg` (`"non-zero return code"`). Automatically detect RBAC / permission errors (`forbidden`, `cannot patch`, `unauthorized`) and surface actionable remediation in alerts.
- **Sendmail Template Lifecycle**: `roles/sendmail` must always freshly render `mail_template` per invocation and reset per-dispatch facts (`mail_html_body`, `mail_final_body`) to prevent template caching across hops.

## Secrets & Security

- Passwords and tokens are **always variable references** (`{{ vault_cluster_d01_password }}`) — never inline literals. This keeps the later Conjur Vault swap a source-only change.
- Secrets must never be written to logs, reports, snapshots, or email bodies. Use `no_log: true` on any task that could echo a credential.
- The kubeconfig is written under `playbook_dir` and must be removed or invalidated on logout.
- One service account per run performs all actions; never embed personal credentials.

## Data, Logging & Storage

- **Live cluster state is ephemeral** — read fresh from `oc` at execution time and held only in registers/facts. Never persist derived state between phases.
- **The Phase 01 baseline JSON snapshot is the single sanctioned cross-phase persistence** — written to `snapshots/<cluster>_<timestamp>_baseline.json`, read only by **Phase 05** for the diff.
- Logs are written to `logs/` in **both `.txt` and `.csv`** for every run.
- HTML reports are written to `output/` only; they are write-only artifacts never read back by the automation.
- Use `to_json` / `from_json` for snapshot handling; **retest snapshot parsing on 2.14 (Python 3)** as part of migration.

## File Organization

- `playbooks/` — `00_Run.sh`, `main.yml`, and the five phase playbooks (`01_Policy_Check`, `02_Pre_upgrade_check`, `03_Initiate_upgrade`, `04_Live_monitoring_upgrade`, `05_post_Upgrade_Checks`). Orchestration only.
- `playbooks/tasks/` — `hop.yml`, the single per-hop upgrade sequence wrapped in `block/rescue`.
- `playbooks/roles/` — one concern per role; each role has `tasks/main.yml` and sensible `defaults/main.yml`.
- `playbooks/vars/` — secrets, SMTP, HTML vars, log paths, API regex, and `upgrade_path`. Inputs only, no logic.
- `playbooks/templates/` — `health-overview.j2`, `error-report.j2`, `progress-mail.j2`. Presentation only.
- `playbooks/logs/` — run logs (`.txt` + `.csv`). Write-only.
- `playbooks/output/` — prevalidation/postvalidation HTML reports. Write-only.
- `playbooks/snapshots/` — baseline JSON snapshot. The only persisted cluster state.

## `00_Run.sh` (CLI Entrypoint) Standards

- Derive all paths from the script's own location (`playbook_dir` base); create `logs/`, `output/`, `snapshots/` if missing. Nothing machine-specific hardcoded.
- Accept the target cluster and ordered `upgrade_path` via args or prompt, then print a confirmation summary before executing anything.
- Run `main.yml` with live output tee'd to `logs/` in `.txt`; return **sensible exit codes** (0 = success, non-zero = specific failure class).
- Keep terminal noise minimal and colour-coded; never echo secrets. `set -euo pipefail` for safe failure.

## Pre-Merge Checklist

- Runs cleanly on **both** Ansible 2.7.17 and 2.14.18 with no source edits.
- No bare `include:`, no `warn:` param, all optionals carry `| default('')`.
- Every task is named; every shell/command sets `changed_when:`/`failed_when:` explicitly.
- All secrets are variable references with `no_log: true`; nothing sensitive appears in logs/reports/snapshots.
- Every failure path logs out via `block/rescue/always`.
- HARD gates use `fail:`; WARN items only report.
- All paths derive from `playbook_dir`; nothing machine-specific is hardcoded.
- `ansible-playbook --syntax-check` passes on the affected playbooks.
