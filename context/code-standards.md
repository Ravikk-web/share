# Code Standards - ARO Cluster Upgrade Automation

Mandatory for everything under `playbooks/`. The code must run **unchanged on Ansible 2.7.17 and 2.14.18**. Prefer plain and explicit over clever.

---

## Keep it simple
- **Flow.** Phase files list *what* happens, top to bottom. `steps/` files do the work. Templates only render. `vars/` holds every setting.
- **No roles.** No role defaults and no new entry points: everything starts at `00_Run.sh -> main.yml`.
- **One failure handler.** It is `steps/common/handle_failure.yml`, run by `main.yml`'s `rescue:`. Do not add a phase-level rescue. A local `block/rescue` is allowed only to turn a non-critical problem into a WARN (mail, report rendering, Developer perspective).
- **Checks.** A check file reads the cluster and appends one record to `preval_checks` / `postval_checks`: `{num, name, gate, status, observed}`. Checks never `fail:`; the phase file applies the gate. Checks never change the cluster (a read-only `oc exec` into an existing pod, such as the kernel check of Check 14, is allowed and documented).
- **Phase 03 tasks.** A task file (`steps/03/task_<n>_<name>.yml`) checks, changes only if needed, watches any rollout with `steps/03/watch_rollout.yml`, verifies, and ends with `steps/03/record_task.yml`, which records one row in `preimpl_tasks` and stops the run on FAIL / FIX-FAILED. Each task reads the cluster itself (no dependency on Phase 02 facts), so a phase or task can be commented out for a test.
- **Inputs to a step.** Pass them as `include_tasks ... vars:` (scoped to that include). Facts that persist are results, not inputs.
- **Comments.** Each file has a short header: purpose, inputs and outputs, and any cluster write. Explain *why* for anything non-obvious.
- **Settings.** Gates, thresholds and switches live in `vars/`, never as literals buried in tasks.

## Ansible (2.7.17 syntax)
- Use short module names. Name every task.
- Use `include_tasks` for loops and conditions, with `{{ playbook_dir }}/...` paths. Never use bare `include:`, the `warn:` parameter or `import_playbook` in a loop.
- Give every optional variable a typed default: `| default('')`, `| default([])`, `| default(false) | bool`.
- Use `| bool` whenever a computed true/false value is used in a condition.
- Read-only `oc` tasks: `changed_when: false`, plus `retries: "{{ oc_command_retries }}"`, `delay`, `until: x.rc == 0`.
- A wait whose outcome is *data* (operators settling, a CSV reaching Succeeded, the cluster offering an update, `/readyz`) is a **bounded loop inside the shell** with `failed_when: false`. An Ansible `until` whose retries run out fails the task even with `failed_when: false`.
- Use `wait_for: timeout:` between polls, never `pause`.

## Shell and jq
- Every `shell` task that uses `set -o pipefail` sets `args: executable: /bin/bash`.
- Use `shell: |`, not `>-`. Quote every interpolation with `| quote`.
- A read that a result depends on fails the script when it fails (`oc get ... >"$tmpd/x.json" || exit 1`), so `retries` / `until` retry it. It never turns into empty data: an empty pod list must not make a HARD check PASS. Reads that are only extra detail (the node diagnosis) may fall back, but must then say they could not run.
- Use `command` when no pipe or redirection is needed.
- jq **1.5** only:
  - every `if` has an `else`
  - no `IN`, `walk`, `$ENV`, `ascii`, `halt`, `?//`, `@base64d`, `pick`, `abs`
  - no `round`: use `def rnd2: . * 100 | floor / 100;`
  - parenthesise `and` / `or` operands
  - no value parameters in definitions (`def f($x):`) and no `?` error suppression: define the function after the variable it needs (`... as $names | def pool_of: ... $names ...; ...`) and test before converting (`if test("^[0-9]+%$") then ... else 0 end`)
  - `A // B` also replaces `false`: to look up a boolean, use `if has($k) then .[$k] else ... end`
  - no apostrophe inside a single-quoted jq program (it ends the shell string): write "the log of that pod", not "that pod's log"
- `-l '!olm.copiedFrom'` on CSV queries.
- A node's pool is the MachineConfigPool whose rendered configuration it runs (`rendered-<pool>-<hash>` in `machineconfiguration.openshift.io/currentConfig`), else its role (the same `pool_of` definition in every program that needs it).

## Jinja2 pitfalls (each one has broken this project before)
1. **Self-referencing vars.** Never write `vars: x: "{{ x }}"` (infinite recursion). Use a different name.
2. **`ansible_failed_task.name`.** Never reference it. Use `ansible_failed_result.stderr`, then `.msg`.
3. **OpenShift condition statuses.** They may arrive as booleans. Normalise with `| string | lower` before comparing.
4. **`.items`.** On Kubernetes JSON use `['items']`; `.items` is the dict method.
5. **Undefined objects.** Do not read an attribute of a possibly undefined value on 2.7; guard with `(x | default({})).attr`.
6. **Regex backreferences.** Never use `'\1'` in YAML-quoted Jinja (it becomes a control character). Parse versions with `split('.')` and compare with the `version` test.
7. **Facts beat task vars.** Use different names for include inputs and facts.
8. **The `in` test.** Do not use `selectattr(..., 'in', ...)` (Jinja 2.10+). Use `{% for x in y if x not in z %}`.
9. **Timers.** Never time anything with `ansible_date_time` (frozen at fact gathering). Use `lookup('pipe', 'date +%s')`.
10. **Building lists in loops.** Use `{% set out = [] %}…{% set _ = out.append(...) %}…{{ out }}`. A `{% set %}` inside a loop does not leave the loop.

## Errors, gates, logs, mail
- **Gates.** HARD is a `fail:` naming the check, the cluster and the observed value. WARN is reported only. Never use `ignore_errors` to get past a gate.
- **Error extraction.** In the handler: `stderr` → `stderr_lines` → `msg` → fallback text.
- **RBAC.** Errors matching `forbidden | unauthorized | cannot <verb> resource` get the "permission" callout in the alert.
- **Run logs.** Only `steps/common/log_event.yml` writes them, by appending (`printf >>`). Never use `lineinfile` on the run log: it cuts off the tee'd console.
- **Mail.**
  - Only `steps/common/send_mail.yml` sends mail. Include it with `when: send_email | default(true) | bool`.
  - Kinds: summary, alert, heartbeat, degradation. Subjects are ASCII: `[ARO Upgrade][<cluster>][<KIND>] <headline> (run <ts>)`.
  - An SMTP error is a WARN.
- **Exit codes.** 5 login or Phase 01, 10 Phase 02, 15 Phase 03, 20 hop (Phase 04), 30 hop timeout / no progress (Phase 05), 25 Phase 06, 35 Phase 07, 99 other.

## Pre-upgrade changes (Phase 03)
- Only Phase 03 changes the cluster before the first hop. Each change is behind its own switch and `not dry_run` (the unpause and cgroup changes also behind `auto_remediation_enabled`; operator approvals behind `preupgrade_operator_upgrades` and not `skip_operator_upgrade`; the admin-ack behind `auto_apply_admin_acks`).
- A Phase 02 check may record a problem as WARN ("Phase 03 will ...") and add its number to `preval_deferred` only when `preval_defer_fixes` is true (Phase 03 is in the run) and the fix is switched on and can fix it.
- After a change, any MachineConfigPool rollout is watched to the end (Phase 05 rollout mode) before the next task.
- A change the MCO rolls out to the nodes is verified on the nodes, not on its setting: cgroup v2 is AUTO-FIXED only when the MCO finished every node and every node is on v2 by `cgroup_check_method` (`config`: v2 configuration, `kernel`: v2 kernel, `both`) (`steps/03/cgroup_nodes.yml`). A setting with a fixed set of values is validated at the start of `main.yml`, never silently defaulted. A node that cannot be checked counts as not done. Before watching, wait until the MCO has rendered the new configuration for every pool, so the watch cannot "settle" before the rollout started.
- A task records what it changed (`remediation_attempted_nums`, `preval_autofix_items`). If anything changed, or a task watched nodes reboot for an earlier change (`task_recheck`), Phase 03 re-runs **all** 17 prechecks with `preval_defer_fixes: false`; AUTO-FIXED / FIX-FAILED comes from that re-check, and only for checks whose task changed something.
- No Phase 03 change is made while a cluster update is running. A run started again during an update watches it to the end first (`steps/04/finish_running_update.yml`).

## Nodes
- Node problems are reported, never repaired: no step uncordons, drains, reboots, patches or deletes a node or a Machine. `steps/common/diagnose_nodes.yml` gives the problem, the likely cause and what to do from fixed rules; it is read-only and never fails its caller.
- Capacity is judged as the drain sees it (Check 08): per pool except master, with the pool's largest `maxUnavailable` nodes drained, the movable pods (all but DaemonSet and static pods) must fit on the remaining Ready, schedulable nodes.
- **New cluster writes.** Any new write must be added to `context/architecture.md` (Cluster writes), to `WORKFLOW.md` and to the "Changes" line in `00_Run.sh`, in the same change.

## Secrets
- Credentials are `{{ vault_* }}` references in `vars/secrets.yml`.
- Use `no_log: true` on anything that handles them.
- The password reaches `oc login` on stdin.
- Never write secrets to logs, reports, snapshots or mails.

## Templates
- `report.j2` is a standalone page (max 1080px, no external resources). Mails are max 580px, inline CSS, no JavaScript.
- Escape every cluster-provided string with `| e`.
- Statuses and colours come from facts and `vars/report_vars.yml`.

## Before calling a change done
- Run the offline checks: YAML parse, a Jinja parse of every templated string, every include path exists, every embedded jq program compiles (jq 1.5 scan), `bash -n` on each shell block and on `00_Run.sh`, and the behaviour tests for anything changed. The jq scan only compiles with a newer libjq: also read new jq against the jq 1.5 rules above (the scan cannot catch `def f($x)` or `?`).
- On the jump host: `ansible-playbook --syntax-check main.yml` on 2.7.17 and 2.14.18.
- Update `context/progress-tracker.md`, `README.md` and `Documentation.md` (and `WORKFLOW.md` if the flow changed).
