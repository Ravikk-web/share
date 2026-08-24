#!/usr/bin/env bash
###############################################################################
# find_duplicate_appid_namespaces.sh
#
# PURPOSE
#   Scan every namespace definition in this repository, resolve each namespace
#   name, derive its "App ID", and report every App ID that is associated with
#   MORE THAN ONE namespace. Results are written to a CSV file.
#
#   Example:
#     app123445679-namespace1
#     app123445679-namespace2   -> App ID "app123445679" has 2 namespaces  (REPORTED)
#     appr214215122-namespace3  -> single namespace                        (SKIPPED)
#
# HOW IT MIRRORS THE REFERENCE SCRIPT
#   - Discovers namespaces the same way: find <root> -name "values.yaml".
#   - Resolves the namespace NAME from values.yaml via yq (NOT the folder name),
#     which is what the reference does on its (obscured) name= line.
#   - Uses the same yq (mikefarah v4) 'eval' syntax.
#
# APP ID CAN BE DERIVED TWO WAYS (see APP_ID_SOURCE below):
#   1) "name_regex"  -> parse the prefix out of the namespace name (default).
#   2) "annotation"  -> read an explicit annotation (e.g. .../application-id),
#                       which the reference had commented out.
#
# USAGE
#   ./find_duplicate_appid_namespaces.sh                 # normal run
#   DEBUG=1 ./find_duplicate_appid_namespaces.sh         # verbose per-namespace log
#
# REQUIREMENTS
#   - bash 4+          (associative arrays)
#   - yq  (mikefarah)  v4+   ->  https://github.com/mikefarah/yq
#   - find, sort       (coreutils / findutils)
#
# EXIT CODES
#   0  success (ran cleanly; duplicates may or may not exist)
#   1  usage / dependency / environment error
###############################################################################

set -o errexit      # exit on any unhandled command failure
set -o nounset      # error on use of unset variables
set -o pipefail     # a pipeline fails if ANY stage fails

###############################################################################
# CONFIGURATION
###############################################################################

# Root folder that contains the per-namespace directories.
# Override at runtime:  NAMESPACES_ROOT=./namespaces ./find_duplicate_appid_namespaces.sh
NAMESPACES_ROOT="${NAMESPACES_ROOT:-../namespaces}"

# yq path to the namespace NAME inside each values.yaml.
# The reference resolves the name from the YAML (not the folder). Adjust if your
# schema differs (common alternatives: '.namespace', '.metadata.name').
NAME_YAML_PATH="${NAME_YAML_PATH:-.project.metadata.name}"

# If the yq name lookup returns nothing/null, fall back to the folder name?
#   true  -> use the directory name when the YAML has no name
#   false -> skip the namespace and log a warning
FALLBACK_TO_FOLDER_NAME="${FALLBACK_TO_FOLDER_NAME:-true}"

# How to derive the App ID:  "name_regex"  or  "annotation"
APP_ID_SOURCE="${APP_ID_SOURCE:-name_regex}"

# [name_regex mode] Regex applied to the namespace name.
#   The FIRST capture group ( ... ) is taken as the App ID.
#   Default: "app" + digits, up to the first dash.  app123445679-ns1 -> app123445679
APP_ID_REGEX="${APP_ID_REGEX:-^(app[0-9]+)-}"

# [annotation mode] yq path to the App ID annotation inside values.yaml.
# NOTE: keys containing '/' MUST use bracket/quote form in yq v4.
APP_ID_YAML_PATH="${APP_ID_YAML_PATH:-.project.annotations[\"hcsc/application-id\"]}"

# Minimum namespaces an App ID must own to be reported.
MIN_COUNT="${MIN_COUNT:-2}"

# Namespaces to EXCLUDE (exact match against the resolved namespace name).
EXCLUDE_NAMESPACES=(
    "default"
    "openshift"
    "openshift-infra"
    "kube-system"
    "kube-public"
    "kube-node-lease"
)

# Output CSV file.
OUTPUT_FILE="${OUTPUT_FILE:-duplicate_appid_namespaces.csv}"

###############################################################################
# INTERNAL HELPERS
###############################################################################

log()   { printf '%s\n'  "$*" >&2; }
debug() { [[ "${DEBUG:-0}" == "1" ]] && printf '  [debug] %s\n' "$*" >&2 || true; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# CSV-safe: wrap a value in double quotes and escape embedded quotes (RFC 4180).
csv_wrap() {
    local val="${1:-}"
    printf '"%s"' "${val//\"/\"\"}"
}

# True (0) if the given namespace name is in the exclude list.
is_excluded() {
    local ns="$1" ex
    for ex in "${EXCLUDE_NAMESPACES[@]}"; do
        [[ "$ns" == "$ex" ]] && return 0
    done
    return 1
}

###############################################################################
# PRE-FLIGHT VALIDATION
###############################################################################

command -v yq   >/dev/null 2>&1 || die "'yq' (mikefarah v4+) is not installed or not on PATH."
command -v find >/dev/null 2>&1 || die "'find' is not available."

[[ -d "$NAMESPACES_ROOT" ]] || die "NAMESPACES_ROOT does not exist or is not a directory: '$NAMESPACES_ROOT'"

case "$APP_ID_SOURCE" in
    name_regex|annotation) : ;;
    *) die "APP_ID_SOURCE must be 'name_regex' or 'annotation' (got '$APP_ID_SOURCE')." ;;
esac

[[ "$MIN_COUNT" =~ ^[0-9]+$ ]] || die "MIN_COUNT must be a positive integer (got '$MIN_COUNT')."

###############################################################################
# MAIN
###############################################################################

log "----------------------------------------------------------------------"
log "Duplicate App-ID scan"
log "  Root            : $NAMESPACES_ROOT"
log "  Name source     : yq '$NAME_YAML_PATH' (fallback to folder: $FALLBACK_TO_FOLDER_NAME)"
log "  App ID source   : $APP_ID_SOURCE"
[[ "$APP_ID_SOURCE" == "name_regex" ]] && log "  App ID regex    : $APP_ID_REGEX"
[[ "$APP_ID_SOURCE" == "annotation" ]] && log "  App ID yq path  : $APP_ID_YAML_PATH"
log "  Min. count      : $MIN_COUNT"
log "----------------------------------------------------------------------"

# Buckets keyed by App ID.
declare -A appid_count=()     # App ID -> number of namespaces
declare -A appid_list=()      # App ID -> ';'-joined namespace names

scanned=0     # namespaces successfully processed
skipped=0     # namespaces skipped (no name / no app-id / excluded)

# Process substitution (NOT a pipe) so the arrays persist in this shell.
while IFS= read -r file; do
    dir="$(dirname "$file")"

    # ---- Resolve namespace NAME (from YAML, per the reference) --------------
    ns="$(yq e "$NAME_YAML_PATH" "$file" 2>/dev/null || true)"
    if [[ -z "$ns" || "$ns" == "null" ]]; then
        if [[ "$FALLBACK_TO_FOLDER_NAME" == "true" ]]; then
            ns="$(basename "$dir")"
            debug "name not found in YAML, using folder name: $ns  ($file)"
        else
            log "  WARN: no namespace name in '$file' — skipping."
            skipped=$((skipped + 1))
            continue
        fi
    fi

    # ---- Exclusions ---------------------------------------------------------
    if is_excluded "$ns"; then
        debug "excluded: $ns"
        skipped=$((skipped + 1))
        continue
    fi

    # ---- Derive the App ID --------------------------------------------------
    appid=""
    if [[ "$APP_ID_SOURCE" == "name_regex" ]]; then
        if [[ "$ns" =~ $APP_ID_REGEX ]]; then
            appid="${BASH_REMATCH[1]}"
        fi
    else # annotation
        appid="$(yq e "$APP_ID_YAML_PATH" "$file" 2>/dev/null || true)"
        [[ "$appid" == "null" ]] && appid=""
    fi

    if [[ -z "$appid" ]]; then
        debug "no app-id for namespace: $ns"
        skipped=$((skipped + 1))
        continue
    fi

    # ---- Bucket the namespace under its App ID ------------------------------
    appid_count["$appid"]=$(( ${appid_count["$appid"]:-0} + 1 ))
    if [[ -z "${appid_list["$appid"]:-}" ]]; then
        appid_list["$appid"]="$ns"
    else
        appid_list["$appid"]="${appid_list["$appid"]};$ns"
    fi
    scanned=$((scanned + 1))
    debug "namespace '$ns' -> app-id '$appid'"

done < <(find "$NAMESPACES_ROOT" -type f -name "values.yaml" | sort)

# ---- Write CSV (only App IDs owning >= MIN_COUNT namespaces) ----------------
: > "$OUTPUT_FILE"                                   # truncate/create
echo '"App ID","Namespace Count","Namespaces"' >> "$OUTPUT_FILE"

dup_total=0
# Sort the App IDs for stable, readable output.
while IFS= read -r appid; do
    count=${appid_count["$appid"]}
    (( count >= MIN_COUNT )) || continue
    printf '%s,%s,%s\n' \
        "$(csv_wrap "$appid")" \
        "$(csv_wrap "$count")" \
        "$(csv_wrap "${appid_list["$appid"]}")" >> "$OUTPUT_FILE"
    log "  DUPLICATE: $appid -> $count namespaces"
    dup_total=$((dup_total + 1))
done < <(printf '%s\n' "${!appid_count[@]}" | sort)

# ---- Summary ----------------------------------------------------------------
log "----------------------------------------------------------------------"
log "Namespaces processed : $scanned"
log "Namespaces skipped   : $skipped"
if (( dup_total == 0 )); then
    log "Result               : no duplicate app-ids found."
else
    log "Result               : $dup_total duplicate app-id group(s)."
fi
log "Output               : $OUTPUT_FILE"
log "----------------------------------------------------------------------"

exit 0
