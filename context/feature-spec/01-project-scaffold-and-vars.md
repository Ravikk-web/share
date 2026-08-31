# Unit 01: Project Scaffold & Variable Inputs

## Goal

Create the full `playbooks/` directory tree (`vars/ roles/ tasks/ templates/ logs/ output/ snapshots/`) and all `vars/` example files (secrets as variable references, SMTP, HTML/report vars, log paths, API regex, and the `upgrade_path` list) so every later unit has a stable home and a single source of inputs.

## Design

- **System boundary:** `playbooks/` root + `playbooks/vars/` (inputs only, no logic).
- Folder layout is fixed and matches `architecture.md`: only the six main files (`00_Run.sh`, `main.yml`, `01`–`05`) live at the root; everything else is scaffolding.
- All values are declarative. No `oc`/`jq` calls, no `when:`/`fail:` logic in `vars/`.
- Secrets follow the variable-reference pattern (`password: "{{ vault_cluster_d01_password }}"`) so the later Conjur Vault swap is source-only.
- Thresholds and cadences live here as named vars (capacity `<90%`, poll `2m`, timeout `90m`, heartbeat `20m`) — never as literals in tasks. Reference `ui-context.md` colour tokens for the HTML vars file.

## Implementation

### Directory tree
Create `playbooks/{vars,roles,tasks,templates,logs,output,snapshots}`. Add a `.gitkeep` to `logs/`, `output/`, `snapshots/` so empty dirs are tracked. Root holds placeholder `main.yml` (built in Unit 2) and the phase files as they land.

### `vars/secrets.yml`
Cluster list with `name`, `api_url`, `username`, and `password` as `{{ vault_* }}` references. Include a header comment: never commit real credentials, `no_log: true` enforced at task level, Conjur-swap note.

### `vars/smtp.yml`
`smtp_host`, `smtp_port` (default 25), `mail_from`, `mail_to` (recipient list), and the heartbeat/alert subject prefixes.

### `vars/report_vars.yml`
Colour tokens (green/amber/red/neutral/surface/page-bg/border/heading hex from `ui-context.md`), report title, org/footer strings, and status glyphs (`✔ ! ✖`).

### `vars/paths.yml`
Dynamic path anchors derived from `playbook_dir` at runtime: `log_dir`, `output_dir`, `snapshot_dir`, `kubeconfig_path`. Values are Jinja expressions resolved in-play, documented here.

### `vars/api_regex.yml`
`desired_cluster_api_regex` and the `cluster_name` extraction regex from the API URL.

### `vars/upgrade.yml`
`upgrade_path: []` (ordered target versions, user-supplied), plus thresholds: `max_cpu_percent: 90`, `max_memory_percent: 90`, `poll_interval_minutes: 2`, `hop_timeout_minutes: 90`, `heartbeat_minutes: 20`, `fail_on_zero_disruption_pdb`, `allowed_unschedulable_nodes: []`.

### File headers
Every `.yml` opens with `# Targets Ansible 2.7.17. # MIGRATION 2.14: <notes>` comment.

## Dependencies

- none (first unit)
- oc | jq | sendmail | shell available on the RHEL 8 jump server (runtime only, not built here)

## Verify when done

- [ ] Full `playbooks/` tree exists with all seven subfolders
- [ ] All six `vars/` files present and load without error
- [ ] Secrets use `{{ vault_* }}` references only — no inline credentials
- [ ] Thresholds/cadences present as named vars, not literals
- [ ] Every file carries the 2.7.17 header + `# MIGRATION 2.14:` note
- [ ] `| default('')` documented for optional vars
- [ ] `ansible-inventory`/`--syntax-check` friendly (valid YAML)
- [ ] progress-tracker.md updated
