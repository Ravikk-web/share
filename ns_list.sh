#!/usr/bin/env bash
###############################################################################
# find_duplicate_appid_namespaces.sh
#
# PURPOSE
#   Scan every namespace definition in this repository, resolve each namespace
#   name + its App ID + the cluster(s) it targets, and report every App ID that
#   is associated with MORE THAN ONE namespace ON THE SAME CLUSTER.
#   Results are written to a CSV, ONE ROW PER NAMESPACE (exploded).
#
#   Example CSV:
#     "Cluster","App ID","Namespace Count","Namespaces"
#     "arop05","app00007051","2","app00007051-mcp-api"
#     "arop05","app00007051","2","app00007051-member-contact-preferences-api"
#
# CONFIRMED SCHEMA (verified via DIAGNOSE on the real repo):
#   values.yaml
#     project:
#       name: app00000061-blueaccess-producer-portal      <- namespace name
#       labels:
#         kubernetes.io/metadata.name: ...
#         hcsc/application-metallic-tier: tier-2
#       annotations:
#         hcsc/application-id: app00000061                 <- APP ID (here!)
#
#   clusters.yaml  (same folder)
#     clusters:
#       - name: arod05
#       - name: arot05
#
# HOW TO RUN  (script lives in, and is run from, the 'namespaces' folder)
#   ./find_duplicate_appid_namespaces.sh              # normal scan -> writes CSV
#   DEBUG=1    ./find_duplicate_appid_namespaces.sh   # + per-namespace mapping
#   DIAGNOSE=1 ./find_duplicate_appid_namespaces.sh   # schema inspection ONLY
#
#   NOTE: DIAGNOSE=1 inspects the first few files and EXITS WITHOUT SCANNING.
#         It intentionally does NOT produce the CSV. Run without DIAGNOSE=1
#         to actually generate the report.
#
# REQUIREMENTS
#   bash 4+, yq (mikefarah) v4+, find, sort
#
# EXIT CODES
#   0 success   |   1 usage / dependency / environment error
###############################################################################

set -o errexit
set -o nounset
set -o pipefail

###############################################################################
# CONFIGURATION  (all overridable via environment variables)
###############################################################################

# Root folder holding the per-namespace directories.
# The script sits INSIDE 'namespaces/', and each namespace is a sibling folder,
# so '.' is the correct default. ('../namespaces' also works from here.)
NAMESPACES_ROOT="${NAMESPACES_ROOT:-.}"

# Namespace NAME lookup inside values.yaml
NAME_YAML_PATH="${NAME_YAML_PATH:-.project.name}"
FALLBACK_TO_FOLDER_NAME="${FALLBACK_TO_FOLDER_NAME:-true}"

# App ID resolution mode: annotation | label | recursive | name_regex | auto
# CONFIRMED: the App ID lives under .project.annotations -> default 'annotation'.
APP_ID_SOURCE="${APP_ID_SOURCE:-annotation}"

# The bare key name used for the App ID.
APP_ID_KEY="${APP_ID_KEY:-hcsc/application-id}"

# Regex fallback: first capture group = App ID.
APP_ID_REGEX="${APP_ID_REGEX:-^(app[0-9]+)-}"

# Treat App IDs case-insensitively when grouping (APP00007051 == app00007051).
NORMALIZE_APPID_CASE="${NORMALIZE_APPID_CASE:-true}"

# ---- Cluster resolution -----------------------------------------------------
CLUSTERS_YAML_NAME="${CLUSTERS_YAML_NAME:-clusters.yaml}"
CLUSTERS_YAML_PATH="${CLUSTERS_YAML_PATH:-.clusters[].name}"
NO_CLUSTER_LABEL="${NO_CLUSTER_LABEL:-(unknown-cluster)}"

# Minimum namespaces an App ID must own (per cluster) to be reported.
MIN_COUNT="${MIN_COUNT:-2}"

# Namespaces to EXCLUDE (exact match against the resolved namespace name).
EXCLUDE_NAMESPACES=(
    "default" "openshift" "openshift-infra"
    "kube-system" "kube-public" "kube-node-lease"
)

OUTPUT_FILE="${OUTPUT_FILE:-duplicate_appid_namespaces.csv}"

###############################################################################
# HELPERS
###############################################################################

log()   { printf '%s\n'  "$*" >&2; }
debug() { [[ "${DEBUG:-0}" == "1" ]] && printf '  [debug] %s\n' "$*" >&2 || true; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

csv_wrap() { local v="${1:-}"; printf '"%s"' "${v//\"/\"\"}"; }

# Clean a yq result: strip CR (Git-Bash/Windows CRLF files), trim whitespace,
# and convert yq's literal "null" into an empty string.
clean() {
    local v="${1:-}"
    v="${v//$'\r'/}"                      # critical on MINGW64 / Windows repos
    v="${v#"${v%%[![:space:]]*}"}"        # ltrim
    v="${v%"${v##*[![:space:]]}"}"        # rtrim
    [[ "$v" == "null" ]] && v=""
    printf '%s' "$v"
}

is_excluded() {
    local ns="$1" ex
    for ex in "${EXCLUDE_NAMESPACES[@]}"; do
        [[ "$ns" == "$ex" ]] && return 0
    done
    return 1
}

# --- App ID lookup strategies ------------------------------------------------
get_from_label()      { clean "$(yq e ".project.labels[\"$APP_ID_KEY\"]"      "$1" 2>/dev/null || true)"; }
get_from_annotation() { clean "$(yq e ".project.annotations[\"$APP_ID_KEY\"]" "$1" 2>/dev/null || true)"; }

# Recursive: find the key ANYWHERE in the document, take the first hit.
get_recursive() {
    clean "$(yq e "[.. | select(tag == \"!!map\") | select(has(\"$APP_ID_KEY\")) | .[\"$APP_ID_KEY\"]] | .[0] // \"\"" "$1" 2>/dev/null || true)"
}

resolve_appid() {
    local file="$1" ns="$2" v=""
    case "$APP_ID_SOURCE" in
        annotation) v="$(get_from_annotation "$file")" ;;
        label)      v="$(get_from_label "$file")" ;;
        recursive)  v="$(get_recursive "$file")" ;;
        name_regex) [[ "$ns" =~ $APP_ID_REGEX ]] && v="${BASH_REMATCH[1]}" || v="" ;;
        auto)
            v="$(get_from_annotation "$file")"
            [[ -z "$v" ]] && v="$(get_from_label "$file")"
            [[ -z "$v" ]] && v="$(get_recursive "$file")"
            if [[ -z "$v" && "$ns" =~ $APP_ID_REGEX ]]; then v="${BASH_REMATCH[1]}"; fi
            ;;
    esac
    printf '%s' "$v"
}

###############################################################################
# PRE-FLIGHT
###############################################################################

command -v yq   >/dev/null 2>&1 || die "'yq' (mikefarah v4+) not found on PATH."
command -v find >/dev/null 2>&1 || die "'find' not available."
[[ -d "$NAMESPACES_ROOT" ]] || die "NAMESPACES_ROOT is not a directory: '$NAMESPACES_ROOT'"
[[ "$MIN_COUNT" =~ ^[0-9]+$ ]] || die "MIN_COUNT must be a positive integer."
case "$APP_ID_SOURCE" in
    auto|label|annotation|recursive|name_regex) : ;;
    *) die "APP_ID_SOURCE must be auto|label|annotation|recursive|name_regex" ;;
esac

###############################################################################
# DIAGNOSE MODE — inspect schema, then EXIT (does NOT produce the CSV)
###############################################################################
if [[ "${DIAGNOSE:-0}" == "1" ]]; then
    log "=== DIAGNOSE MODE : inspecting the first 3 values.yaml files ==="
    log "    (this mode does NOT scan or write the CSV — run without DIAGNOSE=1)"
    n=0
    while IFS= read -r f; do
        n=$((n+1)); (( n > 3 )) && break
        log ""
        log "FILE: $f"
        log "--- .project keys ---------------------------------------------"
        yq e '.project | keys' "$f" 2>&1 | sed 's/^/    /' >&2 || true
        log "--- .project.labels -------------------------------------------"
        yq e '.project.labels' "$f" 2>&1 | sed 's/^/    /' >&2 || true
        log "--- .project.annotations --------------------------------------"
        yq e '.project.annotations' "$f" 2>&1 | sed 's/^/    /' >&2 || true
        log "--- resolution results ----------------------------------------"
        log "    name        : '$(clean "$(yq e "$NAME_YAML_PATH" "$f" 2>/dev/null || true)")'"
        log "    label       : '$(get_from_label "$f")'"
        log "    annotation  : '$(get_from_annotation "$f")'"
        log "    recursive   : '$(get_recursive "$f")'"
        log "--- clusters.yaml ---------------------------------------------"
        cf="$(dirname "$f")/$CLUSTERS_YAML_NAME"
        if [[ -f "$cf" ]]; then
            yq e "$CLUSTERS_YAML_PATH" "$cf" 2>&1 | sed 's/^/    /' >&2 || true
        else
            log "    (no $CLUSTERS_YAML_NAME in this folder)"
            log "    sibling files: $(ls "$(dirname "$f")" | tr '\n' ' ')"
        fi
    done < <(find "$NAMESPACES_ROOT" -type f -name "values.yaml" | sort)
    log ""
    log "=== END DIAGNOSE (no CSV written) ==="
    exit 0
fi

###############################################################################
# OUTPUT FILE — created immediately, rows appended as found
###############################################################################

: > "$OUTPUT_FILE"
echo '"Cluster","App ID","Namespace Count","Namespaces"' >> "$OUTPUT_FILE"
log "Output file created: $OUTPUT_FILE"

###############################################################################
# MAIN
###############################################################################

log "----------------------------------------------------------------------"
log "Duplicate App-ID scan (per cluster)"
log "  Root            : $NAMESPACES_ROOT"
log "  Name source     : yq '$NAME_YAML_PATH'"
log "  App ID source   : $APP_ID_SOURCE   (key: $APP_ID_KEY)"
log "  Cluster source  : $CLUSTERS_YAML_NAME -> yq '$CLUSTERS_YAML_PATH'"
log "  Min. count      : $MIN_COUNT"
log "----------------------------------------------------------------------"

declare -A appid_count=()       # cluster|appid -> namespace count
declare -A appid_list=()        # cluster|appid -> ';'-joined namespace names
declare -A appid_display=()     # normalized id -> original-cased id

scanned=0; skipped=0; no_name=0; no_appid=0; no_cluster=0; files_found=0

while IFS= read -r file; do
    files_found=$((files_found+1))
    dir="$(dirname "$file")"

    # ---- namespace NAME -----------------------------------------------------
    ns="$(clean "$(yq e "$NAME_YAML_PATH" "$file" 2>/dev/null || true)")"
    if [[ -z "$ns" ]]; then
        if [[ "$FALLBACK_TO_FOLDER_NAME" == "true" ]]; then
            ns="$(basename "$dir")"
        else
            no_name=$((no_name+1)); skipped=$((skipped+1)); continue
        fi
    fi

    if is_excluded "$ns"; then
        skipped=$((skipped+1)); continue
    fi

    # ---- App ID -------------------------------------------------------------
    appid="$(resolve_appid "$file" "$ns")"
    if [[ -z "$appid" ]]; then
        debug "NO APP-ID for '$ns'  ($file)"
        no_appid=$((no_appid+1)); skipped=$((skipped+1)); continue
    fi

    if [[ "$NORMALIZE_APPID_CASE" == "true" ]]; then
        idkey="$(printf '%s' "$appid" | tr '[:upper:]' '[:lower:]')"
    else
        idkey="$appid"
    fi
    appid_display["$idkey"]="$appid"

    # ---- cluster(s) ---------------------------------------------------------
    cluster_file="$dir/$CLUSTERS_YAML_NAME"
    clusters=()
    if [[ -f "$cluster_file" ]]; then
        while IFS= read -r cl; do
            cl="$(clean "$cl")"
            [[ -z "$cl" ]] && continue
            clusters+=("$cl")
        done < <(yq e "$CLUSTERS_YAML_PATH" "$cluster_file" 2>/dev/null || true)
    fi
    if (( ${#clusters[@]} == 0 )); then
        clusters=("$NO_CLUSTER_LABEL"); no_cluster=$((no_cluster+1))
    fi

    # ---- bucket -------------------------------------------------------------
    for cl in "${clusters[@]}"; do
        key="${cl}|${idkey}"
        appid_count["$key"]=$(( ${appid_count["$key"]:-0} + 1 ))
        if [[ -z "${appid_list["$key"]:-}" ]]; then
            appid_list["$key"]="$ns"
        else
            appid_list["$key"]="${appid_list["$key"]};$ns"
        fi
        debug "'$ns' -> cluster '$cl' -> app-id '$appid'"
    done
    scanned=$((scanned+1))

done < <(find "$NAMESPACES_ROOT" -type f -name "values.yaml" | sort)

###############################################################################
# EMIT RESULTS — one row per namespace
###############################################################################

dup_total=0
if (( ${#appid_count[@]} > 0 )); then
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        count=${appid_count["$key"]:-0}
        (( count >= MIN_COUNT )) || continue

        cluster="${key%%|*}"
        idkey="${key##*|}"
        appid="${appid_display["$idkey"]:-$idkey}"

        IFS=';' read -ra ns_arr <<< "${appid_list["$key"]}"
        for one_ns in "${ns_arr[@]}"; do
            printf '%s,%s,%s,%s\n' \
                "$(csv_wrap "$cluster")" "$(csv_wrap "$appid")" \
                "$(csv_wrap "$count")"   "$(csv_wrap "$one_ns")" >> "$OUTPUT_FILE"
        done
        log "  DUPLICATE: [$cluster] $appid -> $count namespaces"
        dup_total=$((dup_total+1))
    done < <(printf '%s\n' "${!appid_count[@]}" | sort)
fi

###############################################################################
# SUMMARY
###############################################################################

log "----------------------------------------------------------------------"
log "values.yaml files found : $files_found"
log "Namespaces processed    : $scanned"
log "Namespaces skipped      : $skipped   (no name: $no_name, no app-id: $no_appid)"
log "Namespaces w/o cluster  : $no_cluster  (reported as $NO_CLUSTER_LABEL)"
if (( dup_total == 0 )); then
    log "Result                  : no duplicate app-ids found."
    (( scanned == 0 )) && log "HINT: try  DIAGNOSE=1 $0   to inspect the schema."
else
    log "Result                  : $dup_total duplicate app-id group(s)."
fi
log "Output                  : $OUTPUT_FILE"
log "----------------------------------------------------------------------"

exit 0
