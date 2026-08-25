#!/usr/bin/env bash
###############################################################################
# find_duplicate_appid_namespaces.sh
#
# PURPOSE
#   Scan every namespace definition in this repository, resolve each namespace
#   name + its App ID + the cluster(s) it targets, and report every App ID that
#   is associated with MORE THAN ONE namespace ON THE SAME CLUSTER.
#   Results are written to a CSV, ONE ROW PER NAMESPACE (exploded), including
#   the cluster it belongs to.
#
#   Example CSV:
#     "Cluster","App ID","Namespace Count","Namespaces"
#     "arop05","app00007051","2","app00007051-mcp-api"
#     "arop05","app00007051","2","app00007051-member-contact-preferences-api"
#
# CONFIRMED SCHEMA (values.yaml):
#   project:
#     name: app00237094-claims-payment-integrity-solution   <- namespace name
#     labels:
#       hcsc/application-id: APP00237094                     <- App ID
#
# CLUSTER SOURCE (clusters.yaml, same folder as values.yaml):
#   clusters:
#     - name: arop05
#     - name: arot05
#
# BEHAVIOUR NOTES
#   - Grouping is PER CLUSTER: an App ID must own >= MIN_COUNT namespaces on the
#     SAME cluster to be reported for that cluster.
#   - The CSV file + header are created IMMEDIATELY (before scanning); qualifying
#     rows are APPENDED as they are determined.
#
# USAGE
#   ./find_duplicate_appid_namespaces.sh                 # normal run
#   DEBUG=1 ./find_duplicate_appid_namespaces.sh         # verbose per-namespace log
#
# REQUIREMENTS
#   - bash 4+          (associative arrays)
#   - yq  (mikefarah)  v4+
#   - find, sort
#
# EXIT CODES
#   0  success (ran cleanly; duplicates may or may not exist)
#   1  usage / dependency / environment error
###############################################################################

set -o errexit
set -o nounset
set -o pipefail

###############################################################################
# CONFIGURATION  (all overridable via environment variables)
###############################################################################

# Root folder that contains the per-namespace directories.
NAMESPACES_ROOT="${NAMESPACES_ROOT:-../namespaces}"

# yq path to the namespace NAME inside each values.yaml.
NAME_YAML_PATH="${NAME_YAML_PATH:-.project.name}"

# If the yq name lookup returns nothing/null, fall back to the folder name?
FALLBACK_TO_FOLDER_NAME="${FALLBACK_TO_FOLDER_NAME:-true}"

# How to derive the App ID:  "annotation" (label) or "name_regex"
APP_ID_SOURCE="${APP_ID_SOURCE:-annotation}"

# [annotation mode] yq path to the App ID LABEL inside values.yaml.
# NOTE: keys containing '/' MUST use bracket/quote form in yq v4.
APP_ID_YAML_PATH="${APP_ID_YAML_PATH:-.project.labels[\"hcsc/application-id\"]}"

# [name_regex mode] first capture group = App ID.
APP_ID_REGEX="${APP_ID_REGEX:-^(app[0-9]+)-}"

# ---- Cluster resolution -----------------------------------------------------
# File (relative to each namespace folder) that lists the target clusters.
CLUSTERS_YAML_NAME="${CLUSTERS_YAML_NAME:-clusters.yaml}"
# yq path to the list of cluster names inside that file.
CLUSTERS_YAML_PATH="${CLUSTERS_YAML_PATH:-.clusters[].name}"
# Label used when a namespace has no clusters.yaml / no clusters listed.
NO_CLUSTER_LABEL="${NO_CLUSTER_LABEL:-(unknown-cluster)}"

# Minimum namespaces an App ID must own (per cluster) to be reported.
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
# OUTPUT FILE — create + write header IMMEDIATELY (before scanning)
###############################################################################

: > "$OUTPUT_FILE"                                             # create/truncate now
echo '"Cluster","App ID","Namespace Count","Namespaces"' >> "$OUTPUT_FILE"
log "Output file created: $OUTPUT_FILE"

###############################################################################
# MAIN
###############################################################################

log "----------------------------------------------------------------------"
log "Duplicate App-ID scan (per cluster)"
log "  Root            : $NAMESPACES_ROOT"
log "  Name source     : yq '$NAME_YAML_PATH' (fallback to folder: $FALLBACK_TO_FOLDER_NAME)"
log "  App ID source   : $APP_ID_SOURCE"
[[ "$APP_ID_SOURCE" == "annotation" ]] && log "  App ID yq path  : $APP_ID_YAML_PATH"
[[ "$APP_ID_SOURCE" == "name_regex" ]] && log "  App ID regex    : $APP_ID_REGEX"
log "  Cluster source  : $CLUSTERS_YAML_NAME -> yq '$CLUSTERS_YAML_PATH'"
log "  Min. count      : $MIN_COUNT"
log "----------------------------------------------------------------------"

# Buckets keyed by "cluster|appid":
declare -A appid_count=()     # cluster|appid -> number of namespaces
declare -A appid_list=()      # cluster|appid -> ';'-joined namespace names

scanned=0
skipped=0

while IFS= read -r file; do
    dir="$(dirname "$file")"

    # ---- Resolve namespace NAME (from YAML) ---------------------------------
    ns="$(yq e "$NAME_YAML_PATH" "$file" 2>/dev/null || true)"
    if [[ -z "$ns" || "$ns" == "null" ]]; then
        if [[ "$FALLBACK_TO_FOLDER_NAME" == "true" ]]; then
            ns="$(basename "$dir")"
            debug "name not found in YAML, using folder name: $ns  ($file)"
        else
            log "  WARN: no namespace name in '$file' — skipping."
            skipped=$((skipped + 1)); continue
        fi
    fi

    # ---- Exclusions ---------------------------------------------------------
    if is_excluded "$ns"; then
        debug "excluded: $ns"; skipped=$((skipped + 1)); continue
    fi

    # ---- Derive the App ID --------------------------------------------------
    appid=""
    if [[ "$APP_ID_SOURCE" == "annotation" ]]; then
        appid="$(yq e "$APP_ID_YAML_PATH" "$file" 2>/dev/null || true)"
        [[ "$appid" == "null" ]] && appid=""
    else
        [[ "$ns" =~ $APP_ID_REGEX ]] && appid="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$appid" ]]; then
        debug "no app-id for namespace: $ns"; skipped=$((skipped + 1)); continue
    fi

    # ---- Resolve the cluster(s) this namespace targets ----------------------
    cluster_file="$dir/$CLUSTERS_YAML_NAME"
    clusters=()
    if [[ -f "$cluster_file" ]]; then
        while IFS= read -r cl; do
            [[ -z "$cl" || "$cl" == "null" ]] && continue
            clusters+=("$cl")
        done < <(yq e "$CLUSTERS_YAML_PATH" "$cluster_file" 2>/dev/null || true)
    fi
    # Fallback when no clusters found
    (( ${#clusters[@]} == 0 )) && clusters=("$NO_CLUSTER_LABEL")

    # ---- Bucket this namespace under each cluster|appid ---------------------
    for cl in "${clusters[@]}"; do
        key="${cl}|${appid}"
        appid_count["$key"]=$(( ${appid_count["$key"]:-0} + 1 ))
        if [[ -z "${appid_list["$key"]:-}" ]]; then
            appid_list["$key"]="$ns"
        else
            appid_list["$key"]="${appid_list["$key"]};$ns"
        fi
        debug "namespace '$ns' -> cluster '$cl' -> app-id '$appid'"
    done
    scanned=$((scanned + 1))

done < <(find "$NAMESPACES_ROOT" -type f -name "values.yaml" | sort)

###############################################################################
# EMIT RESULTS — one row PER NAMESPACE, appended as determined
###############################################################################

dup_total=0
# Only iterate if we actually collected at least one bucket. Expanding the keys
# of an EMPTY associative array would emit a blank line and trigger a
# "bad array subscript" error on the empty key below — so guard against it.
if (( ${#appid_count[@]} > 0 )); then
    # Sort keys for stable, grouped output (cluster then app id).
    while IFS= read -r key; do
        # Defensive: skip any empty key (should not happen, but keeps us safe).
        [[ -z "$key" ]] && continue

        count=${appid_count["$key"]:-0}
        (( count >= MIN_COUNT )) || continue

        cluster="${key%%|*}"        # part before '|'
        appid="${key##*|}"          # part after  '|'

        # Explode: write one row for each namespace under this cluster|appid.
        IFS=';' read -ra ns_arr <<< "${appid_list["$key"]}"
        for one_ns in "${ns_arr[@]}"; do
            printf '%s,%s,%s,%s\n' \
                "$(csv_wrap "$cluster")" \
                "$(csv_wrap "$appid")" \
                "$(csv_wrap "$count")" \
                "$(csv_wrap "$one_ns")" >> "$OUTPUT_FILE"
        done
        log "  DUPLICATE: [$cluster] $appid -> $count namespaces"
        dup_total=$((dup_total + 1))
    done < <(printf '%s\n' "${!appid_count[@]}" | sort)
fi

###############################################################################
# SUMMARY
###############################################################################

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
