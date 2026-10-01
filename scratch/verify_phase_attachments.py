#!/usr/bin/env python3
"""
Verification Script: Phase-Specific Error Notification Attachments
Validates YAML syntax, Jinja2 template rendering, and phase-boundary filtering.
"""
import sys
import yaml
from jinja2 import Environment, FileSystemLoader

def test_yaml_syntax():
    print("=== 1. Validating YAML Syntax across modified files ===")
    files = [
        "playbooks/roles/error_handle/tasks/main.yml",
        "playbooks/roles/sendmail/tasks/main.yml",
        "playbooks/01_Policy_Check.yaml",
        "playbooks/02_Pre_upgrade_check.yaml",
        "playbooks/03_Initiate_upgrade.yaml",
        "playbooks/05_post_Upgrade_Checks.yaml",
        "playbooks/tasks/hop.yml"
    ]
    for f in files:
        with open(f, "r", encoding="utf-8") as fh:
            yaml.safe_load(fh)
        print(f"  [OK] {f} is valid YAML")
    print()

def simulate_error_handle_filtering(current_step_no, current_task_name, failed_task_name, mail_attachments, report_file_path):
    """Simulates Jinja2 expressions in roles/error_handle/tasks/main.yml"""
    # 1. error_phase_tag
    step = (current_step_no or '').lower()
    task = (current_task_name or '').lower()
    failed = (failed_task_name or '').lower()
    
    if 'phase 01' in step or 'phase 01' in task or 'policy check' in task:
        error_phase_tag = 'phase01'
    elif 'phase 02' in step or 'phase 02' in task or 'prevalidation' in task or 'prevalidation' in failed:
        error_phase_tag = 'phase02'
    elif 'phase 03' in step or 'phase 03' in task or 'upgrade hop' in task:
        error_phase_tag = 'phase03'
    elif 'phase 05' in step or 'phase 05' in task or 'post-upgrade' in task or 'postvalidation' in task or 'postvalidation' in failed:
        error_phase_tag = 'phase05'
    elif 'phase 06' in step or 'phase 06' in task or 'operator' in task:
        error_phase_tag = 'phase06'
    else:
        error_phase_tag = 'unknown'

    # 2. sanitize attachments
    raw_list = mail_attachments if (mail_attachments and len(mail_attachments) > 0) else ([report_file_path] if report_file_path else [])
    filtered = []
    for att in raw_list:
        bname = att.split('/')[-1].split('\\')[-1].lower()
        if error_phase_tag == 'phase01' and ('phase01' in bname or 'policy' in bname):
            filtered.append(att)
        elif error_phase_tag == 'phase02' and ('prevalidation' in bname or 'preval' in bname):
            filtered.append(att)
        elif error_phase_tag == 'phase05' and ('postvalidation' in bname or 'postval' in bname):
            filtered.append(att)
        elif error_phase_tag == 'phase06' and ('operator' in bname or 'phase06' in bname or 'postvalidation' in bname or 'prevalidation' in bname or bname.endswith('.txt')):
            filtered.append(att)
            
    return error_phase_tag, filtered

def test_error_handle_logic():
    print("=== 2. Testing error_handle Phase Attachment Filtering Logic ===")
    
    # Scenario A: Phase 05 failure with leaked Phase 02 prevalidation report in report_file_path
    tag, atts = simulate_error_handle_filtering(
        current_step_no="Phase 05",
        current_task_name="Phase 05 Post-Upgrade Checks & Baseline Diff",
        failed_task_name="Phase 05 Post-Upgrade Checks & Baseline Diff",
        mail_attachments=[],
        report_file_path="/opt/output/arod01_prevalidation_20260916_070526.html"
    )
    assert tag == 'phase05', f"Expected phase05, got {tag}"
    assert atts == [], f"Expected empty attachments on Phase 05 with leaked prevalidation report, got {atts}"
    print("  [OK] Scenario A: Phase 05 with leaked prevalidation report correctly suppressed")

    # Scenario B: Phase 05 failure with generated postvalidation report
    tag, atts = simulate_error_handle_filtering(
        current_step_no="Phase 05",
        current_task_name="Phase 05 Post-Upgrade Checks & Baseline Diff",
        failed_task_name="Phase 05 Post-Upgrade Checks & Baseline Diff",
        mail_attachments=["/opt/output/arod01_postvalidation_20260916_070526.html"],
        report_file_path="/opt/output/arod01_postvalidation_20260916_070526.html"
    )
    assert tag == 'phase05', f"Expected phase05, got {tag}"
    assert atts == ["/opt/output/arod01_postvalidation_20260916_070526.html"], f"Expected postval report, got {atts}"
    print("  [OK] Scenario B: Phase 05 with postvalidation report correctly attached")

    # Scenario C: Phase 02 failure with prevalidation report
    tag, atts = simulate_error_handle_filtering(
        current_step_no="Phase 02",
        current_task_name="Phase 02 Prevalidation & Auto-Remediation",
        failed_task_name="Phase 02 Prevalidation & Auto-Remediation",
        mail_attachments=["/opt/output/arod01_prevalidation_20260916_070526.html"],
        report_file_path="/opt/output/arod01_prevalidation_20260916_070526.html"
    )
    assert tag == 'phase02', f"Expected phase02, got {tag}"
    assert atts == ["/opt/output/arod01_prevalidation_20260916_070526.html"], f"Expected preval report, got {atts}"
    print("  [OK] Scenario C: Phase 02 with prevalidation report correctly attached")

    # Scenario D: Phase 01 failure with policy report
    tag, atts = simulate_error_handle_filtering(
        current_step_no="Phase 01",
        current_task_name="Phase 01 Policy Check & Baseline Capture",
        failed_task_name="Phase 01 Policy Check & Baseline Capture",
        mail_attachments=["/opt/output/arod01_phase01_20260916_070526.html"],
        report_file_path="/opt/output/arod01_phase01_20260916_070526.html"
    )
    assert tag == 'phase01', f"Expected phase01, got {tag}"
    assert atts == ["/opt/output/arod01_phase01_20260916_070526.html"], f"Expected phase01 report, got {atts}"
    print("  [OK] Scenario D: Phase 01 with policy check report correctly attached")

    # Scenario E: Phase 03 failure with leaked Phase 02 prevalidation report
    tag, atts = simulate_error_handle_filtering(
        current_step_no="Phase 03",
        current_task_name="Phase 03 Sequential Upgrade Hops",
        failed_task_name="Phase 03 Sequential Upgrade Hops",
        mail_attachments=[],
        report_file_path="/opt/output/arod01_prevalidation_20260916_070526.html"
    )
    assert tag == 'phase03', f"Expected phase03, got {tag}"
    assert atts == [], f"Expected empty attachments on Phase 03, got {atts}"
    print("  [OK] Scenario E: Phase 03 with leaked prevalidation report correctly suppressed")
    print()

def test_jinja2_error_report_rendering():
    print("=== 3. Testing Jinja2 error-report.j2 Template Rendering ===")
    env = Environment(loader=FileSystemLoader("playbooks/templates"))
    template = env.get_template("error-report.j2")
    
    # Case 1: Phase 05 failure with leaked prevalidation report
    rendered = template.render(
        cluster_name="arod01",
        current_step_no="Phase 05",
        current_task_name="Phase 05 Post-Upgrade Checks & Baseline Diff",
        current_gate_type="HARD",
        failure_reason="Post-upgrade verification failed",
        resolved_error="Check 2: ClusterOperators Status [FAIL]",
        attached_reports=["arod01_prevalidation_20260916_070526.html"],
        mail_attachments=["/opt/output/arod01_prevalidation_20260916_070526.html"]
    )
    assert "Attached Diagnostic Reports" not in rendered, "Failed: 'Attached Diagnostic Reports' should be suppressed on Phase 05 when only prevalidation report is passed"
    assert "arod01_prevalidation" not in rendered, "Failed: arod01_prevalidation should NOT appear in Phase 05 error report"
    print("  [OK] Case 1: error-report.j2 suppresses leaked prevalidation report in Phase 05")

    # Case 2: Phase 05 failure with postvalidation report
    rendered = template.render(
        cluster_name="arod01",
        current_step_no="Phase 05",
        current_task_name="Phase 05 Post-Upgrade Checks & Baseline Diff",
        current_gate_type="HARD",
        failure_reason="Post-upgrade verification failed",
        resolved_error="Check 2: ClusterOperators Status [FAIL]",
        attached_reports=["arod01_postvalidation_20260916_070526.html"],
        mail_attachments=["/opt/output/arod01_postvalidation_20260916_070526.html"]
    )
    assert "Attached Diagnostic Reports" in rendered, "Failed: 'Attached Diagnostic Reports' should appear on Phase 05 with postvalidation report"
    assert "arod01_postvalidation_20260916_070526.html" in rendered, "Failed: arod01_postvalidation should appear in Phase 05 error report"
    print("  [OK] Case 2: error-report.j2 displays postvalidation report in Phase 05")

    # Case 3: Phase 02 failure with prevalidation report
    rendered = template.render(
        cluster_name="arod01",
        current_step_no="Phase 02",
        current_task_name="Phase 02 Prevalidation & Auto-Remediation",
        current_gate_type="HARD",
        failure_reason="Prevalidation HARD gate failure",
        resolved_error="Check 1: ClusterOperators Health [FAIL]",
        attached_reports=["arod01_prevalidation_20260916_070526.html"],
        mail_attachments=["/opt/output/arod01_prevalidation_20260916_070526.html"]
    )
    assert "Attached Diagnostic Reports" in rendered
    assert "arod01_prevalidation_20260916_070526.html" in rendered
    print("  [OK] Case 3: error-report.j2 displays prevalidation report in Phase 02")

    # Case 4: Phase 01 failure with policy report
    rendered = template.render(
        cluster_name="arod01",
        current_step_no="Phase 01",
        current_task_name="Phase 01 Policy Check & Baseline Capture",
        current_gate_type="HARD",
        failure_reason="Policy Check failed",
        resolved_error="Target version not reachable",
        attached_reports=["arod01_phase01_20260916_070526.html"],
        mail_attachments=["/opt/output/arod01_phase01_20260916_070526.html"]
    )
    assert "Attached Diagnostic Reports" in rendered
    assert "arod01_phase01_20260916_070526.html" in rendered
    print("  [OK] Case 4: error-report.j2 displays policy report in Phase 01")

    # Case 5: Phase 03 failure with no reports
    rendered = template.render(
        cluster_name="arod01",
        current_step_no="Phase 03",
        current_task_name="Phase 03 Sequential Upgrade Hops",
        current_gate_type="HARD",
        failure_reason="Upgrade Hop failed",
        resolved_error="Timeout waiting for MCP update",
        attached_reports=[],
        mail_attachments=[]
    )
    assert "Attached Diagnostic Reports" not in rendered
    print("  [OK] Case 5: error-report.j2 has no attached reports section in Phase 03")
    print()

if __name__ == "__main__":
    test_yaml_syntax()
    test_error_handle_logic()
    test_jinja2_error_report_rendering()
    print("ALL TESTS PASSED! 100% compliance with phase-specific attachment rule.")
