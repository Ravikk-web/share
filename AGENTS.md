# AGENTS.md — ARO Cluster Upgrade Automation

## Application Building Context

Read the following files in order before implementing or making any architectural decision:

- `context/project-overview.md` — product definition, goals, features, and scope
- `context/architecture.md` — system structure, boundaries, storage model, and invariants
- `context/ui-context.md` — theme, colors, typography, and component conventions
- `context/code-standards.md` — implementation rules and conventions
- `context/ai-workflow-rules.md` — development workflow, scoping rules, and delivery approach
- `context/progress-tracker.md` — current phase, completed work, open questions, and next steps

If implementation changes the architecture, scope, or standards documented in the context files, update the relevant file **before** continuing.

## Progress & Documentation Rules

- **Update `context/progress-tracker.md` after each meaningful implementation change** — current phase, completed work, in-progress items, next up, open questions, architecture decisions, and session notes.
- **Update `README.md` in the same style as the progress tracker.** After each meaningful change, keep the README's status section current (what's built, what's next, how to run) so it always mirrors the tracker at a glance. Treat the README as the human-facing summary of the same state.
- **Keep documenting the project in `Documentation.md`.** This is the running, cumulative record of the project — every unit built, key decisions and their rationale, gate/threshold definitions, migration notes, and anything a new engineer needs to understand the system. Append to it continuously as work progresses; never let it fall behind the code.

## Version Control Rules

- **Do not commit or push to GitHub until I explicitly specify.** Stage and build locally only.
- No `git commit`, `git push`, tag, or PR actions are to be taken on your own initiative — wait for an explicit instruction each time.
- You may prepare commit messages or a change summary for review, but do not execute version-control operations until told.

## Keeping Docs in Sync

Whenever implementation changes any of the following, update the relevant file in the **same step**:

- System architecture, folder boundaries, or the storage/snapshot model → `architecture.md`
- A code convention, gate rule, threshold, or standard → `code-standards.md`
- Feature scope, flow, or success criteria → `project-overview.md`
- Report/email styling, colours, or components → `ui-context.md`
- Any invariant → `architecture.md` (and confirm no other unit violates it)
- Current state / progress → `progress-tracker.md` **and** `README.md`
- Cumulative project record → `Documentation.md`

Never let code and docs drift. If they disagree, the docs are wrong until you fix them — update the docs, then continue.
