# Unit 15: Report Rendering (`health-overview.j2` + `report` role)

## Goal

Build the modern looking client-facing HTML report template `health-overview.j2` and the `report` role that renders it to `output/` — colour-coded summary tiles, per-check status table, collapsible detail, and a copy button.

## Design

- **System boundary:** `playbooks/templates/health-overview.j2` + `playbooks/roles/report`.
- Presentation-only template; all colour/status from passed-in vars per `ui-context.md`.
- Report anatomy (fixed): header band + verdict pill → summary tiles → colour-coded status table(s) → collapsible `<details>` → copy button → footer.
- Print/PDF friendly: `@media print` expands `<details>`; status paired with text label + glyph.

## Implementation

### `health-overview.j2`
Render from `health_summary` + `failed_validations`: summary counts (`X passed / Y warn / Z fail`) as tiles; one table row per check (number, name, observed value, HARD/WARN, status pill with `row_class`); collapsible raw `oc`/`jq` detail; a copy button (inline JS, reports only) for failed node names/cluster/run ID.

### `report/tasks/main.yml`
`template:` `health-overview.j2` → `output/<cluster>_<phase>_<timestamp>.html`. Also emit the dual `.txt` + `.csv` log rows for the run. `changed_when: false` on reads. Parameterised by phase (prevalidation vs postvalidation).

### Defaults
All optional display fields guarded with `| default('N/A')`.

## Dependencies

- Unit 01 (`vars/report_vars.yml` tokens)
- (consumes `health_summary` populated by check roles)

## Verify when done

- [ ] HTML report written to `output/` with correct name
- [ ] Summary tiles + status table + collapsible detail + copy button present
- [ ] Colour/status driven by passed-in vars only
- [ ] `.txt` + `.csv` log rows emitted to `logs/`
- [ ] Print/PDF expands collapsibles; grayscale-safe
- [ ] `| default('N/A')` on optional fields; no secrets rendered
- [ ] Runs on 2.7.17 and 2.14.18
- [ ] progress-tracker.md updated
