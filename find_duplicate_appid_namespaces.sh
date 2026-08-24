#!/bin/bash
#
# find_duplicate_appid_namespaces.sh
# ------------------------------------------------------------------------------
# Purpose : Scan the namespace folders in THIS repository and identify "App IDs"
#           that own MORE THAN ONE namespace (i.e. multiple namespaces share the
#           same app-id prefix) for each cluster, then save the result to a CSV.
#
#           Run this from inside the repo (same as the example script).
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
#
# Requires: bash 4+, yq (same dependency your example uses)
# ------------------------------------------------------------------------------

set -uo pipefail

# ============================== CONFIG ========================================
# 1) Root folder that holds the per-namespace directories.
#    Your example used ../namespaces/  -> keep or change as needed.
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
#    Add any system / shared namespaces you don't want counted.
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

# Write CSV header
echo '"Cluster","App ID","Namespace Count","Namespaces"' > "$OUTPUT_FILE"

# Process one cluster at a time so duplicates are reported per cluster
for cluster in "${CLUSTERS[@]}"; do
    echo "----------------------------------------------------------------------"
    echo "Processing cluster: $cluster"

    # Reset per-cluster buckets
    #   appid_count -> how many namespaces share each app-id
    #   appid_list  -> the namespace names (';' separated) for each app-id
    declare -A appid_count=()
    declare -A appid_list=()

    # Loop through every namespace defined in the repo
    while read -r file; do
        dir="$(dirname "$file")"
        ns="$(basename "$dir")"            # namespace name = folder name
        cluster_file="$dir/clusters.yaml"

        # Skip excluded namespaces
        if is_excluded "$ns"; then
            continue
        fi

        # Only count this namespace if it targets the current cluster
        if [[ -f "$cluster_file" ]]; then
            if ! yq e '.clusters[].name' "$cluster_file" 2>/dev/null \
                 | grep -qxF "$cluster"; then
                continue
            fi
        else
            # No clusters.yaml -> cannot confirm cluster membership, skip
            continue
        fi

        # Extract the app-id from the namespace name
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

    # Write only the app-ids that own >= MIN_COUNT namespaces
    dup_found=0
    for appid in "${!appid_count[@]}"; do
        count=${appid_count["$appid"]}
        if (( count >= MIN_COUNT )); then
            echo "\"$cluster\",\"$appid\",\"$count\",\"${appid_list["$appid"]}\"" >> "$OUTPUT_FILE"
            echo "  DUPLICATE: $appid -> $count namespaces"
            dup_found=1
        fi
    done
    [[ "$dup_found" -eq 0 ]] && echo "  No duplicate app-ids found."

    # Clean up before next cluster
    unset appid_count appid_list
done

echo "----------------------------------------------------------------------"
echo "Done. Output saved to: $OUTPUT_FILE"
