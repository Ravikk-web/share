# UI Context — ARO Cluster Upgrade Automation

This project has **no web UI**. "UI" here means the **client-facing HTML reports and progress emails** rendered from Jinja2 templates (`health-overview.j2`, `error-report.j2`, `progress-mail.j2`). All styling rules below apply to that output.

**Golden rule:** all colour and status coding is driven by **variables passed into the template** — never computed in the template. A template only *renders* a status; the role decides it via `set_fact`.

## Theme

Light, clean, print-friendly. The design language is a **modern operational report** — white/near-white backgrounds, subtle card surfaces, and clear colour-coded status. Reports must be readable both in a browser and inside an email client, and must render acceptably when **printed to PDF** for client hand-off.

- Prefer **inline CSS** (or a single `<style>` block in `<head>`) — external stylesheets do not survive email clients.
- Use a system font stack; do not rely on web fonts.
- Layout must be single-column and responsive-safe (max-width container, no horizontal scroll on mobile mail clients).
- Avoid JavaScript in emails. The **copy button** may use a tiny inline script in the standalone HTML reports (`output/`) only, never in the email body.

## Colors

Define these as reusable style values (inline CSS variables in reports, hardcoded hex in emails since CSS vars are unreliable in mail clients). Status colour is always chosen upstream and passed in as a variable (e.g. `status_color`, `row_class`).

| Token | Hex | Meaning |
|---|---|---|
| `--green` / PASS | `#1a7f37` (text) on `#e6f4ea` (bg) | Healthy / check passed / hop complete |
| `--amber` / WARN | `#9a6700` (text) on `#fff8e1` (bg) | Non-blocking warning / in-progress / draining |
| `--red` / FAIL | `#b42318` (text) on `#fdecea` (bg) | HARD failure / degraded / NotReady |
| `--neutral` | `#344054` (text) on `#f2f4f7` (bg) | Informational / not-applicable / N/A |
| `--surface` | `#ffffff` | Card background |
| `--page-bg` | `#f8f9fb` | Page background |
| `--border` | `#e4e7ec` | Card / table borders |
| `--heading` | `#101828` | Primary heading text |

- Green = PASS, Amber = WARN, Red = FAIL is a **fixed convention** across all three templates and both report types.
- Never encode status by colour alone — pair every colour with a text label (`PASS` / `WARN` / `FAIL`) and/or an icon glyph (`✔` / `!` / `✖`) for accessibility and print-to-grayscale safety.

## Typography

- Font stack: `-apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`.
- Base body `14px`, line-height `1.5`; report title `20–22px` bold; section headings `16px` semibold.
- Monospace (`"SFMono-Regular", Consolas, "Liberation Mono", monospace`) for node names, versions, cluster API URLs, and any copyable token.
- Keep contrast WCAG-AA friendly; never render light-grey text on white for critical status.

## Components (consistent across all templates)

Every HTML report (`health-overview.j2`, `error-report.j2`) must contain, in order:

1. **Header band** — report title, cluster name, run ID / timestamp, and overall verdict pill (PASS / WARN / FAIL).
2. **Summary section** — at-a-glance counts (e.g. `X passed, Y warnings, Z failed`) as colour-coded tiles, plus hop `x/y` and elapsed time where relevant.
3. **Colour-coded status table(s)** — one row per check: number, check name, observed value, gate type (HARD/WARN), and status pill. Row tint driven by the passed-in `row_class`.
4. **Collapsible detail** — full `oc`/`jq` output and per-node breakdowns hidden behind `<details>`/`<summary>` (collapsed by default to reduce noise).
5. **Copy button** — copies key identifiers (e.g. failed node names, cluster, run ID) to clipboard. Reports only, never in email.
6. **Footer** — generated-by line, host, and a note that HTML lives in `output/` and logs in `logs/`.

### Progress email (`progress-mail.j2`) specifics

- **Short & concise design (≤ 580px)**: Flat, compact, single-card layout formatted for instant scanning.
- **MCP status is always shown**: Renders clean pool names, machines count (`ready/total`), updated status, updating, degraded, and status pill.
- **Service account access notice**: If the service account lacks RBAC permissions to query MachineConfigPools, a distinct warning callout is rendered instead of breaking the layout or defaulting to `N/A`.
- **Node activity surfaced conditionally**: Active working nodes (draining/rebooting) and degraded-only nodes are shown only when present; healthy nodes are omitted to keep the email short.
- Header shows cluster, **hop x/y**, **target**, **% complete**, **elapsed**, and **cadence note**.
- Colour-coded green/amber/red pills for MCP and node states. All styles inline; no `<details>` or JS.

### Failure alert email (`error-report.j2`) specifics

- **Short & concise alert design (≤ 580px)**: Compact single-card layout with high-visibility verdict pill (`FAIL ✖`).
- **Dedicated RBAC / Permission Warning Box**: If an operation fails due to `forbidden`, `cannot patch`, or `unauthorized`, renders an amber/red callout detailing the missing OpenShift API resource/verb and actionable remediation guidance for the operator.
- **Compact failure details table**: Failed check/task, gate type (HARD), observed state, exact error output, and safe session teardown confirmation.
- 1-line operator next-step guidance and run log path.

## Content & Tone

- Minimise noise: surface only meaningful status. Do not dump full JSON into the email body — that belongs in the report's collapsible detail.
- Every status value must be explicit and human-readable (`Updated=True`, `Degraded=False`, `CPU 72% / MEM 65%`), not raw booleans without labels.
- Guard every optional field with `| default('N/A')` so a missing value renders cleanly, never `Undefined`.
- Never render secrets, tokens, kubeconfig contents, or passwords in any report or email — they must be filtered upstream (`no_log`) and never reach the template context.

## Print / PDF Behaviour

- Target A4/Letter width; ensure the summary and status tables fit without clipping.
- Status must remain distinguishable in grayscale (rely on the paired text label + glyph, not colour alone).
- Collapsible `<details>` should be expanded for print via a `@media print { details { display: block; } summary { display:none; } }` rule in report templates.
