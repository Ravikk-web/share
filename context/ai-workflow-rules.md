# AI Workflow Rules — ARO Cluster Upgrade Automation

These are **rules, not guidelines**. Follow them exactly when building this project. This is a production-grade, rule-based ARO upgrade automation suite that must run **unchanged on Ansible 2.7.17 and 2.14.18**. Determinism, explicit failure, and spec fidelity outrank speed and cleverness.

## Approach

- Build this project incrementally using a **spec-driven workflow**. The context files define what to build, how to build it, and the current state of progress.
- Implement only against the specs in `project-overview.md`, `architecture.md`, `code-standards.md`, and this file. Do not infer, invent, or "improve" behaviour that is not written down.
- Read all context files in the order defined in `AGENTS.md` before implementing or making any architectural decision.
- Treat every locked design decision as fixed: **no AI in the execution path**, **login once / logout on failure**, **hybrid `import_playbook` + `include_tasks` loop**, **oc live queries only**, **manual validated `upgrade_path`**, **HARD/WARN gate model**, **flat 00–05 numbering**, **GitOps + Argo removed**.
- Never introduce a dependency outside `oc`, `jq`, `sendmail`, and shell. Do not add Python modules or external collections to the execution path.

## Scoping Rules

- Work on **exactly one feature unit at a time**. A unit is one role, one phase playbook, or one template — never several at once.
- Prefer small, verifiable increments over large speculative changes. Ship a working `mcp` health check role before starting the `node` health check role.
- Do not combine unrelated system boundaries in a single step. Do not edit a role and a phase playbook and a template in the same increment.
- Do not write speculative code for features not yet scoped. Build only the current unit defined in `progress-tracker.md`.
- Do not refactor unrelated code while implementing a unit. Note the refactor as an open question instead.

## When to Split Work

Split an implementation step if it combines any of the following:

- **Cluster logic and presentation** — for example, a role's `oc`/`jq` query work and its Jinja2 report template.
- **Multiple unrelated roles or phases** — for example, prevalidation checks and monitor polling logic.
- **Orchestration and a unit** — for example, editing `main.yml`/`hop.yml` flow and building a role in the same step.
- **Behaviour not clearly defined** in the context files — stop and resolve the spec first.

If a change cannot be verified end to end quickly, the scope is too broad. Split it.

## Handling Missing or Ambiguous Requirements

- Do not invent product behaviour, thresholds, gate rules, or check logic not defined in the context files.
- If a requirement is ambiguous, resolve it in the relevant context file **before writing any code**. Update `project-overview.md`, `architecture.md`, or `code-standards.md` first.
- If a requirement is missing, add it as an **open question in `progress-tracker.md`** before continuing. Do not guess.
- Never silently choose a threshold, timeout, or gate severity. Every such value must trace back to a context file (e.g. capacity < 90% requests-based, 2-min poll, 90-min timeout, 20-min heartbeat).
- If two context files conflict, stop and flag it as an open question. Do not pick one arbitrarily.

## Protected Files

Do not modify the following unless explicitly instructed:

- **`vars/` secrets files** — never inline a real credential or alter the variable-reference pattern that keeps the Conjur swap source-only.
- **The dual-email block** in the send-mail path — keep the active `sendmail` block and the commented `community.general.mail` block intact; do not delete either.
- **Any file's `# MIGRATION 2.14:` header comments** and inline notes — preserve them; they are part of the dual-version contract.
- **The baseline snapshot format and location contract** — do not change `snapshots/<cluster>_<timestamp>_baseline.json` without explicit instruction.
- **`main.yml` master flow ordering** — do not reorder or remove phases (`01 → 02 → 03/04 looped → 05`) without explicit instruction.
- **The six-file process surface** — do not add new top-level phase files beyond `00_Run.sh` and `01`–`05`; new logic goes into roles/tasks/templates.

## Keeping Docs in Sync

Update the relevant context file in the **same step** whenever implementation changes any of the following:

- System architecture, folder boundaries, or the storage/snapshot model → update `architecture.md`.
- A code convention, gate rule, threshold, or standard → update `code-standards.md`.
- Feature scope, flow, or success criteria → update `project-overview.md`.
- Report/email styling, colours, or components → update `ui-context.md`.
- Any invariant → update `architecture.md` and confirm no other unit violates it.

Never let code and docs drift. If they disagree, the **docs are wrong until you fix them** — update the docs, then continue.

## Verification Checklist — Before Moving to the Next Unit

Do not start the next unit until all of the following are true:

- The current unit works end to end within its defined scope.
- It runs unchanged on **both Ansible 2.7.17 and 2.14.18** (short module names, no bare `include:`, no `warn:` param, `| default('')` on optionals).
- No invariant defined in `architecture.md` was violated.
- Every shell/command task sets `changed_when:`/`failed_when:` explicitly, and secrets carry `no_log: true`.
- HARD gates use `fail:` and log out via `block/rescue/always`; WARN items only report.
- All paths derive from `playbook_dir`; nothing machine-specific is hardcoded.
- `progress-tracker.md` reflects the completed work, current phase, and any new open questions.
- A syntax check passes (`ansible-playbook --syntax-check`) on the affected playbooks.
