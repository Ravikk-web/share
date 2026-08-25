#!/usr/bin/env bash
# ==============================================================================
# File        : get_user_list_by_cluster.sh
# Purpose     : Read project/user metadata from local repository values.yaml
#               files and export only records mapped to selected clusters.
# Compatibility: Bash 4+, jq 1.5+, find
#
# Examples:
#   ./get_user_list_by_cluster.sh -c "arod01,arot02"
#   ./get_user_list_by_cluster.sh -c "arod01, arot02" -r ../namespaces -o output.csv
#
# Notes:
#   - Cluster matching is exact and case-sensitive.
#   - A project mapped to both requested clusters is written once, with both
#     matching cluster names in the Clusters column.
#   - The script does not store credentials or perform cluster login.
# ==============================================================================

set -uo pipefail

# Default locations. Override with -r and -o.
repository_root="../namespaces"
output_file="output.csv"
cluster_csv=""

usage() {
    cat <<'USAGE'
Usage:
  ./get_user_list_by_cluster.sh -c "arod01,arot02" [-r REPOSITORY_ROOT] [-o OUTPUT_FILE]

Required:
  -c  Comma-separated cluster names, for example: "arod01,arot02"

Optional:
  -r  Directory containing namespace subdirectories (default: ../namespaces)
  -o  CSV output file (default: output.csv)
  -h  Show this help
USAGE
}

while getopts ":c:r:o:h" option; do
    case "$option" in
        c) cluster_csv="$OPTARG" ;;
        r) repository_root="$OPTARG" ;;
        o) output_file="$OPTARG" ;;
        h) usage; exit 0 ;;
        :) printf 'ERROR: Option -%s requires a value.\n' "$OPTARG" >&2; usage; exit 2 ;;
        \?) printf 'ERROR: Unknown option: -%s\n' "$OPTARG" >&2; usage; exit 2 ;;
    esac
done

if [[ -z "$cluster_csv" ]]; then
    printf 'ERROR: Specify at least one cluster with -c. Example: -c "arod01,arot02"\n' >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    printf 'ERROR: jq is required but was not found in PATH.\n' >&2
    exit 1
fi

if [[ ! -d "$repository_root" ]]; then
    printf 'ERROR: Repository directory does not exist: %s\n' "$repository_root" >&2
    exit 1
fi

# Normalize the user input into a Bash array.
# Input example: "arod01, arot02" -> requested_clusters=("arod01" "arot02")
IFS=',' read -r -a raw_clusters <<< "$cluster_csv"
requested_clusters=()
for item in "${raw_clusters[@]}"; do
    item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$item" ]] && requested_clusters+=("$item")
done

if [[ ${#requested_clusters[@]} -eq 0 ]]; then
    printf 'ERROR: No valid cluster names were supplied.\n' >&2
    exit 2
fi

# Build a JSON array once so jq can perform exact cluster-name matching.
requested_json="$(printf '%s\n' "${requested_clusters[@]}" | jq -R . | jq -s .)"

csv_escape() {
    # RFC 4180-style escaping: double embedded quotes and quote every field.
    local value="${1-}"
    value=${value//\"/\"\"}
    printf '"%s"' "$value"
}

# Create a temporary file beside the target, then replace the target only after
# a successful scan. This avoids leaving a partially written report.
output_dir="$(dirname "$output_file")"
if [[ ! -d "$output_dir" ]]; then
    printf 'ERROR: Output directory does not exist: %s\n' "$output_dir" >&2
    exit 1
fi

tmp_file="$(mktemp "${output_file}.tmp.XXXXXX")" || exit 1
trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

printf '%s\n' '"Name","Product Owner","AYS Group","Support Email","Clusters"' > "$tmp_file"

scanned=0
matched=0
invalid=0

# -print0 safely handles spaces and special characters in paths.
while IFS= read -r -d '' file; do
    scanned=$((scanned + 1))

    if ! jq -e . "$file" >/dev/null 2>&1; then
        printf 'WARN: Skipping invalid JSON/YAML-for-jq file: %s\n' "$file" >&2
        invalid=$((invalid + 1))
        continue
    fi

    # Only retain cluster names that are present in the requested list.
    matched_clusters="$(jq -r --argjson requested "$requested_json" '
        [(.clusters // [])[]? | .name // empty | select(. as $name | $requested | index($name))]
        | unique
        | join(", ")
    ' "$file" 2>/dev/null)"

    [[ -z "$matched_clusters" ]] && continue

    # Extract the same fields as the reference script. Missing values become blank.
    name="$(jq -r '.project.name // ""' "$file" 2>/dev/null)"
    product_owner="$(jq -r '.project.annotations["hcsc/product-owner"] // ""' "$file" 2>/dev/null)"
    ays_group="$(jq -r '.project.annotations["hcsc/ays-group"] // ""' "$file" 2>/dev/null)"
    support_email="$(jq -r '.project.annotations["hcsc/support-email"] // ""' "$file" 2>/dev/null)"

    printf '%s,%s,%s,%s,%s\n' \
        "$(csv_escape "$name")" \
        "$(csv_escape "$product_owner")" \
        "$(csv_escape "$ays_group")" \
        "$(csv_escape "$support_email")" \
        "$(csv_escape "$matched_clusters")" >> "$tmp_file"

    matched=$((matched + 1))
done < <(find "$repository_root" -type f -name 'values.yaml' -print0)

mv -f "$tmp_file" "$output_file"
trap - EXIT HUP INT TERM

printf 'PASS: Extraction complete.\n'
printf '  Requested clusters : %s\n' "$(IFS=', '; printf '%s' "${requested_clusters[*]}")"
printf '  values.yaml scanned: %d\n' "$scanned"
printf '  Matching records   : %d\n' "$matched"
printf '  Invalid files      : %d\n' "$invalid"
printf '  Output             : %s\n' "$output_file"
