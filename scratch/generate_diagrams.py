"""
Generate all 18 production architectural diagrams for ARO Cluster Upgrade Automation.
Outputs high-resolution 300 DPI PNG images into ARO_Cluster_Upgrade_Diagrams/.
"""

import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.patches import FancyBboxPatch, Rectangle, ArrowStyle
import numpy as np

OUTPUT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "ARO_Cluster_Upgrade_Diagrams"))
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Theme Palette (Matches context/ui-context.md)
NAVY = "#0F2744"
BLUE = "#1D4ED8"
LIGHT_BLUE = "#EFF6FF"
CYAN = "#0284C7"
GREEN = "#1A7F37"
LIGHT_GREEN = "#E6F4EA"
AMBER = "#B45309"
LIGHT_AMBER = "#FFF8E1"
RED = "#B42318"
LIGHT_RED = "#FDECEA"
SLATE = "#334155"
LIGHT_SLATE = "#F1F5F9"
BORDER = "#CBD5E1"
WHITE = "#FFFFFF"

plt.rcParams['font.sans-serif'] = 'Arial'
plt.rcParams['font.family'] = 'sans-serif'

def draw_card(ax, x, y, w, h, title, subtitle="", bg=WHITE, border=BORDER, title_color=NAVY, sub_color=SLATE, radius=0.03, lw=1.5, ls="-"):
    """Draw a styled enterprise card."""
    box = FancyBboxPatch((x, y), w, h, boxstyle=f"round,pad={radius},rounding_size={radius}",
                         facecolor=bg, edgecolor=border, linewidth=lw, linestyle=ls, zorder=2)
    ax.add_patch(box)
    if title and subtitle:
        ax.text(x + w/2, y + h*0.62, title, ha="center", va="center", fontsize=9.5, fontweight="bold", color=title_color, zorder=3)
        ax.text(x + w/2, y + h*0.35, subtitle, ha="center", va="center", fontsize=7.5, color=sub_color, zorder=3)
    elif title:
        ax.text(x + w/2, y + h/2, title, ha="center", va="center", fontsize=9, fontweight="bold", color=title_color, zorder=3)

def draw_arrow(ax, x1, y1, x2, y2, color=SLATE, text="", lw=1.5, ls="-"):
    """Draw a directed arrow with optional label."""
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="->,head_width=0.3,head_length=0.4",
                                color=color, lw=lw, ls=ls), zorder=4)
    if text:
        mx, my = (x1 + x2)/2, (y1 + y2)/2
        ax.text(mx, my + 0.02, text, ha="center", va="bottom", fontsize=7.5, fontweight="semibold",
                color=color, bbox=dict(facecolor=WHITE, edgecolor="none", pad=1.5), zorder=5)

# -------------------------------------------------------------
# Figure 1: System Context Diagram
# -------------------------------------------------------------
def gen_fig01():
    fig, ax = plt.subplots(figsize=(12, 6.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    # Title
    ax.text(0.5, 0.95, "Figure 1: System Context & Integration Architecture", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.91, "Operational boundaries, infrastructure touchpoints, and security perimeters", ha="center", fontsize=9, color=SLATE)

    # Core System Boundary Box
    core_box = FancyBboxPatch((0.28, 0.12), 0.44, 0.72, boxstyle="round,pad=0.02,rounding_size=0.03",
                              facecolor=LIGHT_SLATE, edgecolor=BLUE, linewidth=2, linestyle="--", zorder=1)
    ax.add_patch(core_box)
    ax.text(0.5, 0.81, "RHEL 8 JUMP SERVER (EXECUTION HOST)", ha="center", fontsize=10, fontweight="bold", color=BLUE)

    # Components inside jump server
    draw_card(ax, 0.31, 0.58, 0.38, 0.18, "ARO Upgrade Automation Suite", "playbooks/ (00_Run.sh, main.yml, 24 Roles)", bg=WHITE, border=BLUE, lw=2)
    draw_card(ax, 0.31, 0.36, 0.38, 0.16, "Tooling & Execution Layer", "oc CLI | jq v1.5 | Python / smtplib | bash", bg=WHITE, border=BORDER)
    draw_card(ax, 0.31, 0.16, 0.38, 0.14, "Scoped Storage Boundary", "logs/ (.txt, .csv) | output/ (HTML) | snapshots/", bg=WHITE, border=BORDER)

    # Left: Human / Admin Context
    draw_card(ax, 0.04, 0.60, 0.18, 0.16, "Platform Ops Team", "CLI Operator (00_Run.sh)", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.04, 0.28, 0.18, 0.16, "Report Consumers", "Platform Engineers & Clients", bg=LIGHT_GREEN, border=GREEN)

    # Right: External Systems
    draw_card(ax, 0.78, 0.62, 0.18, 0.18, "ARO Cluster API", "Port 6443 (oc client TLS)\nClusterVersion & Operators", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.78, 0.38, 0.18, 0.16, "Corporate SMTP Gateway", "Port 25 (Direct smtplib)\nHeartbeats & Failure Alerts", bg=LIGHT_AMBER, border=AMBER)
    draw_card(ax, 0.78, 0.14, 0.18, 0.16, "CyberArk Conjur Vault", "Planned Secrets Source\n(Future Migration)", bg=LIGHT_SLATE, border=SLATE, lw=1.5)

    # Connections
    draw_arrow(ax, 0.22, 0.68, 0.31, 0.68, color=BLUE, text="One-Touch CLI")
    draw_arrow(ax, 0.31, 0.24, 0.22, 0.35, color=GREEN, text="HTML Audit Reports")
    draw_arrow(ax, 0.69, 0.68, 0.78, 0.71, color=BLUE, text="oc API calls")
    draw_arrow(ax, 0.69, 0.44, 0.78, 0.46, color=AMBER, text="HTML Mail")
    draw_arrow(ax, 0.78, 0.22, 0.69, 0.22, color=SLATE, text="Var References", ls=":")

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig01_system_context.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 2: High-Level Architecture Diagram
# -------------------------------------------------------------
def gen_fig02():
    fig, ax = plt.subplots(figsize=(12, 7.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.96, "Figure 2: High-Level Architecture & Layered System Model", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.92, "Orchestration, scaffolding, presentation, and cluster interface boundaries", ha="center", fontsize=9, color=SLATE)

    layers = [
        ("Layer 1: CLI & User Experience", 0.81, 0.08, [
            ("00_Run.sh", "Pre-flight checks, menu engine, PID locks, tee'd logging", 0.05, 0.43, BLUE),
            ("scripts/cli_helpers.sh", "ANSI boxes, 72-col UI, risk calculation, visual journey", 0.52, 0.43, CYAN)
        ]),
        ("Layer 2: Master Orchestrator", 0.68, 0.08, [
            ("main.yml", "Hybrid chain, skip_to_phase / stop_after_phase bounds, dry-run teardown", 0.05, 0.90, NAVY)
        ]),
        ("Layer 3: Seven-File Process Surface (Phase Playbooks)", 0.52, 0.11, [
            ("01_Policy_Check", "Auth, Snapshot, Edge", 0.05, 0.13, BLUE),
            ("02_Pre_upgrade", "14-Check Gate, Auto-Fix", 0.20, 0.15, BLUE),
            ("03_Initiate", "Per-Hop Driver", 0.37, 0.12, BLUE),
            ("04_Live_monitoring", "2m Poll, Settle-Gate", 0.51, 0.15, BLUE),
            ("05_post_Upgrade", "10-Check Diff Gate", 0.68, 0.14, BLUE),
            ("06_Operator_Upgrade", "OLM Scan & Approve", 0.84, 0.13, BLUE),
        ]),
        ("Layer 4: Supporting Scaffolding (24 Roles & Sub-Tasks)", 0.33, 0.14, [
            ("Session (3)", "login, logout, snapshot", 0.05, 0.13, SLATE),
            ("Health (6)", "api, co, mcp, node, etcd", 0.20, 0.13, GREEN),
            ("Disruption (4)", "util, pv, pvc, pdb", 0.35, 0.13, AMBER),
            ("Engine (2)", "upgrade, monitor", 0.50, 0.13, BLUE),
            ("Auto-Fix (1)", "remediate", 0.65, 0.13, RED),
            ("Operators (3)", "compat, upg, val", 0.80, 0.15, CYAN),
        ]),
        ("Layer 5: Presentation & Storage", 0.17, 0.11, [
            ("vars/*.yml (6 Files)", "upgrade, secrets, smtp, paths, report_vars, api_regex", 0.05, 0.43, SLATE),
            ("templates/*.j2 (3 Files)", "health-overview, progress-mail, error-report", 0.52, 0.43, AMBER)
        ]),
        ("Layer 6: Tooling & Audit Artifacts", 0.03, 0.09, [
            ("Binaries: oc CLI, jq 1.5, smtplib, bash", "Deterministic execution", 0.05, 0.43, NAVY),
            ("Artifacts: logs/ (.txt, .csv), output/ (HTML), snapshots/", "Write-only audit trail", 0.52, 0.43, GREEN)
        ])
    ]

    for title, y, h, cards in layers:
        ax.text(0.05, y + h + 0.01, title, fontsize=9.5, fontweight="bold", color=NAVY)
        for ctitle, csub, cx, cw, ccol in cards:
            draw_card(ax, cx, y, cw, h, ctitle, csub, bg=WHITE, border=ccol, title_color=ccol)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig02_high_level_architecture.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 3: Seven-Process-File Flowchart
# -------------------------------------------------------------
def gen_fig03():
    fig, ax = plt.subplots(figsize=(12, 6), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.95, "Figure 3: Seven-Process-File Flowchart & Chaining Hierarchy", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.90, "Linear phase execution, per-hop task inclusion, and life-cycle isolation", ha="center", fontsize=9, color=SLATE)

    draw_card(ax, 0.03, 0.55, 0.12, 0.22, "00_Run.sh", "CLI Entrypoint\nPre-flight, Menus,\nPID Lock", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.18, 0.55, 0.12, 0.22, "main.yml", "Master Orchestrator\nPhase bounds &\nDry-run intercepts", bg=LIGHT_SLATE, border=NAVY)
    draw_card(ax, 0.33, 0.55, 0.12, 0.22, "Phase 01", "01_Policy_Check\nLogin, Snapshot,\nEdge verification", bg=WHITE, border=BLUE)
    draw_card(ax, 0.48, 0.55, 0.12, 0.22, "Phase 02", "02_Pre_upgrade\n14 Health Checks,\nAuto-Remediation", bg=WHITE, border=BLUE)
    draw_card(ax, 0.63, 0.55, 0.15, 0.22, "Phase 03 / 04", "03_Initiate_upgrade\nLoops tasks/hop.yml\n& 04_Live_monitoring", bg=LIGHT_AMBER, border=AMBER)
    draw_card(ax, 0.81, 0.55, 0.15, 0.22, "Phase 05", "05_post_Upgrade\n10 Checks & Baseline\nDiff Analysis", bg=WHITE, border=BLUE)

    draw_card(ax, 0.63, 0.15, 0.33, 0.22, "Phase 06: 06_Operator_Upgrade.yaml", "OLM Operator compatibility scan, InstallPlan approval, CSV settle, & terminal logout", bg=LIGHT_GREEN, border=GREEN)
    draw_card(ax, 0.48, 0.15, 0.12, 0.22, "Dry-Run Intercept", "Post-Phase 02\nLogout & Stop\n(if dry_run=true)", bg=LIGHT_RED, border=RED)

    draw_arrow(ax, 0.15, 0.66, 0.18, 0.66, color=NAVY)
    draw_arrow(ax, 0.30, 0.66, 0.33, 0.66, color=NAVY)
    draw_arrow(ax, 0.45, 0.66, 0.48, 0.66, color=NAVY)
    draw_arrow(ax, 0.60, 0.66, 0.63, 0.66, color=NAVY)
    draw_arrow(ax, 0.78, 0.66, 0.81, 0.66, color=NAVY)
    draw_arrow(ax, 0.88, 0.55, 0.88, 0.37, color=NAVY)
    draw_arrow(ax, 0.54, 0.55, 0.54, 0.37, color=RED, text="dry_run", ls="--")

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig03_seven_process_flow.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 4: End-to-End Upgrade Flowchart
# -------------------------------------------------------------
def gen_fig04():
    fig, ax = plt.subplots(figsize=(12, 7), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.96, "Figure 4: End-to-End Upgrade Execution Flow", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.92, "Chronological lifecycle from pre-flight checks to digest notification and logout", ha="center", fontsize=9, color=SLATE)

    steps = [
        (0.05, 0.78, 0.16, 0.10, "1. CLI Pre-flight", "Validates bash, oc, jq, python\n& 6 vars/*.yml files", BLUE),
        (0.24, 0.78, 0.16, 0.10, "2. Interactive Menus", "Selects cluster, path, mode\nTier risk evaluation", BLUE),
        (0.43, 0.78, 0.16, 0.10, "3. PID Lock & Login", "Creates /tmp/aro-*.lock\noc login creates kubeconfig", NAVY),
        (0.62, 0.78, 0.16, 0.10, "4. Phase 01 Snapshot", "Baseline JSON captured\nValidates update edge", GREEN),
        (0.81, 0.78, 0.16, 0.10, "5. Phase 02 Preval", "14 Health Checks evaluated\nDetects upgrade blockers", AMBER),

        (0.81, 0.55, 0.16, 0.10, "6. Auto-Remediation", "Tier 1: cgroup v2, admin-acks,\nunpause MCP | Re-verify", RED),
        (0.62, 0.55, 0.16, 0.10, "7. Preval Report", "Renders HTML report\nHalts if residual HARD fail", GREEN),
        (0.43, 0.55, 0.16, 0.10, "8. Per-Hop Upgrade", "tasks/hop.yml: Set channel,\nvalidate edge, trigger upgrade", BLUE),
        (0.24, 0.55, 0.16, 0.10, "9. Live Monitoring", "2m poll, 20m heartbeat email,\nstate alert, 90m timeout guard", AMBER),
        (0.05, 0.55, 0.16, 0.10, "10. Settle Gate", "Asserts CV at target, COs\nhealthy, MCPs updated", GREEN),

        (0.05, 0.32, 0.16, 0.10, "11. Next Hop / Loop", "Advance to Hop N+1 or\ncontinue to Phase 05", BLUE),
        (0.24, 0.32, 0.16, 0.10, "12. Phase 05 Postval", "10 health checks & baseline\ndiff analysis against Phase 01", BLUE),
        (0.43, 0.32, 0.16, 0.10, "13. Postval Report", "Generates HTML postval report\nDispatches email with report", GREEN),
        (0.62, 0.32, 0.16, 0.10, "14. Phase 06 Operators", "Scans compat, approves plans,\nsettles CSVs (Tier 2 recovery)", CYAN),
        (0.81, 0.32, 0.16, 0.10, "15. Operator Report", "Generates HTML operator report\nRecords operator states", GREEN),

        (0.62, 0.09, 0.16, 0.10, "16. Upgrade Digest", "Sends final email with 4 audit\nattachments (3 HTML + log)", GREEN),
        (0.43, 0.09, 0.16, 0.10, "17. Terminal Logout", "Revokes token, removes\ntarget cluster kubeconfig", NAVY),
        (0.24, 0.09, 0.16, 0.10, "18. Lock Cleanup", "Removes PID lock file\nRestores terminal echo", SLATE),
        (0.05, 0.09, 0.16, 0.10, "19. Post-Run Summary", "Displays 72-col tabular summary,\nexact durations & artifacts", BLUE)
    ]

    for x, y, w, h, title, sub, col in steps:
        draw_card(ax, x, y, w, h, title, sub, bg=WHITE, border=col, title_color=col)

    draw_arrow(ax, 0.21, 0.83, 0.24, 0.83)
    draw_arrow(ax, 0.40, 0.83, 0.43, 0.83)
    draw_arrow(ax, 0.59, 0.83, 0.62, 0.83)
    draw_arrow(ax, 0.78, 0.83, 0.81, 0.83)
    draw_arrow(ax, 0.89, 0.78, 0.89, 0.65)
    draw_arrow(ax, 0.81, 0.60, 0.78, 0.60)
    draw_arrow(ax, 0.62, 0.60, 0.59, 0.60)
    draw_arrow(ax, 0.43, 0.60, 0.40, 0.60)
    draw_arrow(ax, 0.24, 0.60, 0.21, 0.60)
    draw_arrow(ax, 0.13, 0.55, 0.13, 0.42)
    draw_arrow(ax, 0.21, 0.37, 0.24, 0.37)
    draw_arrow(ax, 0.40, 0.37, 0.43, 0.37)
    draw_arrow(ax, 0.59, 0.37, 0.62, 0.37)
    draw_arrow(ax, 0.78, 0.37, 0.81, 0.37)
    draw_arrow(ax, 0.89, 0.32, 0.70, 0.19)
    draw_arrow(ax, 0.62, 0.14, 0.59, 0.14)
    draw_arrow(ax, 0.43, 0.14, 0.40, 0.14)
    draw_arrow(ax, 0.24, 0.14, 0.21, 0.14)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig04_end_to_end_workflow.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 5: Multi-Hop Upgrade Flow
# -------------------------------------------------------------
def gen_fig05():
    fig, ax = plt.subplots(figsize=(12, 5.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.94, "Figure 5: Multi-Hop Upgrade Model & Sequential Settle Gates", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.89, "Sequential Y-stream compliance: strict version validation without skipping minor releases", ha="center", fontsize=9, color=SLATE)

    draw_card(ax, 0.04, 0.50, 0.13, 0.24, "Initial Version", "4.18.09\n(stable-4.18)", bg=LIGHT_SLATE, border=SLATE)
    draw_card(ax, 0.21, 0.50, 0.17, 0.24, "Hop 1: 4.18 -> 4.19", "Target: 4.19.15\nChannel: stable-4.19\nLive Edge Verified", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.21, 0.18, 0.17, 0.22, "Settle Gate 1", "CV=4.19.15 (Progressing=False)\nCOs=Available / Degraded=0\nMCPs=Updated (ready/total)", bg=LIGHT_GREEN, border=GREEN)
    draw_card(ax, 0.43, 0.50, 0.17, 0.24, "Hop 2: 4.19 -> 4.20", "Target: 4.20.08\nChannel: stable-4.20\nLive Edge Verified", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.43, 0.18, 0.17, 0.22, "Settle Gate 2", "CV=4.20.08 (Progressing=False)\nCOs=Available / Degraded=0\nMCPs=Updated (ready/total)", bg=LIGHT_GREEN, border=GREEN)
    draw_card(ax, 0.65, 0.50, 0.14, 0.24, "Target Version", "4.20.08\nCluster Hops Settled", bg=LIGHT_GREEN, border=GREEN)
    draw_card(ax, 0.83, 0.50, 0.13, 0.24, "Phase 05 & 06", "Postval Diff &\nOperator Rollouts", bg=LIGHT_AMBER, border=AMBER)

    draw_arrow(ax, 0.17, 0.62, 0.21, 0.62, color=BLUE, text="Edge Check")
    draw_arrow(ax, 0.29, 0.50, 0.29, 0.40, color=GREEN, text="Monitor Loop")
    draw_arrow(ax, 0.38, 0.29, 0.43, 0.29, color=NAVY, text="Hop 1 Pass")
    draw_arrow(ax, 0.51, 0.40, 0.51, 0.50, color=BLUE, text="Next Hop")
    draw_arrow(ax, 0.51, 0.50, 0.51, 0.40, color=GREEN, text="Monitor Loop")
    draw_arrow(ax, 0.60, 0.29, 0.65, 0.29, color=NAVY)
    draw_arrow(ax, 0.72, 0.40, 0.72, 0.50, color=GREEN, text="All Settled")
    draw_arrow(ax, 0.79, 0.62, 0.83, 0.62, color=AMBER, text="Advance")

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig05_multihop_upgrade_flow.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 6: Auto-Remediation Decision Flowchart
# -------------------------------------------------------------
def gen_fig06():
    fig, ax = plt.subplots(figsize=(12, 7.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.96, "Figure 6: Three-Tier Auto-Remediation Decision Logic", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.92, "Deterministic resolution of known blockers, safety guards, and revalidation protocol", ha="center", fontsize=9, color=SLATE)

    draw_card(ax, 0.38, 0.82, 0.24, 0.08, "14 Prevalidation Checks", "8 HARD Gates | 6 WARN Advisories", bg=WHITE, border=BLUE)
    draw_card(ax, 0.38, 0.68, 0.24, 0.08, "Residual HARD Blockers?", "Checks evaluated against gates", bg=LIGHT_AMBER, border=AMBER)
    draw_card(ax, 0.75, 0.68, 0.20, 0.08, "Proceed to Phase 03", "Status: ALL PASSED", bg=LIGHT_GREEN, border=GREEN)
    draw_card(ax, 0.38, 0.54, 0.24, 0.08, "auto_remediation_enabled?", "Master toggle in vars/upgrade.yml", bg=LIGHT_AMBER, border=AMBER)
    draw_card(ax, 0.05, 0.54, 0.20, 0.08, "Hard Stop & Logout", "Status: FAIL (Remediation OFF)", bg=LIGHT_RED, border=RED)

    tier_box = FancyBboxPatch((0.15, 0.22), 0.70, 0.24, boxstyle="round,pad=0.02,rounding_size=0.03",
                              facecolor=LIGHT_SLATE, edgecolor=BLUE, linewidth=1.5, linestyle="--", zorder=1)
    ax.add_patch(tier_box)
    ax.text(0.5, 0.43, "THREE-TIER REMEDIATION ENGINE (remediate role)", ha="center", fontsize=9.5, fontweight="bold", color=NAVY)

    draw_card(ax, 0.17, 0.25, 0.20, 0.15, "Tier 1: Auto-Fix (Default ON)", "1. cgroupMode -> v2\n2. Dynamic Admin-Acks\n3. Unpause MCPs", bg=WHITE, border=GREEN)
    draw_card(ax, 0.40, 0.25, 0.20, 0.15, "Tier 2: Guided (Default OFF)", "1. Degraded CO pod restart\n2. Stalled MCD force re-apply\n3. CSV rollout retry", bg=WHITE, border=AMBER)
    draw_card(ax, 0.63, 0.25, 0.20, 0.15, "Tier 3: Hard-Stop", "Gateway API CRD conflict\nImmediate Halt & Guidance\n(No heuristic guessing)", bg=WHITE, border=RED)

    draw_card(ax, 0.20, 0.04, 0.26, 0.10, "Revalidation: PASS", "Status: AUTO-FIXED\nProceed to Phase 03", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.54, 0.04, 0.26, 0.10, "Revalidation: FAIL", "Status: FIX-FAILED\nHalt, Email Alert, Logout", bg=LIGHT_RED, border=RED)

    draw_arrow(ax, 0.50, 0.82, 0.50, 0.76)
    draw_arrow(ax, 0.62, 0.72, 0.75, 0.72, color=GREEN, text="No Blockers")
    draw_arrow(ax, 0.50, 0.68, 0.50, 0.62, color=AMBER, text="Blocker Detected")
    draw_arrow(ax, 0.38, 0.58, 0.25, 0.58, color=RED, text="Toggle=False")
    draw_arrow(ax, 0.50, 0.54, 0.50, 0.47, color=GREEN, text="Toggle=True")
    draw_arrow(ax, 0.27, 0.25, 0.33, 0.14, color=BLUE, text="Re-verify")
    draw_arrow(ax, 0.50, 0.25, 0.45, 0.14)
    draw_arrow(ax, 0.73, 0.25, 0.67, 0.14)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig06_auto_remediation_flow.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 7: Authentication & Session Sequence Diagram
# -------------------------------------------------------------
def gen_fig07():
    fig, ax = plt.subplots(figsize=(12, 6.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.95, "Figure 7: Authentication & Session Lifecycle Sequence", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.91, "Dedicated kubeconfig isolation, cross-phase session reuse, and guaranteed fail-safe teardown", ha="center", fontsize=9, color=SLATE)

    lifelines = [
        ("Operator / CLI\n(00_Run.sh)", 0.12),
        ("Master Orchestrator\n(main.yml)", 0.32),
        ("Session Roles\n(login / logout)", 0.52),
        ("Dedicated Kubeconfig\n(.kubeconfig-<cluster>)", 0.72),
        ("ARO Cluster API\n(Port 6443)", 0.90)
    ]

    for title, x in lifelines:
        draw_card(ax, x - 0.08, 0.78, 0.16, 0.09, title.split('\n')[0], title.split('\n')[1] if '\n' in title else "", bg=LIGHT_SLATE, border=NAVY)
        ax.plot([x, x], [0.12, 0.78], color=BORDER, linestyle="--", lw=1.5, zorder=1)

    calls = [
        (0.72, 0.12, 0.32, "1. Execute ./00_Run.sh --cluster <name>", BLUE),
        (0.64, 0.32, 0.52, "2. Phase 01: include_role: login", BLUE),
        (0.56, 0.52, 0.90, "3. oc login --username --password (execve argv:)", NAVY),
        (0.48, 0.90, 0.72, "4. Returns session token & writes isolated kubeconfig", GREEN),
        (0.40, 0.32, 0.72, "5. Phases 02-05 reuse dedicated KUBECONFIG", SLATE),
        (0.32, 0.32, 0.52, "6. Phase 06 Complete: include_role: logout", GREEN),
        (0.24, 0.52, 0.90, "7. oc logout (token revoked)", RED),
        (0.16, 0.52, 0.72, "8. file: state=absent (removes .kubeconfig file)", RED)
    ]

    for y, x1, x2, msg, col in calls:
        draw_arrow(ax, x1, y, x2, y, color=col, text=msg)

    box = FancyBboxPatch((0.08, 0.03), 0.84, 0.06, boxstyle="round,pad=0.01,rounding_size=0.01",
                         facecolor=LIGHT_RED, edgecolor=RED, linewidth=1, zorder=2)
    ax.add_patch(box)
    ax.text(0.5, 0.06, "FAIL-SAFE INVARIANT: Every phase wraps execution in block/rescue/always; always block unconditionally triggers logout.",
            ha="center", va="center", fontsize=8, fontweight="bold", color=RED, zorder=3)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig07_auth_session_sequence.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 8: Baseline Snapshot Data Flow
# -------------------------------------------------------------
def gen_fig08():
    fig, ax = plt.subplots(figsize=(12, 6), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.95, "Figure 8: Baseline Snapshot Data Flow & Postvalidation Diff", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.90, "Single sanctioned cross-phase state persistence model (Phase 01 capture -> Phase 05 audit)", ha="center", fontsize=9, color=SLATE)

    draw_card(ax, 0.04, 0.45, 0.22, 0.35, "Phase 01: Capture",
              "1. oc get cv -o json\n2. oc get nodes -o json\n3. oc get co -o json\n4. oc get routes -A -o json\n\nParsed via strict jq 1.5\nAssemble baseline_dict",
              bg=LIGHT_BLUE, border=BLUE)

    draw_card(ax, 0.35, 0.45, 0.28, 0.35, "Single Persisted State Artifact",
              "snapshots/<cluster>_<timestamp>_baseline.json\n\n- cluster_id & channel\n- starting_version\n- node inventory (ready, roles, kubelet)\n- operators inventory (available, degraded)\n- exposed routes inventory\n(NO SECRETS STORED)",
              bg=LIGHT_SLATE, border=NAVY)

    draw_card(ax, 0.72, 0.45, 0.24, 0.35, "Phase 05: Baseline Diff",
              "1. slurp / from_json snapshot\n2. Query live cluster state\n3. Audit node readiness & count\n4. Audit operator availability\n5. Audit route reachability\n\nSurfaces missing/degraded items",
              bg=LIGHT_GREEN, border=GREEN)

    draw_card(ax, 0.50, 0.12, 0.35, 0.18, "Client Postvalidation HTML Report",
              "output/<cluster>_postvalidation_<ts>.html\nTabular Baseline Diff + 10 Postval Health Checks", bg=WHITE, border=GREEN)

    draw_arrow(ax, 0.26, 0.62, 0.35, 0.62, color=BLUE, text="to_nice_json")
    draw_arrow(ax, 0.63, 0.62, 0.72, 0.62, color=NAVY, text="from_json")
    draw_arrow(ax, 0.84, 0.45, 0.72, 0.30, color=GREEN, text="Diff Findings")

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig08_baseline_snapshot_dataflow.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 9: Live Monitoring Loop Flowchart
# -------------------------------------------------------------
def gen_fig09():
    fig, ax = plt.subplots(figsize=(12, 7), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.96, "Figure 9: Live Monitoring Loop & Telemetry Engine", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.92, "Bounded 2-minute polling loop with heartbeats, state-change alerts, and settle-gate evaluation", ha="center", fontsize=9, color=SLATE)

    draw_card(ax, 0.05, 0.68, 0.18, 0.18, "1. Poll Iteration", "Every 2 minutes (bounded)\noc get cv, co, mcp, nodes\njq 1.5 parsing & progress %", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.28, 0.68, 0.18, 0.18, "2. State Change?", "Detects new node draining,\nMCP progress, or CO change", bg=LIGHT_AMBER, border=AMBER)
    draw_card(ax, 0.28, 0.36, 0.18, 0.18, "Send Alert Email", "Immediate notification\nwith RBAC remediation", bg=LIGHT_RED, border=RED)
    draw_card(ax, 0.51, 0.68, 0.18, 0.18, "3. Heartbeat Due?", "Every 20 minutes elapsed", bg=LIGHT_SLATE, border=SLATE)
    draw_card(ax, 0.51, 0.36, 0.18, 0.18, "Send Heartbeat Mail", "HTML progress card,\nMCP table, node status", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.74, 0.68, 0.22, 0.18, "4. Settle Gate Met?", "CV=Target & not Progressing\nCOs=100% Available/Degraded=0\nMCPs=100% Updated", bg=LIGHT_GREEN, border=GREEN)
    draw_card(ax, 0.74, 0.36, 0.22, 0.18, "Settle Pass -> Hop Done", "Sends Hop-Complete email\nAdvances to Hop N+1", bg=LIGHT_GREEN, border=GREEN)
    draw_card(ax, 0.05, 0.36, 0.18, 0.18, "Timeout (90m) Check", "If loop reaches max iterations\nwithout settling: HARD FAIL", bg=LIGHT_RED, border=RED)
    draw_card(ax, 0.74, 0.08, 0.22, 0.14, "Sleep 120 Seconds", "Pauses before next iteration", bg=WHITE, border=SLATE)

    draw_arrow(ax, 0.23, 0.77, 0.28, 0.77)
    draw_arrow(ax, 0.37, 0.68, 0.37, 0.54, color=RED, text="Yes")
    draw_arrow(ax, 0.46, 0.77, 0.51, 0.77, color=SLATE, text="No")
    draw_arrow(ax, 0.60, 0.68, 0.60, 0.54, color=BLUE, text="Yes")
    draw_arrow(ax, 0.69, 0.77, 0.74, 0.77, color=SLATE, text="No")
    draw_arrow(ax, 0.85, 0.68, 0.85, 0.54, color=GREEN, text="Settled")
    draw_arrow(ax, 0.85, 0.68, 0.85, 0.22, color=SLATE, text="Not Settled")
    draw_arrow(ax, 0.74, 0.15, 0.14, 0.15, color=SLATE)
    draw_arrow(ax, 0.14, 0.15, 0.14, 0.36, color=SLATE)
    draw_arrow(ax, 0.14, 0.54, 0.14, 0.68, color=SLATE, text="Under 90m")

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig09_monitoring_loop.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 10: Role Interaction & Categorization Diagram
# -------------------------------------------------------------
def gen_fig10():
    fig, ax = plt.subplots(figsize=(12, 7.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.96, "Figure 10: Role Interaction & Architectural Categorization", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.92, "Mapping all 24 modular roles across functional domains and operational phases", ha="center", fontsize=9, color=SLATE)

    domains = [
        ("Session & Infra", 0.04, 0.70, 0.21, 0.18, ["login (Auth)", "logout (Teardown)", "snapshot (JSON Capture)"], NAVY),
        ("Health Checks", 0.28, 0.70, 0.21, 0.18, ["api_check (Context)", "api_readiness (/readyz)", "co, mcp, node, etcd"], BLUE),
        ("Capacity & Disruption", 0.52, 0.70, 0.21, 0.18, ["utilization (CPU/Mem)", "pv, pvc (Storage)", "pdb (Drain Deadlock)"], AMBER),
        ("Aggregators & Gates", 0.75, 0.70, 0.21, 0.18, ["prevalidation (14 Checks)", "postvalidation (10 Checks)"], GREEN),

        ("Upgrade Engine", 0.04, 0.40, 0.21, 0.18, ["upgrade (Trigger & Channel)", "monitor (Polling Loop)"], BLUE),
        ("Auto-Remediation", 0.28, 0.40, 0.21, 0.18, ["remediate (Tier 1/2 Dispatch:\ncgroup, acks, mcp, co)"], RED),
        ("Operators (Phase 06)", 0.52, 0.40, 0.21, 0.18, ["operator_compat (Scan)", "operator_upgrade (Patch)", "operator_validate (Health)"], CYAN),
        ("Reporting & Alerts", 0.75, 0.40, 0.21, 0.18, ["report (HTML Generator)", "sendmail (Native SMTP)", "error_handle (Rescue)"], GREEN)
    ]

    for dtitle, x, y, w, h, items, col in domains:
        box = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.015,rounding_size=0.02",
                             facecolor=WHITE, edgecolor=col, linewidth=1.5, zorder=2)
        ax.add_patch(box)
        ax.text(x + w/2, y + h - 0.03, dtitle, ha="center", fontsize=9.5, fontweight="bold", color=col, zorder=3)
        for idx, item in enumerate(items):
            ax.text(x + 0.02, y + h - 0.065 - (idx * 0.035), f"• {item}", fontsize=8, color=SLATE, zorder=3)

    sum_box = FancyBboxPatch((0.04, 0.08), 0.92, 0.22, boxstyle="round,pad=0.02,rounding_size=0.02",
                             facecolor=LIGHT_SLATE, edgecolor=BLUE, linewidth=1.5, zorder=1)
    ax.add_patch(sum_box)
    ax.text(0.5, 0.25, "DATA FLOW & ORCHESTRATION CONTRACT", ha="center", fontsize=10, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.19, "1. 01_Policy_Check invokes Session roles & Snapshot -> establishes authenticated session and JSON state baseline.", ha="center", fontsize=8.5, color=SLATE)
    ax.text(0.5, 0.15, "2. 02_Pre_upgrade invokes Prevalidation (calling Health, Capacity, & Disruption roles) -> delegates to Remediate -> calls Report.", ha="center", fontsize=8.5, color=SLATE)
    ax.text(0.5, 0.11, "3. 03_Initiate_upgrade loops tasks/hop.yml -> calls Upgrade, Monitor, and Sendmail for each minor release hop.", ha="center", fontsize=8.5, color=SLATE)
    ax.text(0.5, 0.07, "4. 05_post_Upgrade diffs baseline -> calls Report; 06_Operator_Upgrade runs Operator roles -> sends 4-attachment digest -> calls Logout.", ha="center", fontsize=8.5, color=SLATE)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig10_role_interaction.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 11: Deployment Diagram
# -------------------------------------------------------------
def gen_fig11():
    fig, ax = plt.subplots(figsize=(12, 6.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.95, "Figure 11: RHEL 8 Jump Server Deployment & Network Architecture", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.90, "Physical and logical boundaries, filesystem layout, and egress network flows", ha="center", fontsize=9, color=SLATE)

    host_box = FancyBboxPatch((0.05, 0.10), 0.55, 0.75, boxstyle="round,pad=0.02,rounding_size=0.03",
                              facecolor=LIGHT_SLATE, edgecolor=BLUE, linewidth=2, zorder=1)
    ax.add_patch(host_box)
    ax.text(0.325, 0.81, "RHEL 8 ENTERPRISE JUMP SERVER", ha="center", fontsize=11, fontweight="bold", color=BLUE)

    draw_card(ax, 0.08, 0.58, 0.23, 0.18, "Runtime Engines", "Ansible 2.7.17 (test)\nAnsible 2.14.18 (prod)\nPython 3.6 / 3.11", bg=WHITE, border=NAVY)
    draw_card(ax, 0.34, 0.58, 0.23, 0.18, "CLI Tooling", "oc client (/usr/local/bin/oc)\njq v1.5 JSON processor\nBash >= 4.2", bg=WHITE, border=CYAN)
    draw_card(ax, 0.08, 0.35, 0.23, 0.18, "Automation Codebase", "playbooks/ (Seven Files)\nplaybooks/roles/ (24 roles)\nvars/ & templates/", bg=WHITE, border=BLUE)
    draw_card(ax, 0.34, 0.35, 0.23, 0.18, "Ephemeral Storage", ".kubeconfig-<cluster>\n/tmp/aro-upgrade-*.lock\nSnapshots (JSON)", bg=WHITE, border=AMBER)
    draw_card(ax, 0.08, 0.14, 0.49, 0.16, "Write-Only Audit Artifacts", "playbooks/logs/ (<cluster>_<ts>.txt, .csv) | playbooks/output/ (*.html)", bg=WHITE, border=GREEN)

    draw_card(ax, 0.72, 0.62, 0.23, 0.22, "ARO OpenShift API", "Port 6443 / HTTPS TLS\nAPI Endpoint: api.<cluster>:6443\nControl plane & Nodes", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.72, 0.34, 0.23, 0.20, "Corporate SMTP Relay", "Port 25 / Direct smtplib\nNo local postfix daemon required\nDirect HTML dispatch", bg=LIGHT_AMBER, border=AMBER)
    draw_card(ax, 0.72, 0.10, 0.23, 0.18, "CyberArk Conjur Vault", "HTTPS / Port 443\nFuture target secrets engine\nReplaces vars/secrets.yml", bg=LIGHT_SLATE, border=SLATE, ls="--")

    draw_arrow(ax, 0.57, 0.68, 0.72, 0.72, color=BLUE, text="HTTPS 6443 (oc CLI)")
    draw_arrow(ax, 0.57, 0.44, 0.72, 0.44, color=AMBER, text="SMTP Port 25")
    draw_arrow(ax, 0.57, 0.22, 0.72, 0.22, color=SLATE, text="REST API (Future)", ls=":")

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig11_deployment_diagram.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 12: Security Trust Boundary Diagram
# -------------------------------------------------------------
def gen_fig12():
    fig, ax = plt.subplots(figsize=(12, 6.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.95, "Figure 12: Security Trust Boundaries & Data Protection", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.91, "Isolation of credentials, no_log protection, dedicated kubeconfigs, and sanitization", ha="center", fontsize=9, color=SLATE)

    zones = [
        ("ZONE 1: SECRETS REPOSITORY", 0.04, 0.12, 0.20, 0.75, LIGHT_SLATE, SLATE, [
            ("Variable References", "secrets.yml: zero plaintext\n{{ vault_cluster_password }}"),
            ("No Secrets in Git", "Plaintext tokens banned;\nstaged locally only"),
            ("Future Conjur Vault", "Seamless vault integration\nwithout code refactoring")
        ]),
        ("ZONE 2: RUNTIME EXECUTION", 0.27, 0.12, 0.22, 0.75, LIGHT_BLUE, BLUE, [
            ("no_log: true", "Enforced on all auth tasks;\ncredentials never in stdout"),
            ("Password Masking", "Diagnostics replace passwords\nwith ****** mask"),
            ("Argv Execution", "execve() bypasses shell;\nno $ expansion bugs")
        ]),
        ("ZONE 3: CLUSTER SESSION", 0.52, 0.12, 0.21, 0.75, LIGHT_AMBER, AMBER, [
            ("Dedicated Kubeconfig", ".kubeconfig-<cluster>\nDefault ~/.kube untouched"),
            ("Least Privilege", "Service account token;\nstrict RBAC checks"),
            ("Fail-Safe Logout", "always block guarantees\ntoken invalidation & removal")
        ]),
        ("ZONE 4: OUTPUT AUDIT", 0.76, 0.12, 0.20, 0.75, LIGHT_GREEN, GREEN, [
            ("Clean Run Logs", "No tokens in .txt or .csv"),
            ("Sanitized Reports", "Diagnostic HTML contains\nno cluster secrets"),
            ("Write-Only Boundary", "Reports never ingested back\ninto automation logic")
        ])
    ]

    for ztitle, x, y, w, h, bg, col, items in zones:
        box = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.015,rounding_size=0.02",
                             facecolor=bg, edgecolor=col, linewidth=1.5, zorder=1)
        ax.add_patch(box)
        ax.text(x + w/2, y + h - 0.04, ztitle, ha="center", fontsize=9, fontweight="bold", color=col, zorder=2)
        for idx, (ititle, isub) in enumerate(items):
            draw_card(ax, x + 0.015, y + h - 0.22 - (idx * 0.22), w - 0.03, 0.18, ititle, isub, bg=WHITE, border=col)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig12_security_trust_boundaries.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 13: Recommended Validation Pipeline Diagram
# -------------------------------------------------------------
def gen_fig13():
    fig, ax = plt.subplots(figsize=(12, 5.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.95, "Figure 13: Recommended CI/CD & Automated Verification Pipeline", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.90, "Automated quality gates enforcing syntax, AST validation, jq 1.5, and pre-merge standards", ha="center", fontsize=9, color=SLATE)

    pipeline = [
        ("1. Static Analysis", "PyYAML safe_load() on all 71 files\nbash -n on 00_Run.sh & helpers\nCheck executable: /bin/bash", BLUE),
        ("2. Dual-Version Linter", "Zero 'warn:' parameters\nZero bare 'include:'\nAll optionals carry | default('')", NAVY),
        ("3. jq 1.5 Compliance", "Audit 56 jq pipelines\nZero bare 'round' calls (use rnd2)\nParenthesized or/and operands", AMBER),
        ("4. Jinja2 & Type Audit", "Bracket notation ['items']\nBoolean normalization | string | trim\nTemplate mock rendering tests", CYAN),
        ("5. Integration Dry-Run", "./00_Run.sh --pre-check (exit 0)\nPID lock acquisition & cleanup\n14 checks evaluated & report verified", GREEN)
    ]

    for idx, (title, sub, col) in enumerate(pipeline):
        cx = 0.04 + (idx * 0.19)
        draw_card(ax, cx, 0.40, 0.16, 0.35, title, sub, bg=WHITE, border=col, title_color=col)
        if idx < 4:
            draw_arrow(ax, cx + 0.16, 0.57, cx + 0.19, 0.57, color=NAVY)

    box = FancyBboxPatch((0.04, 0.12), 0.92, 0.18, boxstyle="round,pad=0.015,rounding_size=0.02",
                         facecolor=LIGHT_GREEN, edgecolor=GREEN, linewidth=1.5, zorder=1)
    ax.add_patch(box)
    ax.text(0.5, 0.23, "AUTOMATED TEST HARNESS: scratch/verify_unit17.py", ha="center", fontsize=10, fontweight="bold", color=GREEN)
    ax.text(0.5, 0.16, "Executes all 5 verification suites in 4.2 seconds; validates 100% compliance across 11 master pre-merge criteria.", ha="center", fontsize=8.5, color=SLATE)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig13_validation_pipeline.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 14: Reporting & Notification Flow
# -------------------------------------------------------------
def gen_fig14():
    fig, ax = plt.subplots(figsize=(12, 6.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.95, "Figure 14: Reporting Architecture & Notification Engine", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.91, "Data aggregation, presentation templates, HTML artifact generation, and SMTP routing", ha="center", fontsize=9, color=SLATE)

    draw_card(ax, 0.04, 0.70, 0.22, 0.18, "Prevalidation Facts", "health_summary (14 checks)\nautofix_items (remediations)", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.04, 0.44, 0.22, 0.18, "Monitoring Telemetry", "mcp_summary_table, active nodes,\nhop_elapsed_duration, % complete", bg=LIGHT_AMBER, border=AMBER)
    draw_card(ax, 0.04, 0.18, 0.22, 0.18, "Operator & Postval Facts", "operator_compat_plan, CSV phase,\nbaseline snapshot structural diff", bg=LIGHT_GREEN, border=GREEN)

    draw_card(ax, 0.38, 0.62, 0.24, 0.26, "roles/report", "health-overview.j2\n- Header verdict badge\n- 5-tile summary metrics\n- Structured status table\n- Auto-fix callout card", bg=WHITE, border=BLUE)
    draw_card(ax, 0.38, 0.20, 0.24, 0.32, "roles/sendmail", "progress-mail.j2 | error-report.j2\n- Fresh lookup template rendering\n- Native mail module direct SMTP\n- Post-dispatch fact cleanup\n(clears mail_html_body)", bg=WHITE, border=AMBER)

    draw_card(ax, 0.74, 0.65, 0.22, 0.23, "HTML Reports (output/)", "1. <cluster>_prevalidation_<ts>.html\n2. <cluster>_postvalidation_<ts>.html\n3. <cluster>_operators_<ts>.html", bg=LIGHT_BLUE, border=BLUE)
    draw_card(ax, 0.74, 0.38, 0.22, 0.20, "SMTP Notifications", "1. 20m Progress Heartbeat\n2. State-Change Alert (RBAC)\n3. Hop-Complete Notification", bg=LIGHT_AMBER, border=AMBER)
    draw_card(ax, 0.74, 0.12, 0.22, 0.20, "Upgrade Digest Email", "Final completion digest\nDelivers ALL 4 audit attachments\n(3 HTML reports + run log)", bg=LIGHT_GREEN, border=GREEN)

    draw_arrow(ax, 0.26, 0.79, 0.38, 0.75, color=BLUE)
    draw_arrow(ax, 0.26, 0.53, 0.38, 0.40, color=AMBER)
    draw_arrow(ax, 0.26, 0.27, 0.38, 0.30, color=GREEN)
    draw_arrow(ax, 0.62, 0.75, 0.74, 0.75, color=BLUE)
    draw_arrow(ax, 0.62, 0.45, 0.74, 0.48, color=AMBER)
    draw_arrow(ax, 0.62, 0.25, 0.74, 0.22, color=GREEN)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig14_reporting_notification_flow.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 15: Storage & Concurrency Diagram
# -------------------------------------------------------------
def gen_fig15():
    fig, ax = plt.subplots(figsize=(12, 6), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.95, "Figure 15: Storage Architecture, State Persistence & Concurrency Model", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.90, "Strict persistence boundaries: ephemeral memory facts, single baseline JSON, and PID lock", ha="center", fontsize=9, color=SLATE)

    draw_card(ax, 0.04, 0.52, 0.28, 0.32, "PID Concurrency Lock",
              "File: /tmp/aro-upgrade-<cluster>.lock\n\n- Created at startup by 00_Run.sh\n- Stores active process PID\n- kill -0 detects & clears stale locks\n- Blocks simultaneous runs on same cluster\n- Automatically removed by EXIT trap",
              bg=LIGHT_RED, border=RED)

    draw_card(ax, 0.36, 0.52, 0.28, 0.32, "Ephemeral In-Memory State",
              "Ansible Host Facts (localhost)\n\n- health_summary & preval results\n- clusterversion live conditions\n- mcp_summary_table & node state\n- operator_compat_plan & CSV status\n- DISCARDED CLEANLY ON COMPLETION",
              bg=LIGHT_BLUE, border=BLUE)

    draw_card(ax, 0.68, 0.52, 0.28, 0.32, "Baseline Snapshot (Single Persistence)",
              "File: snapshots/<cluster>_<ts>_baseline.json\n\n- Created strictly during Phase 01\n- Persists cluster version, nodes, operators, routes\n- Read strictly by Phase 05 for diff audit\n- ZERO OTHER STATE PERSISTED TO DISK",
              bg=LIGHT_GREEN, border=GREEN)

    draw_card(ax, 0.20, 0.12, 0.60, 0.28, "Write-Only Audit Artifacts (Never Read Back into Logic)",
              "playbooks/logs/<cluster>_<ts>.txt  (Console output tee'd in real-time)\nplaybooks/logs/<cluster>_<ts>.csv  (Machine-readable audit record with phase timestamps)\nplaybooks/output/<cluster>_*.html  (Client-facing standalone HTML reports with deep diagnostics)\n\nGuarantees zero circular dependencies and complete audit compliance.",
              bg=LIGHT_SLATE, border=SLATE)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig15_storage_concurrency.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 16: Three-Way Architectural Venn Diagram
# -------------------------------------------------------------
def gen_fig16():
    fig, ax = plt.subplots(figsize=(12, 7), dpi=300)
    ax.set_xlim(-1.5, 1.5)
    ax.set_ylim(-1.3, 1.3)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0, 1.22, "Figure 16: Three-Way Health, Remediation & Postvalidation Overlap", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0, 1.15, "Mapping verified health checks, auto-remediation capabilities, and postvalidation audit pillars", ha="center", fontsize=9, color=SLATE)

    r = 0.8
    circle_preval = plt.Circle((-0.35, 0.2), r, color=BLUE, alpha=0.15, ec=BLUE, lw=2)
    circle_remed = plt.Circle((0.35, 0.2), r, color=RED, alpha=0.15, ec=RED, lw=2)
    circle_postval = plt.Circle((0, -0.35), r, color=GREEN, alpha=0.15, ec=GREEN, lw=2)

    ax.add_patch(circle_preval)
    ax.add_patch(circle_remed)
    ax.add_patch(circle_postval)

    ax.text(-0.75, 0.85, "Prevalidation (14 Checks)", fontsize=11, fontweight="bold", color=BLUE)
    ax.text(0.75, 0.85, "Auto-Remediation Engine", fontsize=11, fontweight="bold", color=RED)
    ax.text(0, -1.05, "Postvalidation (10 Checks & Diff)", fontsize=11, fontweight="bold", color=GREEN, ha="center")

    ax.text(-0.72, 0.25, "• API Check\n• API Readiness\n• Utilization\n• PDB Audit\n• PV & PVC\n• CSRs\n• Critical Pods", fontsize=7.5, color=NAVY)
    ax.text(0.48, 0.25, "• Stalled MCD\n  Force Re-apply\n• Degraded CO\n  Pod Restart\n• CSV Deletion\n  & Retry", fontsize=7.5, color=RED)
    ax.text(0, -0.65, "• Baseline Snapshot Diff\n• Target Kubelet Version Derivation\n• Prometheus Firing Alerts", fontsize=7.5, color=GREEN, ha="center")

    ax.text(0, 0.55, "• cgroup v2 patch\n• dynamic admin-acks\n• unpause MCPs", fontsize=7.5, fontweight="bold", color=AMBER, ha="center")
    ax.text(-0.35, -0.15, "• Node Pressures\n• etcd Pod Quorum\n• PV State Audit", fontsize=7.5, fontweight="bold", color=NAVY, ha="center")
    ax.text(0.35, -0.15, "• Operator CSV\n  Reconciliation", fontsize=7.5, fontweight="bold", color=SLATE, ha="center")

    ax.text(0, 0.05, "CORE PILLARS:\n• ClusterOperators\n• MachineConfigPools\n• Node Readiness", fontsize=8, fontweight="bold", color=NAVY, ha="center",
            bbox=dict(facecolor=WHITE, edgecolor=NAVY, boxstyle="round,pad=0.2"))

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig16_venn_diagram.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 17: Production Readiness Summary Graphic
# -------------------------------------------------------------
def gen_fig17():
    fig, ax = plt.subplots(figsize=(12, 7), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.96, "Figure 17: Production Readiness Assessment & Quality Scorecard", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.92, "Verified capabilities, partial controls, identified operational gaps, and roadmap recommendations", ha="center", fontsize=9, color=SLATE)

    categories = [
        ("Functional Completeness", "VERIFIED", "One-touch execution, 14-check preval, sequential hops, postval diff, operator lifecycle", GREEN),
        ("Architecture Conformity", "VERIFIED", "Seven-file process surface, dual-version 2.7/2.14 compatibility, short module names", GREEN),
        ("Zero AI Invariant", "VERIFIED", "100% deterministic rules (when:, fail:, deterministic oc patch), zero probabilistic inference", GREEN),
        ("Session Safety & Logout", "VERIFIED", "Single login in Phase 01; fail-safe always block teardown; kubeconfig file removal", GREEN),
        ("Concurrency Safety", "VERIFIED", "PID-based lock (/tmp/aro-upgrade-<cluster>.lock) with stale cleanup & EXIT signal traps", GREEN),
        ("Transient Fault Tolerance", "VERIFIED", "Bounded retry loops (retries: 3 / delay: 10) on all cluster oc reads and mutations", GREEN),
        ("Dual-Format Audit Logging", "VERIFIED", "Simultaneous .txt and .csv run logs written continuously to write-only logs/ directory", GREEN),
        ("Secret Management", "PARTIALLY VERIFIED", "Zero plaintext secrets; variable references used; Conjur Vault integration remains planned", AMBER),
        ("Log & Report Retention", "GAP IDENTIFIED", "Artifacts written indefinitely; jump host cron-based pruning policy recommended", RED),
        ("Jump Host Multi-Tenancy", "RECOMMENDATION", "Scoped kubeconfig prevents default collision; shared jump host sudo isolation recommended", BLUE)
    ]

    for idx, (dim, status, desc, col) in enumerate(categories):
        cy = 0.82 - (idx * 0.075)
        ax.text(0.05, cy + 0.02, dim, fontsize=9, fontweight="bold", color=NAVY)
        box = FancyBboxPatch((0.28, cy), 0.16, 0.045, boxstyle="round,pad=0.008,rounding_size=0.01",
                             facecolor=WHITE, edgecolor=col, linewidth=1.5)
        ax.add_patch(box)
        ax.text(0.36, cy + 0.022, status, ha="center", va="center", fontsize=7.5, fontweight="bold", color=col)
        ax.text(0.46, cy + 0.02, desc, fontsize=8, color=SLATE)
        ax.plot([0.05, 0.95], [cy - 0.015, cy - 0.015], color=LIGHT_SLATE, lw=1)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig17_production_readiness_summary.png"), dpi=300)
    plt.close()

# -------------------------------------------------------------
# Figure 18: Complete Module Wiring & Fact Flow Diagram
# -------------------------------------------------------------
def gen_fig18():
    fig, ax = plt.subplots(figsize=(12, 8.5), dpi=300)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")
    fig.patch.set_facecolor(WHITE)

    ax.text(0.5, 0.97, "Figure 18: Complete Module Wirings, Caller-Callee Bindings & Fact Flow", ha="center", fontsize=13, fontweight="bold", color=NAVY)
    ax.text(0.5, 0.94, "Exhaustive component wiring: CLI to playbooks, roles, tasks, registered facts, and Jinja2 templates", ha="center", fontsize=9, color=SLATE)

    draw_card(ax, 0.03, 0.65, 0.18, 0.25, "00_Run.sh (CLI)",
              "Passes JSON extra-vars:\n- cluster_name\n- upgrade_path: [...]\n- dry_run / skip_to_phase\n- run_timestamp\n- auto_remediation_enabled",
              bg=LIGHT_BLUE, border=BLUE)

    draw_card(ax, 0.03, 0.32, 0.18, 0.28, "main.yml (Orchestrator)",
              "Loads 6 vars/*.yml\nImports:\n- 01_Policy_Check\n- 02_Pre_upgrade\n- Intercept (Logout)\n- 03_Initiate_upgrade\n- 05_post_Upgrade\n- 06_Operator_Upgrade",
              bg=LIGHT_SLATE, border=NAVY)

    draw_card(ax, 0.25, 0.72, 0.22, 0.18, "01_Policy_Check.yaml",
              "Calls: login, snapshot\nValidates: upgrade_path[0]\nExports: baseline_snapshot_file",
              bg=WHITE, border=BLUE)

    draw_card(ax, 0.25, 0.50, 0.22, 0.19, "02_Pre_upgrade_check.yaml",
              "Calls: prevalidation (14 roles)\nCalls: remediate (Auto-Fix)\nCalls: report\nExports: health_summary",
              bg=WHITE, border=BLUE)

    draw_card(ax, 0.25, 0.28, 0.22, 0.19, "03_Initiate_upgrade.yaml",
              "Loops: tasks/hop.yml\nCalls: upgrade\nCalls: 04_Live_monitoring\nCalls: sendmail",
              bg=WHITE, border=BLUE)

    draw_card(ax, 0.25, 0.06, 0.22, 0.19, "05_post & 06_Operator",
              "05 Calls: postval, report\n06 Calls: compat, upg, val\nExports: 4 attached reports\nCalls: logout (Terminal)",
              bg=WHITE, border=GREEN)

    draw_card(ax, 0.51, 0.72, 0.22, 0.18, "Session Roles",
              "login: creates .kubeconfig\nsnapshot: writes JSON\nlogout: oc logout & rm file",
              bg=LIGHT_SLATE, border=NAVY)

    draw_card(ax, 0.51, 0.50, 0.22, 0.19, "Health & Remediate Roles",
              "14 Checks: co, mcp, node, etcd...\nremediate: cgroup_v2, admin_acks,\nunpause_mcp, restart_operator",
              bg=LIGHT_AMBER, border=AMBER)

    draw_card(ax, 0.51, 0.28, 0.22, 0.19, "Engine: tasks/hop.yml",
              "upgrade: set channel, edge, trigger\nmonitor: poll loop, settle gate\nsendmail: hop-complete email",
              bg=LIGHT_BLUE, border=BLUE)

    draw_card(ax, 0.51, 0.06, 0.22, 0.19, "Operator Roles (Phase 06)",
              "operator_compat: scan subs\noperator_upgrade: patch plans\noperator_validate: CSV check",
              bg=LIGHT_GREEN, border=GREEN)

    draw_card(ax, 0.77, 0.55, 0.20, 0.35, "Fact Registry (Consumed)",
              "In-Memory Facts:\n• cluster_kubeconfig\n• baseline_snapshot_file\n• health_summary (14 items)\n• autofix_items\n• hop_target_version\n• settle_gate_passed\n• postval_health_summary\n• operator_compat_plan\n• attached_reports (4 files)",
              bg=LIGHT_BLUE, border=BLUE)

    draw_card(ax, 0.77, 0.15, 0.20, 0.35, "Presentation Consumers",
              "Jinja2 Templates:\n• health-overview.j2\n  (output/ HTML reports)\n• progress-mail.j2\n  (Heartbeats & Hop Mail)\n• error-report.j2\n  (RBAC Alerts on rescue:)\n\nAudit Outputs:\n• logs/<cluster>_*.txt, .csv",
              bg=LIGHT_GREEN, border=GREEN)

    draw_arrow(ax, 0.12, 0.65, 0.12, 0.60)
    draw_arrow(ax, 0.21, 0.46, 0.25, 0.78)
    draw_arrow(ax, 0.21, 0.46, 0.25, 0.58)
    draw_arrow(ax, 0.21, 0.46, 0.25, 0.36)
    draw_arrow(ax, 0.21, 0.46, 0.25, 0.15)

    draw_arrow(ax, 0.47, 0.81, 0.51, 0.81)
    draw_arrow(ax, 0.47, 0.59, 0.51, 0.59)
    draw_arrow(ax, 0.47, 0.37, 0.51, 0.37)
    draw_arrow(ax, 0.47, 0.15, 0.51, 0.15)

    draw_arrow(ax, 0.73, 0.72, 0.77, 0.72)
    draw_arrow(ax, 0.73, 0.37, 0.77, 0.37)
    draw_arrow(ax, 0.87, 0.55, 0.87, 0.50)

    plt.tight_layout()
    plt.savefig(os.path.join(OUTPUT_DIR, "fig18_module_wiring_fact_flow.png"), dpi=300)
    plt.close()

if __name__ == "__main__":
    print("Generating all 18 production architectural diagrams...")
    gen_fig01()
    print("  [1/18] Figure 1: System Context Diagram generated.")
    gen_fig02()
    print("  [2/18] Figure 2: High-Level Architecture Diagram generated.")
    gen_fig03()
    print("  [3/18] Figure 3: Seven-Process-File Flowchart generated.")
    gen_fig04()
    print("  [4/18] Figure 4: End-to-End Upgrade Flowchart generated.")
    gen_fig05()
    print("  [5/18] Figure 5: Multi-Hop Upgrade Flow generated.")
    gen_fig06()
    print("  [6/18] Figure 6: Auto-Remediation Decision Flowchart generated.")
    gen_fig07()
    print("  [7/18] Figure 7: Authentication & Session Sequence Diagram generated.")
    gen_fig08()
    print("  [8/18] Figure 8: Baseline Snapshot Data Flow generated.")
    gen_fig09()
    print("  [9/18] Figure 9: Live Monitoring Loop Flowchart generated.")
    gen_fig10()
    print("  [10/18] Figure 10: Role Interaction & Categorization Diagram generated.")
    gen_fig11()
    print("  [11/18] Figure 11: Deployment Diagram generated.")
    gen_fig12()
    print("  [12/18] Figure 12: Security Trust Boundary Diagram generated.")
    gen_fig13()
    print("  [13/18] Figure 13: Recommended Validation Pipeline Diagram generated.")
    gen_fig14()
    print("  [14/18] Figure 14: Reporting & Notification Flow generated.")
    gen_fig15()
    print("  [15/18] Figure 15: Storage & Concurrency Diagram generated.")
    gen_fig16()
    print("  [16/18] Figure 16: Three-Way Architectural Venn Diagram generated.")
    gen_fig17()
    print("  [17/18] Figure 17: Production Readiness Summary Graphic generated.")
    gen_fig18()
    print("  [18/18] Figure 18: Complete Module Wiring & Fact Flow Diagram generated.")
    print(f"All 18 diagrams generated successfully in: {OUTPUT_DIR}")
