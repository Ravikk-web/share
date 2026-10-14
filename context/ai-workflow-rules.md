# AI Workflow Rules - ARO Cluster Upgrade Automation

Mandatory rules for changing this project. It upgrades production clusters and must run unchanged on Ansible 2.7.17 and 2.14.18.

## Before changing anything
- Read `WORKFLOW.md`, then `context/architecture.md` and `context/code-standards.md`.

## Scope
- Make one change at a time, finish it, verify it and document it.
- Do not add features, modes, switches or entry points the user did not ask for. Put ideas in `context/progress-tracker.md` under Open questions.
- Keep the shape:
  - `00_Run.sh -> main.yml -> 01..07` phase files
  - work in `steps/<phase>/`
  - one failure handler
  - settings in `vars/`
- If something would make the flow harder to read, ask first.

## Protected
1. `vars/secrets.yml`: credentials stay vault references with `no_log`; never plaintext.
2. Phase order 01 → 02 → 03(+05) → 04(+05) → 06 → 07. Only `mode_phases` in `main.yml` leaves phases out (commenting a phase out is for local testing only).
3. The baseline snapshot is the only state saved between phases.
4. The cluster-writes table in `context/architecture.md`: a new write goes there, in `WORKFLOW.md` and in `00_Run.sh`'s "Changes" line.
5. Every YAML file keeps its `# Targets: Ansible 2.7.17 / 2.14.18` and `# MIGRATION 2.14:` header lines.

## Pre-upgrade changes
- Only in Phase 03, behind their own switch and `not dry_run`; Phase 02 stays read-only.
- Each change is followed by a rollout watch and a verification. Phase 03 re-runs all prechecks to decide AUTO-FIXED or FIX-FAILED.

## Checklist before a change is done
- [ ] The offline checks pass (see `context/code-standards.md`, "Before calling a change done").
- [ ] No bare `include:`, no `warn:`, no `ansible_failed_task.name`, no regex backreferences, no `ansible_date_time` timers, no Jinja `in` test.
- [ ] jq programs use only jq 1.5 syntax.
- [ ] A dry run still makes no cluster write.
- [ ] `context/progress-tracker.md`, `README.md` and `Documentation.md` are updated; `WORKFLOW.md` too if the flow changed.
- [ ] Nothing is committed or pushed until the user asks.
