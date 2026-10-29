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
