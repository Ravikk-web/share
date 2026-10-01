# Unit 15: Exception Handling & Error Extraction Patterns (Cross-Cutting Specification)

> **Revision 2026-10-01 (review remediation)** — Rescues extract a fresh `resolved_error` (stderr → stderr_lines → msg), set `phase_exit_code`, and rely on `error_handle`'s single-alert guard. New mandatory patterns: no attribute access on possibly undefined facts (Ansible 2.7), bounded in-shell waits instead of `until` for data outcomes. See `code-standards.md` anti-patterns 6–12.

## Goal

Provide the authoritative standard for all error handling, rescue block extraction, RBAC permission error detection, remediation status tracking, and fail-safe session cleanup across all roles and playbooks in the ARO Cluster Upgrade Automation suite.

---

## Design & Philosophy

- **Zero Unhandled Exceptions**: Any failure during execution must be caught, recorded in structured format, alerted via email, and followed by immediate session teardown.
- **Hierarchical Error Resolution**: When commands fail, extract error text from raw stderr, stderr lines, or Ansible task msg. Never show generic "non-zero return code" without context.
- **No `ansible_failed_task` Templating**: Never reference `ansible_failed_task.name` or `ansible_failed_task` properties in rescue blocks. `Task` objects contain non-serializable `FieldAttribute` instances that trigger unhandled Ansible exceptions when evaluated.
- **Fail-Safe Teardown Invariant**: All phase playbooks must encapsulate volatile work in `block/rescue/always`. The `always` block calls `logout` to guarantee that tokens and kubeconfig files are destroyed upon error.

---

## Implementation Patterns

### 1. Standard Error Extraction Hierarchy

In any `rescue:` block, extract the root cause using the following priority cascade:

```yaml
- name: "Extract sanitized error message from failure result"
  set_fact:
    resolved_error: >-
      {{ ansible_failed_result.stderr | default('')
         if (ansible_failed_result.stderr | default('') | length > 0)
         else (ansible_failed_result.stderr_lines | default([]) | join('\n'))
         if (ansible_failed_result.stderr_lines | default([]) | length > 0)
         else ansible_failed_result.msg | default('Unknown error — inspect logs') }}
```

### 2. RBAC & Permission Error Detection

Many ARO failures occur because the cluster service account lacks specific cluster-scoped RBAC permissions (e.g., `patch` on `machineconfigpools` or `nodes.config`). Detect these patterns automatically and expose an `is_rbac_error` boolean fact:

```yaml
- name: "Evaluate whether failure is an RBAC / authorization error"
  set_fact:
    is_rbac_error: >-
      {{ (resolved_error | lower is search('forbidden'))
         or (resolved_error | lower is search('cannot patch'))
         or (resolved_error | lower is search('unauthorized'))
         or (resolved_error | lower is search('cannot get'))
         or (resolved_error | lower is search('cannot list'))
         or (resolved_error | lower is search('cannot create')) }}
```

When `is_rbac_error` is `true`, downstream alert templates (`error-report.j2`) render an amber/red diagnostic callout with the exact missing verb/resource and copy-paste remediation commands.

### 3. Anti-Pattern: Avoiding Self-Referencing Variables

Never pass variables in `vars:` that refer to the same variable name in outer scope:

```yaml
# ❌ WRONG: Triggers Jinja2 recursive loop:
# AnsibleError: An unhandled exception occurred while templating
- include_role:
    name: error_handle
  vars:
    failure_reason: "{{ failure_reason }}"
    failure_observed: "{{ failure_observed }}"

# ✅ CORRECT: Set facts first, then invoke role with no vars: block:
- set_fact:
    failure_reason: "Prevalidation HARD gate failure"
    failure_observed: "{{ resolved_error }}"
- include_role:
    name: error_handle
```

### 4. Remediation Status Tracking

The `health_summary` fact list records the lifecycle state of each check:
- `PASS`: Passed verification on first pass.
- `WARN`: Advisory finding (non-blocking).
- `FAIL`: Unresolved HARD gate failure; triggers halt and alert.
- `AUTO-FIXED`: Check failed initially, automated remediation executed successfully, and re-verification passed.
- `FIX-FAILED`: Remediation was attempted but re-verification failed; escalated to `FAIL`.

### 5. Resilient Command Execution Wrapper

All `oc` CLI commands must implement transient failure protection:

```yaml
- name: "Query OpenShift resource with transient retry"
  shell: "oc get {{ resource_name }} -o json"
  register: query_result
  until: query_result.rc == 0
  retries: "{{ oc_command_retries | default(3) }}"
  delay: "{{ oc_command_retry_delay | default(10) }}"
  changed_when: false
  args:
    executable: /bin/bash
```

---

## Verification Checklist

- [ ] Every `rescue:` block extracts `stderr` before `stderr_lines` before `msg`.
- [ ] No task in any role references `ansible_failed_task.name`.
- [ ] RBAC detection logic is present in `error_handle` and alert templates.
- [ ] No `include_role` passes self-referencing `vars:` blocks.
- [ ] `always:` block in each phase playbook invokes `logout` with `failed_when: false`.
- [ ] All `oc` shell tasks specify `args: executable: /bin/bash` when using pipes.
