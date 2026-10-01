# Unit 16: Developer Comments & Documentation Standards (Cross-Cutting Specification)

## Goal

Define the mandatory inline documentation, file header structures, role variable annotations, and commentary requirements for every playbook, role, task, template, and script in the ARO Cluster Upgrade Automation codebase.

---

## Design & Philosophy

- **Zero-Ambiguity Codebase**: A new platform engineer reading any YAML file or script should immediately understand its purpose, dual-version behavior, dependencies, and failure implications without consulting external systems.
- **Explain the "Why", Not the "What"**: Comments must articulate *why* a particular pattern is chosen (e.g. jq 1.5 workaround, Ansible 2.7.17 compatibility, OpenShift API quirk) rather than simply paraphrasing the task name.
- **Continuous Documentation Sync**: As code changes, inline documentation and `Documentation.md` must be updated concurrently.

---

## Standards by Component

### 1. Mandatory File Header Blocks

Every playbook (`.yaml`/`.yml`), task file, and role entrypoint must begin with the standard header block:

```yaml
# ============================================================================
# <Single-Line Component Description>
# ============================================================================
# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)
# MIGRATION 2.14: <Specific migration notes or "No syntax changes needed">
#
# Purpose: <Detailed multi-line explanation of what this component executes>
# Role / Playbook Dependencies: <List of roles/vars required by this file>
# Gate Type: <HARD / WARN / AUTO-REMEDIATION / N/A>
# Outputs: <Facts exposed, files written, or notifications dispatched>
# ============================================================================
```

### 2. Task-Level Inline Comments

- **Mandatory `name:`**: Every task must have an action-oriented, numbered or tagged `name:` field.
- **Non-Obvious Logic Annotations**: Use `# Why:` comments before tasks that implement known workarounds:
  ```yaml
  # Why: jq 1.5 does not support round(); custom rnd2 function avoids lexer token collision
  # Why: bracket notation ['items'] used because .items invokes Python's dict.items() method
  # Why: | string | trim applied because OpenShift conditions may deserialize as boolean True
  # Why: set -o pipefail requires /bin/bash; Ansible default /bin/sh defaults to dash on Debian
  ```

### 3. Role Defaults Documentation (`defaults/main.yml`)

Every variable defined in a role's `defaults/main.yml` must be documented with its data type, purpose, and override source:

```yaml
# ============================================================================
# Role Defaults — <Role Name>
# ============================================================================

# Target ARO cluster name (string, mandatory)
# Sourced from vars/upgrade.yml or overridden via CLI --cluster
cluster_name: ""

# Maximum allowable node CPU requests percentage before triggering gate (integer, 1-100)
# Sourced from vars/upgrade.yml
max_cpu_percent: 90

# Master toggle for automatic blocker remediation (boolean)
# Sourced from vars/upgrade.yml; defaults to true for one-touch execution
auto_remediation_enabled: true
```

### 4. Rescue Block Documentation

Every `rescue:` section must document:
1. The error extraction cascade used.
2. What alerts are triggered.
3. Why session logout is guaranteed by the caller's `always:` block.

### 5. Template Documentation (`templates/*.j2`)

Every Jinja2 template must include a comment block at the top declaring:
- Target rendering context (Email vs Standalone HTML report).
- Inbound fact dependencies (e.g. `health_summary`, `mcp_parsed_data`).
- Accessibility and email-client rendering constraints (e.g. `≤ 580px`, inline CSS only).

---

## Verification Checklist

- [ ] All YAML files start with the standardized 2.7.17/2.14 header block.
- [ ] Every task has a descriptive `name:`.
- [ ] All jq expressions, bracket queries, and shell flags include `# Why:` comments.
- [ ] Every role's `defaults/main.yml` defines variable types and sources.
- [ ] No temporary debugging comments or commented-out dead code remain in the codebase.
