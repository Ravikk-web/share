# Antigravity Prompt — Generate Word Documentation + PowerPoint for ARO Upgrade Automation

> Copy everything below the line into Antigravity. It instructs the agent to read your existing context/spec files and produce a professional Word document **and** a PowerPoint deck, both with flowcharts, diagrams, and workflow visuals.

---

## ROLE

You are a senior technical writer and solutions architect. Produce **two polished, client-ready deliverables** documenting my existing project **"ARO Cluster Upgrade Automation"**:

1. A **Microsoft Word document** (`.docx`) — full technical documentation.
2. A **PowerPoint presentation** (`.pptx`) — an executive + technical walkthrough deck.

Both must include **flowcharts, architecture diagrams, and workflow visuals** (not just text).

## SOURCE OF TRUTH (read these first — do not invent behaviour)

Read all of the following project files before writing anything, and base 100% of the content on them:

- `context/project-overview.md` — product definition, goals, features, scope, success criteria
- `context/architecture.md` — stack table, system boundaries, storage model, auth model, invariants
- `context/code-standards.md` — implementation rules and conventions
- `context/ai-workflow-rules.md` — build workflow and scoping rules
- `context/ui-context.md` — report/email styling tokens (green/amber/red status model)
- `context/progress-tracker.md` — current build state
- The build specs `unit-01` … `unit-20` — the full unit-by-unit build order and behaviour

If any file is missing, list what you could not find, then proceed using the files that exist. Do not fabricate features, thresholds, or gate rules that are not in these files.

## PROJECT CONTEXT (summary — verify against the files)

- **What it is:** A rule-based, deterministic **Ansible** automation suite that performs **Y-stream (minor) ARO/OpenShift upgrades** in ordered sequential hops (e.g. `4.18.09 → 4.19.15 → 4.20.08`). **No AI in the execution path.**
- **Dual runtime:** Runs unchanged on **Ansible 2.7.17 (test)** and **2.14.18 (prod)**; tooling limited to `oc`, `jq`, `sendmail`, shell.
- **Lifecycle:** Login once → baseline snapshot → load secrets → **13-check prevalidation hard gate** → looped upgrade hops (each: set channel → verify edge → admin-ack → `oc adm upgrade --to` → monitor → settle-gate) → **10-check postvalidation + baseline diff** → **operator upgrade & validation (Unit 20)**.
- **Safety:** Login once, **logout on any failure** via `block/rescue/always`; HARD gates halt the chain, WARN items report only.
- **Monitoring:** Poll cv/mcp/nodes every 2 min; 20-min HTML heartbeat email + change alerts; 90-min per-hop timeout guard.
- **Outputs:** Colour-coded client HTML reports, dual `.txt`/`.csv` logs, baseline JSON snapshot.

## DELIVERABLE 1 — WORD DOCUMENT (`ARO-Upgrade-Automation-Documentation.docx`)

Professional formatting: title page, auto table of contents, page numbers, consistent heading styles, a subtle brand-blue accent (`#2563eb`), and status colour legend (green `#16a34a` / amber `#d97706` / red `#dc2626`).

Sections (in order):

1. **Title Page** — project name, subtitle "Rule-Based Ansible Automation for ARO Y-Stream Upgrades", author, date, version.
2. **Executive Summary** — 1 page: what it does, why it matters, key benefits (deterministic, auditable, dual-version safe).
3. **Table of Contents** — auto-generated.
4. **Solution Overview** — goals, core user flow, in-scope / out-of-scope.
5. **Architecture** — the stack table; system-boundary description; storage model; auth model; **invariants**. Include an **architecture diagram**.
6. **End-to-End Workflow** — narrative of the full lifecycle with a **master flowchart** (login → snapshot → secrets → prevalidation gate → hop loop → postvalidation → operator upgrade → logout).
7. **Phase Deep-Dives** — one subsection per phase (00–08 + hop loop + Unit 20). For each: purpose, inputs, key `oc`/`jq` actions, gate type (HARD/WARN), and a small flow snippet.
8. **Validation Model** — the **13 prevalidation checks** and **10 postvalidation checks** as formatted tables (columns: #, Check, Rule, Gate). Colour-code the Gate column.
9. **Upgrade Hop Mechanics** — the per-hop sequence with a **hop flowchart** and the settle-gate entry condition.
10. **Monitoring & Notifications** — polling cadence, heartbeat/alert logic, timeout guard; include a **monitoring loop diagram**.
11. **Operator Upgrade & Validation (Unit 20)** — compatibility scan → InstallPlan approval → CSV settle → final validation; include a **flowchart**.
12. **Reporting, Logging & Outputs** — HTML report anatomy, `.txt`/`.csv` logs, baseline snapshot + diff.
13. **Dual-Version Compatibility & Migration** — 2.7.17 vs 2.14.18 rules; the migration checklist.
14. **Build Units Reference** — a table of Units 1–20 (Unit #, Name, What it builds, Dependencies).
15. **Appendix** — directory structure tree, example `upgrade_path`, glossary (ARO, MCP, CO, CSV, InstallPlan, edge, admin-ack, Y-stream).

## DELIVERABLE 2 — POWERPOINT (`ARO-Upgrade-Automation-Deck.pptx`)

16:9 widescreen, clean corporate theme, consistent master layout, brand-blue accent (`#2563eb`), the same status colour legend, readable fonts, minimal text per slide (speaker notes carry detail). ~16–20 slides:

1. **Title slide** — project name, subtitle, author, date.
2. **The Problem** — manual ARO upgrades: risk, inconsistency, no audit trail.
3. **The Solution** — deterministic, rule-based, no-AI Ansible automation.
4. **Key Benefits** — icon row: deterministic, auditable, dual-version, safe-fail.
5. **Architecture at a Glance** — architecture **diagram** + stack table (condensed).
6. **End-to-End Workflow** — the **master flowchart** (full slide).
7. **Phase Map** — the 8 phases as a horizontal **process diagram**.
8. **Prevalidation Hard Gate** — the 13 checks summarised; HARD vs WARN visual.
9. **Upgrade Hops** — Y-stream hop concept diagram (`4.18 → 4.19 → 4.20`) + per-hop **flowchart**.
10. **Monitoring & Alerts** — polling/heartbeat/timeout **diagram**; sample colour-coded status tiles.
11. **Postvalidation & Baseline Diff** — the 10 checks + diff concept.
12. **Operator Upgrade & Validation** — Unit 20 **flowchart**.
13. **Safety & Guardrails** — login-once/logout-on-failure, HARD gates halt, `--force` manual-only.
14. **Dual-Version Strategy** — 2.7.17 ↔ 2.14.18 with the migration path.
15. **Reporting & Outputs** — sample HTML report mock + logs/snapshot.
16. **Build Roadmap** — Units 1–20 as a phased timeline/roadmap graphic.
17. **Summary & Next Steps.**
18. **Q&A / Thank You.**

Add concise **speaker notes** on every slide.

## DIAGRAMS & FLOWCHARTS (required — generate real visuals, not placeholders)

Produce these as actual rendered graphics embedded in both files. Prefer generating diagram source (e.g. **Mermaid** or **Graphviz/DOT**) and rendering to PNG/SVG, then embedding. Keep a consistent visual language: rounded nodes, brand-blue for process steps, green/amber/red for gate outcomes, diamonds for decisions.

Minimum diagram set:
1. **System architecture diagram** — jump server, Ansible engine, `oc`/`jq`/`sendmail`, ARO cluster, outputs (reports/logs/snapshots).
2. **Master workflow flowchart** — full lifecycle with decision diamonds at each HARD gate (fail → alert → logout → stop).
3. **Per-hop upgrade flowchart** — set channel → verify edge → admin-ack → `oc adm upgrade --to` → monitor → settle-gate.
4. **Monitoring loop diagram** — 2-min poll, 20-min heartbeat, change-alert, 90-min timeout branch.
5. **Prevalidation gate diagram** — 13 checks → HARD/WARN split → proceed/halt.
6. **Operator upgrade flowchart (Unit 20)** — compat scan → approve InstallPlan → CSV settle → validate.
7. **Build-units roadmap** — Units 1–20 grouped by stage (Foundation → Session → Reporting → Checks → Gates → Upgrade Engine → Closeout → Operators).

## STYLE & QUALITY BARS

- Faithful to the source files — no invented behaviour, thresholds, or commands.
- Consistent status colour legend everywhere: green = PASS, amber = WARN, red = FAIL/HARD.
- Tables for all check lists and the build-units reference.
- Professional, concise, client-presentable tone.
- Every diagram legible at 100% zoom; label all nodes and decision branches.

## OUTPUT

Deliver both files:
- `ARO-Upgrade-Automation-Documentation.docx`
- `ARO-Upgrade-Automation-Deck.pptx`

Plus a short `DIAGRAMS/` folder containing the diagram source (Mermaid/DOT) and rendered PNG/SVG used in both. Report any source file you could not locate and any assumption you had to make.
