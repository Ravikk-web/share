#!/bin/bash
#
# oc_find_duplicate_appid_namespaces.sh
# ------------------------------------------------------------------------------
# Purpose : Query the LIVE cluster you're currently logged into (oc login --token)
#           and identify "App IDs" that own MORE THAN ONE namespace (multiple
#           namespaces sharing the same app-id prefix), then save to CSV.
#
# Usage   : 1) oc login --token=<TOKEN> --server=<API_URL>
#           2) ./oc_find_duplicate_appid_namespaces.sh
#
# Example : app123445679-namespace1
#           app123445679-namespace2   -> "app123445679" has 2 -> reported
#           appr214215122-namespace3  -> single             -> NOT reported
#
# Requires: oc (authenticated), bash 4+
# ------------------------------------------------------------------------------

set -uo pipefail

# ============================== CONFIG ========================================
# Regex to extract the App ID. FIRST capture group = App ID.
# Default: "app" + digits, up to the first dash.  app123445679-ns1 -> app123445679
APP_ID_REGEX='^(app[0-9]+)-'

# An App ID must own at least this many namespaces to be reported.
MIN_COUNT=2

# Namespaces to EXCLUDE (exact match).
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

# --- Safety: make sure we are actually logged in ------------------------------
if ! oc whoami >/dev/null 2>&1; then
    echo "ERROR: Not logged in. Run 'oc login --token=<TOKEN> --server=<API_URL>' first."
    exit 1
fi

# Capture the current cluster/server so it appears in the CSV
CLUSTER="$(oc whoami --show-server 2>/dev/null)"
echo "Logged in to: $CLUSTER"

is_excluded() {
    local ns="$1" ex
    for ex in "${EXCLUDE_NAMESPACES[@]}"; do
        [[ "$ns" == "$ex" ]] && return 0
    done
    return 1
}

# CSV header
echo '"Cluster","App ID","Namespace Count","Namespaces"' > "$OUTPUT_FILE"

declare -A appid_count=()
declare -A appid_list=()

# Pull all namespace names from the live cluster and bucket by app-id
while read -r ns; do
    [[ -z "$ns" ]] && continue
    is_excluded "$ns" && continue

    if [[ "$ns" =~ $APP_ID_REGEX ]]; then
        appid="${BASH_REMATCH[1]}"
        appid_count["$appid"]=$(( ${appid_count["$appid"]:-0} + 1 ))
        if [[ -z "${appid_list["$appid"]:-}" ]]; then
            appid_list["$appid"]="$ns"
        else
            appid_list["$appid"]="${appid_list["$appid"]};$ns"
        fi
    fi
done < <(oc get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# Emit only app-ids with >= MIN_COUNT namespaces
dup_total=0
for appid in "${!appid_count[@]}"; do
    count=${appid_count["$appid"]}
    if (( count >= MIN_COUNT )); then
        echo "\"$CLUSTER\",\"$appid\",\"$count\",\"${appid_list["$appid"]}\"" >> "$OUTPUT_FILE"
        echo "  DUPLICATE: $appid -> $count namespaces"
        dup_total=$(( dup_total + 1 ))
    fi
done

echo "----------------------------------------------------------------------"
(( dup_total == 0 )) && echo "No duplicate app-ids found."
echo "Done. $dup_total group(s) written to: $OUTPUT_FILE"
