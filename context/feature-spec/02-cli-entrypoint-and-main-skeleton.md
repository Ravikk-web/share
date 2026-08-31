# Unit 02: CLI Entrypoint + `main.yml` Skeleton

## Goal

Build `00_Run.sh` as the robust CLI base (dynamic paths, directory creation, input capture, confirmation summary, live + logged execution, sensible exit codes) and a runnable-but-empty `main.yml` that it invokes.

## Design

- **System boundary:** `playbooks/` root (`00_Run.sh`, `main.yml`).
- `00_Run.sh` derives every path from its own location — nothing machine-specific hardcoded. Uses `set -euo pipefail`.
- Terminal output is minimal and colour-coded (green/amber/red) using the same status convention as reports.
- `main.yml` is a valid playbook that prints a banner and exits 0 — a placeholder the later phase-wiring unit fills in.

## Implementation

### Path bootstrap
`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`; derive `LOG_DIR`, `OUTPUT_DIR`, `SNAPSHOT_DIR`; `mkdir -p` each if missing.

### Input capture
Accept `--cluster <name>` and `--path "4.18.x,4.19.x,4.20.x"` args, or prompt interactively if absent. Parse the comma list into an ordered `upgrade_path`. Optional `--dry-run` flag (open question — validate + prevalidate only).

### Confirmation summary
Print cluster, ordered hop list, log/output/snapshot paths, and Ansible version detected. Require an explicit `y` to proceed (skippable with `--yes`).

### Execution + logging
Run `ansible-playbook main.yml -e "cluster_name=... upgrade_path=[...]"`, tee stdout to `logs/<cluster>_<timestamp>.txt`. Return the playbook's exit code; map to named exit classes (0 ok, 10 prevalidation fail, 20 upgrade fail, 30 timeout).

### `main.yml` skeleton
Single play on `localhost`, `connection: local`, `gather_facts: true`. Prints a start banner via `debug`. Header comment with 2.7.17 target + migration notes. No phase imports yet.

## Dependencies

- Unit 01 (directory tree + `vars/` for path anchors)
- bash, ansible-playbook

## Verify when done

- [ ] `00_Run.sh` runs end to end and invokes `main.yml`
- [ ] All paths derived from script location; dirs auto-created
- [ ] Args and interactive prompt both work; confirmation gate enforced
- [ ] Live output shown AND written to `logs/*.txt`
- [ ] Exit codes are deterministic and documented
- [ ] `set -euo pipefail`; no secrets echoed
- [ ] `main.yml` passes `ansible-playbook --syntax-check` on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
