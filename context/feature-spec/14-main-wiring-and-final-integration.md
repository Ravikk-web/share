# Unit 14: Master Wiring & End-to-End Integration (`main.yml`)

> **Revision 2026-10-01 (review remediation)** — Wiring changed: `main.yml` = imports of Phases 01, 02, 03, 05, 06 + close-out play. Each phase guards itself (skip / stop / dry-run rules); failed hosts never reach the close-out, so a failed run ends with its single alert. New shared task files: `validate_upgrade_path.yml`, `log_event.yml`, `notify.yml`, `send_run_summary.yml`.

## Goal

Wire the complete master orchestrator playbook (`playbooks/main.yml`) to sequentially execute all phases (`01` through `06`), enforce dry-run restrictions, support selective phase execution (`skip_to_phase`), and deliver end-to-end integration across the entire seven-file process surface.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/main.yml`, integrating all phase playbooks and roles.
- **Fixed Phase Chain**: The master flow executes:
  ```
  01_Policy_Check.yaml
      └── 02_Pre_upgrade_check.yaml
              └── [Dry-Run Check: Stop if dry_run=true]
                      └── 03_Initiate_upgrade.yaml (loops hop.yml ──▶ 04_Live_monitoring)
                              └── 05_post_Upgrade_Checks.yaml
                                      └── 06_Operator_Upgrade.yaml
  ```
- **Dry-Run Enforcement**: When `dry_run: true` is passed (via CLI `--dry-run`), the master playbook executes Phase 01 (baseline) and Phase 02 (prevalidation + auto-remediation), generates the prevalidation HTML report, invokes `logout`, and halts cleanly without triggering any cluster mutation in Phase 03.
- **Selective Execution (`skip_to_phase`)**: If `skip_to_phase` is defined (e.g. `skip_to_phase: "05"` or `"06"`), preceding phases are skipped via `when:` guards, allowing targeted postvalidation or operator upgrade runs during recovery workflows.

---

## Implementation Details (`playbooks/main.yml`)

```yaml
# ============================================================================
# main.yml — Master Orchestrator for ARO Cluster Upgrade Automation
# ============================================================================
# Targets: Ansible 2.7.17 (test) / 2.14.18 (prod)
# MIGRATION 2.14: Uses import_playbook for isolated phase execution.
#
# Process Surface:
#   Phase 01: 01_Policy_Check.yaml
#   Phase 02: 02_Pre_upgrade_check.yaml
#   Phase 03: 03_Initiate_upgrade.yaml (includes hop.yml and 04 monitoring)
#   Phase 05: 05_post_Upgrade_Checks.yaml
#   Phase 06: 06_Operator_Upgrade.yaml
# ============================================================================

- name: "ARO Upgrade Automation — Initialization & Variable Loading"
  hosts: localhost
  connection: local
  gather_facts: true
  vars_files:
    - vars/upgrade.yml
    - vars/secrets.yml
    - vars/paths.yml
    - vars/smtp.yml
    - vars/report_vars.yml
    - vars/api_regex.yml
  tasks:
    - name: "Display workflow initialization banner"
      debug:
        msg:
          - "========================================================"
          - "  ARO Cluster Upgrade Automation — One-Touch Engine"
          - "========================================================"
          - "Target Cluster : {{ cluster_name }}"
          - "Upgrade Path   : {{ upgrade_path | join(' -> ') }}"
          - "Dry Run Mode   : {{ dry_run | default(false) }}"
          - "Auto-Remediate : {{ auto_remediation_enabled | default(true) }}"
          - "Skip To Phase  : {{ skip_to_phase | default('None (Full Run)') }}"
          - "Stop After     : {{ stop_after_phase | default('None (Full Run)') }}"
          - "========================================================"

# --- Phase 01: Policy Check, Baseline Snapshot & Edge Validation ---
- import_playbook: 01_Policy_Check.yaml
  when:
    - skip_to_phase is not defined or (skip_to_phase | int) <= 1
    - stop_after_phase is not defined or (stop_after_phase | int) >= 1

# --- Phase 02: 14-Check Prevalidation & Auto-Remediation ---
- import_playbook: 02_Pre_upgrade_check.yaml
  when:
    - skip_to_phase is not defined or (skip_to_phase | int) <= 2
    - stop_after_phase is not defined or (stop_after_phase | int) >= 2

# --- Prevalidation / Dry-Run Intercept: Clean Stop after Phase 02 ---
- name: "Prevalidation / Dry-Run Intercept & Early Teardown"
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: "Halt workflow cleanly when dry-run or pre-check only is requested"
      block:
        - name: "Log prevalidation/dry-run completion"
          debug:
            msg: "✔ Prevalidation/dry-run complete. Prevalidation report generated. Stopping before Phase 03."
        - name: "Teardown cluster session"
          include_role:
            name: logout
        - name: "Terminate execution cleanly"
          meta: end_play
      when: (dry_run | default(false) | bool) or (stop_after_phase is defined and (stop_after_phase | int) <= 2)

# --- Phase 03 & 04: Sequential Upgrade Hops & Live Monitoring ---
- import_playbook: 03_Initiate_upgrade.yaml
  when:
    - not (dry_run | default(false) | bool)
    - skip_to_phase is not defined or (skip_to_phase | int) <= 3
    - stop_after_phase is not defined or (stop_after_phase | int) >= 3

# --- Phase 05: 10-Check Postvalidation & Baseline Diff ---
- import_playbook: 05_post_Upgrade_Checks.yaml
  when:
    - not (dry_run | default(false) | bool)
    - skip_to_phase is not defined or (skip_to_phase | int) <= 5
    - stop_after_phase is not defined or (stop_after_phase | int) >= 5

# --- Post-Check Intercept: Clean Stop after Phase 05 ---
- name: "Post-Check Intercept & Early Teardown"
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: "Halt workflow cleanly when post-check only is requested"
      block:
        - name: "Log post-check completion"
          debug:
            msg: "✔ Post-check verification complete. Postvalidation report generated. Stopping before Phase 06."
        - name: "Teardown cluster session"
          include_role:
            name: logout
        - name: "Terminate execution cleanly"
          meta: end_play
      when: stop_after_phase is defined and (stop_after_phase | int) <= 5

# --- Phase 06: Operator Compatibility, Upgrades & Closeout ---
- import_playbook: 06_Operator_Upgrade.yaml
  when:
    - not (dry_run | default(false) | bool)
    - skip_to_phase is not defined or (skip_to_phase | int) <= 6
    - stop_after_phase is not defined or (stop_after_phase | int) >= 6
```

---

## Verification Checklist

- [ ] `main.yml` chains all 5 phase playbooks in strict order (`01 → 02 → 03 → 05 → 06`).
- [ ] `--dry-run` halts execution after Phase 02, logs out, and does not execute Phase 03.
- [ ] `--skip-to-phase` conditionally activates targeted playbooks.
- [ ] Extra-vars JSON parsing works seamlessly across all child plays.
- [ ] Entire suite passes `ansible-playbook --syntax-check playbooks/main.yml`.
- [ ] Single authenticated session is successfully carried through Phase 06.
