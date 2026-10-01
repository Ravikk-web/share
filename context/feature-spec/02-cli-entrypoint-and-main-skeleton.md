# Unit 02: CLI Entrypoint (`00_Run.sh`), Helper Library & `main.yml` Skeleton

> **Revision 2026-10-01 (review remediation)** — PROD confirmation can no longer be bypassed by `--yes`; flock run lock; static path validation; change scope from the selected phases; exit code read from `logs/<cluster>_<ts>.status` (5 / 10 / 20 / 25 / 30 / 35 / 99). `main.yml` is now phase imports plus one close-out play (summary mail + logout); the intercept plays were removed. See `Documentation.md` §6.

## Goal

Build the complete, robust CLI operational surface (`00_Run.sh`), the sourced shell display library (`scripts/cli_helpers.sh`), and the top-level orchestrator skeleton (`main.yml`) implementing all 14 CLI improvements, pre-flight checks, interactive selection menus, PID run locks, and post-run summaries.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/00_Run.sh`, `playbooks/scripts/cli_helpers.sh`, and `playbooks/main.yml`.
- **Pre-Flight Validation**: Fail fast at the CLI level before invoking Ansible if essential tools (`oc`, `jq`, `ansible-playbook`, `bash`) or configuration files are missing/malformed.
- **Interactive Experience**: Provide clean ANSI box-drawn selection menus for target clusters, upgrade paths (global/cluster/custom), and execution modes.
- **Concurrency Safety**: Enforce a PID lock file (`/tmp/aro-upgrade-<cluster>.lock`) to block accidental parallel executions.
- **Structured Exit Codes**: Return deterministic exit codes (0 = success, 1 = usage, 2 = cancelled, 3 = config missing, 10 = prevalidation failed, 20 = upgrade failed, 30 = timeout, 99 = unexpected).
- **Orchestrator Skeleton**: `main.yml` acts as the root playbook, loading all vars files and establishing the initial execution facts.

---

## Implementation Details

### 1. Sourced Library (`playbooks/scripts/cli_helpers.sh`)
Contains reusable Bash functions:
- Terminal color helpers (`C_GREEN`, `C_AMBER`, `C_RED`, `C_CYAN`, `C_RESET`).
- Message formatters: `msg_ok()`, `msg_warn()`, `msg_err()`, `msg_info()`, `msg_step()`.
- Box drawing primitives: `draw_box_header()`, `draw_box_row()`, `draw_box_footer()`.
- `print_banner()`: Displays the magenta ASCII art banner and project subtitle.
- `render_menu()`: Renders a numbered 72-column selection box.
- `render_post_run_summary()`: Formats the final execution table (phases, durations, check counts, report paths).

### 2. CLI Entrypoint (`playbooks/00_Run.sh`)
Flow of execution:
1. **Bootstrap & Traps**: Sets `set -euo pipefail`. Traps `EXIT INT TERM` to clean up the PID lock file and reset terminal settings.
2. **Flag Parsing**:
   - `--cluster <name>`: Target cluster override.
   - `--path "4.18.x,4.19.x"`: Upgrade path override.
   - `--dry-run`: Enables dry-run validation.
   - `--yes`: Skips interactive confirmations.
   - `--no-menu`: Skips interactive menus, using configured defaults.
   - `--skip-to-phase <NN>`: Jumps directly to a specific phase (e.g. `05` or `06`).
   - `--resume`: Detects last completed hop from logs and resumes.
   - `--verbose` / `-v`, `--quiet`: Controls Ansible verbosity.
3. **Pre-Flight Dependency Validation**:
   - Confirms `ansible-playbook`, `oc`, `jq`, and `bash >= 4` are executable. Exits with code 1 on failure.
4. **Vars File Validation**:
   - Parses all 6 YAML files using Python `yaml.safe_load`. Validates cluster existence, non-empty paths, and required keys.
5. **Interactive Selection Menus** (unless bypassed):
   - **Cluster Menu**: Extracted from `vars/secrets.yml`. Shows configured clusters, default marked with `★`.
   - **Upgrade Path Menu**: Shows global path, cluster-specific path, and custom entry option.
   - **Run Mode Menu**: Choose Full Upgrade, Dry Run, Pre-check Only, or Status Check.
6. **Visual Hop Journey & Risk Confirmation**:
   - Prints visual sequence: `4.14.12 ──▶ 4.14.40 ──▶ 4.15.35`.
   - Displays duration estimate, hop count, and risk tier (LOW/MEDIUM/HIGH).
   - If cluster is PROD, requires typing `UPGRADE` to proceed.
7. **Concurrency Lock**:
   - Verifies `/tmp/aro-upgrade-<cluster>.lock` does not exist (or PID is dead). Writes current PID.
8. **Execution & Logging**:
   - Builds extra-vars as a single JSON string: `-e '{"cluster_name":"...","upgrade_path":[...],"dry_run":false}'`.
   - Executes `ansible-playbook playbooks/main.yml`, teeing stdout/stderr live to `logs/<cluster>_<ts>.txt`.
9. **Post-Run Summary**:
   - Evaluates playbook exit code, formats duration, prints artifact links, removes lock file, and exits with mapped code.

### 3. Orchestrator Skeleton (`playbooks/main.yml`)
- Play 1 (`localhost`, `connection: local`):
  - Loads all 6 `vars_files`.
  - Validates `cluster_name` and `upgrade_path` are non-empty.
  - Displays formatted run banner and parameters.
  - Declares commented placeholder imports for Phases 01 through 06.

---

## Verification Checklist

- [ ] `00_Run.sh` is executable (`chmod +x`).
- [ ] Pre-flight dependency check flags missing binaries properly.
- [ ] Concurrency lock file blocks duplicate runs on the same cluster.
- [ ] Menus render cleanly within 72 columns.
- [ ] `main.yml` passes `ansible-playbook --syntax-check`.
- [ ] Extra-vars are passed as valid JSON object strings.
- [ ] Exit codes map correctly (0, 1, 2, 3, 10, 20, 30, 99).
