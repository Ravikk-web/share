# Unit 13: Operator Lifecycle Roles & Phase 06 (`06_Operator_Upgrade.yaml`)

> **Revision 2026-10-01 (review remediation)** — Phase 06 approves only each UpgradePending subscription's current InstallPlan, waits for those CSVs (one Deployment restart on Failed), gates on approved operators and regressions (exit 35), and enables the web console Developer perspective (`roles/console`). The final summary is sent by the `main.yml` close-out.

## Goal

Build the operator lifecycle roles (`operator_compat`, `operator_upgrade`, `operator_validate`) and the Phase 06 playbook (`06_Operator_Upgrade.yaml`) to scan installed OLM operators for OCP version compatibility, approve manual InstallPlans sequentially, validate that all ClusterServiceVersions (CSVs) reach `Succeeded`, generate the Operator Validation HTML report, dispatch the final Upgrade-Complete digest with 4 attachments, and perform terminal session logout.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/operator_compat`, `operator_upgrade`, `operator_validate`, and `playbooks/06_Operator_Upgrade.yaml`.
- **Phase 06 Renumbering**: Consistently renumbered from legacy "08" to **Phase 06** to maintain a clean sequential chain: `01 → 02 → 03/04 → 05 → 06`.
- **Independent Failure Domain**: An operator upgrade failure in Phase 06 is recorded as a HARD finding for this phase only. **It never rolls back completed cluster version hops.**
- **Automated CSV Recovery**: If a CSV rollout stalls, deletes the failed CSV pod once to let OLM subscription reconciliation re-attempt the deployment.
- **Terminal Logout Responsibility**: Phase 06 is the final playbook in the automation lifecycle. It performs the definitive session logout and token revocation upon completion.

---

## Role Specifications

### 1. `roles/operator_compat/` (Compatibility Scan)
- **Purpose**: Query all installed OLM `Subscription` resources in the cluster and verify that available update channels support the newly upgraded cluster version.
- **Tasks**:
  1. `oc get subscriptions.operators.coreos.com -A -o json` | jq v1.5.
  2. For each operator subscription, query `PackageManifest` to verify that the configured channel (or target channel) supports the cluster's target OpenShift version.
  3. Identify operators requiring channel switches and expose `operator_compat_plan` fact.

### 2. `roles/operator_upgrade/` (InstallPlan Approval & Rollout)
- **Purpose**: Sequentially approve pending manual InstallPlans and monitor CSV rollout.
- **Tasks**:
  1. Discover unapproved InstallPlans:
     `oc get installplan -A -o json | jq '.items[] | select(.spec.approved == false)'`
  2. Sequentially approve each InstallPlan:
     `oc patch installplan {{ item.name }} -n {{ item.namespace }} --type=merge -p '{"spec":{"approved":true}}'`
  3. Bounded polling loop waiting for target CSV to reach `status.phase == "Succeeded"`.
  4. **Automated Recovery**: If CSV fails with `InstallCheckFailed` or timeout, delete the CSV once (`oc delete csv <name> -n <ns>`) and re-poll.

### 3. `roles/operator_validate/` (Health Verification & Reports)
- **Purpose**: Validate post-upgrade operator health and generate audit artifacts.
- **Tasks**:
  1. Assert all subscriptions have `installedCSV` matching active CSV.
  2. Confirm all active CSVs report `phase: Succeeded`.
  3. Call `report` role with `report_type: "operators"` to generate `output/<cluster>_operators_<ts>.html`.

---

## Phase 06 Playbook (`playbooks/06_Operator_Upgrade.yaml`)

```yaml
- name: "Phase 06 — Operator Upgrade & Workflow Closeout"
  hosts: localhost
  connection: local
  gather_facts: true
  vars_files:
    - vars/upgrade.yml
    - vars/secrets.yml
    - vars/paths.yml
    - vars/smtp.yml
    - vars/report_vars.yml
  tasks:
    - name: "Execute operator lifecycle within protected block"
      block:
        - name: "1. Scan operator version compatibility"
          include_role:
            name: operator_compat

        - name: "2. Execute operator upgrades and approve InstallPlans"
          include_role:
            name: operator_upgrade

        - name: "3. Validate operator health and generate report"
          include_role:
            name: operator_validate

        - name: "4. Dispatch final Upgrade-Complete digest email"
          include_role:
            name: sendmail
          vars:
            mail_subject: "{{ heartbeat_subject_prefix }} — ALL PHASES COMPLETE ✔ — {{ cluster_name }}"
            mail_template: "progress-mail.j2"
            mail_attachments:
              - "{{ output_dir }}/{{ cluster_name }}_prevalidation_{{ run_timestamp }}.html"
              - "{{ output_dir }}/{{ cluster_name }}_postvalidation_{{ run_timestamp }}.html"
              - "{{ output_dir }}/{{ cluster_name }}_operators_{{ run_timestamp }}.html"
              - "{{ log_dir }}/{{ cluster_name }}_{{ run_timestamp }}.txt"

        - name: "5. Perform definitive session logout"
          include_role:
            name: logout

      rescue:
        - name: "Extract error and alert platform team"
          include_role:
            name: error_handle
          vars:
            current_task_name: "Phase 06 Operator Upgrade"
            current_gate_type: "HARD"

        - name: "Perform terminal logout on failure"
          include_role:
            name: logout
```

---

## Verification Checklist

- [ ] Numbered consistently as Phase 06 (`06_Operator_Upgrade.yaml`).
- [ ] OLM Subscriptions scanned and verified against PackageManifests.
- [ ] Manual InstallPlans patched with `approved: true`.
- [ ] CSV polling implements one-shot recovery retry on failure.
- [ ] Operator report written to `output/`.
- [ ] Upgrade-complete email dispatched with all 4 audit attachments.
- [ ] Definitive `logout` executed in both success and rescue branches.
- [ ] Playbook passes `ansible-playbook --syntax-check`.
