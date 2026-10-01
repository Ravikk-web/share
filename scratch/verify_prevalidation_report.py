import os
import shutil
import jinja2
import yaml

print("=================================================================")
print("RUNNING COMPREHENSIVE PREVALIDATION HTML REPORT VERIFICATION")
print("=================================================================")

# 1. Validate YAML parsing of 02_Pre_upgrade_check.yaml
with open('playbooks/02_Pre_upgrade_check.yaml', 'r', encoding='utf-8') as f:
    play = yaml.safe_load(f)[0]

print("1. Validated 02_Pre_upgrade_check.yaml YAML syntax.")

# Verify pre_tasks removed and login inside tasks block
assert 'pre_tasks' not in play, "pre_tasks should not be present in play root"
tasks_block = play['tasks'][0]['block']
rescue_tasks = play['tasks'][0]['rescue']

login_found = any('login' in str(t.get('include_role', {})) for t in tasks_block)
assert login_found, "login role must be inside tasks block"
print("2. Confirmed login role is inside tasks block (session verified in protected block).")

# Verify report generation in rescue
report_in_rescue = any('report' in str(t.get('include_role', {})) for t in rescue_tasks)
assert report_in_rescue, "report role must be called inside rescue block"
print("3. Confirmed report role is invoked in rescue block on failure.")

# Verify no nested blocks inside rescue (Ansible syntax rule)
for t in rescue_tasks:
    assert 'block' not in t, f"Nested block found in rescue task: {t.get('name')}"
print("4. Confirmed zero nested blocks in rescue section (valid Ansible syntax).")

# 2. Setup Jinja2 environment and load template
template_path = 'playbooks/templates/phase02-prevalidation.j2'
assert os.path.exists(template_path), f"Template file not found at {template_path}"

with open(template_path, 'r', encoding='utf-8') as f:
    template_source = f.read()

env = jinja2.Environment()
template = env.from_string(template_source)
print(f"5. Successfully compiled Jinja2 template: {template_path} ({len(template_source)} bytes).")

output_dir = 'output'
os.makedirs(output_dir, exist_ok=True)

# Define Canonical 15 Checks
canonical_15 = [
    {'num': 1, 'name': 'ClusterOperators Health', 'gate': 'HARD'},
    {'num': 2, 'name': 'Node Health and Conditions', 'gate': 'HARD'},
    {'num': 3, 'name': 'MachineConfigPools Synchronization', 'gate': 'HARD'},
    {'num': 4, 'name': 'API Context Verification', 'gate': 'HARD'},
    {'num': 5, 'name': 'API Server Readiness Probe', 'gate': 'HARD'},
    {'num': 6, 'name': 'etcd Quorum and Member Health', 'gate': 'HARD'},
    {'num': 7, 'name': 'Administrator Acknowledgement (Admin-Acks)', 'gate': 'HARD'},
    {'num': 8, 'name': 'Node Request Capacity Headroom', 'gate': 'HARD'},
    {'num': 9, 'name': 'Pending Node Certificate Signing Requests (CSRs)', 'gate': 'WARN'},
    {'num': 10, 'name': 'PersistentVolumes Health', 'gate': 'WARN'},
    {'num': 11, 'name': 'PersistentVolumeClaims Health', 'gate': 'WARN'},
    {'num': 12, 'name': 'PodDisruptionBudgets Headroom', 'gate': 'WARN'},
    {'num': 13, 'name': 'Critical Namespace Pod Health', 'gate': 'WARN'},
    {'num': 14, 'name': 'CGroup Mode Compatibility', 'gate': 'HARD'},
    {'num': 15, 'name': 'OLM Operator Upgrade Compatibility', 'gate': 'HARD'}
]

# Scenario 1: Clean Pass (All 15 checks PASS)
s1_checks = []
for c in canonical_15:
    s1_checks.append({
        'num': c['num'],
        'name': c['name'],
        'gate': c['gate'],
        'status': 'PASS',
        'observed': f"Validation check #{c['num']:02d} passed healthy"
    })

s1_context = {
    'cluster_name': 'aro-prod-eastus-01',
    'cluster_tier': 'Production',
    'baseline_current_version': '4.18.09',
    'preval_resolved_target_version': '4.19.15',
    'upgrade_path': ['4.19.15', '4.20.08'],
    'run_timestamp': '20260916_clean_pass',
    'overall_verdict': 'PASS',
    'total_checks': 15,
    'passed_count': 15,
    'warning_count': 0,
    'autofixed_count': 0,
    'failed_count': 0,
    'phase02_duration_seconds': 42,
    'checks': s1_checks,
    'co_all_operators': [{'name': f'operator-{i}', 'version': '4.18.09', 'available': 'True', 'degraded': 'False'} for i in range(32)],
    'nodes_parsed_data': [{'name': f'node-{i}', 'role': 'worker', 'ready': True} for i in range(6)],
    'mcp_parsed_data': [{'name': 'master', 'machine_count': 3, 'ready_machine_count': 3}, {'name': 'worker', 'machine_count': 3, 'ready_machine_count': 3}],
    'active_cluster_server': 'https://api.aro-prod-eastus-01.aroapp.io:6443',
    'desired_cluster_api_regex': '^https://api\\.aro-prod-eastus-01\\.',
    'etcd_total_pods': 3,
    'cluster_cpu_percent': 64.2,
    'cluster_mem_percent': 58.1,
    'preval_detected_cgroup_mode': 'v2',
    'operator_compat_plan': [
        {'subscription': 'advanced-cluster-management', 'namespace': 'open-cluster-management', 'installed_csv': 'v2.11.0', 'current_channel': 'release-2.11', 'target_channel': 'release-2.12', 'status': 'PASS'}
    ]
}

s1_html = template.render(**s1_context)
s1_path = os.path.join(output_dir, 'test_preval_clean_pass.html')
with open(s1_path, 'w', encoding='utf-8') as f:
    f.write(s1_html)

print(f"6. Scenario 1 (Clean Pass): Rendered {len(s1_html)} bytes -> {s1_path}")
assert 'PASS ✔' in s1_html
assert '15 Scanned' in s1_html
assert 'Prevalidation 15-Check Contract Checklist' in s1_html
for c in canonical_15:
    assert c['name'] in s1_html, f"Check {c['name']} missing from checklist"

# Scenario 2: Auto-Remediation Active (cgroup v2, admin-acks, unpause MCP)
s2_checks = []
for c in canonical_15:
    if c['num'] in [3, 7, 14]:
        status = 'AUTO-FIXED'
        obs = 'Automatically remediated and verified compliant'
    else:
        status = 'PASS'
        obs = 'Healthy'
    s2_checks.append({
        'num': c['num'],
        'name': c['name'],
        'gate': c['gate'],
        'status': status,
        'observed': obs
    })

s2_context = {
    'cluster_name': 'aro-stage-remediate-02',
    'cluster_tier': 'Staging',
    'baseline_current_version': '4.18.09',
    'preval_resolved_target_version': '4.19.15',
    'upgrade_path': ['4.19.15'],
    'run_timestamp': '20260916_autofix',
    'overall_verdict': 'AUTO-FIXED',
    'total_checks': 15,
    'passed_count': 12,
    'warning_count': 0,
    'autofixed_count': 3,
    'failed_count': 0,
    'phase02_duration_seconds': 58,
    'checks': s2_checks,
    'autofix_items': [
        {'name': 'CGroup v2 Mode Migration', 'action': 'Patched nodes.config/cluster to v2', 'reference': 'https://docs.openshift.com'},
        {'name': 'Admin-Acks Acknowledgement', 'action': 'Applied required ack-4.18-api-removals key', 'reference': 'https://docs.openshift.com'},
        {'name': 'MachineConfigPool Unpausing', 'action': 'Unpaused worker pool', 'reference': 'https://docs.openshift.com'}
    ]
}

s2_html = template.render(**s2_context)
s2_path = os.path.join(output_dir, 'test_preval_autofix.html')
with open(s2_path, 'w', encoding='utf-8') as f:
    f.write(s2_html)

print(f"7. Scenario 2 (Auto-Remediation): Rendered {len(s2_html)} bytes -> {s2_path}")
assert 'AUTO-FIXED ⚙' in s2_html
assert 'Automated Remediation Applied' in s2_html
assert 'CGroup v2 Mode Migration' in s2_html

# Scenario 3: Residual HARD Gate Failure (Residual failures halt execution)
s3_checks = []
for c in canonical_15:
    if c['num'] == 14:
        status = 'FAIL'
        obs = 'Cluster cgroupMode is v1. Upgrades targeting >= 4.19 require cgroupMode v2 (Auto-fix failed / disabled)'
    elif c['num'] == 15:
        status = 'FAIL'
        obs = 'Incompatible operator detected: compliance-operator has no compatible channel for 4.19'
    else:
        status = 'PASS'
        obs = 'Healthy'
    s3_checks.append({
        'num': c['num'],
        'name': c['name'],
        'gate': c['gate'],
        'status': status,
        'observed': obs
    })

s3_context = {
    'cluster_name': 'aro-test-hard-fail',
    'cluster_tier': 'Dev',
    'baseline_current_version': '4.18.09',
    'preval_resolved_target_version': '4.19.15',
    'upgrade_path': ['4.19.15'],
    'run_timestamp': '20260916_residual_fail',
    'overall_verdict': 'FAIL',
    'overall_status': 'FAIL',
    'total_checks': 15,
    'passed_count': 13,
    'warning_count': 0,
    'autofixed_count': 0,
    'failed_count': 2,
    'phase02_duration_seconds': 35,
    'checks': s3_checks
}

s3_html = template.render(**s3_context)
s3_path = os.path.join(output_dir, 'test_preval_hard_fail.html')
with open(s3_path, 'w', encoding='utf-8') as f:
    f.write(s3_html)

print(f"8. Scenario 3 (Residual HARD Gate Failure): Rendered {len(s3_html)} bytes -> {s3_path}")
assert 'FAIL ✖' in s3_html
assert 'Prevalidation Contract Failed' in s3_html
assert 'Zero cluster mutations were committed' in s3_html

# Scenario 4: Early Failure Simulation (Failure at Check 04: API Context)
# Checks 1-3 PASS, Check 4 FAIL, Checks 5-15 SKIPPED
s4_executed = [
    {'num': 1, 'name': 'ClusterOperators Health', 'gate': 'HARD', 'status': 'PASS', 'observed': 'All 32 operators healthy'},
    {'num': 2, 'name': 'Node Health and Conditions', 'gate': 'HARD', 'status': 'PASS', 'observed': 'All 6 nodes Ready=True'},
    {'num': 3, 'name': 'MachineConfigPools Synchronization', 'gate': 'HARD', 'status': 'PASS', 'observed': 'All 2 MCPs synchronized'},
    {'num': 4, 'name': 'API Context Verification', 'gate': 'HARD', 'status': 'FAIL', 'observed': 'Halted with error: Connected server endpoint did not match target regex'}
]

s4_failure_checks = []
for c in canonical_15:
    matched = [h for h in s4_executed if h['num'] == c['num']]
    if matched:
        s4_failure_checks.append(matched[0])
    else:
        s4_failure_checks.append({
            'num': c['num'],
            'name': c['name'],
            'gate': c['gate'],
            'status': 'SKIPPED',
            'observed': 'Check was not evaluated due to prior failure in prevalidation sequence'
        })

s4_context = {
    'cluster_name': 'aro-test-early-abort',
    'cluster_tier': 'Dev',
    'baseline_current_version': '4.18.09',
    'preval_resolved_target_version': '4.19.15',
    'upgrade_path': ['4.19.15'],
    'run_timestamp': '20260916_early_abort',
    'overall_verdict': 'FAIL',
    'overall_status': 'FAIL',
    'total_checks': 15,
    'passed_count': 3,
    'warning_count': 0,
    'autofixed_count': 0,
    'failed_count': 1,
    'phase02_duration_seconds': 14,
    'checks': s4_failure_checks
}

s4_html = template.render(**s4_context)
s4_path = os.path.join(output_dir, 'test_preval_early_abort.html')
with open(s4_path, 'w', encoding='utf-8') as f:
    f.write(s4_html)

print(f"9. Scenario 4 (Early Failure with SKIPPED rows): Rendered {len(s4_html)} bytes -> {s4_path}")
assert 'FAIL ✖' in s4_html
assert 'SKIPPED' in s4_html
# Confirm ALL 15 checks are present in checklist
for c in canonical_15:
    assert c['name'] in s4_html, f"Check {c['name']} missing from early abort checklist"

# Clean up test artifacts
for p in [s1_path, s2_path, s3_path, s4_path]:
    if os.path.exists(p):
        os.remove(p)

print("10. Successfully cleaned up test HTML artifacts.")
print("=================================================================")
print("ALL PREVALIDATION HTML REPORT VERIFICATION TESTS PASSED CLEANLY!")
print("=================================================================")
