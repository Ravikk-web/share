# AI Workflow Rules — ARO Cluster Upgrade Automation

These are **mandatory rules, not optional guidelines**. Follow them precisely when developing, refactoring, or rebuilding this project. This is an enterprise-grade, rule-based ARO upgrade automation suite designed for mission-critical clusters running unchanged on **both Ansible 2.7.17 and 2.14.18**. Determinism, explicit error handling, and spec fidelity take precedence over speed.

---

## Approach & Rebuild Workflow

- **Spec-Driven Implementation**: The files in `context/` and `context/feature-spec/` define the single source of truth for requirements, architecture, standards, and build order.
- **Sequential Unit Order**: Implement units in strictly numbered order (Feature Specs `01` through `14`, referencing cross-cutting specs `15`–`17`). Never jump ahead or build speculative scaffolding out of order.
- **Anti-Pattern Compliance**: Before writing or modifying any role or task, review the Jinja2 and shell anti-pattern catalog in `context/code-standards.md`. Never introduce self-referencing variables, unquoted shell interpolations, or bare `include:`.
- **Zero AI in Runtime**: The running automation contains no probabilistic models, heuristics, or AI agents. Every decision is a deterministic rule (`when:` conditions, `fail:` gates, deterministic `oc patch` actions).

---

## Scoping Rules

- **One Unit at a Time**: Work on exactly one feature spec / role / phase at a time. Finish, test, and document it before proceeding.
- **Separate Orchestration from Scaffolding**: Do not modify orchestration playbooks (`main.yml`, `00_Run.sh`) and individual task roles in the same commit or step unless specifically requested by an integration spec.
- **Keep System Boundaries Intact**: Cluster queries belong in roles; orchestration belongs in phase playbooks; presentation belongs in templates; inputs belong in `vars/`. Never blur these boundaries.
- **No Speculative Extensions**: Build strictly what is defined in the current feature spec. If an edge case or potential enhancement is discovered, document it in `progress-tracker.md` as an open question rather than writing unapproved code.

---

## Auto-Remediation & Resilience Rules

- **Toggleable by Default**: Every auto-remediation action must be gated behind its specific boolean toggle in `vars/upgrade.yml` and the master switch `auto_remediation_enabled`.
- **Tier 1 vs Tier 2 Defaults**:
  - Enabled by default: cgroup v2 migration and allow-listed MCP unpause (Phase 02), admin-ack per minor hop after the removed-API check (Phase 03), one operator Deployment restart for a Failed approved CSV (Phase 06).
  - Disabled by default (explicit opt-in per cluster): degraded operator pod restart (Phase 02), machine-config daemon force on a daemon-Degraded node (Phase 04).
  - Any new cluster write must be added to `architecture.md` → Cluster Writes and to the CLI change scope.
- **Idempotency & Re-Verification**: Auto-remediation tasks detect → remediate → verify their own change and record only what they applied. Phase 02 then waits for any node rollout and re-runs the full scan; the check status (`AUTO-FIXED` / `FIX-FAILED`) comes from that re-scan, never from the remediation task.
- **Transient Command Retries**: One-shot `oc` queries use `retries: 3 / delay: 10 / until: rc == 0`. Monitoring polls tolerate API outages in the poll logic instead, and waits whose outcome is data are bounded in-shell loops (`until` marks the task failed when retries run out).

---

## Protected Files & Conventions

Do not modify the following patterns or structures without explicit user authorization:

1. **`vars/secrets.yml`**: Credentials must remain variable references (`{{ vault_cluster_d01_password }}`) with `no_log: true`. Never hardcode plaintext passwords.
2. **Seven-File Process Surface**: The process surface consists strictly of `00_Run.sh` and the six phase playbooks `01_Policy_Check.yaml` through `06_Operator_Upgrade.yaml`. Supporting logic resides in `roles/`, `tasks/`, and `scripts/`.
3. **Dual-Version Directives**: Every YAML file must retain its `# Targets: Ansible 2.7.17 / 2.14.18` and `# MIGRATION 2.14:` header comments.
4. **Baseline Snapshot Contract**: Persisted state is strictly restricted to `snapshots/<cluster>_<timestamp>_baseline.json`. No other cross-phase state files may be introduced.
5. **Phase Ordering**: `main.yml` executes `01 → 02 → 03/04 (looped) → 05 → 06`. Phases cannot be reordered or removed.
6. **Shell Executable Declaration**: Shell tasks utilizing `set -o pipefail` must declare `args: executable: /bin/bash`.

---

## Keeping Documentation in Sync

Whenever code or architecture changes, update the corresponding documentation in the **exact same step**:

- System boundaries, process surface, role catalog, or invariants → `context/architecture.md`
- Code rules, error extraction hierarchy, anti-patterns, or thresholds → `context/code-standards.md`
- Scope, CLI features, user flow, or success criteria → `context/project-overview.md`
- HTML styling, email formatting, status tokens, or pills → `context/ui-context.md`
- Execution progress, phase status, or open questions → `context/progress-tracker.md` **and** `README.md`
- Cumulative build history and architectural rationale → `Documentation.md`

Code and documentation must never drift. If they disagree, the documentation must be brought into alignment immediately.

---

## Pre-Unit Completion Checklist

Before declaring any implementation unit or feature spec complete, verify:

- [ ] Unit executes cleanly and idempotently within its defined scope.
- [ ] Runs unmodified on both **Ansible 2.7.17 and 2.14.18** (`--syntax-check` passes).
- [ ] No bare `include:` statements; dynamic loops use `include_tasks:`, static includes use `import_tasks:`.
- [ ] All optional Jinja2 variables carry typed defaults (`| default('')`, `| bool`, `| int`).
- [ ] No self-referencing variables in `vars:` blocks; facts pre-computed via `set_fact`.
- [ ] All `jq` expressions verified for **jq v1.5** compatibility (e.g. `def rnd2: ...`, parenthesized `or`/`and`).
- [ ] Condition comparisons against OpenShift booleans use `| string | trim`.
- [ ] Rescue blocks extract `stderr` before `msg`, detect RBAC errors, and never reference `ansible_failed_task.name`.
- [ ] Mails go through `tasks/notify.yml` only (one alert per failed run, one summary per successful run); run logs only through `tasks/log_event.yml`.
- [ ] No `ansible_date_time` in timers, no regex backreferences, no attribute access on possibly undefined facts (Ansible 2.7).
- [ ] Offline checks run: YAML / Jinja / jq compile and the relevant simulations (`feature-spec/17-verification-and-testing.md`).
- [ ] HARD gates halt execution and guarantee session logout via `block/rescue/always`.
- [ ] All auto-remediations verify state post-patch and log `AUTO-FIXED` or `FIX-FAILED`.
- [ ] `progress-tracker.md` and `README.md` updated to reflect the completed unit.
