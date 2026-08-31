# Unit 06: `error_handle` Role

## Goal

Build the `error_handle` role that standardises every failure path: record the step number/name and observed reason, emit an alert email, and guarantee logout — the shared `rescue:` target for all phases.

## Design

- **System boundary:** `playbooks/roles/error_handle`.
- Deterministic: no inference; it only records, alerts, and hands off to logout.
- Consumes `current_step_no` / `current_task_name` passed by the caller (with `| default('')`).

## Implementation

### `error_handle/tasks/main.yml`
1. `set_fact` to append a FAIL entry to `failed_validations` (step, task, observed value/reason).
2. Write the reason to the run log (`.txt` + `.csv`).
3. Include the `sendmail` role with the `error-report.j2` selector (alert email).
4. Ensure the caller's `always:` block runs `logout` (documented contract; logout invoked by the phase, not here, to keep the role single-purpose).

### `error_handle/defaults/main.yml`
`current_step_no: 0`, `current_task_name: ""`, both `| default('')`.

### Messaging
Failure messages name the check, the cluster, and the observed value per `code-standards.md`.

## Dependencies

- Unit 05 (`sendmail`)
- Unit 03 (`logout` contract)

## Verify when done

- [ ] Records a structured FAIL entry with step/task/reason
- [ ] Sends an alert email via `sendmail` + `error-report.j2`
- [ ] Logout guaranteed via caller `block/rescue/always`
- [ ] No secrets in the recorded reason or email
- [ ] `| default('')` on `current_step_no`/`current_task_name`
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
