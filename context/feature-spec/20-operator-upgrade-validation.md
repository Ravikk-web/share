# Unit 20: Operator Compatibility, Upgrade & Validation

## Goal
After all cluster hops complete and postvalidation passes, check every OLM-managed operator for compatibility with the final cluster version, initiate operator upgrades where an approval-pending or newer compatible CSV exists, and validate that all operators land Succeeded at the end — as a rule-based, no-AI phase driven only by `oc` + `jq`.

## Design
Terminal + one client-facing HTML report (`operator-report`, styled per `ui-context.md`: summary-first tiles, green/amber/red status, collapsible per-operator table, copy button). Runs **once**, after `07_postvalidation.yml`. Operator work must never block or roll back the completed cluster upgrade — a failed operator upgrade is a **HARD** finding for this phase only (reported + alerted), it does not undo cluster hops. Uses the same status-record contract (`{check, rule, observed, status}`) as Units 09–11 so it plugs into the existing `report` and `error-handling` roles.

## Implementation

### Phase file: 08_operator_upgrade.yml
Runs once on `localhost`, `gather_facts: false`, after postvalidation, wrapped in `block/rescue/always` so any failure logs out. Header comment targets 2.7.17 with `# MIGRATION 2.14:` notes. Orchestrates the three roles below in order: compatibility scan → conditional upgrade → final validation → render report.

### Role: operator compatibility check (roles/operator_compat/tasks/main.yml)
- Enumerate all subscriptions cluster-wide: `oc get subscriptions --all-namespaces -o json`, parse with `jq`.
- For each subscription capture: `name`, `namespace`, `channel`, `installedCSV`, `currentCSV`, `state`, and `installPlanApproval` (Automatic/Manual).
- Resolve the installed CSV: `oc get csv -n <ns> <installedCSV> -o json` → `phase`, `version`, and `spec.minKubeVersion` (compatibility signal against the new cluster kubelet/version).
- **Compatibility rule (HARD):** if a CSV reports `minKubeVersion` greater than the cluster's server version, or the CSV `phase` is `Failed`, mark FAIL.
- **Upgrade-available rule (WARN → actionable):** if `currentCSV != installedCSV` OR a `state: UpgradePending` / pending `InstallPlan` exists, mark the operator as "upgrade available/needed".
- Emit a status record per operator. Thresholds/allow-lists (e.g. operators to skip) sourced from `vars/`, never inline.

### Role: operator upgrade (roles/operator_upgrade/tasks/main.yml)
- Build the worklist = operators flagged "upgrade available/needed" from the compat role. **Skip anything already current.**
- For each operator in the worklist:
  - Find the pending InstallPlan: `oc get installplan -n <ns> -o json | jq` for `spec.approved == false`.
  - **Approve it (the upgrade trigger):** `oc patch installplan <ip> -n <ns> --type merge -p '{"spec":{"approved":true}}'`. `changed_when` set on successful patch; `failed_when` explicit.
  - This deterministically initiates the OLM upgrade for both Manual and (already-auto) subscriptions. No channel changes are made here unless a target channel is defined in `vars/` (optional, commented seam).
  - Poll the CSV until `phase: Succeeded` or a per-operator timeout (default 15 min, from `vars/`). On timeout → HARD finding → alert → recorded (does not roll back cluster).
- `# MIGRATION 2.14:` note on `oc patch` JSON quoting under Python 3.
- Last-resort/manual seam (commented): forcing a specific target CSV — never automatic.

### Role: operator final validation (roles/operator_validate/tasks/main.yml)
Runs after all upgrades settle. For **every** operator (not just upgraded ones):
- CSV `phase == Succeeded` → PASS, else FAIL (HARD).
- No subscription in `UpgradePending` / `InstallPlanFailed` → PASS, else FAIL (HARD).
- No leftover unapproved InstallPlans for operators that were in scope → WARN.
- Operator deployment pods Ready in their namespace → WARN.
- Produce the final per-operator status list for the report.

### Reporting & wiring
- Render `operator-report` via the existing `report` role into `{{ output_dir }}/<cluster>_<timestamp>_operators.html`.
- Route any HARD finding through the Unit 08 `error-handling` role (alert email + logout + `fail:`). WARN items surface in the report only.
- Append operator results to the dual `.txt`/`.csv` logs (Unit 18 contract).
- **main.yml wiring:** add `- import_playbook: 08_operator_upgrade.yml` **after** `07_postvalidation.yml` (once-only static chain — it does not loop, so `import_playbook` is correct).

## Dependencies
- oc CLI — subscription/CSV/installplan queries and the `oc patch` approval trigger (already present from Unit 03).
- jq (v1.5) — parsing OLM JSON (already present from Unit 04).
- Reuses roles from Units 06 (report), 07 (send mail), 08 (error-handling), 18 (logging). No new packages.

## Verify when done
- [ ] Compatibility scan lists every operator with channel, installed/current CSV, phase, and compat status
- [ ] Operators already current are skipped; only pending/available upgrades are actioned
- [ ] Pending InstallPlans are approved and the operator reaches CSV `phase: Succeeded`
- [ ] Per-operator timeout produces a HARD finding + alert email, without rolling back the cluster upgrade
- [ ] Final validation confirms all operators `Succeeded` with no pending/failed subscriptions
- [ ] Colour-coded operator HTML report renders to `output/`; results appended to `.txt`/`.csv` logs
- [ ] Phase runs **once**, after `07_postvalidation.yml`, and logs out on any failure
- [ ] `--syntax-check` passes on 2.7.17 and 2.14.18 (short names, no bare `include:`, no `warn:`, `| default('')`)
- [ ] `progress-tracker.md` updated
