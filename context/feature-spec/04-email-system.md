# Unit 04: Email Notification System & Templates

> **Revision 2026-10-01 (review remediation)** — All mails go through `tasks/notify.yml` → `roles/sendmail` (per-type routing, ASCII subjects, SMTP errors non-fatal, `notification_ledger`). Mail set: prevalidation (full runs), heartbeat (20 min), degradation (once per condition), one alert per failed run, one closing summary (`email-summary.j2`). Hop-complete and state-change mails were removed. See `ui-context.md` → Email Templates.

## Goal

Build the consolidated notification system: the `sendmail` role (dispatched via Ansible's native `mail` module using direct SMTP) and all three Jinja2 templates (`error-report.j2`, `progress-mail.j2`, `health-overview.j2`), implementing strict template rendering lifecycles, fact cleanup, RBAC error callouts, and support for `AUTO-FIXED` / `FIX-FAILED` status pills.

---

## Design & System Boundaries

- **System Boundary**: `playbooks/roles/sendmail/` and `playbooks/templates/*.j2`.
- **Native Direct SMTP**: Uses Ansible's built-in `mail` module (Python `smtplib`). Eliminates dependencies on local `/usr/sbin/sendmail` MTA binaries while remaining 100% compatible with Ansible 2.7.17 and 2.14.18.
- **Template Rendering Lifecycle**:
  1. Resolve template path.
  2. Always render fresh HTML via `lookup('template', ...)` into `mail_html_body`.
  3. Dispatch email via native `mail`.
  4. **Crucial Fact Reset**: Clear `mail_html_body` and `mail_final_body` facts immediately after dispatch to prevent body caching across subsequent hops.
- **Attachments Support**: Support passing file paths via `mail_attachments` (e.g. attaching Prevalidation report on hop completion, and 4 audit reports on final upgrade completion).

---

## Implementation Details

### 1. `roles/sendmail/`
- **`defaults/main.yml`**:
  ```yaml
  smtp_host: "smtp.example.com"
  smtp_port: 25
  mail_from: "aro-upgrades@example.com"
  mail_to: []
  mail_subject: "[ARO Upgrade] Notification"
  mail_template: ""
  mail_html_body: ""
  mail_attachments: []
  mail_charset: "utf-8"
  ```
- **`tasks/main.yml`**:
  1. Resolve template path (handle relative to `templates/` or absolute).
  2. If `mail_template` is provided, freshly render it:
     ```yaml
     - name: "Render email HTML template"
       set_fact:
         mail_html_body: "{{ lookup('template', resolved_template_path) }}"
       when: mail_template | length > 0
     ```
  3. Dispatch email using native `mail` module:
     ```yaml
     - name: "Dispatch email notification via direct SMTP"
       mail:
         host: "{{ smtp_host }}"
         port: "{{ smtp_port | int }}"
         from: "{{ mail_from }}"
         to: "{{ mail_to }}"
         subject: "{{ mail_subject }}"
         body: "{{ mail_html_body }}"
         subtype: html
         charset: "{{ mail_charset }}"
         attach: "{{ mail_attachments | default([]) }}"
       delegate_to: localhost
     ```
  4. **Post-Dispatch Fact Cleanup**:
     ```yaml
     - name: "Reset email body facts to prevent cross-hop caching"
       set_fact:
         mail_html_body: ""
         mail_final_body: ""
         mail_attachments: []
     ```

### 2. Failure Alert Template (`playbooks/templates/error-report.j2`)
- High-contrast alert card (`≤ 580px`, red accent border).
- Overall verdict: `UPGRADE HALTED ✖`.
- **RBAC Warning Callout**: Rendered when `is_rbac_error == true`, showing:
  - Missing OpenShift API verb and resource.
  - Actionable remediation command (e.g. `oc adm policy add-cluster-role-to-user ...`).
- Diagnostic matrix: failed task name, gate type (`HARD`), observed state, exact error output.
- Safe teardown confirmation (cluster session closed, token revoked).
- Log file link in `logs/`.

### 3. Progress & Heartbeat Template (`playbooks/templates/progress-mail.j2`)
- Compact progress card (`≤ 580px`).
- Header metrics: Hop X/Y, Target version, % Complete, Elapsed time.
- MachineConfigPool table: always shown with ready/total machines, Updated, Updating, Degraded, and status pills.
- Working node display: actively draining/rebooting nodes shown; healthy nodes suppressed.
- Degraded nodes list: explicitly surfaces any `NotReady` or pressured nodes.
- **Hop Complete State**: Header shows `HOP COMPLETE ✔` with Prevalidation report attached.

### 4. Health Overview & Report Template (`playbooks/templates/health-overview.j2`)
- Multi-purpose report template for Prevalidation, Postvalidation, and Operator Validation.
- Renders:
  - Summary metric tiles (Passed, Warnings, Auto-Fixed, Failed).
  - Status table with check number, name, observed value, gate type, and status pills.
  - **Status Pill Support**:
    - `PASS ✔` (Green `#1a7f37` on `#e6f4ea`)
    - `WARN !` (Amber `#9a6700` on `#fff8e1`)
    - `FAIL ✖` (Red `#b42318` on `#fdecea`)
    - `AUTO-FIXED ⚙` (Blue `#1d4ed8` on `#eff6ff`)
    - `FIX-FAILED ⚠` (Orange `#c2410c` on `#ffedd5`)
  - Auto-Remediation Callout summarizing any automated fixes applied.
  - Collapsible `<details>` section for raw `oc`/`jq` JSON outputs.
  - Copy-to-clipboard button (standalone reports only).

---

## Verification Checklist

- [ ] `sendmail` role dispatches via native `mail` module with direct SMTP.
- [ ] `mail_html_body` is freshly rendered and explicitly cleared post-dispatch.
- [ ] `error-report.j2` renders RBAC warning callout when `is_rbac_error` is true.
- [ ] `health-overview.j2` correctly styles `AUTO-FIXED` (blue) and `FIX-FAILED` (orange) pills.
- [ ] Attachment paths are accepted and passed to `attach` parameter.
- [ ] All templates render without `Undefined` errors when optional fields are empty.
