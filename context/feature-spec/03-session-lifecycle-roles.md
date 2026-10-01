# Unit 03: Session Lifecycle Roles (`login`, `logout`)

> **Revision 2026-10-01 (review remediation)** — Login passes the password on stdin, does not retry authentication failures, and verifies API URL, optional `cluster_id` pin and `api_regex`. Later phases log in only without an active session; the monitor logs in again on Unauthorized; logout removes the kubeconfig. See `architecture.md` → Auth.

## Goal

Build the `login` and `logout` roles to establish a single authenticated OpenShift session at the start of the upgrade workflow and guarantee complete token revocation and kubeconfig removal upon workflow completion or any failure.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/login` and `playbooks/roles/logout`.
- **Single Login Contract**: `login` executes once during Phase 01. The generated kubeconfig is retained and reused across all subsequent phases (including Phase 06 operator upgrades).
- **Guaranteed Teardown**: `logout` is idempotent and safe to execute even after a failed login or unauthenticated session. Called in the `always:` block of every phase playbook.
- **Dedicated Kubeconfig**: The kubeconfig is isolated to `playbooks/.kubeconfig-<cluster>` — it never mutates or relies on the user's default `~/.kube/config`.
- **Zero Credential Leaks**: Credentials are provided via variable references with `no_log: true`.

---

## Implementation Details

### 1. `roles/login/`
- **`defaults/main.yml`**:
  ```yaml
  kubeconfig_path: "{{ playbook_dir }}/.kubeconfig-{{ cluster_name | default('default') }}"
  desired_cluster_api_regex: "^https://api\\.[a-zA-Z0-9.-]+:6443/?$"
  ```
- **`tasks/main.yml`**:
  1. Discover `oc` binary path (`/usr/local/bin/oc` or system PATH).
  2. Resolve cluster endpoint and credentials supporting both flat (`cluster_*`), dictionary (`cluster.*`), and inventory maps (`clusters[...]`).
  3. Validate that `cluster_name` is set and credentials exist in facts.
  4. Execute `oc login` with `shell: |` using bash, `--username="..."`, `--password="..."`, `"{{ cluster_api_url }}"`, `--kubeconfig={{ kubeconfig_path }}`, and `--insecure-skip-tls-verify=true` with `no_log: true`.
  5. Register login result; fail explicitly if returncode != 0, naming the cluster URL.
  6. Verify server identity: `{{ oc_binary }} whoami --show-server --kubeconfig={{ kubeconfig_path }}`.
  7. Assert that the returned server matches `desired_cluster_api_regex` (`^https://api\.[a-zA-Z0-9.-]+:6443/?$`).
  8. Export `KUBECONFIG` environment fact for child tasks.

### 2. `roles/logout/`
- **`defaults/main.yml`**:
  ```yaml
  kubeconfig_path: "{{ playbook_dir }}/.kubeconfig-{{ cluster_name | default('default') }}"
  ```
- **`tasks/main.yml`**:
  1. Revoke active session token via `oc logout --kubeconfig={{ kubeconfig_path }}` with `failed_when: false` and `changed_when: false`.
  2. Remove the temporary kubeconfig file from disk using `file: path={{ kubeconfig_path }} state=absent`.
  3. Unset `KUBECONFIG` environment facts to prevent token leakage.
  4. Output clean debug confirmation: "Session closed and kubeconfig removed for cluster {{ cluster_name }}."

---

## Exception Handling & Teardown Contract

- `login` must handle authentication failure without exposing passwords. If `oc login` fails, capture error message and trigger the caller's `rescue:` block.
- `logout` must never fail. All commands inside `logout` use `failed_when: false` and ignore errors, ensuring session cleanup never masks the underlying failure reason.

---

## Verification Checklist

- [ ] `oc login` uses `no_log: true` and writes to custom `kubeconfig_path`.
- [ ] Active cluster server is verified against `desired_cluster_api_regex`.
- [ ] `oc logout` revokes token and removes `.kubeconfig-<cluster>` file.
- [ ] `logout` executes cleanly even if `.kubeconfig` file does not exist.
- [ ] Dual-version headers present in both roles.
