# Unit 03: Session Lifecycle Roles (`login`, `logout`)

## Goal

Build the `login` role (single `oc login`, kubeconfig written under `playbook_dir`) and the `logout` role (session teardown / kubeconfig invalidation), verified together as the login-once / logout-on-failure foundation.

## Design

- **System boundary:** `playbooks/roles/login`, `playbooks/roles/logout`.
- Login happens once; all later phases reuse the session — no re-login per phase.
- Logout is idempotent and safe to call from an `always:` block even if login failed.
- Kubeconfig path derived from `playbook_dir`; removed/invalidated on logout.

## Implementation

### `login/tasks/main.yml`
`command: oc login <api_url> -u <username> -p <password> --kubeconfig <kubeconfig_path>`. `no_log: true` (password). `register` result; `failed_when: rc != 0` with a clear message naming the cluster. Confirm context with `oc whoami --show-server` and validate it against `desired_cluster_api_regex`.

### `login/defaults/main.yml`
`kubeconfig_path` default derived from `playbook_dir`; empty defaults for optional overrides with `| default('')`.

### `logout/tasks/main.yml`
`command: oc logout --kubeconfig <kubeconfig_path>` with `failed_when: false` (never fail teardown). Then remove/invalidate the kubeconfig file. `changed_when: false` on the read parts.

### Migration notes
Short module names (`command`). `# MIGRATION 2.14:` note on Jinja strictness for optional overrides.

## Dependencies

- Unit 01 (`vars/secrets.yml`, `vars/paths.yml`, `vars/api_regex.yml`)
- oc CLI

## Verify when done

- [ ] `login` establishes a session and writes kubeconfig under `playbook_dir`
- [ ] Password task carries `no_log: true`
- [ ] Context validated against `desired_cluster_api_regex`
- [ ] `logout` never fails teardown and removes the kubeconfig
- [ ] Safe to call `logout` even after a failed login
- [ ] Short module names; `| default('')` on optionals; no `warn:`
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
