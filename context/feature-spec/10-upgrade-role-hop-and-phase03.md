# Unit 10: Upgrade Role, Per-Hop Task (`tasks/hop.yml`) & Phase 03 (`03_Initiate_upgrade.yaml`)

> **Revision 2026-10-01 (review remediation)** — `roles/upgrade` is split into `main.yml` (plan: skip / resume / trigger / blocked) and `apply.yml` (channel patch, wait for the offered edge, conditional-risk policy, admin-ack apply mode, trigger, acceptance check). `tasks/hop.yml` waits for a stable cluster first and sends no hop mails; one alert per failure (exit 20 / 30).

## Goal

Build the `upgrade` role, the per-hop sequence task (`tasks/hop.yml`), and the Phase 03 playbook (`03_Initiate_upgrade.yaml`) to sequentially drive minor-version cluster hops (channel update → edge verification → dynamic admin-ack application → `oc adm upgrade --to`), handing off each hop to live monitoring.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/upgrade/`, `playbooks/tasks/hop.yml`, and `playbooks/03_Initiate_upgrade.yaml`.
- **Ansible 2.7.17 Looping Contract**: Because `import_playbook` cannot loop on Ansible 2.7.17, the per-hop iteration is implemented as a single play on `localhost` looping `include_tasks: tasks/hop.yml` over `upgrade_path`.
- **Strictly Guarded Cluster Mutation**: The single write operation permitted against the cluster is `oc adm upgrade --to=<version>`. The emergency `--to-image=<digest> --allow-not-recommended --force` path is strictly gated behind an explicit manual boolean variable (`allow_force_upgrade: false`) that fails unconditionally if invoked automatically.
- **Fail-Safe Hop Enclosure**: Each hop is wrapped in `block/rescue` to guarantee alert notification and session logout on failure.

---

## Implementation Details

### 1. `roles/upgrade/`
- **`defaults/main.yml`**:
  ```yaml
  target_version: ""
  target_channel: ""
  allow_force_upgrade: false
  force_image_pullspec: ""
  ```
- **`tasks/main.yml`**:
  1. Determine target channel from version prefix (e.g. `4.15.35` → `stable-4.15` or `fast-4.15`).
  2. Set upgrade channel: `oc adm upgrade channel {{ target_channel }}` with `changed_when: true`.
  3. Re-verify update edge: assert that `target_version` appears in `oc adm upgrade` available updates for the newly configured channel.
  4. Dynamic Admin-Ack Check: If target version requires an acknowledgment, execute `remediate/tasks/admin_acks.yml` dynamically.
  5. Trigger Upgrade:
     ```yaml
     - name: "Trigger cluster upgrade to target version"
       command: "oc adm upgrade --to={{ target_version }}"
       register: upgrade_trigger_result
       changed_when: true
       failed_when:
         - upgrade_trigger_result.rc != 0
         - "'already at' not in upgrade_trigger_result.stderr"
     ```
  6. Force Guard: If `allow_force_upgrade` is true, enforce explicit confirmation prompts; otherwise reject `--force` unconditionally.

### 2. Per-Hop Sequence Task (`playbooks/tasks/hop.yml`)
Invoked per item in `upgrade_path` with loop variables `hop_item` and index:
- **`block:`**:
  1. Compute hop metadata: `hop_number`, `hop_total`, `hop_label: "{{ hop_number }}/{{ hop_total }}"`.
  2. Log hop start banner to console and logs.
  3. Pre-Hop Settle Assertion: Confirm cluster is in a stable, unblocked state prior to triggering.
  4. Invoke `roles/upgrade` with `target_version: "{{ hop_item }}"`.
  5. Hand off to live monitoring: `include_tasks: ../04_Live_monitoring_upgrade.yaml`.
  6. Settle-Gate Verification: Assert cv at target, all COs Available and not Progressing, MCP Updated=True.
  7. Dispatch hop-complete email via `sendmail` role with Prevalidation HTML report attached.
- **`rescue:`**:
  - Call `error_handle` role to record failure and send alert email.
  - Call `logout` role to tear down cluster session.
  - Fail the playbook execution.

### 3. Phase 03 Playbook (`playbooks/03_Initiate_upgrade.yaml`)
- Runs on `localhost` reusing existing authenticated session.
- Loops over `upgrade_path`:
  ```yaml
  - name: "Phase 03 — Sequential Upgrade Hop Execution"
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
      - name: "Execute sequential upgrade hops"
        include_tasks: tasks/hop.yml
        loop: "{{ upgrade_path }}"
        loop_control:
          loop_var: hop_item
          index_var: hop_index
  ```

---

## Verification Checklist

- [ ] Loop executes using `include_tasks: tasks/hop.yml` (no looped `import_playbook`).
- [ ] Channel is updated and verified before triggering `oc adm upgrade --to`.
- [ ] Admin-ack is checked and dynamically applied if required.
- [ ] Only cluster write is `oc adm upgrade --to`.
- [ ] `--force` path fails immediately unless manually opted in.
- [ ] Each hop is wrapped in `block/rescue` with fail-safe logout.
- [ ] Playbook passes `ansible-playbook --syntax-check`.
