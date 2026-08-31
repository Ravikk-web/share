# Unit 08: API Readiness Roles (`api_check`, `api_readiness`)

## Goal

Build `api_check` (confirm current cluster API-server context matches the expected cluster) and `api_readiness` (confirm the API server is reachable and ready), the first two prevalidation building blocks.

## Design

- **System boundary:** `playbooks/roles/api_check`, `playbooks/roles/api_readiness`.
- Read-only; both feed a structured PASS/FAIL result into `health_summary`.
- `api_check` is a HARD context guard; `api_readiness` confirms responsiveness before heavier checks.

## Implementation

### `api_check/tasks/main.yml`
`oc whoami --show-server` → validate against `desired_cluster_api_regex`; `fail:` on mismatch naming observed vs expected. `changed_when: false`.

### `api_readiness/tasks/main.yml`
`oc get --raw='/readyz'` (or `oc get clusterversion`) → assert healthy response; `failed_when` on non-ready. Record PASS into `health_summary` via `set_fact`.

### Defaults
Regex and optional overrides carry `| default('')`.

## Dependencies

- Unit 03 (`login`), Unit 01 (`api_regex`)
- oc, jq

## Verify when done

- [ ] `api_check` validates context against regex; mismatch → `fail:`
- [ ] `api_readiness` confirms API readiness and records PASS
- [ ] Reads `changed_when: false`; explicit `failed_when:`
- [ ] Results appended to `health_summary`
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
