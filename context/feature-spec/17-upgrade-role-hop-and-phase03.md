# Unit 17: `upgrade` Role + `tasks/hop.yml` + Phase 03 (`03_Initiate_upgrade.yaml`)

## Goal

Build the `upgrade` role and `tasks/hop.yml` per-hop sequence (set channel → verify edge → apply admin-ack if needed → `oc adm upgrade --to`), driven by `03_Initiate_upgrade.yaml` as a `loop:` over `upgrade_path` via `include_tasks`.

## Design

- **System boundary:** `playbooks/roles/upgrade` + `playbooks/tasks/hop.yml` + phase file `03_Initiate_upgrade.yaml`.
- Hybrid chaining: `import_playbook` cannot loop on 2.7.17, so per-hop iteration uses `include_tasks: tasks/hop.yml` with `loop:`.
- The only cluster write is `oc adm upgrade --to`. `--to-image ... --force` exists only as a hard-gated manual last resort, never automatic.
- Each hop wrapped in `block/rescue` → logout on failure.

## Implementation

### `upgrade/tasks/main.yml`
Tasks: set channel (`oc adm upgrade channel <stable-x.y>`), re-verify the edge live, apply required admin-ack if the target needs it, then `command: oc adm upgrade --to=<version>`. `register` + explicit `failed_when` on rc/stderr. `changed_when: true` only on the actual trigger.

### `tasks/hop.yml`
Per-hop block: pre-hop settle assertion (entry condition), call `upgrade` role, then hand off to monitor (Unit 18). `rescue:` → `error_handle` (alert) → logout → stop. Uses `loop_var` for the current target and computes hop `x/y`.

### `03_Initiate_upgrade.yaml`
Play on localhost that loops `include_tasks: tasks/hop.yml` over `upgrade_path`. Session reused (no re-login). Header + migration notes; explicit comment on why `include_tasks + loop` (not `import_playbook`).

### Last-resort path
`--to-image=<digest> --allow-not-recommended --force` gated behind an explicit manual flag/var, defaulting off, with a `fail:` guard requiring deliberate opt-in.

## Dependencies

- Unit 07 (edge validation), Unit 03 (`login`/`logout`), Unit 06 (`error_handle`)
- Unit 18 provides the monitor called inside the hop (built next; hop.yml references it just-in-time)
- oc, jq

## Verify when done

- [ ] Per-hop sequence runs: channel → edge → admin-ack → `oc adm upgrade --to`
- [ ] Iteration via `include_tasks: tasks/hop.yml` + `loop:` (no looped `import_playbook`)
- [ ] Only write is `oc adm upgrade`; `--force` path gated manual-only
- [ ] Hop wrapped block/rescue; logout on failure
- [ ] Hop `x/y` computed; entry settle assertion present
- [ ] Runs on 2.7.17 and 2.14.18; `--syntax-check` passes
- [ ] progress-tracker.md updated
