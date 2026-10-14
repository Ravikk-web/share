# Project Overview - ARO Cluster Upgrade Automation

## What it is
A rule-based, one-command Ansible automation that upgrades Azure Red Hat OpenShift clusters through ordered minor-version hops (for example `4.14.40 -> 4.15.35 -> 4.16.18`). It then validates the result, finishes the OLM operator updates and enables the web console Developer perspective. It runs from a RHEL 8 jump server with a cluster-admin automation account, on Ansible 2.7.17 (test) and 2.14.18 (prod). No AI or heuristics are in the execution path.

## Goals
1. **One command, one flow.** `00_Run.sh` runs `main.yml`, which runs the phases in a fixed order with one failure handler.
2. **Easy to follow.** A new engineer can read `WORKFLOW.md`, then `main.yml` and the seven phase files, top to bottom.
3. **Safe.**
   - The whole path is validated before any change.
   - Gates stop the run with the exact reason.
   - The dry run changes nothing.
   - PROD changes need `UPGRADE` typed in.
   - Only one run per cluster at a time.
4. **Checks first, then verified pre-upgrade changes.** Phase 02 only reads. Phase 03 makes every change needed before the first hop, one task at a time:
   - unpausing allow-listed MachineConfigPools
   - cgroup v2 when the path reaches 4.19+
   - approving pending operator upgrades, then stopping if an operator still blocks the target
   - the admin-ack, after APIRequestCount shows no remaining callers of removed APIs

   Any node rollout a change starts is watched to the end before the next task. After the changes all prechecks run again, and AUTO-FIXED is given only if the check then passes.
5. **Hop acknowledgements handled.** Phase 03 applies the ack the next minor hop needs. A later minor hop's ack only appears once the cluster is on that minor, so it is applied right before that hop, again only after the removed-API check.
6. **Quiet notifications.**
   - A heartbeat every 20 minutes and one degradation mail per new problem while the cluster updates.
   - Then exactly one summary (success) or one alert (failure).
7. **Resumable.** Running the same command again skips finished hops and watches a running update.

## Run modes
| Mode | Phases | Cluster changes |
|---|---|---|
| upgrade (default) | 01 02 03(+05) 04(+05) 06 07 | yes |
| `--dry-run` | 01 02 03 04 06 07 | none |
| `--pre-check` | 01 02 03(+05) | Phase 03 pre-upgrade changes only |
| `--post-check` | 06 | none |

## Phases
- **01 Policy check.** Takes the baseline snapshot and validates the whole path: shape, update graph per hop channel, and the cluster's own offer.
- **02 Prechecks.** Runs 16 read-only checks, then the gate. A problem Phase 03 will fix (paused allow-listed pool, cgroup v1, a blocking operator with an upgrade pending) is a WARN, not a stop. Check 16 covers installed operator health: CSV phase, subscription problems, an operator's own upgrade being blocked, and a better channel for the target.
- **03 Pre-upgrade implementation.** Four tasks, each check -> change -> watch the node rollout (Phase 05) -> verify: unpause pools, cgroup v2, operator upgrades, admin-ack. Then all 16 prechecks again and the gate.
- **04 Hops.** For each hop: plan, stable-cluster wait, channel, offer, any admin-ack still pending, trigger, then watch (Phase 05).
- **05 Watch.** Included by 03 and 04. Polls until settled, sends heartbeats and degradation mails, and fails on no progress, timeout, a long API outage, a rejected release or ClusterVersion Failing.
- **06 Postchecks.** Runs 10 checks, including the baseline diff, then the gate (audit only in a dry run).
- **07 Operators.** Approves the current InstallPlan of each pending subscription, validates operators, enables the Developer perspective, then the gate.

## In scope
- Sequential Y-stream upgrades.
- Update-graph validation.
- Admin-acks gated by removed-API usage.
- Pre-upgrade changes (Phase 03) with rollout watching and a full re-check.
- Approving pending operator upgrades before and after the cluster upgrade.
- Live monitoring.
- Postvalidation with baseline diff.
- OLM operator approvals and validation.
- The Developer perspective.

## Out of scope
- AI or non-deterministic logic.
- Skipping minor versions or major-version jumps.
- Forced image upgrades (`--to-image --force`).
- Accepting conditional-update risks automatically: it requires `allow_conditional_updates: true`.
- Running a single phase on its own, outside the four modes (phases can be commented out in `main.yml` for testing).
- Changing an operator's subscription channel.
- Restarting degraded ClusterOperators, or forcing the machine-config daemon on nodes.
- etcd backup.
- GitOps.
- Git operations.

## Success criteria
1. `./00_Run.sh --cluster <c>` runs every phase without manual steps and ends with one summary mail and one report.
2. An invalid path, or a HARD precheck failure, stops the run before any change. A failed Phase 03 change stops it before the first hop.
3. Every failed run ends with one alert, a `.status` exit code, a report and a logout.
4. A dry run makes no cluster change.
5. The code runs unchanged on Ansible 2.7.17 and 2.14.18.
