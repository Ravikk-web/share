# ARO Cluster Capacity & Health Check Automation

[![Ansible](https://img.shields.io/badge/Ansible-2.7%2B-red.svg?logo=ansible&logoColor=white)](https://www.ansible.com/)
[![OpenShift](https://img.shields.io/badge/OpenShift-ARO%20%2F%20OCP-red.svg?logo=redhatopenshift&logoColor=white)](https://cloud.redhat.com/)
[![CLI-oc](https://img.shields.io/badge/CLI-oc%20%7C%20jq-blue.svg)](https://docs.openshift.com/)
[![Automation](https://img.shields.io/badge/Automation-Health%20%26%20Capacity-green.svg)](#)

An automated Ansible solution designed to perform comprehensive health, resource utilization, and capacity assessments across multiple **Azure Red Hat OpenShift (ARO)** and **OpenShift Container Platform (OCP)** clusters.

It evaluates 17 critical infrastructure checks, generates interactive **HTML** and **CSV** reports, and sends an executive summary email directly to operations and engineering teams.

---

## 📌 Table of Contents

- [Features](#-features)
- [How It Works](#-how-it-works)
- [The 17 Health & Capacity Checks](#-the-17-health--capacity-checks)
- [Repository Structure](#-repository-structure)
- [Prerequisites](#-prerequisites)
- [Configuration](#-configuration)
  - [1. Cluster Inventory (`clusters.yml`)](#1-cluster-inventory-clustersyml)
  - [2. Unified Exclusions (`exclusions.yml`)](#2-unified-exclusions-exclusionsyml)
  - [3. Email & SMTP Settings (`email_vars.yml`)](#3-email--smtp-settings-email_varsyml)
  - [4. Thresholds & Window Settings](#4-thresholds--window-settings)
- [Usage](#-usage)
  - [Run Full Assessment & Email](#run-full-assessment--email)
  - [Resend Email Only](#resend-email-only)
- [Reports & Outputs](#-reports--outputs)
- [Troubleshooting & FAQ](#-troubleshooting--faq)

---

## 🚀 Features

- **Multi-Cluster Support**: Scan multiple ARO/OCP clusters in a single playbook execution.
- **17 In-Depth Checks**: Audits control plane health, operator status, operator stuck durations, node overcommit, actual usage, node condition events (cordoned, degraded, network), pod health, storage, and active alerts.
- **Unified Exclusions (`exclusions.yml`)**: Single configuration file to exclude noisy namespaces, operators, nodes, and Prometheus alerts without modifying code.
- **Interactive HTML Dashboard**:
  - **Quick Triage Banner**: Immediately surfaces top failing checks across all clusters.
  - **Live Search & Filter Toolbar**: Instant filtering by status (Fail, Warn, Pass) or keyword search across clusters and checks.
  - **NOC Dark Mode Toggle**: Built-in dark/light theme switch with persistent memory.
  - **Copy Slack Summary**: One-click formatted Markdown export for Slack/Teams incident response.
  - **Node Condition Chips & Operator Duration Badges**: Visual indicators for cordoned nodes and time-stuck operators.
  - **Print & PDF Optimized**: Clean layout export for documentation and stakeholders.
- **CSV Export**: Machine-readable breakdown of every check per cluster for audits and external reporting.
- **Smart Email Notifications**: Delivers an executive email digest with dynamic subject line alert tags (`[CRITICAL]`, `[WARNING]`, `[HEALTHY]`), status left-border indicators, and report attachments.

---

## 🔄 How It Works

```mermaid
flowchart LR
    A[Playbook Starts] --> B[Load Inventory & Exclusions]
    B --> C[Loop Through Clusters]
    C --> D[Run 17 Health & Capacity Checks]
    D --> E[Aggregate Master Results]
    E --> F[Generate HTML & CSV Reports]
    F --> G[Send Email via SMTP]
    G --> H[Cleanup Local Temp Reports]
```

1. **Initialization**: Reads target clusters, unified exclusions (`exclusions.yml`), and alerting thresholds.
2. **Cluster Assessment**: Logs into each cluster using the OpenShift CLI (`oc`) and runs 17 targeted queries.
3. **Report Generation**: Aggregates statuses into an interactive HTML dashboard and a CSV file.
4. **Email Delivery**: Uses an embedded Ansible role (`sendmail`) to email results to stakeholders.
5. **Cleanup**: Removes local temporary report artifacts after successful delivery.

---

## 🔍 The 17 Health & Capacity Checks

| # | Check Name | Description | Status Criteria |
|---|---|---|---|
| **1** | **ClusterVersion Status** | Verifies OCP version and checks `Available`, `Degraded`, and `Progressing` conditions | **PASS**: Available=True & Degraded!=True |
| **2** | **Insights Operator** | Confirms the Insights Operator is healthy and active | **PASS**: Degraded!=True |
| **3** | **Control Plane Health** | Checks API server status and master node conditions | **PASS**: All master nodes Ready |
| **4** | **Cluster Operators** | Scans all cluster operators (`oc get co`) against cluster version | **PASS**: All available and not degraded |
| **5** | **Cluster Alerts** | Checks active alerts from Prometheus/Alertmanager within lookback window (filtered by exclusions) | **PASS**: No alerts \| **WARN**: Warning alerts \| **FAIL**: Critical alerts |
| **6** | **Node Status** | Validates worker and infra node conditions | **PASS**: All non-excluded nodes in `Ready` state |
| **7** | **Node Resource Pressure** | Checks for `MemoryPressure`, `DiskPressure`, or `PIDPressure` | **PASS**: Zero nodes under pressure |
| **8** | **Node CPU Overcommit** | Calculates requested CPU against allocatable capacity | **PASS** ≤ 85% \| **WARN** > 85% \| **FAIL** > 95% |
| **9** | **Node Memory Overcommit** | Calculates requested Memory against allocatable capacity | **PASS** ≤ 85% \| **WARN** > 85% \| **FAIL** > 95% |
| **10** | **Node CPU Actual Usage** | Evaluates real-time node CPU utilization metrics via `oc adm top` | **PASS** ≤ 85% \| **WARN** > 85% \| **FAIL** > 95% |
| **11** | **Node Memory Actual Usage** | Evaluates real-time node Memory utilization metrics via `oc adm top` | **PASS** ≤ 85% \| **WARN** > 85% \| **FAIL** > 95% |
| **12** | **Pod Health** | Identifies problematic pods (CrashLoopBackOff, Error, Failed outside excluded namespaces) | **PASS**: 0 problematic pods \| **WARN**: Issues detected |
| **13** | **MCP Status** | Checks MachineConfigPools (`master`, `worker`) updating/degraded states | **PASS**: Updated=True, Degraded=False |
| **14** | **StorageClasses** | Checks configured StorageClasses and identifies default storage class | **PASS**: StorageClasses present |
| **15** | **PVC Status** | Verifies PersistentVolumeClaims are `Bound` | **PASS**: No PVCs stuck in `Pending`/`Lost` |
| **16** | **Node Condition Events** | In-depth audit of node conditions (`SchedulingDisabled`, `NotReady`, `Degraded`, `Progressing`, `NetworkUnavailable`) with duration tracking | **PASS**: All nodes clean \| **WARN**: Cordoned/Progressing \| **FAIL**: NotReady/Network/Degraded |
| **17** | **Cluster Operator Duration** | Time-aware audit of cluster operators tracking how long operators have been `Degraded`, `Progressing`, or `Unavailable` | **PASS**: All healthy \| **WARN**: Progressing > 30m \| **FAIL**: Degraded or Unavailable |

### 🚦 Health & Status Rollup Logic

The playbook calculates the **Overall Status** of each cluster based on a hierarchical rollup:

1. **🔴 FAIL**: Assigned if cluster login fails OR if **any** of the 17 checks returns a `FAIL` status.
2. **🟡 WARN**: Assigned if **no** checks failed, but **one or more** checks return a `WARN` status (e.g. CPU/Memory overcommit > 85%, active warning alerts, cordoned nodes, or non-running pods).
3. **🟢 PASS**: Assigned only when **all 17 checks** evaluate to `PASS`.

---

## 📁 Repository Structure

```text
aro-capacity-check/
├── capacity_check.yml       # Main playbook: initialization, loop, report & email trigger
├── cluster_checks.yml      # Tasks file: contains all 17 check implementations
├── clusters.yml            # Inventory file: target cluster URLs and credentials
├── exclusions.yml          # Central exclusions: namespaces, operators, nodes, alerts
├── email_vars.yml          # SMTP server details and email distribution list
├── SendEmail.yml           # Standalone playbook to trigger report email delivery
├── sendmail/               # Ansible role for formatting & sending HTML emails
│   └── tasks/
│       └── main.yml        # Role logic: email body templating and SMTP dispatch
└── README.md               # Project documentation
```

---

## ⚙️ Prerequisites

Ensure the following tools are installed on the machine running Ansible:

1. **Ansible**: Version 2.7.17 or newer.
   ```bash
   ansible --version
   ```
2. **OpenShift CLI (`oc`)**: Must be installed at `/usr/local/bin/oc` or available in `$PATH`.
   ```bash
   oc version --client
   ```
3. **`jq` utility**: Used for JSON parsing in shell tasks.
   ```bash
   jq --version
   ```
4. **Network Access**:
   - Outbound access to target cluster API URLs (`port 6443`).
   - Outbound access to your internal SMTP server (`port 25` or configured port).

---

## 🛠️ Configuration

### 1. Cluster Inventory (`clusters.yml`)

Define the clusters to evaluate with API endpoints and service account credentials:

```yaml
---
clusters:
  - name: "arod01"
    api_url: "https://api.arod01.dev.example.com:6443"
    username: "service-account"
    password: "secure-password-or-token"

  - name: "arod03"
    api_url: "https://api.arod03.dev.example.com:6443"
    username: "service-account"
    password: "secure-password-or-token"
```

> 🔒 **Security Tip**: For production environments, use [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html) to encrypt sensitive credentials in `clusters.yml`.

### 2. Unified Exclusions (`exclusions.yml`)

Configure exclusions across all checks in one central location:

```yaml
---
# Namespaces excluded from Pod failure/crashloop checks (Check 12)
exclude_namespaces:
  - openshift-insights
  - twistlock
  - openshift-gitops
  - app00046878-openshift-platform
  - default

# Cluster operators excluded from operator checks (Checks 4 & 17)
exclude_cluster_operators:
  - operator-lifecycle-manager
  - aro

# Nodes to bypass from node health/capacity checks (Checks 6-11 & 16)
exclude_nodes: []
  # - "test-worker-01"

# Prometheus alerts to ignore from cluster alert check (Check 5)
exclude_alerts:
  - Watchdog
  - InfoInhibitor
  - AlertmanagerReceiversNotConfigured
```

### 3. Email & SMTP Settings (`email_vars.yml`)

Configure the SMTP relay host and recipients who will receive reports:

```yaml
---
smtp_host: smtp.example.com
smtp_port: 25
sender: Cluster-Upgrade-Automation@ARO-Team
recipients:
  - user1@example.com
  - user2@example.com
```

### 4. Thresholds & Window Settings

Global thresholds can be modified at the top of `capacity_check.yml`:

```yaml
report_dir: "./reports"       # Temporary directory where reports are created
warn_threshold: 85            # Triggers WARN if resource usage exceeds 85%
fail_threshold: 95            # Triggers FAIL if resource usage exceeds 95%
alert_window: "6h"            # Prometheus alert lookback window (e.g., 6h)
```

---

## 💻 Usage

### Run Full Assessment & Email

Execute the main playbook from the repository root:

```bash
ansible-playbook capacity_check.yml
```

**What this does:**
1. Validates connectivity and logs into each cluster.
2. Runs all 17 checks sequentially per cluster.
3. Builds the interactive HTML and CSV reports under `./reports/`.
4. Dispatches the email with summary details, status-coded accents, and attached reports.
5. Deletes `./reports/` upon completion.

### Resend Email Only

If you generated reports manually and only wish to trigger the email notification:

```bash
ansible-playbook SendEmail.yml
```

---

## 📊 Reports & Outputs

### 1. Interactive HTML Report (`.html`)
- **Quick Triage Banner**: Immediate visual briefing of blocking issues.
- **Real-Time Filter & Search**: Instantly filter clusters by name, node, check, or status (`Fail`, `Warn`, `Pass`).
- **Dark Mode**: Switch between Light and NOC Dark modes with auto-saved preference.
- **Copy Slack Summary**: Fast incident-channel sharing with pre-formatted Markdown.
- **Node Condition Chips**: Color-coded badges for cordoned, degraded, or progressing nodes.
- **Operator Duration Timeline**: Clear duration badges (`2d 5h`, `45m`) highlighting chronic stuck operators.
- **Resource Usage Bars & SVG Gauges**: High-to-low sorted node resource table with 1-click node name copy.

### 2. CSV Report (`.csv`)
Formatted for spreadsheet analysis and SIEM/ticketing ingestion:
```csv
Cluster Name,API URL,OCP Version,Overall Status,Check Name,Check Status,Details
"arod01","https://api.arod01...","4.14.16","FAIL","Node Condition Events","WARN","Node conditions - worker-01: [SchedulingDisabled (since 2d 4h)]"
```

<<<<<<< HEAD
## Current status
- **Phase:** Live-run fixes (2026-10-26), after the first live run on arod01. That run stopped with the worker pool at "0 of 3" behind one cordoned worker, and the resume then stopped in the prechecks.
  - **Resume:** running the same command again first watches an update that is still running to the end. That includes a hop whose control plane is done while its workers are still updating. Then the prechecks run.
  - **cgroup v2 is checked on every node.** `cgroup_check_method` in `vars/upgrade.yml` chooses how:
    - `config` (default): the MCO configuration the node runs;
    - `kernel`: its kernel (`stat -c %T -f /sys/fs/cgroup` through the node's machine-config-daemon pod, needs `pods/exec`);
    - `both`.

    AUTO-FIXED only when every node is on v2.
  - **Node problems** are reported with the likely cause and what to do, in Check 02, the degradation mails and the alert. The automation never repairs a node.
  - **"Pool cannot continue" alert:** no node updating while unavailable nodes use up `maxUnavailable`.
  - **New checks:** Check 08 now checks drain headroom per pool (HARD), and the new Check 17 checks router headroom (WARN).
  - **Logs:** the last 5 runs per cluster are kept.
  - **Settings:** `log_keep_runs`, `cgroup_check_method`, `cgroup_render_wait_minutes`, `cgroup_node_check_wait_minutes`, `degradation_pool_blocked_minutes`, `node_overcommit_memory_usage_percent`, `node_overcommit_memory_limits_percent`. No new cluster writes.
- **Verified offline only** (no Ansible on the workstation). After an independent review whose findings were all fixed, and including the `cgroup_check_method` switch: static checks 0 problems, unit checks 62/62, flow scenarios 33/33 (147 checks, 0 failed).
  - Static checks: YAML, Jinja, include paths, the jq programs compiled plus a jq 1.5 scan, `bash -n`.
  - Unit checks of each new shell step against a fake cluster.
  - End-to-end flow scenarios: the real `main.yml` run by a small Ansible emulator against a fake `oc` cluster.
- **Next:**
  1. arod01: free the cordoned worker (runbook in `Documentation.md`), let the worker pool finish, then run the same command again.
  2. On the jump host: `ansible-playbook --syntax-check main.yml` with Ansible 2.7.17 and 2.14.18.
  3. Check the new reads on a real cluster: `oc get machines.machine.openshift.io`, `oc adm top nodes` and, before using `cgroup_check_method` `kernel` or `both`, the `oc exec ... stat` kernel check.
  4. `--dry-run`, `--pre-check`, then a one-hop upgrade on DEV.
- The live-run fixes are committed (`de65045`). The `cgroup_check_method` switch is not committed yet. Nothing is pushed.
=======
---

## ❓ Troubleshooting & FAQ

<details>
<summary><b>1. Cluster login fails with TLS verification errors</b></summary>
The playbook uses <code>--insecure-skip-tls-verify=true</code> by default in <code>cluster_checks.yml</code>. If connection fails, ensure the API URL is reachable from the Ansible runner host:
<pre>curl -k https://&lt;api-url&gt;:6443/readyz</pre>
</details>

<details>
<summary><b>2. How can I keep the generated reports locally instead of deleting them?</b></summary>
In <code>capacity_check.yml</code>, comment out or remove the final cleanup task at the bottom:
<pre>
# - name: "Delete the Logs"
#   file:
#     path: "{{ report_dir }}"
#     state: absent
</pre>
</details>

<details>
<summary><b>3. How do I silence a known-degraded operator or cordoned test node?</b></summary>
Add the operator name to <code>exclude_cluster_operators</code> or the node name to <code>exclude_nodes</code> in <code>exclusions.yml</code>. The checks will automatically skip them during evaluation.
</details>

---

## 👥 Authors & Maintainers

- **ARO Infrastructure & Cloud Operations Team**
- Automation maintained for OpenShift / Azure Red Hat OpenShift operations.
>>>>>>> 8c2122e (branch change)
