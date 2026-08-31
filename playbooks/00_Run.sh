#!/usr/bin/env bash
# =============================================================================
# 00_Run.sh — CLI Entrypoint for ARO Cluster Upgrade Automation
# =============================================================================
# Targets: Bash 4+ on RHEL 8
# MIGRATION 2.14: No Bash changes needed; Ansible version is detected and
#                 displayed in the confirmation summary for operator awareness.
#
# Responsibilities:
#   1. Derive every path from this script's location (nothing machine-specific).
#   2. Create logs/, output/, snapshots/ if missing.
#   3. Read cluster_name and upgrade_path from vars/upgrade.yml by default.
#   4. Support optional CLI overrides via --cluster <name> and --path "4.18.x,4.19.x".
#   5. Print a confirmation summary and require explicit 'y' (--yes to skip).
#   6. Run main.yml with live output tee'd to logs/<cluster>_<timestamp>.txt.
#   7. Return deterministic exit codes.
#
# Exit codes:
#   0  — Success (all phases completed)
#   1  — Usage / argument error
#   2  — User cancelled at confirmation
#   3  — Missing cluster or upgrade path configuration
#   10 — Prevalidation failure
#   20 — Upgrade / phase failure
#   30 — Timeout
#   99 — Unknown / unexpected error
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colour helpers (terminal only — never written to logs)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_GREEN='\033[0;32m'
    C_AMBER='\033[0;33m'
    C_RED='\033[0;31m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
    C_MAGENTA='\033[0;35m'
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
else
    C_GREEN='' C_AMBER='' C_RED='' C_BLUE='' C_CYAN='' C_MAGENTA='' C_BOLD='' C_RESET=''
fi

msg_ok()   { printf "${C_GREEN}✅ %s${C_RESET}\n" "$1"; }
msg_warn() { printf "${C_AMBER}⚠️  %s${C_RESET}\n" "$1"; }
msg_err()  { printf "${C_RED}❌ %s${C_RESET}\n" "$1" >&2; }
msg_info() { printf "${C_CYAN}ℹ️  %s${C_RESET}\n" "$1"; }
msg_step() { printf "\n${C_BLUE}${C_BOLD}▶ %s${C_RESET}\n" "$1"; }

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
print_banner() {
    printf "${C_MAGENTA}${C_BOLD}"
    cat << "EOF"
    ___    ____  ____     ____  __                              
   /   |  / __ \/ __ \   / __ \/ /_  ____ _________  _____      
  / /| | / /_/ / / / /  / /_/ / __ \/ __ `/ ___/ _ \/ ___/      
 / ___ |/ _, _/ /_/ /  / ____/ / / / /_/ / /  /  __(__  )       
/_/  |_/_/ |_|\____/  /_/   /_/ /_/\__,_/_/   \___/____/        
                                                                
EOF
    printf "${C_RESET}"
    printf "${C_CYAN}${C_BOLD}      ARO Cluster Upgrade Automation Entrypoint ${C_RESET}\n\n"
}

# ---------------------------------------------------------------------------
# Path bootstrap — everything derives from script location
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
OUTPUT_DIR="${SCRIPT_DIR}/output"
SNAPSHOT_DIR="${SCRIPT_DIR}/snapshots"
VARS_UPGRADE_FILE="${SCRIPT_DIR}/vars/upgrade.yml"

# Create output directories if missing
mkdir -p "${LOG_DIR}" "${OUTPUT_DIR}" "${SNAPSHOT_DIR}"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
CLUSTER_NAME=""
UPGRADE_PATH_RAW=""
DRY_RUN=false
AUTO_YES=false
SKIP_PATH_MENU=false
CLUSTER_SOURCE="vars/upgrade.yml"
PATH_SOURCE="vars/upgrade.yml"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    print_banner
    cat <<EOF
${C_BOLD}Usage:${C_RESET} $(basename "$0") [OPTIONS]

${C_BOLD}Options:${C_RESET}
  ${C_CYAN}--cluster${C_RESET}  <name>             Optional override for target cluster (default: reads vars/upgrade.yml)
  ${C_CYAN}--path${C_RESET}     "4.18.x,4.19.x"    Optional override for upgrade path (bypasses selection menu)
  ${C_CYAN}--dry-run${C_RESET}                     Validate + prevalidation only; no upgrade trigger
  ${C_CYAN}--yes${C_RESET}                         Skip confirmation prompt
  ${C_CYAN}--no-menu${C_RESET}                     Skip the upgrade path selection menu; use configured default
  ${C_CYAN}-h, --help${C_RESET}                    Show this help and exit

${C_BOLD}Configuration:${C_RESET}
  Both target cluster name and version sequences can be defined directly
  in '${VARS_UPGRADE_FILE}'. When configured there, you can run simply with:
    $(basename "$0")
    $(basename "$0") --yes

${C_BOLD}Examples:${C_RESET}
  $(basename "$0")                                     # Reads cluster and path; shows selection menu
  $(basename "$0") --cluster aro-prod-01               # Overrides cluster, shows selection menu
  $(basename "$0") --cluster aro-prod-01 --path "4.14.40,4.15.35" # Full CLI override (no menu)
  $(basename "$0") --no-menu                           # Use configured default path, skip menu
  $(basename "$0") --dry-run                           # Test mode with prevalidation only

${C_BOLD}Exit codes:${C_RESET}
  ${C_GREEN}0   Success${C_RESET}               ${C_RED}10  Prevalidation failure${C_RESET}
  ${C_RED}1   Usage/argument error${C_RESET}   ${C_RED}20  Upgrade/phase failure${C_RESET}
  ${C_AMBER}2   User cancelled${C_RESET}         ${C_RED}30  Timeout${C_RESET}
  ${C_RED}3   Missing configuration${C_RESET}  ${C_RED}99  Unknown error${C_RESET}
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cluster)
            [[ -z "${2:-}" ]] && { msg_err "--cluster requires a value"; exit 1; }
            CLUSTER_NAME="$2"
            CLUSTER_SOURCE="CLI argument (--cluster)"
            shift 2 ;;
        --path)
            [[ -z "${2:-}" ]] && { msg_err "--path requires a value"; exit 1; }
            UPGRADE_PATH_RAW="$2"
            PATH_SOURCE="CLI argument (--path)"
            SKIP_PATH_MENU=true
            shift 2 ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --yes)
            AUTO_YES=true; shift ;;
        --no-menu)
            SKIP_PATH_MENU=true; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            msg_err "Unknown option: $1"
            usage; exit 1 ;;
    esac
done

print_banner
msg_step "Initialization & Validation"

# ---------------------------------------------------------------------------
# Resolve Cluster Name (from CLI override or vars/upgrade.yml)
# ---------------------------------------------------------------------------
if [[ -z "${CLUSTER_NAME}" && -f "${VARS_UPGRADE_FILE}" ]]; then
    # Try Python YAML parser first
    if command -v python3 &>/dev/null; then
        CLUSTER_NAME="$(python3 -c "
import yaml
try:
    with open('${VARS_UPGRADE_FILE}', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
    print(str(data.get('cluster_name', '')).strip())
except Exception:
    pass
" 2>/dev/null || true)"
    elif command -v python &>/dev/null; then
        CLUSTER_NAME="$(python -c "
import yaml
try:
    with open('${VARS_UPGRADE_FILE}', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
    print(str(data.get('cluster_name', '')).strip())
except Exception:
    pass
" 2>/dev/null || true)"
    fi

    # Fallback to awk/sed parser if python not available
    if [[ -z "${CLUSTER_NAME}" ]]; then
        CLUSTER_NAME="$(awk '
            /^cluster_name:/ {
                sub(/^cluster_name:[[:space:]]*/, "");
                gsub(/[\"'\'']/,"");
                sub(/[[:space:]]*#.*/, "");
                print $0;
                exit
            }
        ' "${VARS_UPGRADE_FILE}" || true)"
    fi

    if [[ -n "${CLUSTER_NAME}" ]]; then
        CLUSTER_SOURCE="vars/upgrade.yml"
    fi
fi

# If cluster name is still empty, prompt interactively
if [[ -z "${CLUSTER_NAME}" ]]; then
    msg_warn "No cluster_name configured in ${VARS_UPGRADE_FILE}."
    printf "${C_BOLD}Enter target cluster name: ${C_RESET}"
    read -r CLUSTER_NAME
    [[ -z "${CLUSTER_NAME}" ]] && { echo ""; msg_err "Cluster name cannot be empty. Define it in vars/upgrade.yml or via --cluster."; exit 3; }
    CLUSTER_SOURCE="Interactive input"
fi

# ---------------------------------------------------------------------------
# Resolve Upgrade Path (from CLI override or vars/upgrade.yml)
# ---------------------------------------------------------------------------
UPGRADE_HOPS=()

if [[ -n "${UPGRADE_PATH_RAW}" ]]; then
    # Provided via CLI --path argument — skip menu
    IFS=',' read -ra RAW_HOPS <<< "${UPGRADE_PATH_RAW}"
    for hop in "${RAW_HOPS[@]}"; do
        trimmed="$(echo "${hop}" | xargs)"
        [[ -n "${trimmed}" ]] && UPGRADE_HOPS+=("${trimmed}")
    done
else
    # ---------------------------------------------------------------------------
    # Build the full catalogue of available upgrade paths from vars/upgrade.yml
    # ---------------------------------------------------------------------------
    # MENU_PATH_LABELS : human-readable label for each path option
    # MENU_PATH_VALUES : comma-separated version string for each option
    MENU_PATH_LABELS=()
    MENU_PATH_VALUES=()

    if [[ -f "${VARS_UPGRADE_FILE}" ]]; then
        if command -v python3 &>/dev/null; then
            # Parse all paths via Python (most reliable with YAML)
            CATALOGUE_JSON="$(python3 -c "
import yaml, json
try:
    with open('${VARS_UPGRADE_FILE}', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
    catalogue = []
    # 1. Global upgrade_path
    global_path = data.get('upgrade_path', []) or []
    if isinstance(global_path, list) and global_path:
        catalogue.append({'label': 'Global path (upgrade_path)',
                          'versions': [str(v).strip() for v in global_path if str(v).strip()]})
    # 2. Per-cluster paths
    per_cluster = data.get('cluster_upgrade_paths', {}) or {}
    if isinstance(per_cluster, dict):
        for cluster_key in sorted(per_cluster.keys()):
            path_list = per_cluster[cluster_key] or []
            if isinstance(path_list, list) and path_list:
                catalogue.append({'label': 'Per-cluster: ' + str(cluster_key),
                                  'versions': [str(v).strip() for v in path_list if str(v).strip()]})
    print(json.dumps(catalogue))
except Exception as e:
    print('[]')
" 2>/dev/null || echo '[]')"

            if command -v python3 &>/dev/null && [[ -n "${CATALOGUE_JSON}" && "${CATALOGUE_JSON}" != '[]' ]]; then
                # Parse catalogue JSON into shell arrays
                ENTRY_COUNT="$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(len(d))" <<< "${CATALOGUE_JSON}" 2>/dev/null || echo 0)"
                for (( ci=0; ci<ENTRY_COUNT; ci++ )); do
                    lbl="$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d[${ci}]['label'])" <<< "${CATALOGUE_JSON}" 2>/dev/null || true)"
                    vers="$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(','.join(d[${ci}]['versions']))" <<< "${CATALOGUE_JSON}" 2>/dev/null || true)"
                    [[ -n "${lbl}" && -n "${vers}" ]] && MENU_PATH_LABELS+=("${lbl}") && MENU_PATH_VALUES+=("${vers}")
                done
            fi
        fi

        # Fallback: awk-based global upgrade_path parse if Python unavailable or catalogue is empty
        if [[ ${#MENU_PATH_VALUES[@]} -eq 0 ]]; then
            AWK_PATH="$(awk '
                /^upgrade_path:/ { in_path=1; next }
                /^[a-zA-Z0-9_]+:/ && in_path { in_path=0 }
                in_path && /^[[:space:]]*-[[:space:]]*/ {
                    sub(/^[[:space:]]*-[[:space:]]*/, "");
                    gsub(/[\"'\'']/,"");
                    sub(/[[:space:]]*#.*/, "");
                    if (length($0) > 0) print $0
                }
            ' "${VARS_UPGRADE_FILE}" | tr '\n' ',' | sed 's/,$//' || true)"
            if [[ -n "${AWK_PATH}" ]]; then
                MENU_PATH_LABELS+=("Global path (upgrade_path)")
                MENU_PATH_VALUES+=("${AWK_PATH}")
            fi
        fi
    fi

    # ---------------------------------------------------------------------------
    # Interactive upgrade path selection menu
    # ---------------------------------------------------------------------------
    if [[ "${SKIP_PATH_MENU}" != true && ${#MENU_PATH_VALUES[@]} -gt 0 ]]; then
        msg_step "Upgrade Path Selection"
        echo ""

        # Determine the currently active path for this cluster (for highlighting)
        ACTIVE_PATH_CSV=""
        if command -v python3 &>/dev/null && [[ -f "${VARS_UPGRADE_FILE}" ]]; then
            ACTIVE_PATH_CSV="$(python3 -c "
import yaml
try:
    with open('${VARS_UPGRADE_FILE}', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
    hops = (data.get('cluster_upgrade_paths', {}) or {}).get('${CLUSTER_NAME}', []) or data.get('upgrade_path', [])
    if isinstance(hops, list) and hops:
        print(','.join([str(h).strip() for h in hops if str(h).strip()]))
except Exception:
    pass
" 2>/dev/null || true)"
        fi

        MENU_W=72
        MENU_HLINE=$(printf '─%.0s' $(seq 1 $MENU_W))
        printf "${C_CYAN}╭${MENU_HLINE}╮${C_RESET}\n"
        printf "${C_CYAN}│${C_RESET} ${C_BOLD}%-$((MENU_W - 2))s${C_RESET} ${C_CYAN}│${C_RESET}\n" " Available Upgrade Paths — Select one to use"
        printf "${C_CYAN}├${MENU_HLINE}┤${C_RESET}\n"

        for (( mi=0; mi<${#MENU_PATH_VALUES[@]}; mi++ )); do
            idx=$(( mi + 1 ))
            lbl="${MENU_PATH_LABELS[$mi]}"
            vers="${MENU_PATH_VALUES[$mi]}"
            # Format versions as arrow-separated hops for readability
            vers_display="$(echo "${vers}" | sed 's/,/ → /g')"
            # Truncate if too long for box
            max_vlen=$(( MENU_W - 10 ))
            if [[ ${#vers_display} -gt $max_vlen ]]; then
                vers_display="${vers_display:0:$((max_vlen - 3))}..."
            fi
            # Highlight if this is the currently configured path for the cluster
            if [[ "${vers}" == "${ACTIVE_PATH_CSV}" ]]; then
                STAR="${C_GREEN}★${C_RESET}"
                printf "${C_CYAN}│${C_RESET} ${STAR} ${C_GREEN}${C_BOLD}%2d)${C_RESET} %-$((MENU_W - 8))s ${C_CYAN}│${C_RESET}\n" "${idx}" "${lbl}"
                printf "${C_CYAN}│${C_RESET}     ${C_GREEN}%-$((MENU_W - 6))s${C_RESET} ${C_CYAN}│${C_RESET}\n" "${vers_display}"
            else
                printf "${C_CYAN}│${C_RESET}   ${C_BOLD}%2d)${C_RESET} %-$((MENU_W - 8))s ${C_CYAN}│${C_RESET}\n" "${idx}" "${lbl}"
                printf "${C_CYAN}│${C_RESET}     ${C_AMBER}%-$((MENU_W - 6))s${C_RESET} ${C_CYAN}│${C_RESET}\n" "${vers_display}"
            fi
            printf "${C_CYAN}│${C_RESET} %-$((MENU_W - 1))s ${C_CYAN}│${C_RESET}\n" ""
        done

        # Extra options: custom path and use-configured-default
        CUSTOM_OPTION_IDX=$(( ${#MENU_PATH_VALUES[@]} + 1 ))
        printf "${C_CYAN}├${MENU_HLINE}┤${C_RESET}\n"
        printf "${C_CYAN}│${C_RESET}   ${C_BOLD}%2d)${C_RESET} %-$((MENU_W - 8))s ${C_CYAN}│${C_RESET}\n" "${CUSTOM_OPTION_IDX}" "Enter a custom upgrade path manually"
        printf "${C_CYAN}│${C_RESET}     ${C_CYAN}%-$((MENU_W - 6))s${C_RESET} ${C_CYAN}│${C_RESET}\n" "(comma-separated, e.g. 4.14.40,4.15.35)"
        printf "${C_CYAN}╰${MENU_HLINE}╯${C_RESET}\n"
        echo ""
        printf "${C_BOLD}  ${C_GREEN}★${C_RESET}${C_BOLD} = currently configured for cluster '${CLUSTER_NAME}'${C_RESET}\n"
        echo ""

        SELECTION_VALID=false
        while [[ "${SELECTION_VALID}" != true ]]; do
            printf "${C_BOLD}Select upgrade path [1-${CUSTOM_OPTION_IDX}]: ${C_RESET}"
            read -r MENU_CHOICE

            if [[ "${MENU_CHOICE}" =~ ^[0-9]+$ ]]; then
                if (( MENU_CHOICE >= 1 && MENU_CHOICE <= ${#MENU_PATH_VALUES[@]} )); then
                    SELECTED_IDX=$(( MENU_CHOICE - 1 ))
                    UPGRADE_PATH_RAW="${MENU_PATH_VALUES[$SELECTED_IDX]}"
                    PATH_SOURCE="Selection #${MENU_CHOICE}: ${MENU_PATH_LABELS[$SELECTED_IDX]}"
                    SELECTION_VALID=true
                elif (( MENU_CHOICE == CUSTOM_OPTION_IDX )); then
                    printf "${C_BOLD}Enter custom upgrade path (comma-separated, e.g. 4.14.40,4.15.35): ${C_RESET}"
                    read -r UPGRADE_PATH_RAW
                    if [[ -z "${UPGRADE_PATH_RAW}" ]]; then
                        msg_err "Custom path cannot be empty."
                    else
                        PATH_SOURCE="Custom interactive input"
                        SELECTION_VALID=true
                    fi
                else
                    msg_warn "Invalid selection '${MENU_CHOICE}'. Enter a number between 1 and ${CUSTOM_OPTION_IDX}."
                fi
            else
                msg_warn "Invalid input '${MENU_CHOICE}'. Enter a number between 1 and ${CUSTOM_OPTION_IDX}."
            fi
        done

        # Parse selected path into UPGRADE_HOPS
        IFS=',' read -ra RAW_HOPS <<< "${UPGRADE_PATH_RAW}"
        for hop in "${RAW_HOPS[@]}"; do
            trimmed="$(echo "${hop}" | xargs)"
            [[ -n "${trimmed}" ]] && UPGRADE_HOPS+=("${trimmed}")
        done

    else
        # SKIP_PATH_MENU=true or no paths found in file — fall through to file/interactive resolution below
        if [[ -f "${VARS_UPGRADE_FILE}" ]]; then
            PARSED_FROM_FILE=""
            # Try Python YAML parser first
            if command -v python3 &>/dev/null; then
                PARSED_FROM_FILE="$(python3 -c "
import yaml
try:
    with open('${VARS_UPGRADE_FILE}', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
    hops = (data.get('cluster_upgrade_paths', {}) or {}).get('${CLUSTER_NAME}', []) or data.get('upgrade_path', [])
    if isinstance(hops, list) and hops:
        print(','.join([str(h).strip() for h in hops if str(h).strip()]))
except Exception:
    pass
" 2>/dev/null || true)"
            elif command -v python &>/dev/null; then
                PARSED_FROM_FILE="$(python -c "
import yaml
try:
    with open('${VARS_UPGRADE_FILE}', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f) or {}
    hops = (data.get('cluster_upgrade_paths', {}) or {}).get('${CLUSTER_NAME}', []) or data.get('upgrade_path', [])
    if isinstance(hops, list) and hops:
        print(','.join([str(h).strip() for h in hops if str(h).strip()]))
except Exception:
    pass
" 2>/dev/null || true)"
            fi

            # Fallback to awk/sed YAML list parser if python not available
            if [[ -z "${PARSED_FROM_FILE}" ]]; then
                PARSED_FROM_FILE="$(awk '
                    /^upgrade_path:/ { in_path=1; next }
                    /^[a-zA-Z0-9_]+:/ && in_path { in_path=0 }
                    in_path && /^[[:space:]]*-[[:space:]]*/ {
                        sub(/^[[:space:]]*-[[:space:]]*/, "");
                        gsub(/[\"'\'']/,"");
                        sub(/[[:space:]]*#.*/, "");
                        if (length($0) > 0) print $0
                    }
                ' "${VARS_UPGRADE_FILE}" | tr '\n' ',' | sed 's/,$//' || true)"
            fi

            if [[ -n "${PARSED_FROM_FILE}" ]]; then
                IFS=',' read -ra RAW_HOPS <<< "${PARSED_FROM_FILE}"
                for hop in "${RAW_HOPS[@]}"; do
                    trimmed="$(echo "${hop}" | xargs)"
                    [[ -n "${trimmed}" ]] && UPGRADE_HOPS+=("${trimmed}")
                done
                PATH_SOURCE="vars/upgrade.yml"
            fi
        fi
    fi
fi

# If still empty, prompt interactively
if [[ ${#UPGRADE_HOPS[@]} -eq 0 ]]; then
    msg_warn "No upgrade_path configured in ${VARS_UPGRADE_FILE}."
    printf "${C_BOLD}Enter upgrade path (comma-separated, e.g. 4.14.40,4.15.35): ${C_RESET}"
    read -r MANUAL_PATH_RAW
    [[ -z "${MANUAL_PATH_RAW}" ]] && { echo ""; msg_err "Upgrade path cannot be empty. Define it in vars/upgrade.yml or via --path."; exit 3; }
    IFS=',' read -ra RAW_HOPS <<< "${MANUAL_PATH_RAW}"
    for hop in "${RAW_HOPS[@]}"; do
        trimmed="$(echo "${hop}" | xargs)"
        [[ -n "${trimmed}" ]] && UPGRADE_HOPS+=("${trimmed}")
    done
    PATH_SOURCE="Interactive input"
fi

# Final validation
if [[ ${#UPGRADE_HOPS[@]} -eq 0 ]]; then
    msg_err "Upgrade path must contain at least one target version."
    exit 3
fi

# Build JSON list for Ansible extra-vars
UPGRADE_PATH_JSON="["
for i in "${!UPGRADE_HOPS[@]}"; do
    [[ $i -gt 0 ]] && UPGRADE_PATH_JSON+=","
    UPGRADE_PATH_JSON+="\"${UPGRADE_HOPS[$i]}\""
done
UPGRADE_PATH_JSON+="]"

msg_ok "Configuration resolved successfully."

# ---------------------------------------------------------------------------
# Detect Ansible version
# ---------------------------------------------------------------------------
if command -v ansible-playbook &>/dev/null; then
    ANSIBLE_VERSION="$(ansible-playbook --version 2>/dev/null | head -1)"
else
    msg_warn "ansible-playbook not found in PATH (will attempt execution anyway)."
    ANSIBLE_VERSION="system default / PATH lookup"
fi

# ---------------------------------------------------------------------------
# Timestamp + log file path
# ---------------------------------------------------------------------------
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_DIR}/${CLUSTER_NAME}_${TIMESTAMP}.txt"

# ---------------------------------------------------------------------------
# Confirmation summary
# ---------------------------------------------------------------------------
echo ""
BOX_W=72
HLINE=$(printf '─%.0s' $(seq 1 $BOX_W))

printf "${C_CYAN}╭${HLINE}╮${C_RESET}\n"
printf "${C_CYAN}│${C_RESET} ${C_BOLD}%-$((BOX_W - 2))s${C_RESET} ${C_CYAN}│${C_RESET}\n" " ARO Cluster Upgrade — Confirmation Summary"
printf "${C_CYAN}├${HLINE}┤${C_RESET}\n"

print_row() {
    local label="$1"
    local value="$2"
    local max_val_len=$((BOX_W - 19))
    if [[ ${#value} -gt $max_val_len ]]; then
        value="${value:0:$((max_val_len - 3))}..."
    fi
    printf "${C_CYAN}│${C_RESET} %-16s %-${max_val_len}s ${C_CYAN}│${C_RESET}\n" "$label" "$value"
}

print_row "Cluster:" "${CLUSTER_NAME} (${CLUSTER_SOURCE})"
print_row "Upgrade path:" "${UPGRADE_HOPS[*]} (${PATH_SOURCE})"
print_row "Hops:" "${#UPGRADE_HOPS[@]}"
print_row "Dry run:" "${DRY_RUN}"
print_row "Log file:" "logs/$(basename "${LOG_FILE}")"
print_row "Ansible:" "${ANSIBLE_VERSION}"

printf "${C_CYAN}╰${HLINE}╯${C_RESET}\n"
echo ""

if [[ "${AUTO_YES}" != true ]]; then
    printf "${C_BOLD}Proceed with the above configuration? [y/N]: ${C_RESET}"
    read -r CONFIRM
    case "${CONFIRM}" in
        [yY]|[yY][eE][sS]) ;;
        *)
            echo ""
            msg_warn "Cancelled by user."
            exit 2
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# Build extra-vars (JSON object format ensures Ansible parses lists natively)
# ---------------------------------------------------------------------------
if [[ "${DRY_RUN}" == true ]]; then
    EXTRA_VARS="{\"cluster_name\":\"${CLUSTER_NAME}\",\"upgrade_path\":${UPGRADE_PATH_JSON},\"dry_run\":true}"
else
    EXTRA_VARS="{\"cluster_name\":\"${CLUSTER_NAME}\",\"upgrade_path\":${UPGRADE_PATH_JSON},\"dry_run\":false}"
fi

# ---------------------------------------------------------------------------
# Execution + logging
# ---------------------------------------------------------------------------
msg_step "Execution Phase"
msg_ok "Starting upgrade automation for cluster '${C_BOLD}${CLUSTER_NAME}${C_RESET}'..."
echo ""

PLAYBOOK="${SCRIPT_DIR}/main.yml"
START_TIME=$(date +%s)

# Run ansible-playbook; tee live output to log file.
PLAYBOOK_RC=0
ansible-playbook "${PLAYBOOK}" \
    -e "${EXTRA_VARS}" \
    2>&1 | tee "${LOG_FILE}" || PLAYBOOK_RC=${PIPESTATUS[0]}

# If PIPESTATUS didn't capture it (some bash versions), fall back
if [[ ${PLAYBOOK_RC} -eq 0 && ${PIPESTATUS[0]:-0} -ne 0 ]]; then
    PLAYBOOK_RC=${PIPESTATUS[0]}
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_STR=$(printf '%02dh:%02dm:%02ds\n' $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60)))

# ---------------------------------------------------------------------------
# Map exit codes to named classes
# ---------------------------------------------------------------------------
msg_step "Completion Phase"
case ${PLAYBOOK_RC} in
    0)
        msg_ok "Upgrade automation completed successfully for cluster '${C_BOLD}${CLUSTER_NAME}${C_RESET}'."
        ;;
    10)
        msg_err "Prevalidation failure (exit 10). Check report in ${OUTPUT_DIR}."
        ;;
    20)
        msg_err "Upgrade / phase failure (exit 20). Check log: ${LOG_FILE}"
        ;;
    30)
        msg_err "Timeout (exit 30). A monitoring loop exceeded its deadline."
        ;;
    *)
        msg_err "Unexpected error (exit ${PLAYBOOK_RC}). Check log: ${LOG_FILE}"
        PLAYBOOK_RC=99
        ;;
esac

echo ""
msg_info "Execution time: ${DURATION_STR}"
msg_info "Log written to: ${LOG_FILE}"
echo ""

exit ${PLAYBOOK_RC}
