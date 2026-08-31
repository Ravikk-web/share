# Unit 05: `sendmail` Role

## Goal

Build the `sendmail` role with the mandatory dual implementation — an active `sendmail` shell block (2.7.17) and a commented `community.general.mail` block (2.14) — that renders the Unit 04 templates and sends colour-coded HTML mail.

## Design

- **System boundary:** `playbooks/roles/sendmail`.
- Dual-email contract: both blocks must stay in the file; only one is active.
- Sends HTML MIME mail; body produced by rendering `progress-mail.j2` or `error-report.j2` into a fact first.

## Implementation

### `sendmail/tasks/main.yml` — active (2.7)
Render the chosen template to `mail_html_body` via `template` → `set_fact` (or `lookup('template', ...)`). Then:
```
shell: |
  /usr/sbin/sendmail -t <<'EOF'
  To: {{ mail_to }}
  From: {{ mail_from }}
  Subject: {{ mail_subject }}
  MIME-Version: 1.0
  Content-Type: text/html; charset=UTF-8

  {{ mail_html_body }}
  EOF
```
`changed_when: false`. Comment: short-name `shell` intentional, **no `warn:`**.

### Commented 2.14 block
`# - name: Send via community.general.mail` with `host/port/to/from/subject/subtype: html/body`, plus enable/disable instructions and the `ansible-galaxy collection install community.general` note.

### `sendmail/defaults/main.yml`
`smtp_port: 25`, `mail_subject: ""` with `| default('')`, template selector var.

## Dependencies

- Unit 04 (templates)
- Unit 01 (`vars/smtp.yml`)
- sendmail binary (`/usr/sbin/sendmail`)

## Verify when done

- [x] Active sendmail block sends HTML mail successfully
- [x] Commented `community.general.mail` block present with switch instructions
- [x] Neither block deleted (dual-email contract intact)
- [x] No `warn:` param; short module names
- [x] `changed_when:` set; optional vars carry `| default('')`
- [x] No secrets in the mail body
- [x] Runs on 2.7.17 (2.14 note verified)
- [x] progress-tracker.md updated
