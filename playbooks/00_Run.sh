#!/usr/bin/env bash
# ============================================================================
# CLI Entrypoint — ARO Cluster Upgrade Automation
# ============================================================================
# Targets: Bash 4.2+ (RHEL 8 jump server)
# Purpose: Single one-touch operational CLI surface (00_Run.sh) providing
#          pre-flight tool validation, YAML configuration schema checks,
#          static upgrade-path validation, interactive cluster / mode / path
#          menus, a mutation-aware production safety gate, a per-cluster run
#          lock that only its owner can release, live-tee'd execution logging,
#          and structured exit codes read from the run status file that the
#          playbooks write on failure.
# Role / Playbook Dependencies: scripts/cli_helpers.sh, vars/*.yml, main.yml,
#                               01_Policy_Check.yaml … 06_Operator_Upgrade.yaml
# Gate Type: N/A (CLI Entrypoint & Safety Controls)
# Outputs: Console terminal UI, logs/<cluster>_<ts>.txt run log, structured exit codes
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# System & Path Derivations (Anchored strictly to script directory)
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}"

# Ensure write-only operational directories exist
mkdir -p "${BASE_DIR}/logs" "${BASE_DIR}/output" "${BASE_DIR}/snapshots"

# Source CLI helper library
if [[ -f "${BASE_DIR}/scripts/cli_helpers.sh" ]]; then
    # shellcheck source=scripts/cli_helpers.sh
    source "${BASE_DIR}/scripts/cli_helpers.sh"
else
    echo "ERROR: Missing required helper library: ${BASE_DIR}/scripts/cli_helpers.sh" >&2
    exit 3
fi

# ----------------------------------------------------------------------------
# Execution State & Default Parameters
# ----------------------------------------------------------------------------
START_SECONDS=$SECONDS
TARGET_CLUSTER=""
CLI_PATH=""
DRY_RUN=false
AUTO_YES=false
NO_MENU=false
SKIP_TO_PHASE=""
STOP_AFTER_PHASE=""
TARGET_ISOLATED_PHASE=""
AUTO_REMEDIATION_MODE=""
DRY_RUN_INCLUDE_POSTVAL=""
MAIL_TO_CLI=""
RESUME=false
VERBOSE=false
QUIET=false
SKIP_CGROUP_CHECK=false
SKIP_OPERATOR_UPGRADE=false
DO_CLEAN_ARTIFACTS=false
PYTHON_CMD=""
LOCK_FILE=""
IS_MUTATING_UPGRADE=true
MUTATION_REASONS=()

# ----------------------------------------------------------------------------
# Signal Trap & Run Lock Teardown
# ----------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    # Why: release_run_lock only releases a lock this process acquired. A run that
    #      was rejected by the lock must never delete the active run's lock.
    release_run_lock
    # Reset terminal settings if in interactive TTY
    if [[ -t 0 ]]; then
        stty echo 2>/dev/null || true
    fi
    exit "${exit_code}"
}
trap cleanup EXIT INT TERM

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
# Normalizes phase numbers to two digits ("5" -> "05").
# Why: 10# forces base-10 so "08"/"09" are not rejected as invalid octal.
normalize_phase() {
    local raw="$1"
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
        printf '%02d' "$((10#$raw))"
    else
        printf '%s' "$raw"
    fi
}

# Reads a top-level key from the validated vars JSON.
vars_get() {
    "$PYTHON_CMD" -c 'import sys, json
data = json.loads(sys.argv[1])
value = data.get(sys.argv[2], "")
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)' "$VARS_JSON" "$1"
}

# ----------------------------------------------------------------------------
# CLI Help Screen
# ----------------------------------------------------------------------------
show_help() {
    print_banner
    cat << 'EOF'
Usage: ./00_Run.sh [OPTIONS]

One-touch operational entrypoint for sequential Y-stream OpenShift upgrades
and automated OLM operator upgrades.

Options:
  -c, --cluster <name>      Target cluster name (defined in vars/secrets.yml)
  -p, --path <versions>     Comma-separated upgrade path (e.g. "4.15.35,4.16.18")
  -d, --dry-run             Read-only validation: Phases 01, 02 and 05 with no cluster changes
      --pre-check           Phases 01 & 02 with auto-remediation, then stop (can change the cluster)
      --post-check          Run the post-upgrade validation gate (Phase 05) only
      --phase <NN>          Run a single phase in isolation (01, 02, 03, 05, 06); add --dry-run for read-only
      --clean, --clear      Purge generated logs, output reports, and snapshots (refused while a run is active)
  -y, --yes                 Non-interactive confirmation (PROD runs that change the cluster still require typing UPGRADE)
      --no-menu             Bypass interactive selection menus, using configured defaults
  -s, --skip-to-phase <NN>  Start at a specific phase (e.g. 02, 05, 06)
      --stop-after-phase <NN> Stop after a specific phase (e.g. 02, 05)
  -m, --mail-to <email>     Send informational mails to these recipients instead of the configured lists
                            (comma-separated); failure/degradation alerts still go to alert_mail_to as well
  -r, --resume              Re-run an interrupted upgrade; hops the cluster has already reached are skipped
      --skip-cgroup         Skip the CGroup v2 compatibility check and remediation
      --skip-operator-upgrade Skip operator InstallPlan approvals in Phase 06 (compatibility scan and validation still run)
  -v, --verbose             Enable verbose Ansible output (-v)
  -q, --quiet               Suppress the banner and guidance boxes
  -h, --help                Display this help screen and exit

Exit Codes:
  0   Success
  1   Usage or Pre-flight Dependency Error, or cluster locked by another run
  2   User Cancelled
  3   Configuration or Upgrade Path Invalid
  5   Policy Check / Upgrade Path Validation Failed (Phase 01)
  10  Prevalidation Gate Failed (Phase 02)
  20  Upgrade Hop Failed (Phase 03/04)
  25  Postvalidation Gate Failed (Phase 05)
  30  Upgrade Hop Stopped Progressing / Timed Out (Phase 04)
  35  Operator Upgrade / Validation Failed (Phase 06)
  99  Unexpected Execution Error

Examples:
  ./00_Run.sh
  ./00_Run.sh --help
  ./00_Run.sh --clean
  ./00_Run.sh --cluster cluster_d01 --phase 01
  ./00_Run.sh --cluster cluster_d01 --phase 02 --dry-run
  ./00_Run.sh --cluster cluster_d01 --path "4.14.40,4.15.35,4.16.18"
  ./00_Run.sh --cluster cluster_d01 --dry-run
  ./00_Run.sh --cluster cluster_d01 --pre-check --yes
  ./00_Run.sh --cluster cluster_d01 --skip-to-phase 05 --yes
EOF
}

# ----------------------------------------------------------------------------
# Flag & Argument Parsing
# ----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean|--clear|--clear-artifacts)
            DO_CLEAN_ARTIFACTS=true
            shift
            ;;
        --phase)
            [[ -n "${2:-}" ]] || { msg_err "Flag '$1' requires a phase number (01, 02, 03, 05 or 06)."; exit 1; }
            TARGET_PHASE="$(normalize_phase "$2")"
            case "$TARGET_PHASE" in
                01|02|03|05|06) ;;
                04) msg_err "Phase 04 (live monitoring) runs inside Phase 03. Use --phase 03."; exit 1 ;;
                *)  msg_err "Unsupported phase '$2'. Use 01, 02, 03, 05 or 06."; exit 1 ;;
            esac
            SKIP_TO_PHASE="$TARGET_PHASE"
            STOP_AFTER_PHASE="$TARGET_PHASE"
            shift 2
            ;;
        -c|--cluster)
            [[ -n "${2:-}" ]] || { msg_err "Flag '$1' requires a cluster name."; exit 1; }
            TARGET_CLUSTER="$2"
            shift 2
            ;;
        -p|--path)
            [[ -n "${2:-}" ]] || { msg_err "Flag '$1' requires a comma-separated path."; exit 1; }
            CLI_PATH="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            AUTO_REMEDIATION_MODE="false"
            shift
            ;;
        --pre-check|--pre-check-only)
            DRY_RUN=true
            STOP_AFTER_PHASE="02"
            AUTO_REMEDIATION_MODE="true"
            # Why: pre-check stops after Phase 02; the read-only Phase 05 audit is a dry-run feature.
            DRY_RUN_INCLUDE_POSTVAL="false"
            shift
            ;;
        --post-check|--post-check-only)
            SKIP_TO_PHASE="05"
            STOP_AFTER_PHASE="05"
            shift
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        --no-menu)
            NO_MENU=true
            shift
            ;;
        -s|--skip-to-phase)
            [[ -n "${2:-}" ]] || { msg_err "Flag '$1' requires a phase number (e.g. 02)."; exit 1; }
            SKIP_TO_PHASE="$(normalize_phase "$2")"
            shift 2
            ;;
        --stop-after|--stop-after-phase)
            [[ -n "${2:-}" ]] || { msg_err "Flag '$1' requires a phase number (e.g. 02)."; exit 1; }
            STOP_AFTER_PHASE="$(normalize_phase "$2")"
            shift 2
            ;;
        -m|--mail-to)
            [[ -n "${2:-}" ]] || { msg_err "Flag '$1' requires an email address."; exit 1; }
            MAIL_TO_CLI="$2"
            shift 2
            ;;
        -r|--resume)
            RESUME=true
            shift
            ;;
        --skip-cgroup|--skip-cgroup-check)
            SKIP_CGROUP_CHECK=true
            shift
            ;;
        --skip-operator-upgrade|--skip-operator-upgrades)
            SKIP_OPERATOR_UPGRADE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            msg_err "Unknown option: $1"
            echo "Use ./00_Run.sh --help for available options." >&2
            exit 1
            ;;
    esac
done

# Handle manual operational artifact purge request (--clean / --clear)
if [[ "$DO_CLEAN_ARTIFACTS" == "true" ]]; then
    ACTIVE_RUNS="$(list_active_runs)"
    if [[ -n "$ACTIVE_RUNS" ]]; then
        # Why: purging during a run would delete its session kubeconfig, run log and baseline snapshot.
        msg_err "Refusing to purge artifacts while an upgrade run is active: ${ACTIVE_RUNS//$'\n'/, }"
        exit 1
    fi
    if [[ "$AUTO_YES" == "false" && -t 0 ]]; then
        printf "\n  Are you sure you want to delete all generated files in logs/, output/, and snapshots/? [y/N]: "
        read -r CLEAN_CONFIRM
        if [[ ! "$CLEAN_CONFIRM" =~ ^[yY]([eE][sS])?$ ]]; then
            msg_info "Cleanup cancelled by operator."
            exit 0
        fi
    fi
    purge_artifacts "${BASE_DIR}"
    exit 0
fi

# A matching start/stop phase is an isolated single-phase run.
if [[ -n "${SKIP_TO_PHASE}" && "${SKIP_TO_PHASE}" == "${STOP_AFTER_PHASE}" ]]; then
    TARGET_ISOLATED_PHASE="${SKIP_TO_PHASE}"
fi

# Isolated Phase 02 with --dry-run is a read-only prevalidation scan.
if [[ "${TARGET_ISOLATED_PHASE}" == "02" && "$DRY_RUN" == "true" ]]; then
    AUTO_REMEDIATION_MODE="false"
fi

# ----------------------------------------------------------------------------
# Pre-Flight Dependency Validation
# ----------------------------------------------------------------------------
# Confirms bash >= 4, python, ansible-playbook, oc and jq; warns on optional tools.
validate_dependencies() {
    local missing=0

    # 1. Check Bash version
    if (( BASH_VERSINFO[0] < 4 )); then
        msg_err "Bash version 4.2 or higher is required (detected: ${BASH_VERSION})."
        missing=1
    fi

    # 2. Check Python (used for YAML parsing and JSON formatting)
    local py_ok=0
    if python3 -c "import sys" >/dev/null 2>&1; then
        PYTHON_CMD="python3"
        py_ok=1
    elif python -c "import sys" >/dev/null 2>&1; then
        PYTHON_CMD="python"
        py_ok=1
    fi

    if (( py_ok == 0 )); then
        msg_err "A functional Python interpreter (python3 or python) was not found in PATH."
        missing=1
    fi

    # Allow mock testing in environments where tools are pending install
    if [[ "${ARO_MOCK_PREFLIGHT:-0}" == "1" ]]; then
        msg_warn "ARO_MOCK_PREFLIGHT=1: Bypassing external binary presence check."
        return 0
    fi

    # 3. Check required CLI binaries
    local required_tools=("ansible-playbook" "oc" "jq")
    local tool
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            msg_err "Required CLI executable '${tool}' not found in PATH."
            missing=1
        fi
    done

    if (( missing != 0 )); then
        msg_err "Pre-flight dependency validation failed. Please install the missing tools and re-run."
        exit 1
    fi

    # 4. Optional tools (warn only — the run continues without them)
    # Why: on ansible-core 2.14 the mail module ships in the community.general
    #      collection; without it every notification is skipped (never fatal).
    if ! ansible-doc -t module mail >/dev/null 2>&1; then
        msg_warn "Ansible 'mail' module not found (install the community.general collection). Email notifications will be skipped."
    fi
    if ! command -v curl >/dev/null 2>&1; then
        msg_warn "'curl' not found: the Phase 05 firing-alerts check will report UNKNOWN."
    fi
}

validate_dependencies

# ----------------------------------------------------------------------------
# Vars Schema & Content Validation (Python-based)
# ----------------------------------------------------------------------------
# Validates all 6 YAML files and returns defaults the CLI needs as JSON.
# Why: the validator always prints JSON with an "error" key on failure so the
#      real reason (missing file, YAML error, missing PyYAML) reaches the operator.
set +e
VARS_JSON=$("$PYTHON_CMD" -c '
import sys, os, json

def out(payload):
    print(json.dumps(payload))
    sys.exit(0)

try:
    import yaml
except ImportError:
    out({"error": "PyYAML package is required but not installed (pip install pyyaml)."})

class TolerantLoader(yaml.SafeLoader):
    pass

# Why: tolerate Ansible Vault (!vault) and other custom tags so encrypted values do not break the CLI.
TolerantLoader.add_multi_constructor("!", lambda loader, suffix, node: None)

base_dir = sys.argv[1]
vars_dir = os.path.join(base_dir, "vars")
required_files = ["upgrade.yml", "secrets.yml", "smtp.yml", "paths.yml", "report_vars.yml", "api_regex.yml"]

loaded = {}
for fname in required_files:
    fpath = os.path.join(vars_dir, fname)
    if not os.path.isfile(fpath):
        out({"error": "Missing required vars file: vars/{}".format(fname)})
    try:
        with open(fpath, "r") as handle:
            data = yaml.load(handle, Loader=TolerantLoader) or {}
    except Exception as exc:
        out({"error": "Failed to parse YAML in vars/{}: {}".format(fname, exc)})
    if not isinstance(data, dict):
        out({"error": "vars/{} must contain a YAML mapping (found {}).".format(fname, type(data).__name__)})
    loaded[fname] = data

upgrade_vars = loaded["upgrade.yml"]
clusters = loaded["secrets.yml"].get("clusters") or {}
if not isinstance(clusters, dict) or not clusters:
    out({"error": "No clusters configured in vars/secrets.yml (clusters dict is empty)."})

out({
    "error": "",
    "default_cluster": upgrade_vars.get("cluster_name", "") or "",
    "default_path": upgrade_vars.get("upgrade_path", []) or [],
    "cluster_paths": upgrade_vars.get("cluster_upgrade_paths", {}) or {},
    "auto_remediation_enabled": bool(upgrade_vars.get("auto_remediation_enabled", True)),
    "enable_developer_perspective": bool(upgrade_vars.get("enable_developer_perspective", True)),
    "clusters": clusters,
})
' "${BASE_DIR}" 2>&1)
VARS_RC=$?
set -e

CONFIG_ERROR=$("$PYTHON_CMD" -c 'import sys, json
try:
    print(json.loads(sys.argv[1]).get("error", ""))
except Exception:
    print("Validator produced unexpected output: " + sys.argv[1].strip()[-400:])' "$VARS_JSON")

if (( VARS_RC != 0 )) || [[ -n "$CONFIG_ERROR" ]]; then
    msg_err "Configuration validation failed: ${CONFIG_ERROR:-validator exited with code ${VARS_RC}}"
    exit 3
fi

# Extract parsed config values
DEFAULT_CLUSTER="$(vars_get default_cluster)"
DEFAULT_AUTO_REMEDIATION="$(vars_get auto_remediation_enabled)"
DEFAULT_ENABLE_DEV_PERSPECTIVE="$(vars_get enable_developer_perspective)"
CLUSTER_KEYS=$("$PYTHON_CMD" -c 'import sys, json; print(" ".join(json.loads(sys.argv[1]).get("clusters", {}).keys()))' "$VARS_JSON")

# If cluster was specified via flag, validate existence
if [[ -n "$TARGET_CLUSTER" ]]; then
    CLUSTER_VALID=$("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
cluster = sys.argv[2]
print("valid" if cluster in data.get("clusters", {}) else "invalid")
' "$VARS_JSON" "$TARGET_CLUSTER")

    if [[ "$CLUSTER_VALID" != "valid" ]]; then
        msg_err "Target cluster '${TARGET_CLUSTER}' is not defined in vars/secrets.yml."
        msg_info "Available clusters: ${CLUSTER_KEYS}"
        exit 3
    fi
fi

# Configured path for a cluster (global upgrade_path first, then per-cluster path).
configured_path_for() {
    "$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
hops = data.get("default_path", []) or data.get("cluster_paths", {}).get(sys.argv[2], [])
print(sys.argv[3].join(hops))
' "$VARS_JSON" "$1" "$2"
}

# ----------------------------------------------------------------------------
# Interactive Menus (When not in --no-menu mode and interactive TTY)
# ----------------------------------------------------------------------------
IS_INTERACTIVE=false
if [[ -t 0 && "$NO_MENU" == "false" ]]; then
    IS_INTERACTIVE=true
fi

if [[ "$IS_INTERACTIVE" == "true" ]]; then
    if [[ "$QUIET" == "false" ]]; then
        print_banner
        print_help_banner
    fi

    # 1. Cluster Selection Menu (if not specified via --cluster)
    if [[ -z "$TARGET_CLUSTER" ]]; then
        mapfile -t CLUSTER_ARR < <("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
for k, v in data.get("clusters", {}).items():
    v = v or {}
    tier = str(v.get("tier", "DEV")).upper()
    desc = v.get("display_name", k)
    print("{} ({}) — {}".format(k, tier, desc))
' "$VARS_JSON")

        mapfile -t CLUSTER_RAW_KEYS < <("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
for k in data.get("clusters", {}).keys():
    print(k)
' "$VARS_JSON")

        # Determine default index
        DEF_IDX=1
        for idx in "${!CLUSTER_RAW_KEYS[@]}"; do
            if [[ "${CLUSTER_RAW_KEYS[$idx]}" == "$DEFAULT_CLUSTER" ]]; then
                DEF_IDX=$((idx + 1))
                break
            fi
        done

        render_menu "Select Target OpenShift Cluster" "$DEF_IDX" "${CLUSTER_ARR[@]}"
        SELECTED_CHOICE="$MENU_CHOICE"
        TARGET_CLUSTER="${CLUSTER_RAW_KEYS[$((SELECTED_CHOICE - 1))]}"
        msg_ok "Selected cluster: ${C_BOLD}${TARGET_CLUSTER}${C_RESET}"
    fi

    # 2. Run Mode Selection Menu (if not specified via flags)
    if [[ "$DRY_RUN" == "false" && -z "$SKIP_TO_PHASE" && -z "$STOP_AFTER_PHASE" ]]; then
        MODE_OPTIONS=(
            "Full Upgrade (Phases 01 -> 06 End-to-End)"
            "Dry Run (Read-only: Phases 01, 02 and 05, no cluster changes)"
            "Pre-check Only (Phases 01 & 02 with auto-remediation)"
            "Post-check Only (Run Phase 05 Postvalidation Gate)"
            "Isolated Phase Execution (Run a single phase in isolation)"
            "Clean Operational Artifacts (Purge logs/, output/, snapshots/)"
        )

        render_menu "Select Execution Mode" 1 "${MODE_OPTIONS[@]}"
        MODE_CHOICE="$MENU_CHOICE"

        case "$MODE_CHOICE" in
            1)
                DRY_RUN=false
                SKIP_TO_PHASE=""
                STOP_AFTER_PHASE=""
                ;;
            2)
                DRY_RUN=true
                SKIP_TO_PHASE=""
                STOP_AFTER_PHASE=""
                AUTO_REMEDIATION_MODE="false"
                ;;
            3)
                DRY_RUN=true
                SKIP_TO_PHASE=""
                STOP_AFTER_PHASE="02"
                AUTO_REMEDIATION_MODE="true"
                DRY_RUN_INCLUDE_POSTVAL="false"
                ;;
            4)
                DRY_RUN=false
                SKIP_TO_PHASE="05"
                STOP_AFTER_PHASE="05"
                TARGET_ISOLATED_PHASE="05"
                ;;
            5)
                PHASE_SUB_OPTIONS=(
                    "Phase 01: Policy Check, Path Validation & Baseline Snapshot"
                    "Phase 02: 15-Check Prevalidation & Auto-Remediation Gate"
                    "Phase 03: Sequential Upgrade Hop Execution & Monitoring"
                    "Phase 05: Post-Upgrade Checks & Baseline Diff Validation"
                    "Phase 06: Operator Upgrades, Developer Console & Closeout"
                )
                render_menu "Select Isolated Phase to Execute" 1 "${PHASE_SUB_OPTIONS[@]}"
                case "$MENU_CHOICE" in
                    1) TARGET_ISOLATED_PHASE="01" ;;
                    2) TARGET_ISOLATED_PHASE="02" ;;
                    3) TARGET_ISOLATED_PHASE="03" ;;
                    4) TARGET_ISOLATED_PHASE="05" ;;
                    5) TARGET_ISOLATED_PHASE="06" ;;
                esac

                EXEC_TYPE_SUB_OPTIONS=(
                    "Final / Live Execution (Perform operations for Phase ${TARGET_ISOLATED_PHASE})"
                    "Dry Run Mode (Read-only validation without cluster changes)"
                )
                render_menu "Select Execution Type for Phase ${TARGET_ISOLATED_PHASE}" 1 "${EXEC_TYPE_SUB_OPTIONS[@]}"
                ISOLATED_TYPE_CHOICE="$MENU_CHOICE"

                SKIP_TO_PHASE="$TARGET_ISOLATED_PHASE"
                STOP_AFTER_PHASE="$TARGET_ISOLATED_PHASE"

                if (( ISOLATED_TYPE_CHOICE == 1 )); then
                    DRY_RUN=false
                    msg_ok "Configured isolated ${C_BOLD}Phase ${TARGET_ISOLATED_PHASE}${C_RESET} in ${C_GREEN_BOLD}FINAL/LIVE${C_RESET} mode."
                else
                    DRY_RUN=true
                    if [[ "$TARGET_ISOLATED_PHASE" == "02" ]]; then
                        AUTO_REMEDIATION_MODE="false"
                    fi
                    msg_ok "Configured isolated ${C_BOLD}Phase ${TARGET_ISOLATED_PHASE}${C_RESET} in ${C_CYAN_BOLD}DRY RUN${C_RESET} mode."
                fi
                ;;
            6)
                ACTIVE_RUNS="$(list_active_runs)"
                if [[ -n "$ACTIVE_RUNS" ]]; then
                    msg_err "Refusing to purge artifacts while an upgrade run is active: ${ACTIVE_RUNS//$'\n'/, }"
                    exit 1
                fi
                printf "\n  Are you sure you want to delete all generated files in logs/, output/, and snapshots/? [y/N]: "
                read -r CLEAN_CONFIRM
                if [[ "$CLEAN_CONFIRM" =~ ^[yY]([eE][sS])?$ ]]; then
                    purge_artifacts "${BASE_DIR}"
                else
                    msg_info "Cleanup cancelled by operator."
                fi
                exit 0
                ;;
        esac
    fi

    # 3. Upgrade Path Selection Menu (if not specified via --path)
    if [[ -z "$CLI_PATH" ]]; then
        DEF_PATH_STR="$(configured_path_for "$TARGET_CLUSTER" " ──▶ ")"
        [[ -n "$DEF_PATH_STR" ]] || DEF_PATH_STR="None"

        if [[ "$TARGET_ISOLATED_PHASE" == "05" || "$TARGET_ISOLATED_PHASE" == "06" ]]; then
            PATH_OPTIONS=(
                "Current Live Cluster Version (Validate settled health at current version)"
                "Configured Path (${DEF_PATH_STR})"
                "Custom Path (Specify comma-separated hops)"
            )
            render_menu "Select Validation Target for ${TARGET_CLUSTER}" 1 "${PATH_OPTIONS[@]}"
            PATH_CHOICE="$MENU_CHOICE"
            if (( PATH_CHOICE == 1 )); then
                CLI_PATH="current"
            elif (( PATH_CHOICE == 2 )); then
                CLI_PATH="$(configured_path_for "$TARGET_CLUSTER" ",")"
            else
                printf "\n  Enter comma-separated version hops (e.g. 4.14.40,4.15.35,4.16.18): "
                read -r CLI_PATH
                [[ -n "$CLI_PATH" ]] || { msg_err "Custom upgrade path cannot be empty."; exit 1; }
            fi
        else
            PATH_OPTIONS=(
                "Configured Path (${DEF_PATH_STR})"
                "Custom Path (Specify comma-separated hops)"
            )
            render_menu "Select Upgrade Path for ${TARGET_CLUSTER}" 1 "${PATH_OPTIONS[@]}"
            PATH_CHOICE="$MENU_CHOICE"

            if (( PATH_CHOICE == 1 )); then
                CLI_PATH="$(configured_path_for "$TARGET_CLUSTER" ",")"
            else
                printf "\n  Enter comma-separated version hops (e.g. 4.14.40,4.15.35,4.16.18): "
                read -r CLI_PATH
                [[ -n "$CLI_PATH" ]] || { msg_err "Custom upgrade path cannot be empty."; exit 1; }
            fi
        fi
    fi
fi

# Fallback to configured defaults if not interactive and not passed via flags
if [[ -z "$TARGET_CLUSTER" ]]; then
    TARGET_CLUSTER="$DEFAULT_CLUSTER"
    [[ -n "$TARGET_CLUSTER" ]] || { msg_err "No cluster specified and no default found in vars/upgrade.yml."; exit 3; }
fi

if [[ -z "$CLI_PATH" ]]; then
    if [[ "$TARGET_ISOLATED_PHASE" == "05" ]]; then
        CLI_PATH="current"
    else
        CLI_PATH="$(configured_path_for "$TARGET_CLUSTER" ",")"
        [[ -n "$CLI_PATH" ]] || { msg_err "No upgrade path specified and no default found for cluster '${TARGET_CLUSTER}' in vars/upgrade.yml."; exit 3; }
    fi
fi

# ----------------------------------------------------------------------------
# Static Upgrade Path Validation
# ----------------------------------------------------------------------------
# Why: catch typos and illegal journeys before touching the cluster. Phase 01
#      re-validates every hop against the live cluster and the OpenShift Update
#      Service graph; this is the offline part: X.Y.Z format, strictly ascending,
#      same major, and never skipping a minor version.
ALLOW_CURRENT=false
if [[ "$TARGET_ISOLATED_PHASE" == "05" || "$TARGET_ISOLATED_PHASE" == "06" ]]; then
    ALLOW_CURRENT=true
fi

PATH_OUTPUT=$("$PYTHON_CMD" -c '
import sys, re
raw, allow_current = sys.argv[1], sys.argv[2] == "true"
hops = [h.strip() for h in raw.split(",") if h.strip()]
if not hops:
    print("ERROR:the upgrade path is empty.")
    sys.exit(0)
if hops == ["current"]:
    if allow_current:
        print("current")
    else:
        print("ERROR:\"current\" is only valid for --post-check or an isolated Phase 05 / 06 run.")
    sys.exit(0)
pattern = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
parsed = []
for hop in hops:
    match = pattern.match(hop)
    if not match:
        print("ERROR:invalid version \"{}\" (expected X.Y.Z, e.g. 4.16.18).".format(hop))
        sys.exit(0)
    parsed.append(tuple(int(part) for part in match.groups()))
for index in range(1, len(parsed)):
    prev, cur = parsed[index - 1], parsed[index]
    if cur <= prev:
        print("ERROR:hops must be strictly ascending ({} -> {}).".format(hops[index - 1], hops[index]))
        sys.exit(0)
    if cur[0] != prev[0]:
        print("ERROR:major version changes are not supported ({} -> {}).".format(hops[index - 1], hops[index]))
        sys.exit(0)
    if cur[1] - prev[1] > 1:
        print("ERROR:{} -> {} skips minor version {}.{}; add a hop for it.".format(hops[index - 1], hops[index], prev[0], prev[1] + 1))
        sys.exit(0)
print("\n".join(hops))
' "$CLI_PATH" "$ALLOW_CURRENT")

if [[ "$PATH_OUTPUT" == ERROR:* ]]; then
    msg_err "Invalid upgrade path '${CLI_PATH}': ${PATH_OUTPUT#ERROR:}"
    exit 3
fi
mapfile -t UPGRADE_HOPS <<< "$PATH_OUTPUT"

# Resolve cluster tier
CLUSTER_TIER=$("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
cluster = data.get("clusters", {}).get(sys.argv[2], {}) or {}
print(str(cluster.get("tier", "DEV")).upper())
' "$VARS_JSON" "$TARGET_CLUSTER")

# ----------------------------------------------------------------------------
# Resume (--resume)
# ----------------------------------------------------------------------------
# Why: hops are idempotent — each hop compares the live cluster version with its
#      target and is skipped when already reached, so resuming is simply a re-run.
if [[ "$RESUME" == "true" ]]; then
    msg_info "Resume requested: hops the cluster has already reached are detected live and skipped automatically."
fi

# ----------------------------------------------------------------------------
# Run Mode Label & Cluster Change Scope
# ----------------------------------------------------------------------------
RUN_MODE="full-upgrade"
if [[ -n "$TARGET_ISOLATED_PHASE" ]]; then
    RUN_MODE="phase-${TARGET_ISOLATED_PHASE}"
    [[ "$TARGET_ISOLATED_PHASE" == "05" && "$DRY_RUN" == "false" ]] && RUN_MODE="post-check"
    [[ "$DRY_RUN" == "true" ]] && RUN_MODE="${RUN_MODE}-dry-run"
elif [[ "$DRY_RUN" == "true" && "$STOP_AFTER_PHASE" == "02" ]]; then
    RUN_MODE="pre-check"
elif [[ "$DRY_RUN" == "true" ]]; then
    RUN_MODE="dry-run"
elif [[ -n "$SKIP_TO_PHASE" || -n "$STOP_AFTER_PHASE" ]]; then
    RUN_MODE="partial-${SKIP_TO_PHASE:-01}-to-${STOP_AFTER_PHASE:-06}"
fi

# Why: the PROD gate must be driven by what the selected phases will actually do,
#      not by flags. Anything not proven read-only is treated as a cluster change.
compute_change_scope() {
    local start=1 end=6
    [[ -n "$SKIP_TO_PHASE" ]] && start=$((10#$SKIP_TO_PHASE))
    [[ -n "$STOP_AFTER_PHASE" ]] && end=$((10#$STOP_AFTER_PHASE))

    local remediation="$DEFAULT_AUTO_REMEDIATION"
    if [[ "$AUTO_REMEDIATION_MODE" == "true" || "$AUTO_REMEDIATION_MODE" == "false" ]]; then
        remediation="$AUTO_REMEDIATION_MODE"
    fi

    MUTATION_REASONS=()
    if (( start <= 2 && end >= 2 )) && [[ "$remediation" == "true" ]]; then
        MUTATION_REASONS+=("Phase 02 auto-remediation (may unpause MCPs / reboot nodes)")
    fi
    if [[ "$DRY_RUN" == "false" ]]; then
        if (( start <= 3 && end >= 3 )); then
            MUTATION_REASONS+=("Phase 03 cluster version upgrade and admin-acks")
        fi
        if (( start <= 6 && end >= 6 )); then
            if [[ "$SKIP_OPERATOR_UPGRADE" == "false" ]]; then
                MUTATION_REASONS+=("Phase 06 operator InstallPlan approvals")
            fi
            if [[ "$DEFAULT_ENABLE_DEV_PERSPECTIVE" == "true" ]]; then
                MUTATION_REASONS+=("Phase 06 Developer console perspective enablement")
            fi
        fi
    fi

    IS_MUTATING_UPGRADE=false
    if (( ${#MUTATION_REASONS[@]} > 0 )); then
        IS_MUTATING_UPGRADE=true
    fi
}
compute_change_scope

# ----------------------------------------------------------------------------
# Visual Hop Journey, Risk & Change Scope
# ----------------------------------------------------------------------------
HOP_COUNT=${#UPGRADE_HOPS[@]}
EST_DURATION=$(( HOP_COUNT * 90 )) # 90 minutes per hop baseline

# Why: the CLI has no cluster session yet; Phase 01 detects and validates the live version.
print_journey "current (live)" "${UPGRADE_HOPS[@]}"
print_risk_assessment "$TARGET_CLUSTER" "$CLUSTER_TIER" "$HOP_COUNT" "$EST_DURATION"
print_change_scope "$IS_MUTATING_UPGRADE" ${MUTATION_REASONS[@]+"${MUTATION_REASONS[@]}"}

# ----------------------------------------------------------------------------
# Confirmation Safety Gate
# ----------------------------------------------------------------------------
if [[ "$CLUSTER_TIER" == "PROD" || "$CLUSTER_TIER" == "PRODUCTION" ]]; then
    if [[ "$IS_MUTATING_UPGRADE" == "true" ]]; then
        msg_warn "Production Safety Guard: Cluster '${TARGET_CLUSTER}' is PRODUCTION and this run changes the cluster."
        if [[ ! -t 0 ]]; then
            # Why: --yes never bypasses the typed confirmation for production changes.
            msg_err "Production runs that change the cluster require an interactive terminal to type UPGRADE."
            exit 2
        fi
        printf "  To proceed, type '%sUPGRADE%s' in capital letters: " "${C_RED_BOLD}" "${C_RESET}"
        read -r PROD_CONFIRM || PROD_CONFIRM=""
        if [[ "$PROD_CONFIRM" != "UPGRADE" ]]; then
            msg_err "Production confirmation mismatched ('${PROD_CONFIRM}'). Run aborted by operator."
            exit 2
        fi
        msg_ok "Production confirmation accepted."
    else
        msg_info "Production Cluster '${TARGET_CLUSTER}': read-only validation run."
        if [[ "$AUTO_YES" == "false" ]]; then
            printf "  Proceed with validation execution on cluster '%s'? [y/N]: " "$TARGET_CLUSTER"
            read -r CONFIRM || CONFIRM=""
            if [[ ! "$CONFIRM" =~ ^[yY]([eE][sS])?$ ]]; then
                msg_err "Execution cancelled by operator."
                exit 2
            fi
            msg_ok "Operator confirmation accepted."
        fi
    fi
elif [[ "$AUTO_YES" == "false" ]]; then
    if [[ "$IS_MUTATING_UPGRADE" == "true" ]]; then
        printf "  Proceed with cluster changes on '%s'? [y/N]: " "$TARGET_CLUSTER"
    else
        printf "  Proceed with read-only validation on cluster '%s'? [y/N]: " "$TARGET_CLUSTER"
    fi
    read -r CONFIRM || CONFIRM=""
    if [[ ! "$CONFIRM" =~ ^[yY]([eE][sS])?$ ]]; then
        msg_err "Execution cancelled by operator."
        exit 2
    fi
    msg_ok "Operator confirmation accepted."
fi

# ----------------------------------------------------------------------------
# Per-Cluster Run Lock
# ----------------------------------------------------------------------------
# Why: blocks parallel runs against the same cluster, including runs started from
#      other checkouts on the same jump host (the lock lives in /tmp).
LOCK_FILE="/tmp/aro-upgrade-${TARGET_CLUSTER}.lock"
set +e
acquire_run_lock "$LOCK_FILE"
LOCK_RC=$?
set -e
if (( LOCK_RC == 1 )); then
    msg_err "Concurrency Conflict: Cluster '${TARGET_CLUSTER}' is locked by PID $(lock_holder_pid "$LOCK_FILE")."
    msg_err "Active lock: ${LOCK_FILE}. Another run is in progress; this run was aborted and the lock left untouched."
    exit 1
elif (( LOCK_RC != 0 )); then
    msg_err "Unable to acquire run lock ${LOCK_FILE}."
    exit 1
fi
msg_info "Acquired run lock: ${LOCK_FILE} (PID: $$, mode: ${RUN_LOCK_MODE})"

# ----------------------------------------------------------------------------
# Playbook Target Resolution & Extra-Vars Serialization
# ----------------------------------------------------------------------------
# Dispatch an isolated phase playbook directly, or main.yml for multi-phase flows.
TARGET_PLAYBOOK="${BASE_DIR}/main.yml"
IS_STANDALONE_PHASE=false

if [[ -n "$TARGET_ISOLATED_PHASE" ]]; then
    case "$TARGET_ISOLATED_PHASE" in
        01) TARGET_PLAYBOOK="${BASE_DIR}/01_Policy_Check.yaml" ;;
        02) TARGET_PLAYBOOK="${BASE_DIR}/02_Pre_upgrade_check.yaml" ;;
        03) TARGET_PLAYBOOK="${BASE_DIR}/03_Initiate_upgrade.yaml" ;;
        05) TARGET_PLAYBOOK="${BASE_DIR}/05_post_Upgrade_Checks.yaml" ;;
        06) TARGET_PLAYBOOK="${BASE_DIR}/06_Operator_Upgrade.yaml" ;;
    esac
    IS_STANDALONE_PHASE=true
fi

# Invariant: Must pass as a single JSON object string (-e '{"key": "value"}')
# Never pass space-separated key=value pairs, which stringifies lists in Ansible 2.7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOPS_CSV=$(IFS=,; echo "${UPGRADE_HOPS[*]}")
EXTRA_VARS=$("$PYTHON_CMD" -c '
import sys, json

(cluster_name, hops_csv, dry_run, skip_to_phase, skip_cgroup_check, stop_after_phase,
 auto_remediation, mail_to_cli, skip_operator_upgrade, run_timestamp, standalone_phase,
 include_postval, run_mode) = sys.argv[1:14]

payload = {
    "cluster_name": cluster_name,
    "upgrade_path": [h.strip() for h in hops_csv.split(",") if h.strip()],
    "dry_run": dry_run.lower() == "true",
    "run_timestamp": run_timestamp,
    "run_mode": run_mode,
}
if skip_to_phase:
    payload["skip_to_phase"] = skip_to_phase
if stop_after_phase:
    payload["stop_after_phase"] = stop_after_phase
if standalone_phase.lower() == "true":
    payload["standalone_phase"] = True
if auto_remediation.lower() in ("true", "false"):
    payload["auto_remediation_enabled"] = auto_remediation.lower() == "true"
if include_postval.lower() in ("true", "false"):
    payload["dry_run_include_postval"] = include_postval.lower() == "true"
# Why: --mail-to is passed as its own variable. Overwriting mail_to / alert lists
#      with an extra var (highest precedence) previously dropped on-call from alerts.
recipients = [m.strip() for m in mail_to_cli.split(",") if m.strip()]
if recipients:
    payload["mail_to_cli"] = recipients
if skip_cgroup_check.lower() == "true":
    payload["skip_cgroup_check"] = True
if skip_operator_upgrade.lower() == "true":
    payload["skip_operator_upgrade"] = True

print(json.dumps(payload))
' "$TARGET_CLUSTER" "$HOPS_CSV" "$DRY_RUN" "${SKIP_TO_PHASE:-}" "$SKIP_CGROUP_CHECK" "${STOP_AFTER_PHASE:-}" \
  "${AUTO_REMEDIATION_MODE:-}" "${MAIL_TO_CLI:-}" "$SKIP_OPERATOR_UPGRADE" "$TIMESTAMP" "$IS_STANDALONE_PHASE" \
  "${DRY_RUN_INCLUDE_POSTVAL:-}" "$RUN_MODE")

# ----------------------------------------------------------------------------
# Playbook Execution & Live Tee'd Logging
# ----------------------------------------------------------------------------
LOG_FILE="${BASE_DIR}/logs/${TARGET_CLUSTER}_${TIMESTAMP}.txt"
STATUS_FILE="${BASE_DIR}/logs/${TARGET_CLUSTER}_${TIMESTAMP}.status"

if [[ "$IS_STANDALONE_PHASE" == "true" ]]; then
    msg_step "Dispatching Isolated Phase Playbook: playbooks/${TARGET_PLAYBOOK##*/}"
else
    msg_step "Dispatching Master Orchestrator: playbooks/main.yml"
fi
msg_info "Run mode: ${RUN_MODE} | Execution log: ${LOG_FILE}"

ANSIBLE_ARGS=()
if [[ "$VERBOSE" == "true" ]]; then
    ANSIBLE_ARGS+=("-v")
fi

# Why: the playbooks target localhost without an inventory; do not write .retry
#      files next to the playbooks and do not warn about the implicit localhost.
export ANSIBLE_RETRY_FILES_ENABLED=False
export ANSIBLE_LOCALHOST_WARNING=False

# Execute ansible-playbook with live console tee
# Capture pipeline exit code explicitly via PIPESTATUS
set +e
if command -v ansible-playbook >/dev/null 2>&1; then
    # Why: ${arr[@]+...} keeps bash 4.2/4.3 happy under set -u when no extra args are given.
    ansible-playbook "${TARGET_PLAYBOOK}" -e "$EXTRA_VARS" ${ANSIBLE_ARGS[@]+"${ANSIBLE_ARGS[@]}"} 2>&1 | tee -a "$LOG_FILE"
    PLAYBOOK_RC="${PIPESTATUS[0]}"
else
    # Mock execution mode for validation in non-Ansible environments
    msg_warn "MOCK EXECUTION: ansible-playbook not present in PATH."
    echo "Target playbook: ${TARGET_PLAYBOOK}" | tee -a "$LOG_FILE"
    echo "Ansible extra-vars JSON: ${EXTRA_VARS}" | tee -a "$LOG_FILE"
    echo "Simulated execution completed successfully." | tee -a "$LOG_FILE"
    PLAYBOOK_RC=0
fi
set -e

# ----------------------------------------------------------------------------
# Post-Run Evaluation & Exit Code Mapping
# ----------------------------------------------------------------------------
ELAPSED_SECONDS=$(( SECONDS - START_SECONDS ))
ELAPSED_MINUTES=$(( ELAPSED_SECONDS / 60 ))
ELAPSED_REMAINDER=$(( ELAPSED_SECONDS % 60 ))
ELAPSED_FMT=$(printf "%dm %ds" "$ELAPSED_MINUTES" "$ELAPSED_REMAINDER")

FINAL_EXIT_CODE=0
VERDICT="PASS"

if (( PLAYBOOK_RC == 0 )); then
    msg_ok "Playbook execution completed successfully."
else
    VERDICT="FAIL"
    FINAL_EXIT_CODE=99
    STATUS_PHASE=""
    STATUS_REASON=""
    # Why: every rescue path writes logs/<cluster>_<ts>.status with the failing phase and
    #      exit class, so the exit code no longer depends on grepping the console log.
    if [[ -f "$STATUS_FILE" ]]; then
        STATUS_LINE=$("$PYTHON_CMD" -c '
import sys, json
try:
    with open(sys.argv[1]) as handle:
        data = json.load(handle)
    reason = " ".join(str(data.get("reason", "")).split())[:300]
    print("{}|{}|{}".format(int(data.get("exit_code", 99)), data.get("phase", ""), reason))
except Exception:
    print("99||")
' "$STATUS_FILE")
        IFS='|' read -r FINAL_EXIT_CODE STATUS_PHASE STATUS_REASON <<< "$STATUS_LINE"
    fi

    case "$FINAL_EXIT_CODE" in
        5)  msg_err "Execution halted: Policy check / upgrade path validation failed (Phase 01)." ;;
        10) msg_err "Execution halted: Prevalidation gate failed (Phase 02)." ;;
        20) msg_err "Execution halted: Upgrade hop failed (Phase 03/04)." ;;
        25) msg_err "Execution halted: Postvalidation gate failed (Phase 05)." ;;
        30) msg_err "Execution halted: Upgrade hop stopped progressing or exceeded its time limit (Phase 04)." ;;
        35) msg_err "Execution halted: Operator upgrade or validation failed (Phase 06)." ;;
        *)  FINAL_EXIT_CODE=99
            msg_err "Execution halted: Unexpected playbook failure (RC: ${PLAYBOOK_RC})." ;;
    esac
    if [[ -n "${STATUS_REASON:-}" ]]; then
        msg_err "Reason (${STATUS_PHASE:-unknown phase}): ${STATUS_REASON}"
    fi
fi

# Render structured 72-column summary table
render_post_run_summary \
    "$TARGET_CLUSTER" \
    "$VERDICT" \
    "$ELAPSED_FMT" \
    "$FINAL_EXIT_CODE" \
    "logs/${TARGET_CLUSTER}_${TIMESTAMP}.txt" \
    "output/${TARGET_CLUSTER}_prevalidation_${TIMESTAMP}.html" \
    "output/${TARGET_CLUSTER}_postvalidation_${TIMESTAMP}.html" \
    "output/${TARGET_CLUSTER}_operators_${TIMESTAMP}.html" \
    "output/${TARGET_CLUSTER}_phase01_${TIMESTAMP}.html"

# Exit with deterministic code
exit "$FINAL_EXIT_CODE"
