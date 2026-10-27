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
   - cgroup v2 when the path reaches 4.19+, verified on every node (the MCO configuration it runs, its kernel, or both: `cgroup_check_method`), not only the setting
   - approving pending operator upgrades, then stopping if an operator still blocks the target
   - the admin-ack, after APIRequestCount shows no remaining callers of removed APIs

   Any node rollout a change starts is watched to the end before the next task. After the changes all prechecks run again, and AUTO-FIXED is given only if the check then passes.
5. **Hop acknowledgements handled.** Phase 03 applies the ack the next minor hop needs. A later minor hop's ack only appears once the cluster is on that minor, so it is applied right before that hop, again only after the removed-API check.
6. **Quiet notifications.**
   - A heartbeat every 20 minutes and one degradation mail per new problem while the cluster updates.
   - Then exactly one summary (success) or one alert (failure).
7. **Resumable.** Running the same command again first watches an update that is still running to the end, including a hop whose control plane is done while its worker nodes are still updating. Then the prechecks judge a settled cluster, and finished hops are skipped. The logs of the last 5 runs of a cluster are kept, so a failed run's log survives the resume.
8. **Node problems explained.** A node that is not Ready, cordoned, under pressure or stuck in its update, and a pool that cannot continue because of it, are reported with the likely cause and what to do: in Check 02, the degradation mails and the alert. The automation never repairs nodes itself.

## Run modes
| Mode | Phases | Cluster changes |
|---|---|---|
| upgrade (default) | 01 02 03(+05) 04(+05) 06 07 | yes |
| `--dry-run` | 01 02 03 04 06 07 | none |
| `--pre-check` | 01 02 03(+05) | Phase 03 pre-upgrade changes only |
| `--post-check` | 06 | none |

## Phases
- **01 Policy check.** Takes the baseline snapshot and validates the whole path: shape, update graph per hop channel, and the cluster's own offer.
- **Resume step.** An update still running (control plane, or the nodes of a completed hop) is watched to the end before the prechecks.
- **02 Prechecks.** Runs 17 read-only checks, then the gate. A problem Phase 03 will fix (paused allow-listed pool, cgroup v1, a v2 rollout not finished, a blocking operator with an upgrade pending) is a WARN, not a stop.
  - Check 08 checks drain headroom: per pool except master, the pods of the largest `maxUnavailable` nodes must fit on the others.
  - Check 14 checks cgroup v2 on every node; the nodes decide, not the setting (an empty `cgroupMode` is v2 on 4.14+).
  - Check 16 covers installed operator health: CSV phase, subscription problems, an operator's own upgrade being blocked, and a better channel for the target.
  - Check 17 warns when routers have no spare eligible node for a drain.
- **03 Pre-upgrade implementation.** Four tasks, each check -> change -> watch the node rollout (Phase 05) -> verify: unpause pools, cgroup v2, operator upgrades, admin-ack. Then all 17 prechecks again and the gate.
- **04 Hops.** For each hop: plan, stable-cluster wait, channel, offer, any admin-ack still pending, trigger, then watch (Phase 05).
- **05 Watch.** Included by 03, 04 and the resume step. Polls until settled, sends heartbeats and degradation mails, and fails on no progress, timeout, a long API outage, a rejected release or ClusterVersion Failing. A pool that cannot continue gets its own degradation mail, with the node diagnosis. A pool cannot continue when no node of it is updating while its unavailable nodes use up `maxUnavailable`.
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
- Repairing nodes: uncordoning, draining, rebooting, patching or replacing nodes or Machines (reported with what to do, never done).
- Changing capacity or ingress settings (MachineSet replicas, router replicas, PodDisruptionBudgets): Checks 08 and 17 only report them.
- etcd backup.
- GitOps.
- Git operations.

## Success criteria
1. `./00_Run.sh --cluster <c>` runs every phase without manual steps and ends with one summary mail and one report.
2. An invalid path, or a HARD precheck failure, stops the run before any change. A failed Phase 03 change stops it before the first hop.
3. Every failed run ends with one alert, a `.status` exit code, a report and a logout.
4. A dry run makes no cluster change.
5. The code runs unchanged on Ansible 2.7.17 and 2.14.18.
