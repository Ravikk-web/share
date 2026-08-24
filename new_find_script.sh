#!/bin/bash
#
# find_duplicate_appid_namespaces.sh
# ------------------------------------------------------------------------------
# Purpose : Walk EVERY namespace folder in this repo, determine the namespace
#           name, extract its App ID, and report any App ID that is associated
#           with MORE THAN ONE namespace. Output saved to CSV.
#
#           Run this from inside the repo (same as the example script).
#           No cluster filtering, no oc — pure repo scan.
#
# Namespace name resolution (per folder):
#   1) Try to read it from values.yaml using NAME_YAML_PATH (if set + found)
#   2) Otherwise fall back to the FOLDER NAME
#
# Example : app123445679-namespace1
#           app123445679-namespace2   -> "app123445679" has 2 -> reported
#           appr214215122-namespace3  -> single             -> NOT reported
#
# Requires: bash 4+, yq (only used if NAME_YAML_PATH is set)
# ------------------------------------------------------------------------------

set -uo pipefail

# ============================== CONFIG ========================================
# Root folder that holds the per-namespace directories.
NAMESPACES_ROOT="../namespaces"

# How to get the namespace name from each folder's values.yaml.
#   - Leave EMPTY ("") to just use the FOLDER NAME as the namespace name.
#   - Or set a yq path, e.g. '.namespace' or '.project.metadata.name'
#     If the path is missing/empty for a folder, it falls back to the folder name.
NAME_YAML_PATH=""

# Regex to extract the App ID from the namespace name.
# FIRST capture group ( ... ) = App ID. Default: "app" + digits before first dash.
#   app123445679-namespace1 -> app123445679
APP_ID_REGEX='^(app[0-9]+)-'

# An App ID must own at least this many namespaces to be reported.
MIN_COUNT=2

# Namespaces to EXCLUDE (exact name match).
EXCLUDE_NAMESPACES=(
    "default"
    "openshift"
    "openshift-infra"
    "kube-system"
    "kube-public"
    "kube-node-lease"
)

# Output file
OUTPUT_FILE="duplicate_appid_namespaces.csv"
# ==============================================================================

is_excluded() {
    local ns="$1" ex
    for ex in "${EXCLUDE_NAMESPACES[@]}"; do
        [[ "$ns" == "$ex" ]] && return 0
    done
    return 1
}

# CSV header
echo '"App ID","Namespace Count","Namespaces"' > "$OUTPUT_FILE"

declare -A appid_count=()
declare -A appid_list=()

echo "Scanning namespace folders under: $NAMESPACES_ROOT"
scanned=0

# Walk every namespace folder (identified by its values.yaml)
while read -r file; do
    dir="$(dirname "$file")"

    # ---- Resolve the namespace name -----------------------------------------
    ns="$(basename "$dir")"          # default: folder name
    if [[ -n "$NAME_YAML_PATH" ]]; then
        val="$(yq e "$NAME_YAML_PATH" "$file" 2>/dev/null)"
        # yq prints 'null' when the path doesn't exist
        if [[ -n "$val" && "$val" != "null" ]]; then
            ns="$val"
        fi
    fi

    # Skip excluded namespaces
    is_excluded "$ns" && continue

    scanned=$(( scanned + 1 ))

    # ---- Extract the App ID and bucket the namespace ------------------------
    if [[ "$ns" =~ $APP_ID_REGEX ]]; then
        appid="${BASH_REMATCH[1]}"
        appid_count["$appid"]=$(( ${appid_count["$appid"]:-0} + 1 ))
        if [[ -z "${appid_list["$appid"]:-}" ]]; then
            appid_list["$appid"]="$ns"
        else
            appid_list["$appid"]="${appid_list["$appid"]};$ns"
        fi
    fi
done < <(find "$NAMESPACES_ROOT" -type f -name "values.yaml")

# ---- Emit only app-ids that own >= MIN_COUNT namespaces ---------------------
dup_total=0
for appid in "${!appid_count[@]}"; do
    count=${appid_count["$appid"]}
    if (( count >= MIN_COUNT )); then
        echo "\"$appid\",\"$count\",\"${appid_list["$appid"]}\"" >> "$OUTPUT_FILE"
        echo "  DUPLICATE: $appid -> $count namespaces"
        dup_total=$(( dup_total + 1 ))
    fi
done

echo "----------------------------------------------------------------------"
echo "Namespaces scanned : $scanned"
(( dup_total == 0 )) && echo "No duplicate app-ids found."
echo "Done. $dup_total duplicate app-id group(s) written to: $OUTPUT_FILE"
