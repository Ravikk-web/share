#!/usr/bin/env bash
# ============================================================================
# 00_Run.sh - START HERE
# ============================================================================
# Runs the ARO cluster upgrade in one go:
#   1. checks the tools on the jump server
#   2. asks (or takes from the flags) the cluster, the run mode and the upgrade path
#   3. shows what will happen and asks for confirmation
#      (PROD runs that change the cluster need the word UPGRADE typed in)
#   4. locks the cluster so only one run can touch it at a time
#   5. empties logs/ (except logs of a run still active on another cluster)
#   6. runs main.yml, keeping the console in logs/<cluster>_<timestamp>.txt
#   7. exits with the code the playbook wrote (see --help)
#
# Run modes:
#   upgrade     (default) the full upgrade: phases 01, 02, 03, 04, 06, 07
#               (05 watches the node rollouts of 03 and every hop of 04)
#   dry-run     the same steps, read-only - nothing on the cluster is changed
#   pre-check   phases 01-03: prechecks and the pre-upgrade changes (unpausing
#               pools, cgroup v2 - nodes may reboot, operator upgrades, admin-ack),
#               no cluster update
#   post-check  phase 06 only, against the version the cluster is on now
# To resume after a failure, run the same command again: hops already done are skipped.
# ============================================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
mkdir -p logs output snapshots

usage() {
    cat <<'EOF'
Usage: ./00_Run.sh [options]

  -c, --cluster NAME     cluster from vars/secrets.yml (asked if not given)
  -p, --path X.Y.Z,...   upgrade path, e.g. 4.15.35,4.16.18 (default: cluster_upgrade_paths in vars/upgrade.yml)
  -d, --dry-run          read-only run of every phase; nothing on the cluster is changed
      --pre-check        phases 01-03 only: prechecks and the pre-upgrade changes
                         (cgroup v2 / unpausing pools can reboot nodes), no upgrade
      --post-check       phase 06 only, against the current cluster version
  -y, --yes              do not ask for confirmation (PROD changes still need UPGRADE typed)
  -r, --resume           accepted for habit; every run resumes on its own (finished hops are skipped)
  -m, --mail-to LIST     send the summary/heartbeat mails to these addresses (comma-separated);
                         alerts still also go to alert_mail_to
  -v, --verbose          verbose Ansible output
  -h, --help             this help

Exit codes:
  0 success   1 bad option, missing tool or cluster already locked   2 cancelled
  5 login or Phase 01 (path)   10 Phase 02 (prechecks)   15 Phase 03 (pre-upgrade changes)
  20 hop failed (Phase 04)   30 hop stopped progressing / timed out (Phase 05)
  25 Phase 06 (postchecks)   35 Phase 07 (operators)   99 other error

Examples:
  ./00_Run.sh
  ./00_Run.sh --cluster cluster_d01 --dry-run
  ./00_Run.sh --cluster cluster_d01 --path 4.15.35,4.16.18
EOF
}

die() { echo "ERROR: $*" >&2; exit "${2:-1}"; }

# ----------------------------------------------------------------------------
# Options
# ----------------------------------------------------------------------------
CLUSTER=""
HOPS=""
MODE=""
YES=false
MAIL_TO=""
VERBOSE=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--cluster)  CLUSTER="${2:-}"; [[ -n "$CLUSTER" ]] || die "--cluster needs a name"; shift 2 ;;
        -p|--path)     HOPS="${2:-}"; [[ -n "$HOPS" ]] || die "--path needs versions"; shift 2 ;;
        -d|--dry-run)  MODE="dry-run"; shift ;;
        --pre-check)   MODE="pre-check"; shift ;;
        --post-check)  MODE="post-check"; shift ;;
        -y|--yes)      YES=true; shift ;;
        -r|--resume)   echo "Note: every run resumes on its own - hops already done are skipped."; shift ;;
        -m|--mail-to)  MAIL_TO="${2:-}"; [[ -n "$MAIL_TO" ]] || die "--mail-to needs an address"; shift 2 ;;
        -v|--verbose)  VERBOSE=(-v); shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "unknown option '$1' (see --help)" ;;
    esac
done
INTERACTIVE=false
[[ -t 0 ]] && INTERACTIVE=true

# ----------------------------------------------------------------------------
# 1. Tools
# ----------------------------------------------------------------------------
for tool in ansible-playbook oc jq curl python3 flock; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool '$tool' is not installed"
done
SEND_EMAIL=true
if ! ansible-doc -t module mail >/dev/null 2>&1; then
    echo "WARN: the Ansible 'mail' module is missing (install the community.general collection); no mails will be sent."
    SEND_EMAIL=false
fi

# ----------------------------------------------------------------------------
# 2. Clusters and their configured paths (vars/secrets.yml, vars/upgrade.yml)
# ----------------------------------------------------------------------------
# One line per cluster: name|tier|path   (tags such as !vault are tolerated)
CLUSTER_LINES="$(python3 - <<'PY'
import sys, yaml
class Loader(yaml.SafeLoader):
    pass
Loader.add_multi_constructor("!", lambda loader, suffix, node: None)
secrets = yaml.load(open("vars/secrets.yml"), Loader=Loader) or {}
upgrade = yaml.load(open("vars/upgrade.yml"), Loader=Loader) or {}
paths = upgrade.get("cluster_upgrade_paths") or {}
for name, c in (secrets.get("clusters") or {}).items():
    c = c or {}
    print("{}|{}|{}".format(name, str(c.get("tier", "DEV")).upper(), ",".join(str(v) for v in (paths.get(name) or []))))
PY
)" || die "could not read vars/secrets.yml or vars/upgrade.yml (python3 needs PyYAML)"
[[ -n "$CLUSTER_LINES" ]] || die "no clusters defined in vars/secrets.yml"
mapfile -t CLUSTER_NAMES < <(cut -d'|' -f1 <<< "$CLUSTER_LINES")

# ----------------------------------------------------------------------------
# 3. Cluster, mode and path
# ----------------------------------------------------------------------------
if [[ -z "$CLUSTER" ]]; then
    $INTERACTIVE || die "--cluster is required when not running in a terminal"
    echo "Which cluster?"
    PS3="Number: "
    select CLUSTER in "${CLUSTER_NAMES[@]}"; do [[ -n "$CLUSTER" ]] && break; done
fi
CLUSTER_LINE="$(grep "^${CLUSTER}|" <<< "$CLUSTER_LINES" || true)"
[[ -n "$CLUSTER_LINE" ]] || die "cluster '$CLUSTER' is not in vars/secrets.yml (known: ${CLUSTER_NAMES[*]})"
TIER="$(cut -d'|' -f2 <<< "$CLUSTER_LINE")"
CONFIGURED_PATH="$(cut -d'|' -f3 <<< "$CLUSTER_LINE")"

if [[ -z "$MODE" ]]; then
    MODE="upgrade"
    if $INTERACTIVE; then
        echo "What should this run do?"
        PS3="Number: "
        select MODE in "upgrade" "dry-run" "pre-check" "post-check"; do [[ -n "$MODE" ]] && break; done
    fi
fi

if [[ "$MODE" == "post-check" ]]; then
    HOPS=""
elif [[ -z "$HOPS" ]]; then
    HOPS="$CONFIGURED_PATH"
    if $INTERACTIVE; then
        read -r -p "Upgrade path [${HOPS:-none configured}] (Enter to accept, or type X.Y.Z,X.Y.Z): " ANSWER || true
        [[ -n "${ANSWER:-}" ]] && HOPS="$ANSWER"
    fi
    [[ -n "$HOPS" ]] || die "no upgrade path: use --path or set cluster_upgrade_paths.$CLUSTER in vars/upgrade.yml"
fi
HOPS="$(tr -d ' ' <<< "$HOPS")"
[[ -z "$HOPS" || "$HOPS" =~ ^[0-9]+\.[0-9]+\.[0-9]+(,[0-9]+\.[0-9]+\.[0-9]+)*$ ]] || die "path '$HOPS' must look like 4.15.35,4.16.18"

# ----------------------------------------------------------------------------
# 4. Show what will happen and confirm
# ----------------------------------------------------------------------------
case "$MODE" in
    upgrade)    CHANGES="YES - pre-upgrade changes (unpause pools, cgroup v2 - nodes may reboot, operator approvals, admin-ack), channel + admin-ack + update per hop, operator approvals, Developer perspective" ;;
    pre-check)  CHANGES="MAYBE - only what is needed: unpause pools, cgroup v2 (nodes reboot), pending operator approvals, admin-ack; no cluster update" ;;
    *)          CHANGES="no - read-only" ;;
esac
echo
echo "  Cluster : $CLUSTER ($TIER)"
echo "  Mode    : $MODE"
echo "  Path    : ${HOPS:-current version}"
echo "  Changes : $CHANGES"
echo

if [[ "$TIER" == PROD* && ( "$MODE" == "upgrade" || "$MODE" == "pre-check" ) ]]; then
    $INTERACTIVE || die "a PROD run that changes the cluster must be confirmed in a terminal" 2
    read -r -p "PRODUCTION cluster. Type UPGRADE to continue: " ANSWER || true
    [[ "${ANSWER:-}" == "UPGRADE" ]] || die "cancelled" 2
elif ! $YES; then
    $INTERACTIVE || die "not running in a terminal: add --yes to confirm" 2
    read -r -p "Continue? [y/N]: " ANSWER || true
    [[ "${ANSWER:-}" =~ ^[yY] ]] || die "cancelled" 2
fi

# ----------------------------------------------------------------------------
# 5. One run per cluster at a time
# ----------------------------------------------------------------------------
# Why: flock is released by the kernel when this script ends, even if it is killed,
#      so a stale lock cannot block the next run.
LOCK_FILE="/tmp/aro-upgrade-${CLUSTER}.lock"
exec 9>>"$LOCK_FILE"
flock -n 9 || die "cluster '$CLUSTER' is already being worked on by PID $(cat "$LOCK_FILE" 2>/dev/null) ($LOCK_FILE)"
echo "$$" > "$LOCK_FILE"

# ----------------------------------------------------------------------------
# 6. Start with an empty logs/ folder
# ----------------------------------------------------------------------------
# Why: logs/ only ever holds the latest run. A log whose cluster has a run going on
#      right now (its lock is held) belongs to that run and is left alone.
#      Reports (output/) and baseline snapshots (snapshots/) are kept.
for old_log in logs/*; do
    [[ -f "$old_log" ]] || continue
    owner=""
    [[ "$(basename "$old_log")" =~ ^(.+)_[0-9]{8}_[0-9]{6}\.[a-z]+$ ]] && owner="${BASH_REMATCH[1]}"
    if [[ -n "$owner" && "$owner" != "$CLUSTER" ]] && ! flock -n "/tmp/aro-upgrade-${owner}.lock" -c true 2>/dev/null; then
        continue
    fi
    rm -f -- "$old_log"
done

# ----------------------------------------------------------------------------
# 7. Run main.yml
# ----------------------------------------------------------------------------
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="logs/${CLUSTER}_${TIMESTAMP}.txt"
STATUS_FILE="logs/${CLUSTER}_${TIMESTAMP}.status"
REPORT_FILE="output/${CLUSTER}_${TIMESTAMP}_report.html"

# Why: extra vars go in as one JSON object; key=value pairs would turn the path list
#      into a string.
EXTRA_VARS="$(python3 -c '
import json, sys
cluster, hops, mode, ts, send_email, mail_to = sys.argv[1:7]
data = {"cluster_name": cluster, "upgrade_path": [h for h in hops.split(",") if h],
        "run_mode": mode, "run_timestamp": ts}
if send_email != "true":
    data["send_email"] = False
if mail_to:
    data["mail_to_cli"] = [m.strip() for m in mail_to.split(",") if m.strip()]
print(json.dumps(data))
' "$CLUSTER" "$HOPS" "$MODE" "$TIMESTAMP" "$SEND_EMAIL" "$MAIL_TO")"

export ANSIBLE_RETRY_FILES_ENABLED=False
export ANSIBLE_LOCALHOST_WARNING=False

echo "Running main.yml - console log: $LOG_FILE"
set +e
ansible-playbook main.yml -e "$EXTRA_VARS" ${VERBOSE[@]+"${VERBOSE[@]}"} 2>&1 | tee -a "$LOG_FILE"
RC="${PIPESTATUS[0]}"
set -e

# ----------------------------------------------------------------------------
# 8. Result and exit code
# ----------------------------------------------------------------------------
echo
if [[ "$RC" -eq 0 ]]; then
    EXIT_CODE=0
    echo "RESULT : SUCCESS ($MODE on $CLUSTER)"
else
    EXIT_CODE="$(grep -m1 '^exit_code=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2 || true)"
    [[ "$EXIT_CODE" =~ ^[0-9]+$ ]] || EXIT_CODE=99
    echo "RESULT : FAILED with exit code $EXIT_CODE ($MODE on $CLUSTER)"
    grep -m1 '^reason=' "$STATUS_FILE" 2>/dev/null | cut -d= -f2- | sed 's/^/REASON : /' || true
fi
[[ -f "$REPORT_FILE" ]] && echo "REPORT : $REPORT_FILE"
echo "LOG    : $LOG_FILE"
exit "$EXIT_CODE"
