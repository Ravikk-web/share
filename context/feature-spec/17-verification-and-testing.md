# Unit 17: Verification & Testing Standards (Cross-Cutting Specification)

> **Revision 2026-10-01 (review remediation)** — Offline verification harness used for this revision (session scratchpad): YAML parse + Jinja compile of all files, jq compile of all 75 embedded programs + jq 1.5 syntax scan, jq behaviour tests, and a task-list simulator with Ansible 2.7 semantics for path validation, monitor and phase flows. Jump-host checklist: `Documentation.md` §6.7.

## Goal

Define the comprehensive pre-merge, syntax validation, runtime testing, and pitfall prevention procedures required to verify that the ARO Cluster Upgrade Automation suite is robust, resilient, and fully operational across both target Ansible environments.

---

## Design & Philosophy

- **Zero-Assumption Validation**: Never assume a playbook or role works because it passed a previous revision. Every component must undergo syntax verification, fact parsing checks, and dual-version compatibility checks.
- **Defensive Pitfall Prevention**: Test explicitly for the 14 known failure modes identified during v1 development before promoting code.
- **Dry-Run & Mock Safety**: Validate prevalidation and policy check phases thoroughly in dry-run mode (`--dry-run`) before testing cluster mutation tasks.

---

## Verification Test Suites

### 1. Dual-Version Syntax Validation

Every playbook and role must pass syntax checking on both target versions:

```bash
# Execute syntax validation across all seven process files
ansible-playbook --syntax-check playbooks/main.yml
ansible-playbook --syntax-check playbooks/01_Policy_Check.yaml
ansible-playbook --syntax-check playbooks/02_Pre_upgrade_check.yaml
ansible-playbook --syntax-check playbooks/03_Initiate_upgrade.yaml
ansible-playbook --syntax-check playbooks/04_Live_monitoring_upgrade.yaml
ansible-playbook --syntax-check playbooks/05_post_Upgrade_Checks.yaml
ansible-playbook --syntax-check playbooks/06_Operator_Upgrade.yaml
```

### 2. jq v1.5 Compatibility Tests

All jq expressions must be tested against a jq 1.5 binary (or verified using 1.5-safe syntax):
- **Test custom rounding function**:
  ```bash
  echo '{"val": 72.456}' | jq 'def rnd2: . * 100 | floor / 100; .val | rnd2'
  ```
- **Test parenthesized logical expressions**:
  Verify no unparenthesized `or`/`and` operators feed booleans into string functions.

### 3. Jinja2 Type & Templating Checks

- **Condition String Normalization**: Verify that all OpenShift condition comparisons apply `| string | trim` before checking truthiness:
  ```jinja2
  when: (cv_available_raw | string | trim | bool)
  ```
- **Bracket Notation Audit**: Search for `.items` access on JSON dictionaries and confirm it has been replaced with `['items']`.
- **Variable Default Audit**: Ensure all variables referenced in tasks or templates carry `| default('')` or typed defaults (`| default(false) | bool`).

### 4. Auto-Remediation Toggle Testing

Verify that all auto-remediation mechanisms respect configuration toggles:
- **Enabled Path**: With `auto_remediation_enabled: true`, trigger a simulated cgroup v1 or admin-ack failure; confirm that remediation executes, state is re-verified, and status is recorded as `AUTO-FIXED`.
- **Disabled Path**: With `auto_remediation_enabled: false` (or individual toggle `false`), confirm that the system cleanly treats the check as a HARD gate and halts with `FAIL`.

### 5. CLI Pre-Flight & Concurrency Tests (`00_Run.sh`)

- **Missing Tool Detection**: Temporarily alter PATH to verify that missing `oc`, `jq`, or `ansible-playbook` triggers a clear, formatted pre-flight error before execution.
- **Run Lock Verification**: Launch an execution and immediately attempt a second execution targeting the same cluster. Confirm that the second run is blocked by `/tmp/aro-upgrade-<cluster>.lock`.
- **Extra-Vars JSON Parsing**: Confirm that `upgrade_path` is passed as a valid JSON array string and correctly deserializes as a native YAML list in Ansible facts.

---

## Pre-Merge Master Checklist

- [ ] All 7 process playbooks pass `ansible-playbook --syntax-check`.
- [ ] No task in the entire codebase uses the removed `warn:` parameter.
- [ ] No bare `include:` exists; all task inclusions use `include_tasks:` or `import_tasks:`.
- [ ] No self-referencing variable assignments exist in `vars:` blocks.
- [ ] No rescue block templates `ansible_failed_task.name`.
- [ ] `sendmail` role clears `mail_html_body` and `mail_final_body` facts after dispatch.
- [ ] Shell tasks with `set -o pipefail` explicitly set `args: executable: /bin/bash`.
- [ ] All `oc` CLI commands implement retry loops (`retries: 3 / delay: 10`).
- [ ] All 14 prevalidation checks are mapped in `health-overview.j2` and `prevalidation/tasks/main.yml`.
- [ ] Concurrency lock file creation and cleanup on exit/trap verified.
- [ ] `context/progress-tracker.md` and `README.md` updated in the same step.
