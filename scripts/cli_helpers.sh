#!/usr/bin/env bash
# ============================================================================
# CLI Helper Library — ARO Cluster Upgrade Automation
# ============================================================================
# Targets: Bash 4.2+ (RHEL 8 / Linux / macOS)
# Purpose: Sourced library providing ANSI terminal colors, UTF-8 box-drawing
#          primitives (72-column standard), formatted message loggers,
#          interactive selection menus, ASCII banner art, visual journey diagrams,
#          risk assessment boxes, and structured post-run execution summaries.
# Dependencies: bash, sed, wc, tput (optional fallback)
# ============================================================================

# Prevent direct execution; must be sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: cli_helpers.sh is a library and must be sourced, not executed directly." >&2
    exit 1
fi

# Normalize locale to UTF-8 if unset or basic C, enabling proper character width measurement
if [[ -z "${LC_ALL:-}" && -z "${LANG:-}" ]]; then
    export LC_ALL="C.UTF-8" 2>/dev/null || export LANG="C.UTF-8" 2>/dev/null || true
elif [[ "${LANG:-}" == "C" || "${LC_ALL:-}" == "C" ]]; then
    if locale -a 2>/dev/null | grep -qi "C\.UTF-8\|en_US\.UTF-8"; then
        export LC_ALL="C.UTF-8" 2>/dev/null || true
    fi
fi

# ----------------------------------------------------------------------------
# ANSI Color & Style Constants (Terminal TTY Detection)
# ----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[0;31m'
    C_RED_BOLD=$'\033[1;31m'
    C_GREEN=$'\033[0;32m'
    C_GREEN_BOLD=$'\033[1;32m'
    C_AMBER=$'\033[0;33m'
    C_AMBER_BOLD=$'\033[1;33m'
    C_YELLOW=$'\033[0;33m'
    C_YELLOW_BOLD=$'\033[1;33m'
    C_BLUE=$'\033[0;34m'
    C_BLUE_BOLD=$'\033[1;34m'
    C_MAGENTA=$'\033[0;35m'
    C_MAGENTA_BOLD=$'\033[1;35m'
    C_CYAN=$'\033[0;36m'
    C_CYAN_BOLD=$'\033[1;36m'
    C_WHITE_BOLD=$'\033[1;37m'
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_RED_BOLD=""
    C_GREEN=""
    C_GREEN_BOLD=""
    C_AMBER=""
    C_AMBER_BOLD=""
    C_YELLOW=""
    C_YELLOW_BOLD=""
    C_BLUE=""
    C_BLUE_BOLD=""
    C_MAGENTA=""
    C_MAGENTA_BOLD=""
    C_CYAN=""
    C_CYAN_BOLD=""
    C_WHITE_BOLD=""
fi

# Backward-compatible aliases for Unit 01 definitions
COLOR_RESET="${C_RESET}"
COLOR_BOLD="${C_BOLD}"
COLOR_DIM="${C_DIM}"
COLOR_RED="${C_RED}"
COLOR_RED_BOLD="${C_RED_BOLD}"
COLOR_GREEN="${C_GREEN}"
COLOR_GREEN_BOLD="${C_GREEN_BOLD}"
COLOR_YELLOW="${C_YELLOW}"
COLOR_YELLOW_BOLD="${C_YELLOW_BOLD}"
COLOR_BLUE="${C_BLUE}"
COLOR_BLUE_BOLD="${C_BLUE_BOLD}"
COLOR_MAGENTA="${C_MAGENTA}"
COLOR_MAGENTA_BOLD="${C_MAGENTA_BOLD}"
COLOR_CYAN="${C_CYAN}"
COLOR_CYAN_BOLD="${C_CYAN_BOLD}"
COLOR_WHITE_BOLD="${C_WHITE_BOLD}"

# ----------------------------------------------------------------------------
# Box-Drawing Primitives (UTF-8 Standard 72-Column Width & ASCII Fallback)
# ----------------------------------------------------------------------------
# Detect terminal UTF-8 capability:
_has_utf8=false
if [[ "${LANG:-}" =~ [Uu][Tt][Ff]-?8 ]] || [[ "${LC_ALL:-}" =~ [Uu][Tt][Ff]-?8 ]] || [[ "${LC_CTYPE:-}" =~ [Uu][Tt][Ff]-?8 ]]; then
    _has_utf8=true
elif [[ -n "${WT_SESSION:-}" || -n "${TERM_PROGRAM:-}" || "${TERM:-}" =~ (xterm-256color|xterm|rxvt|screen|tmux) ]]; then
    _has_utf8=true
fi

if [[ "${ARO_CLI_ASCII:-false}" == "true" ]] || [[ "$_has_utf8" == "false" && "${LANG:-}" == "C" ]]; then
    BOX_TL="+"
    BOX_TR="+"
    BOX_BL="+"
    BOX_BR="+"
    BOX_H="-"
    BOX_V="|"
    BOX_ML="+"
    BOX_MR="+"
    CHAR_DEFAULT="*"
    CHAR_ARROW="-->"
else
    BOX_TL="╭"
    BOX_TR="╮"
    BOX_BL="╰"
    BOX_BR="╯"
    BOX_H="─"
    BOX_V="│"
    BOX_ML="├"
    BOX_MR="┤"
    CHAR_DEFAULT="★"
    CHAR_ARROW="──▶"
fi
BOX_WIDTH=72

# Strip ANSI color escape sequences to calculate visible character count
# Pure Bash pattern replacement: strips genuine ANSI bytes and literal escape strings without spawning subshells
strip_ansi() {
    local text="$1"
    local esc_pattern=$'\033\\[[0-9;?]*[a-zA-Z]'
    while [[ "$text" =~ $esc_pattern ]]; do
        text="${text//${BASH_REMATCH[0]}/}"
    done
    local lit_pattern='(\\033|\\e)\[[0-9;?]*[a-zA-Z]'
    while [[ "$text" =~ $lit_pattern ]]; do
        text="${text//${BASH_REMATCH[0]}/}"
    done
    printf "%s" "$text"
}

# Measure visible length of a string (excluding ANSI color escapes)
visible_length() {
    local raw="$1"
    local stripped
    stripped=$(strip_ansi "$raw")
    echo "${#stripped}"
}

# Draw a repeating horizontal line
draw_horizontal_line() {
    local width="${1:-$BOX_WIDTH}"
    local line=""
    local i
    for ((i=0; i<width; i++)); do line+="${BOX_H}"; done
    printf "%s\n" "$line"
}

# Draw top border with optional embedded title: ╭──── [ Title ] ────╮
# Accommodates 6 embellishment characters: " [ " (3) and " ] " (3)
draw_box_header() {
    local title="${1:-}"
    local inner_width=$((BOX_WIDTH - 2)) # 70
    local i
    
    if [[ -z "$title" ]]; then
        local bar=""
        for ((i=0; i<inner_width; i++)); do bar+="${BOX_H}"; done
        printf "${C_CYAN}%s%s%s${C_RESET}\n" "${BOX_TL}" "${bar}" "${BOX_TR}"
        return
    fi
    
    local title_len
    title_len=$(visible_length "$title")
    local total_title_len=$((title_len + 6)) # " [ " + title + " ] " is 6 characters
    
    if (( total_title_len >= inner_width )); then
        # Title too long for embellishment, print compact header
        printf "${C_CYAN}%s [ %s ] %s${C_RESET}\n" "${BOX_TL}" "$title" "${BOX_TR}"
        return
    fi
    
    local left_pad=$(( (inner_width - total_title_len) / 2 ))
    local right_pad=$(( inner_width - total_title_len - left_pad ))
    
    local left_bar=""
    for ((i=0; i<left_pad; i++)); do left_bar+="${BOX_H}"; done
    local right_bar=""
    for ((i=0; i<right_pad; i++)); do right_bar+="${BOX_H}"; done
    
    printf "${C_CYAN}%s%s${C_RESET} [ ${C_BOLD}%s${C_RESET} ] ${C_CYAN}%s%s${C_RESET}\n" \
        "${BOX_TL}" "${left_bar}" "$title" "${right_bar}" "${BOX_TR}"
}

# Draw middle divider row: ├──────────────────────────────────────────┤
draw_box_divider() {
    local inner_width=$((BOX_WIDTH - 2)) # 70
    local bar=""
    local i
    for ((i=0; i<inner_width; i++)); do bar+="${BOX_H}"; done
    printf "${C_CYAN}%s%s%s${C_RESET}\n" "${BOX_ML}" "${bar}" "${BOX_MR}"
}

# Draw bottom border: ╰──────────────────────────────────────────╯
draw_box_footer() {
    local inner_width=$((BOX_WIDTH - 2)) # 70
    local bar=""
    local i
    for ((i=0; i<inner_width; i++)); do bar+="${BOX_H}"; done
    printf "${C_CYAN}%s%s%s${C_RESET}\n" "${BOX_BL}" "${bar}" "${BOX_BR}"
}

# Draw an aligned row inside the box: │ content ... │
# Uses visible string length to guarantee right border aligns at column 72
draw_box_row() {
    local content="${1:-}"
    local inner_width=$((BOX_WIDTH - 4)) # 68 visible content area (excluding "│ " and " │")
    local vis_len
    vis_len=$(visible_length "$content")
    
    if (( vis_len > inner_width )); then
        # Content exceeds line; print without extra padding
        printf "${C_CYAN}%s${C_RESET} %s ${C_CYAN}%s${C_RESET}\n" "${BOX_V}" "$content" "${BOX_V}"
    else
        local pad_len=$(( inner_width - vis_len ))
        local padding=""
        printf -v padding "%*s" "$pad_len" ""
        printf "${C_CYAN}%s${C_RESET} %s%s ${C_CYAN}%s${C_RESET}\n" "${BOX_V}" "$content" "$padding" "${BOX_V}"
    fi
}

# ----------------------------------------------------------------------------
# Message Formatters & Terminal Loggers
# ----------------------------------------------------------------------------
msg_ok() {
    printf "${C_GREEN_BOLD}[ PASS ✔ ]${C_RESET} %s\n" "$*"
}

msg_warn() {
    printf "${C_AMBER_BOLD}[ WARN ! ]${C_RESET} %s\n" "$*"
}

msg_err() {
    printf "${C_RED_BOLD}[ FAIL ✖ ]${C_RESET} %s\n" "$*" >&2
}

msg_info() {
    printf "${C_CYAN}[ INFO ℹ ]${C_RESET} %s\n" "$*"
}

msg_step() {
    printf "${C_CYAN_BOLD}[ STEP ▶ ]${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$*"
}

msg_autofix() {
    printf "${C_BLUE_BOLD}[ AUTO-FIX ⚙ ]${C_RESET} %s\n" "$*"
}

# Backward-compatible logging aliases
log_info() { msg_info "$*"; }
log_success() { msg_ok "$*"; }
log_warn() { msg_warn "$*"; }
log_error() { msg_err "$*"; }
log_autofix() { msg_autofix "$*"; }

# ----------------------------------------------------------------------------
# ASCII Banner & Visual Branding
# ----------------------------------------------------------------------------
print_banner() {
    printf "${C_MAGENTA_BOLD}"
    cat << 'EOF'
  ___  ____   ___    _   _                                _      
 / _ \|  _ \ / _ \  | | | |_ __   __ _ _ __ __ _  __| | ___ 
| | | | |_) | | | | | | | | '_ \ / _` | '__/ _` |/ _` |/ _ \
| |_| |  _ <| |_| | | |_| | |_) | (_| | | | (_| | (_| |  __/
 \___/|_| \_\\___/   \___/| .__/ \__, |_|  \__,_|\__,_|\___|
                          |_|    |___/                      
EOF
    printf "${C_RESET}"
    printf "${C_CYAN_BOLD}  %s${C_RESET}\n" "ARO CLUSTER UPGRADE AUTOMATION — Version 2.0"
    printf "${C_DIM}  %s${C_RESET}\n\n" "Sequential Minor Upgrades & Automated Operator Lifecycle"
}

# ----------------------------------------------------------------------------
# Visual Upgrade Journey Formatter
# ----------------------------------------------------------------------------
# Example output:
# ╭─────────────────────── [ Planned Upgrade Journey ] ────────────────────────╮
# │ Current Version : 4.14.12                                                  │
# │ Target Hops     : 3 sequential hop(s)                                      │
# │ Journey Route   : 4.14.12 ──▶ 4.14.40 ──▶ 4.15.35 ──▶ 4.16.18             │
# ╰────────────────────────────────────────────────────────────────────────────╯
print_journey() {
    local current_version="${1:-Unknown}"
    shift || true
    local hops=("$@")
    local hop
    
    local route_str="${current_version}"
    for hop in "${hops[@]}"; do
        route_str+=" ${CHAR_ARROW:-──▶} ${hop}"
    done
    
    draw_box_header "Planned Upgrade Journey"
    draw_box_row "Current Version : ${C_BOLD}${current_version}${C_RESET}"
    draw_box_row "Target Hops     : ${#hops[@]} sequential hop(s)"
    draw_box_row "Journey Route   : ${C_CYAN_BOLD}${route_str}${C_RESET}"
    draw_box_footer
}

# ----------------------------------------------------------------------------
# Risk Assessment Box
# ----------------------------------------------------------------------------
print_risk_assessment() {
    local cluster="${1:-Unknown}"
    local tier="${2:-DEV}"
    local hop_count="${3:-1}"
    local est_duration="${4:-90}"
    
    local tier_color="${C_GREEN_BOLD}"
    local risk_badge="${C_GREEN_BOLD}LOW RISK ✔${C_RESET}"
    
    case "${tier^^}" in
        PROD|PRODUCTION)
            tier_color="${C_RED_BOLD}"
            risk_badge="${C_RED_BOLD}HIGH RISK (Production Workload) ✖${C_RESET}"
            ;;
        STAGE|STAGING|TEST|QA)
            tier_color="${C_AMBER_BOLD}"
            risk_badge="${C_AMBER_BOLD}MEDIUM RISK (Staging Environment) !${C_RESET}"
            ;;
        *)
            if (( hop_count > 2 )); then
                tier_color="${C_AMBER_BOLD}"
                risk_badge="${C_AMBER_BOLD}MEDIUM RISK (Multiple Minor Hops) !${C_RESET}"
            fi
            ;;
    esac
    
    draw_box_header "Pre-Upgrade Risk Assessment"
    draw_box_row "Target Cluster  : ${C_BOLD}${cluster}${C_RESET} (Tier: ${tier_color}${tier^^}${C_RESET})"
    draw_box_row "Execution Scope : ${hop_count} sequential minor version hop(s)"
    draw_box_row "Est. Duration   : ~${est_duration} minutes (~90 min/hop + settle)"
    draw_box_row "Risk Evaluation : ${risk_badge}"
    draw_box_footer
}

# ----------------------------------------------------------------------------
# Interactive Menu Selector (Numbered 72-Column Box)
# ----------------------------------------------------------------------------
# Usage:
#   options=("Option 1" "Option 2" "Option 3")
#   render_menu "Select Upgrade Mode" "${options[@]}" 1
#   selected_index=$? # 1-indexed
render_menu() {
    local title="$1"
    local default_idx="$2"
    shift 2
    local options=("$@")
    local num_options=${#options[@]}
    local i
    
    draw_box_header "$title"
    for ((i=1; i<=num_options; i++)); do
        local opt_text="${options[$((i-1))]}"
        local row_str
        if (( i == default_idx )); then
            row_str="  [${C_BOLD}${i}${C_RESET}] ${opt_text} ${C_GREEN_BOLD}${CHAR_DEFAULT:-★} (Default)${C_RESET}"
        else
            row_str="  [${i}] ${opt_text}"
        fi
        draw_box_row "$row_str"
    done
    draw_box_footer
    
    local choice=""
    while true; do
        printf "  Enter selection [1-%d, default: %d]: " "$num_options" "$default_idx"
        read -r choice
        
        # Use default if Enter was pressed with empty string
        if [[ -z "$choice" ]]; then
            choice="$default_idx"
        fi
        
        # Validate selection is a valid numeric index within range
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= num_options )); then
            export MENU_SELECTED_INDEX="$choice"
            export MENU_SELECTED_VALUE="${options[$((choice-1))]}"
            return "$choice"
        else
            printf "  ${C_RED_BOLD}Invalid selection '%s'. Please choose a number between 1 and %d.${C_RESET}\n" "$choice" "$num_options"
        fi
    done
}

# ----------------------------------------------------------------------------
# Structured Post-Run Execution Summary Table
# ----------------------------------------------------------------------------
render_post_run_summary() {
    local cluster="${1:-Unknown}"
    local verdict="${2:-FAIL}"
    local elapsed="${3:-0s}"
    local exit_code="${4:-99}"
    local log_file="${5:-N/A}"
    local pre_report="${6:-N/A}"
    local post_report="${7:-N/A}"
    local op_report="${8:-N/A}"
    
    local verdict_badge
    if [[ "$verdict" == "PASS" || "$exit_code" == "0" ]]; then
        verdict_badge="${C_GREEN_BOLD}SUCCESS (PASS ✔)${C_RESET}"
    elif [[ "$verdict" == "AUTO-FIXED" ]]; then
        verdict_badge="${C_BLUE_BOLD}SUCCESS (AUTO-FIXED ⚙)${C_RESET}"
    else
        verdict_badge="${C_RED_BOLD}FAILED (FAIL ✖) [Exit Code: ${exit_code}]${C_RESET}"
    fi
    
    draw_box_header "Post-Run Execution Summary"
    draw_box_row "Target Cluster : ${C_BOLD}${cluster}${C_RESET}"
    draw_box_row "Run Verdict    : ${verdict_badge}"
    draw_box_row "Total Duration : ${C_BOLD}${elapsed}${C_RESET}"
    draw_box_divider
    draw_box_row "${C_BOLD}Generated Artifacts & Diagnostic References:${C_RESET}"
    
    local pre_stat="${C_DIM}(Not Generated)${C_RESET}"
    [[ -f "$pre_report" || -f "${BASE_DIR:-.}/${pre_report}" ]] && pre_stat="${C_GREEN_BOLD}(Generated ✔)${C_RESET}"
    draw_box_row "  • Pre-validation HTML Report ${pre_stat}:"
    draw_box_row "    ${C_CYAN}${pre_report}${C_RESET}"
    
    local post_stat="${C_DIM}(Not Generated)${C_RESET}"
    [[ -f "$post_report" || -f "${BASE_DIR:-.}/${post_report}" ]] && post_stat="${C_GREEN_BOLD}(Generated ✔)${C_RESET}"
    draw_box_row "  • Post-validation HTML Report ${post_stat}:"
    draw_box_row "    ${C_CYAN}${post_report}${C_RESET}"
    
    local op_stat="${C_DIM}(Not Generated)${C_RESET}"
    [[ -f "$op_report" || -f "${BASE_DIR:-.}/${op_report}" ]] && op_stat="${C_GREEN_BOLD}(Generated ✔)${C_RESET}"
    draw_box_row "  • Operator Health HTML Report ${op_stat}:"
    draw_box_row "    ${C_CYAN}${op_report}${C_RESET}"
    
    draw_box_row "  • Execution Run Log:"
    draw_box_row "    ${C_CYAN}${log_file}${C_RESET}"
    draw_box_footer
}
