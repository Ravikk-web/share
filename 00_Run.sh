#!/usr/bin/env bash
# ============================================================================
# CLI Entrypoint — ARO Cluster Upgrade Automation
# ============================================================================
# Targets: Bash 4.2+ (RHEL 8 / Linux / macOS)
# Purpose: Single one-touch operational CLI surface (00_Run.sh) providing
#          pre-flight tool validation, YAML configuration schema checks,
#          interactive cluster and upgrade-path selection menus, concurrency
#          run locks, visual journey diagrams, production safety gates,
#          live-tee'd execution logging, and structured post-run exit codes.
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
AUTO_REMEDIATION_MODE=""
MAIL_TO_CLI=""
RESUME=false
VERBOSE=false
QUIET=false
SKIP_CGROUP_CHECK=false
LOCK_FILE=""
PYTHON_CMD=""

# ----------------------------------------------------------------------------
# Signal Trap & Concurrency Lock Teardown
# ----------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    # Remove PID run lock if held by this process
    if [[ -n "${LOCK_FILE:-}" && -f "${LOCK_FILE:-}" ]]; then
        rm -f "${LOCK_FILE}" 2>/dev/null || true
    fi
    # Reset terminal settings if in interactive TTY
    if [[ -t 0 ]]; then
        stty echo 2>/dev/null || true
    fi
    exit "${exit_code}"
}
trap cleanup EXIT INT TERM

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
  -d, --dry-run             Run pre-checks and validation without mutating cluster state
      --pre-check           Run pre-upgrade validation gate (Phases 01 & 02) and exit cleanly
      --post-check          Run post-upgrade validation gate (Phase 05) and exit cleanly
  -y, --yes                 Non-interactive confirmation (auto-accept prompts)
      --no-menu             Bypass interactive selection menus, using configured defaults
  -s, --skip-to-phase <NN>  Jump directly to specific phase (e.g. 02, 05, 06)
      --stop-after-phase <NN> Halt execution after specific phase (e.g. 02, 05)
  -m, --mail-to <email>     Override recipient email address (comma-separated for multiple)
  -r, --resume              Resume upgrade from last completed hop detected in logs
      --skip-cgroup         Skip CGroup v2 compatibility check and remediation (for non-admin accounts)
  -v, --verbose             Enable verbose Ansible output (-v)
  -q, --quiet               Suppress non-essential console output
  -h, --help                Display this help screen and exit

Exit Codes:
  0   Success — Upgrade completed cleanly
  1   Usage or Pre-flight Dependency Error
  2   User Cancelled
  3   Configuration Missing or Malformed
  10  Prevalidation Gate Failed (Phase 02)
  20  Upgrade Operation Failed (Phase 03/04)
  25  Postvalidation Gate Failed (Phase 05)
  30  Upgrade Settle-Gate Timeout (Phase 04)
  99  Unexpected Execution Error

Examples:
  ./00_Run.sh
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
            STOP_AFTER_PHASE="02"
            AUTO_REMEDIATION_MODE="false"
            shift
            ;;
        --pre-check|--pre-check-only)
            DRY_RUN=true
            STOP_AFTER_PHASE="02"
            AUTO_REMEDIATION_MODE="true"
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
            SKIP_TO_PHASE="$2"
            shift 2
            ;;
        --stop-after|--stop-after-phase)
            [[ -n "${2:-}" ]] || { msg_err "Flag '$1' requires a phase number (e.g. 02)."; exit 1; }
            STOP_AFTER_PHASE="$2"
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

# ----------------------------------------------------------------------------
# Pre-Flight Dependency Validation
# ----------------------------------------------------------------------------
# Confirms bash >= 4, ansible-playbook, oc, jq, and python are executable
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
}

validate_dependencies

# ----------------------------------------------------------------------------
# Vars Schema & Content Validation (Python-based)
# ----------------------------------------------------------------------------
# Validates all 6 YAML files, checking YAML syntax, mandatory keys, and cluster config
VARS_JSON=$("$PYTHON_CMD" -c '
import sys, os, json

try:
    import yaml
except ImportError:
    print(json.dumps({"error": "PyYAML package is required but not installed."}))
    sys.exit(3)

base_dir = sys.argv[1]
vars_dir = os.path.join(base_dir, "vars")

required_files = [
    "upgrade.yml",
    "secrets.yml",
    "smtp.yml",
    "paths.yml",
    "report_vars.yml",
    "api_regex.yml"
]

# Verify file presence
for fname in required_files:
    fpath = os.path.join(vars_dir, fname)
    if not os.path.isfile(fpath):
        print(json.dumps({"error": "Missing required vars file: vars/{}".format(fname)}))
        sys.exit(3)

loaded = {}
for fname in required_files:
    fpath = os.path.join(vars_dir, fname)
    try:
        with open(fpath, "r") as f:
            data = yaml.safe_load(f) or {}
            loaded[fname] = data
    except Exception as e:
        print(json.dumps({"error": "Failed to parse YAML in vars/{}: {}".format(fname, str(e))}))
        sys.exit(3)

upgrade_vars = loaded.get("upgrade.yml", {})
secrets_vars = loaded.get("secrets.yml", {})

default_cluster = upgrade_vars.get("cluster_name", "")
default_path = upgrade_vars.get("upgrade_path", [])
clusters = secrets_vars.get("clusters", {})

if not clusters:
    print(json.dumps({"error": "No clusters configured in vars/secrets.yml (clusters dict is empty)."}))
    sys.exit(3)

output = {
    "default_cluster": default_cluster,
    "default_path": default_path,
    "cluster_paths": upgrade_vars.get("cluster_upgrade_paths", {}),
    "clusters": clusters
}

print(json.dumps(output))
' "${BASE_DIR}") || {
    msg_err "Configuration validation encountered an unexpected error."
    exit 3
}

# Check if Python script returned an error
HAS_CONFIG_ERROR=$("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
if "error" in data:
    print(data["error"])
    sys.exit(1)
' "$VARS_JSON" 2>/dev/null) || {
    msg_err "Configuration validation failed: ${HAS_CONFIG_ERROR:-Unknown error}"
    exit 3
}

# Extract parsed config values
DEFAULT_CLUSTER=$("$PYTHON_CMD" -c 'import sys, json; print(json.loads(sys.argv[1]).get("default_cluster", ""))' "$VARS_JSON")
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

# ----------------------------------------------------------------------------
# Interactive Menus (When not in --no-menu mode and interactive TTY)
# ----------------------------------------------------------------------------
IS_INTERACTIVE=false
if [[ -t 0 && "$NO_MENU" == "false" ]]; then
    IS_INTERACTIVE=true
fi

if [[ "$IS_INTERACTIVE" == "true" ]]; then
    print_banner
    
    # 1. Cluster Selection Menu (if not specified via --cluster)
    if [[ -z "$TARGET_CLUSTER" ]]; then
        mapfile -t CLUSTER_ARR < <("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
for k, v in data.get("clusters", {}).items():
    tier = v.get("tier", "DEV").upper()
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
        for i in "${!CLUSTER_RAW_KEYS[@]}"; do
            if [[ "${CLUSTER_RAW_KEYS[$i]}" == "$DEFAULT_CLUSTER" ]]; then
                DEF_IDX=$((i + 1))
                break
            fi
        done
        
        render_menu "Select Target OpenShift Cluster" "$DEF_IDX" "${CLUSTER_ARR[@]}"
        SELECTED_CHOICE="$MENU_CHOICE"
        TARGET_CLUSTER="${CLUSTER_RAW_KEYS[$((SELECTED_CHOICE - 1))]}"
        msg_ok "Selected cluster: ${C_BOLD}${TARGET_CLUSTER}${C_RESET}"
    fi
    
    # 2. Upgrade Path Selection Menu (if not specified via --path)
    if [[ -z "$CLI_PATH" ]]; then
        DEF_PATH_STR=$("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
cluster = sys.argv[2]
hops = data.get("default_path", [])
if not hops:
    hops = data.get("cluster_paths", {}).get(cluster, [])
print(" ──▶ ".join(hops) if hops else "None")
' "$VARS_JSON" "$TARGET_CLUSTER")
        
        if [[ "$SKIP_TO_PHASE" == "05" && "$STOP_AFTER_PHASE" == "05" ]]; then
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
                CLI_PATH=$("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
cluster = sys.argv[2]
hops = data.get("default_path", [])
if not hops:
    hops = data.get("cluster_paths", {}).get(cluster, [])
print(",".join(hops))
' "$VARS_JSON" "$TARGET_CLUSTER")
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
                CLI_PATH=$("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
cluster = sys.argv[2]
hops = data.get("default_path", [])
if not hops:
    hops = data.get("cluster_paths", {}).get(cluster, [])
print(",".join(hops))
' "$VARS_JSON" "$TARGET_CLUSTER")
            else
                printf "\n  Enter comma-separated version hops (e.g. 4.14.40,4.15.35,4.16.18): "
                read -r CLI_PATH
                [[ -n "$CLI_PATH" ]] || { msg_err "Custom upgrade path cannot be empty."; exit 1; }
            fi
        fi
    fi
    
    # 3. Run Mode Selection Menu (if not specified via flags)
    if [[ "$DRY_RUN" == "false" && -z "$SKIP_TO_PHASE" && -z "$STOP_AFTER_PHASE" ]]; then
        MODE_OPTIONS=(
            "Full Upgrade (Phases 01 -> 06 End-to-End)"
            "Dry Run (Validate edges & health without mutating cluster state)"
            "Pre-check Only (Run Phase 01 & 02 Prevalidation Gate)"
            "Post-check Only (Run Phase 05 Postvalidation Gate)"
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
                STOP_AFTER_PHASE="02"
                AUTO_REMEDIATION_MODE="false"
                ;;
            3)
                DRY_RUN=true
                SKIP_TO_PHASE=""
                STOP_AFTER_PHASE="02"
                AUTO_REMEDIATION_MODE="true"
                ;;
            4)
                DRY_RUN=false
                SKIP_TO_PHASE="05"
                STOP_AFTER_PHASE="05"
                ;;
        esac
    fi
fi

# Fallback to configured defaults if not interactive and not passed via flags
if [[ -z "$TARGET_CLUSTER" ]]; then
    TARGET_CLUSTER="$DEFAULT_CLUSTER"
    [[ -n "$TARGET_CLUSTER" ]] || { msg_err "No cluster specified and no default found in vars/upgrade.yml."; exit 3; }
fi

if [[ -z "$CLI_PATH" ]]; then
    if [[ "$SKIP_TO_PHASE" == "05" && "$STOP_AFTER_PHASE" == "05" ]]; then
        CLI_PATH="current"
    else
        CLI_PATH=$("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
cluster = sys.argv[2]
hops = data.get("default_path", [])
if not hops:
    hops = data.get("cluster_paths", {}).get(cluster, [])
print(",".join(hops))
' "$VARS_JSON" "$TARGET_CLUSTER")
        [[ -n "$CLI_PATH" ]] || { msg_err "No upgrade path specified and no default found for cluster '${TARGET_CLUSTER}' in vars/upgrade.yml."; exit 3; }
    fi
fi

# Parse CLI_PATH into array
IFS=',' read -r -a UPGRADE_HOPS <<< "$CLI_PATH"
# Trim whitespace from each hop
for i in "${!UPGRADE_HOPS[@]}"; do
    UPGRADE_HOPS[$i]=$(echo "${UPGRADE_HOPS[$i]}" | tr -d ' ')
done

# Resolve cluster tier
CLUSTER_TIER=$("$PYTHON_CMD" -c '
import sys, json
data = json.loads(sys.argv[1])
c = sys.argv[2]
print(data.get("clusters", {}).get(c, {}).get("tier", "DEV").upper())
' "$VARS_JSON" "$TARGET_CLUSTER")

# ----------------------------------------------------------------------------
# Resume Execution Detection (--resume)
# ----------------------------------------------------------------------------
if [[ "$RESUME" == "true" ]]; then
    msg_info "Checking execution logs for last completed hop on cluster '${TARGET_CLUSTER}'..."
    LATEST_LOG=$(ls -t "${BASE_DIR}/logs/${TARGET_CLUSTER}_"*.txt 2>/dev/null | head -n 1 || true)
    
    if [[ -n "$LATEST_LOG" && -f "$LATEST_LOG" ]]; then
        # Scan log for completed hops
        COMPLETED_HOPS=()
        for hop in "${UPGRADE_HOPS[@]}"; do
            if grep -qE "(Hop complete|Settle gate passed).*${hop}" "$LATEST_LOG" 2>/dev/null; then
                COMPLETED_HOPS+=("$hop")
            fi
        done
        
        if (( ${#COMPLETED_HOPS[@]} > 0 )); then
            msg_ok "Detected completed hops in log: ${COMPLETED_HOPS[*]}"
            # Filter remaining hops
            REMAINING_HOPS=()
            for hop in "${UPGRADE_HOPS[@]}"; do
                local already_done=false
                for done_hop in "${COMPLETED_HOPS[@]}"; do
                    if [[ "$hop" == "$done_hop" ]]; then
                        already_done=true
                        break
                    fi
                done
                if [[ "$already_done" == "false" ]]; then
                    REMAINING_HOPS+=("$hop")
                fi
            done
            
            if (( ${#REMAINING_HOPS[@]} == 0 )); then
                msg_ok "All hops in path have already been completed for cluster '${TARGET_CLUSTER}'."
                exit 0
            fi
            
            UPGRADE_HOPS=("${REMAINING_HOPS[@]}")
            msg_info "Resuming with remaining hops: ${UPGRADE_HOPS[*]}"
        else
            msg_info "No completed hops detected in latest log; executing full path."
        fi
    else
        msg_info "No previous execution logs found; executing full path."
    fi
fi

# ----------------------------------------------------------------------------
# Visual Hop Journey & Risk Confirmation
# ----------------------------------------------------------------------------
HOP_COUNT=${#UPGRADE_HOPS[@]}
EST_DURATION=$(( HOP_COUNT * 90 )) # 90 minutes per hop baseline

# Visual journey display
print_journey "Current" "${UPGRADE_HOPS[@]}"

# Risk assessment display
print_risk_assessment "$TARGET_CLUSTER" "$CLUSTER_TIER" "$HOP_COUNT" "$EST_DURATION"

# ----------------------------------------------------------------------------
# Confirmation Safety Gate
# ----------------------------------------------------------------------------
IS_MUTATING_UPGRADE=true
if [[ "$DRY_RUN" == "true" || "${STOP_AFTER_PHASE:-}" == "02" ]]; then
    IS_MUTATING_UPGRADE=false
fi

if [[ "$CLUSTER_TIER" == "PROD" || "$CLUSTER_TIER" == "PRODUCTION" ]]; then
    if [[ "$IS_MUTATING_UPGRADE" == "true" ]]; then
        msg_warn "Production Safety Guard: Cluster '${TARGET_CLUSTER}' is designated as PRODUCTION."
        printf "  To proceed, type '%sUPGRADE%s' in capital letters: " "${C_RED_BOLD}" "${C_RESET}"
        read -r PROD_CONFIRM
        if [[ "$PROD_CONFIRM" != "UPGRADE" ]]; then
            msg_err "Production confirmation mismatched ('${PROD_CONFIRM}'). Upgrade aborted by operator."
            exit 2
        fi
        msg_ok "Production confirmation accepted."
    else
        msg_info "Production Cluster '${TARGET_CLUSTER}': Non-mutating validation mode active."
        if [[ "$AUTO_YES" == "false" ]]; then
            printf "  Proceed with validation execution on cluster '%s'? [y/N]: " "$TARGET_CLUSTER"
            read -r CONFIRM
            if [[ ! "$CONFIRM" =~ ^[yY]([eE][sS])?$ ]]; then
                msg_err "Execution cancelled by operator."
                exit 2
            fi
            msg_ok "Operator confirmation accepted."
        fi
    fi
elif [[ "$AUTO_YES" == "false" ]]; then
    if [[ "$IS_MUTATING_UPGRADE" == "true" ]]; then
        printf "  Proceed with upgrade execution on cluster '%s'? [y/N]: " "$TARGET_CLUSTER"
    else
        printf "  Proceed with validation execution on cluster '%s'? [y/N]: " "$TARGET_CLUSTER"
    fi
    read -r CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]([eE][sS])?$ ]]; then
        msg_err "Execution cancelled by operator."
        exit 2
    fi
    msg_ok "Operator confirmation accepted."
fi

# ----------------------------------------------------------------------------
# Concurrency Run Lock Enforcement
# ----------------------------------------------------------------------------
# Enforce /tmp/aro-upgrade-<cluster>.lock to block parallel runs against the same cluster
LOCK_FILE="/tmp/aro-upgrade-${TARGET_CLUSTER}.lock"

if [[ -f "$LOCK_FILE" ]]; then
    EXISTING_PID=$(cat "$LOCK_FILE" 2>/dev/null || true)
    if [[ -n "$EXISTING_PID" ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
        msg_err "Concurrency Conflict: Cluster '${TARGET_CLUSTER}' is currently locked by PID ${EXISTING_PID}."
        msg_err "Active lock file: ${LOCK_FILE}"
        msg_err "Another upgrade session is actively running. Aborting."
        exit 1
    else
        msg_warn "Found stale lock file for PID ${EXISTING_PID:-Unknown}. Removing."
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
fi

# Acquire lock with current PID
echo "$$" > "$LOCK_FILE"
msg_info "Acquired concurrency lock: ${LOCK_FILE} (PID: $$)"

# ----------------------------------------------------------------------------
# Extra-Vars Assembly (Single JSON String Object)
# ----------------------------------------------------------------------------
# Invariant: Must pass as a single JSON object string (-e '{"key": "value"}')
# Never pass space-separated key=value pairs, which stringifies lists in Ansible 2.7
HOPS_CSV=$(IFS=,; echo "${UPGRADE_HOPS[*]}")
EXTRA_VARS=$("$PYTHON_CMD" -c '
import sys, json

cluster_name = sys.argv[1]
hops_csv = sys.argv[2]
dry_run = sys.argv[3].lower() == "true"
skip_to_phase = sys.argv[4]
skip_cgroup_check = sys.argv[5].lower() == "true"
stop_after_phase = sys.argv[6] if len(sys.argv) > 6 else ""
auto_remediation = sys.argv[7] if len(sys.argv) > 7 else ""
mail_to_cli = sys.argv[8] if len(sys.argv) > 8 else ""

hops_list = [h.strip() for h in hops_csv.split(",") if h.strip()]

payload = {
    "cluster_name": cluster_name,
    "upgrade_path": hops_list,
    "dry_run": dry_run
}

if skip_to_phase:
    payload["skip_to_phase"] = skip_to_phase

if stop_after_phase:
    payload["stop_after_phase"] = stop_after_phase

if auto_remediation.lower() in ("true", "false"):
    payload["auto_remediation_enabled"] = (auto_remediation.lower() == "true")

if mail_to_cli:
    recipients = [m.strip() for m in mail_to_cli.split(",") if m.strip()]
    if recipients:
        payload["mail_to"] = recipients
        payload["preval_mail_to"] = recipients
        payload["postval_mail_to"] = recipients

if skip_cgroup_check:
    payload["skip_cgroup_check"] = True

print(json.dumps(payload))
' "$TARGET_CLUSTER" "$HOPS_CSV" "$DRY_RUN" "${SKIP_TO_PHASE:-}" "$SKIP_CGROUP_CHECK" "${STOP_AFTER_PHASE:-}" "${AUTO_REMEDIATION_MODE:-}" "${MAIL_TO_CLI:-}")

# ----------------------------------------------------------------------------
# Playbook Execution & Live Tee'd Logging
# ----------------------------------------------------------------------------
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${BASE_DIR}/logs/${TARGET_CLUSTER}_${TIMESTAMP}.txt"

msg_step "Dispatching Master Orchestrator: playbooks/main.yml"
msg_info "Execution log: ${LOG_FILE}"

ANSIBLE_ARGS=()
if [[ "$VERBOSE" == "true" ]]; then
    ANSIBLE_ARGS+=("-v")
fi

# Execute ansible-playbook with live console tee
# Capture pipeline exit code explicitly via PIPESTATUS
set +e
if command -v ansible-playbook >/dev/null 2>&1; then
    ansible-playbook "${BASE_DIR}/main.yml" -e "$EXTRA_VARS" "${ANSIBLE_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"
    PLAYBOOK_RC="${PIPESTATUS[0]}"
else
    # Mock execution mode for validation in non-Ansible environments
    msg_warn "MOCK EXECUTION: ansible-playbook not present in PATH."
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

PRE_REPORT="${BASE_DIR}/output/${TARGET_CLUSTER}_prevalidation_${TIMESTAMP}.html"
POST_REPORT="${BASE_DIR}/output/${TARGET_CLUSTER}_postvalidation_${TIMESTAMP}.html"
OP_REPORT="${BASE_DIR}/output/${TARGET_CLUSTER}_operators_${TIMESTAMP}.html"

FINAL_EXIT_CODE=0
VERDICT="PASS"

if (( PLAYBOOK_RC == 0 )); then
    FINAL_EXIT_CODE=0
    VERDICT="PASS"
    msg_ok "Playbook execution completed successfully."
else
    VERDICT="FAIL"
    # Inspect log file for specific failure signatures to map exit code
    if grep -qiE "(prevalidation.*failed|pre_upgrade_check.*failed)" "$LOG_FILE" 2>/dev/null; then
        FINAL_EXIT_CODE=10
        msg_err "Execution halted: Prevalidation gate failed (Phase 02)."
    elif grep -qiE "(settle_gate_timeout|timeout.*waiting for|monitoring.*timed out)" "$LOG_FILE" 2>/dev/null; then
        FINAL_EXIT_CODE=30
        msg_err "Execution halted: Upgrade settle-gate timed out (Phase 04)."
    elif grep -qiE "(postvalidation.*failed|post_upgrade_checks.*failed|Phase 05.*failed)" "$LOG_FILE" 2>/dev/null; then
        FINAL_EXIT_CODE=25
        msg_err "Execution halted: Postvalidation gate failed (Phase 05)."
    elif grep -qiE "(initiate_upgrade.*failed|hop.*failed|upgrade.*failure)" "$LOG_FILE" 2>/dev/null; then
        FINAL_EXIT_CODE=20
        msg_err "Execution halted: Cluster upgrade initiation or rollout failed (Phase 03/04)."
    else
        FINAL_EXIT_CODE=99
        msg_err "Execution halted: Unexpected playbook failure (RC: ${PLAYBOOK_RC})."
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
    "output/${TARGET_CLUSTER}_operators_${TIMESTAMP}.html"

# Exit with deterministic code
exit "$FINAL_EXIT_CODE"
