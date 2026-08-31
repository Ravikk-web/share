# Unit 04: Email Templates (`error-report.j2`, `progress-mail.j2`)

## Goal

Build the two presentation-only Jinja2 email templates — `error-report.j2` (failure alerts) and `progress-mail.j2` (heartbeat + state-change progress) — rendering colour-coded HTML from variables passed in.

## Design

- **System boundary:** `playbooks/templates/`.
- Presentation only — no `oc`/`jq`, no decision logic. All status colour comes from passed-in vars (`status_color`, `row_class`).
- Uses `ui-context.md` tokens: green `#1a7f37/#e6f4ea`, amber `#9a6700/#fff8e1`, red `#b42318/#fdecea`, neutral, surface, borders.
- Email-safe: inline CSS only, no JS, no `<details>`, width ≤ 640px, system font stack.
- Status never colour-only — paired with text label (`PASS/WARN/FAIL`) and glyph (`✔ ! ✖`).

## Implementation

### `progress-mail.j2`
Header: cluster, hop `x/y`, `% complete`, elapsed, next-update note. Body: **MCP status always shown**, then the **current working node** (draining/rebooting now), then **degraded nodes only** (healthy omitted). Flat compact tables, colour-coded pills. Guard every field with `| default('N/A')`.

### `error-report.j2`
Header: cluster, run ID, timestamp, red FAIL verdict pill. Body: failed check name, gate type (HARD), observed value, and the captured reason/log line. Compact and email-safe.

### Shared partial conventions
Consistent pill markup and colour mapping so both templates and the later HTML report look identical. No secrets ever rendered.

## Dependencies

- Unit 01 (`vars/report_vars.yml` colour tokens)

## Verify when done

- [x] Both templates render valid HTML from sample vars
- [x] All colour/status driven by passed-in vars, not computed
- [x] Email-safe: inline CSS, no JS, no collapsibles, ≤640px
- [x] MCP always shown; current node + degraded-only in progress mail
- [x] Every optional field guarded with `| default('N/A')`
- [x] No secrets/tokens in output
- [x] Renders acceptably in a browser and a mail client
- [x] progress-tracker.md updated
