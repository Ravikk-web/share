# Unit 01: Project Scaffold & Variable Inputs

## Goal

Create the complete folder structure and all six input variable files for the ARO Cluster Upgrade Automation suite, including the `scripts/cli_helpers.sh` library stub, directory anchors, and auto-remediation configuration toggles.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/` folder scaffold, `playbooks/vars/*.yml`, `.gitkeep` in write-only directories, and `playbooks/scripts/cli_helpers.sh` stub.
- **Inputs Only**: Files in `playbooks/vars/` contain data values, cadences, thresholds, and regex patterns only — **no executable logic or tasks**.
- **Dynamic Anchors**: All paths must derive from `playbook_dir` so the codebase is completely portable across jump hosts.
- **Conjur Vault Ready**: Secrets in `vars/secrets.yml` are variable references (`{{ vault_* }}`), enabling a zero-code-change migration to Conjur Vault later.
- **Auto-Remediation Controls**: `vars/upgrade.yml` introduces toggles for one-touch automated fixes.

---

## Directory Tree to Create

```
ARO_Cluster_Upgrade/
└── playbooks/
    ├── vars/
    │   ├── upgrade.yml        # Cluster targets, upgrade paths, thresholds, auto-remediation toggles
    │   ├── secrets.yml        # Cluster API URLs and credential references
    │   ├── smtp.yml           # SMTP host, port, recipients, and subject tags
    │   ├── paths.yml          # Centralized dynamic paths based on playbook_dir
    │   ├── report_vars.yml    # Color hex tokens, badges, report layout constants
    │   └── api_regex.yml      # URL validation regex and cluster name patterns
    ├── scripts/
    │   └── cli_helpers.sh     # Library stub for terminal formatting and menus
    ├── roles/                 # 24 modular roles (populated by subsequent units)
    ├── tasks/                 # Sub-playbook workflow tasks (e.g. hop.yml)
    ├── templates/             # Presentation templates (.j2)
    ├── logs/                  # Write-only run logs (.txt and .csv)
    ├── output/                # Write-only client HTML reports
    └── snapshots/             # Write-only baseline JSON snapshots
```

---

## Variable Files Specification

### 1. `vars/upgrade.yml`
Must define:
- `cluster_name: ""` (default empty, resolved via CLI or prompt).
- `upgrade_path: []` (default empty list of target versions).
- `cluster_upgrade_paths: {}` (optional dictionary of pre-configured paths per cluster).
- Thresholds: `max_cpu_percent: 90`, `max_memory_percent: 90`, `fail_on_zero_disruption_pdb: true`.
- Cadences: `poll_interval_minutes: 2`, `hop_timeout_minutes: 90`, `heartbeat_minutes: 20`.
- **Auto-Remediation Toggles (One-Touch Automation)**:
  - `auto_remediation_enabled: true` (master switch).
  - `auto_fix_cgroup_v2: true` (migrate to cgroup v2 if target >= 4.19).
  - `auto_apply_admin_acks: true` (dynamically apply admin-ack ConfigMap).
  - `auto_unpause_mcp: true` (unpause paused MachineConfigPools).
  - `mcp_auto_unpause_list: ["worker", "master"]`.
  - `auto_restart_degraded_operators: false` (Tier 2, default off).
  - `auto_force_stalled_node: false` (Tier 2, default off).
  - `node_stall_threshold_minutes: 30`.
  - `operator_upgrade_retry_count: 1`.
  - `oc_command_retries: 3`.
  - `oc_command_retry_delay: 10`.

### 2. `vars/secrets.yml`
Must define cluster entries with variable references:
- `cluster_d01_api_url: "https://api.aro-d01.example.com:6443"`
- `cluster_d01_username: "svc-aro-upgrade"`
- `cluster_d01_password: "{{ vault_cluster_d01_password | default('') }}"`

### 3. `vars/smtp.yml`
Must define SMTP parameters for direct SMTP dispatch via native `mail`:
- `smtp_host: "smtp.example.com"`, `smtp_port: 25`
- `mail_from: "aro-upgrades@example.com"`
- `mail_to: ["platform-team@example.com"]`
- `heartbeat_subject_prefix: "[ARO Upgrade]"`
- `alert_subject_prefix: "[ARO Upgrade ALERT]"`

### 4. `vars/paths.yml`
Must anchor paths dynamically to `playbook_dir`:
- `log_dir: "{{ playbook_dir }}/logs"`
- `output_dir: "{{ playbook_dir }}/output"`
- `snapshot_dir: "{{ playbook_dir }}/snapshots"`
- `kubeconfig_path: "{{ playbook_dir }}/.kubeconfig-{{ cluster_name | default('default') }}"`

### 5. `vars/report_vars.yml`
Must define UI tokens matching `context/ui-context.md`:
- Colors: `color_pass: "#1a7f37"`, `color_warn: "#9a6700"`, `color_fail: "#b42318"`, `color_autofix: "#1d4ed8"`, `color_fixfailed: "#c2410c"`.
- Badges and labels: `badge_pass: "PASS ✔"`, `badge_warn: "WARN !"`, `badge_fail: "FAIL ✖"`, `badge_autofix: "AUTO-FIXED ⚙"`.

### 6. `vars/api_regex.yml`
Must define regex patterns for cluster context verification:
- `desired_cluster_api_regex: '^https://api\.aro-[a-zA-Z0-9-]+\.[a-zA-Z0-9.-]+:6443/?$'`

---

## Verification Checklist

- [ ] All 6 YAML variable files exist in `playbooks/vars/`.
- [ ] Every file begins with the mandatory `# Targets: Ansible 2.7.17 / 2.14.18` header block.
- [ ] No plaintext passwords or real tokens appear in any file.
- [ ] Auto-remediation toggles are defined in `vars/upgrade.yml`.
- [ ] `.gitkeep` files present in `logs/`, `output/`, and `snapshots/`.
- [ ] `scripts/cli_helpers.sh` stub file is present.
- [ ] All YAML files pass syntax validation.
