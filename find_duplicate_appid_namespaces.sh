#!/bin/bash
#
# find_duplicate_appid_namespaces.sh
# ------------------------------------------------------------------------------
# Purpose : Scan the namespace folders in THIS repository and identify "App IDs"
#           that own MORE THAN ONE namespace (i.e. multiple namespaces share the
#           same app-id prefix) for each cluster, then save the result to a CSV.
#
#           Run this from inside the repo (same as the example script).
#           NOTE: All clusters are scanned in a SINGLE pass over the repo.
#
# Example : Repo contains the namespaces
#             app123445679-namespace1
#             app123445679-namespace2
#             appr214215122-namespace3
#           => "app123445679" has 2 namespaces  -> reported
#           => "appr214215122" has 1 namespace  -> NOT reported (single)
#
# How it works (mirrors your example):
#   - Finds every namespaces/<name>/values.yaml
#   - Namespace name  = the folder name (dirname of values.yaml)
#   - Cluster mapping = read from that namespace's clusters.yaml (.clusters[].name)
#   - App ID          = extracted from the namespace name via APP_ID_REGEX
#   - Buckets keyed by "cluster|appid" so every cluster is handled together.
#
# Requires: bash 4+, yq (same dependency your example uses)
# ------------------------------------------------------------------------------

set -uo pipefail

# ============================== CONFIG ========================================
# 1) Root folder that holds the per-namespace directories.
NAMESPACES_ROOT="../namespaces"

# 2) List of clusters to consider. A namespace is only counted for a cluster
#    if that cluster appears in the namespace's clusters.yaml (.clusters[].name).
CLUSTERS=("cluster-prod" "cluster-test" "cluster-dev")

# 3) Regex used to extract the App ID from a namespace name.
#    FIRST capture group ( ... ) = the App ID.
#    Default: "app" followed by digits, up to the first dash.
#      app123445679-namespace1 -> app123445679
APP_ID_REGEX='^(app[0-9]+)-'

# 4) An App ID must own at least this many namespaces (per cluster) to be reported.
MIN_COUNT=2

# 5) Namespaces to EXCLUDE from the scan entirely (exact folder-name match).
EXCLUDE_NAMESPACES=(
    "default"
    "openshift"
    "openshift-infra"
    "kube-system"
    "kube-public"
    "kube-node-lease"
)

# 6) Output file
OUTPUT_FILE="duplicate_appid_namespaces.csv"
# ==============================================================================

# --- helper: is $1 present in the EXCLUDE_NAMESPACES list? ---------------------
is_excluded() {
    local ns="$1" ex
    for ex in "${EXCLUDE_NAMESPACES[@]}"; do
        [[ "$ns" == "$ex" ]] && return 0
    done
    return 1
}

# --- helper: is $1 present in the CLUSTERS list? ------------------------------
is_wanted_cluster() {
    local c="$1" w
    for w in "${CLUSTERS[@]}"; do
        [[ "$c" == "$w" ]] && return 0
    done
    return 1
}

# Write CSV header
echo '"Cluster","App ID","Namespace Count","Namespaces"' > "$OUTPUT_FILE"

# Single-pass buckets, keyed by "cluster|appid":
#   appid_count -> how many namespaces share each cluster|appid
#   appid_list  -> the namespace names (';' separated) for each cluster|appid
declare -A appid_count=()
declare -A appid_list=()

echo "Scanning all clusters in a single pass..."

# ---- ONE loop over the whole repo; all clusters handled together -------------
while read -r file; do
    dir="$(dirname "$file")"
    ns="$(basename "$dir")"                 # namespace name = folder name
    cluster_file="$dir/clusters.yaml"

    # Skip excluded namespaces
    is_excluded "$ns" && continue

    # Namespace must match the app-id pattern
    [[ "$ns" =~ $APP_ID_REGEX ]] || continue
    appid="${BASH_REMATCH[1]}"

    # A namespace can belong to several clusters; count it under each wanted one
    [[ -f "$cluster_file" ]] || continue
    while read -r cl; do
        [[ -z "$cl" ]] && continue
        is_wanted_cluster "$cl" || continue

        key="${cl}|${appid}"
        appid_count["$key"]=$(( ${appid_count["$key"]:-0} + 1 ))

        if [[ -z "${appid_list["$key"]:-}" ]]; then
            appid_list["$key"]="$ns"
        else
            appid_list["$key"]="${appid_list["$key"]};$ns"
        fi
    done < <(yq e '.clusters[].name' "$cluster_file" 2>/dev/null)

done < <(find "$NAMESPACES_ROOT" -type f -name "values.yaml")

# ---- Emit results: only cluster|appid buckets with >= MIN_COUNT --------------
dup_total=0
for key in "${!appid_count[@]}"; do
    count=${appid_count["$key"]}
    if (( count >= MIN_COUNT )); then
        cluster="${key%%|*}"        # part before '|'
        appid="${key##*|}"          # part after  '|'
        echo "\"$cluster\",\"$appid\",\"$count\",\"${appid_list["$key"]}\"" >> "$OUTPUT_FILE"
        echo "  DUPLICATE: [$cluster] $appid -> $count namespaces"
        dup_total=$(( dup_total + 1 ))
    fi
done

echo "----------------------------------------------------------------------"
if (( dup_total == 0 )); then
    echo "No duplicate app-ids found across the configured clusters."
fi
echo "Done. $dup_total duplicate app-id group(s) written to: $OUTPUT_FILE"
