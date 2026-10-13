# Project Overview - ARO Cluster Upgrade Automation

## What it is
A rule-based, one-command Ansible automation that upgrades Azure Red Hat OpenShift clusters through ordered minor-version hops (for example `4.14.40 -> 4.15.35 -> 4.16.18`). It then validates the result, finishes the OLM operator updates and enables the web console Developer perspective. It runs from a RHEL 8 jump server with a cluster-admin automation account, on Ansible 2.7.17 (test) and 2.14.18 (prod). No AI or heuristics are in the execution path.

## Goals
1. **One command, one flow.** `00_Run.sh` runs `main.yml`, which runs the phases in a fixed order with one failure handler.
2. **Easy to follow.** A new engineer can read `WORKFLOW.md`, then `main.yml` and the six phase files, top to bottom.
3. **Safe.**
   - The whole path is validated before any change.
   - Gates stop the run with the exact reason.
   - The dry run changes nothing.
   - PROD changes need `UPGRADE` typed in.
   - Only one run per cluster at a time.
4. **Verified auto-fixes.**
   - cgroup v2 when the path reaches 4.19+.
   - Unpausing allow-listed MachineConfigPools.
   - Nodes reboot, the rollout is watched, then all checks run again. AUTO-FIXED is given only if the check then passes.
5. **Hop acknowledgements handled.** The admin-ack is applied before each minor hop, only after APIRequestCount shows no remaining callers of removed APIs.
6. **Quiet notifications.**
   - A heartbeat every 20 minutes and one degradation mail per new problem while the cluster updates.
   - Then exactly one summary (success) or one alert (failure).
7. **Resumable.** Running the same command again skips finished hops and watches a running update.

## Run modes
| Mode | Phases | Cluster changes |
|---|---|---|
| upgrade (default) | 01 02 03(+04) 05 06 | yes |
| `--dry-run` | 01 02 03 05 06 | none |
| `--pre-check` | 01 02 | Phase 02 auto-fixes only |
| `--post-check` | 05 | none |

## Phases
- **01 Policy check.** Takes the baseline snapshot and validates the whole path: shape, update graph per hop channel, and the cluster's own offer.
- **02 Prechecks.** Runs 16 checks, applies auto-fixes, waits for any rollout, re-checks, then applies the gate. Check 16 is new: installed operator health, covering CSV phase, subscription problems, an operator's own upgrade being blocked, and a better channel for the target.
- **03 Hops.** For each hop: plan, stable-cluster wait, channel, offer, admin-ack, trigger, then watch (Phase 04).
- **04 Watch.** Polls until settled, sends heartbeats and degradation mails, and fails on no progress, timeout, a long API outage, a rejected release or ClusterVersion Failing.
- **05 Postchecks.** Runs 10 checks, including the baseline diff, then the gate (audit only in a dry run).
- **06 Operators.** Approves the current InstallPlan of each pending subscription, validates operators, enables the Developer perspective, then the gate.

## In scope
- Sequential Y-stream upgrades.
- Update-graph validation.
- Admin-acks gated by removed-API usage.
- Phase 02 auto-fixes with re-check.
- Live monitoring.
- Postvalidation with baseline diff.
- OLM operator approvals and validation.
- The Developer perspective.

## Out of scope
- AI or non-deterministic logic.
- Skipping minor versions or major-version jumps.
- Forced image upgrades (`--to-image --force`).
- Accepting conditional-update risks automatically: it requires `allow_conditional_updates: true`.
- Running a single phase on its own, outside the four modes.
- Restarting degraded ClusterOperators, or forcing the machine-config daemon on nodes.
- etcd backup.
- GitOps.
- Git operations.

## Success criteria
1. `./00_Run.sh --cluster <c>` runs every phase without manual steps and ends with one summary mail and one report.
2. An invalid path, or a HARD precheck failure, stops the run before any upgrade change.
3. Every failed run ends with one alert, a `.status` exit code, a report and a logout.
4. A dry run makes no cluster change.
5. The code runs unchanged on Ansible 2.7.17 and 2.14.18.
