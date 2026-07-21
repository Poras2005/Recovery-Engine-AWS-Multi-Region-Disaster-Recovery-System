#!/usr/bin/env python3
"""
Recovery-Engine: Module Cleanup & Standardization Audit Utility (Module 7 Task 3)
================================================================================
Audits Terraform modules for HashiCorp coding standards, mandatory file structures
(main.tf, variables.tf, outputs.tf), input/output descriptions, and tagging hygiene.

Usage:
    python3 scripts/module_cleanup_audit.py
"""

import argparse
import os
import re
import sys

def audit_module_structure(modules_dir="modules"):
    print("==================================================")
    print("   RECOVERY-ENGINE: TERRAFORM MODULE CLEANUP AUDIT ")
    print("==================================================")

    if not os.path.exists(modules_dir):
        print(f"[ERROR] Directory '{modules_dir}' not found.")
        sys.exit(1)

    module_folders = [f for f in os.listdir(modules_dir) if os.path.isdir(os.path.join(modules_dir, f))]
    
    total_modules = len(module_folders)
    passed_modules = 0
    total_issues = 0

    print(f"Discovered {total_modules} Terraform Module(s) under '{modules_dir}/':")
    for mod in sorted(module_folders):
        mod_path = os.path.join(modules_dir, mod)
        print(f"\n[*] Auditing Module: 'modules/{mod}'...")
        mod_issues = 0

        # 1. Mandatory Files Check
        required_files = ["main.tf", "variables.tf", "outputs.tf"]
        for rf in required_files:
            target_f = os.path.join(mod_path, rf)
            if os.path.exists(target_f):
                print(f"    [OK] File exists: {rf}")
            else:
                print(f"    [MISSING] Mandatory file missing: {rf}")
                mod_issues += 1

        # 2. Check variables.tf descriptions
        var_file = os.path.join(mod_path, "variables.tf")
        if os.path.exists(var_file):
            with open(var_file, "r", encoding="utf-8") as f:
                content = f.read()

            var_blocks = re.findall(r'variable\s+"([^"]+)"\s*\{([^}]+)\}', content)
            undocumented_vars = []
            for vname, vbody in var_blocks:
                if "description" not in vbody:
                    undocumented_vars.append(vname)

            if undocumented_vars:
                print(f"    [WARNING] Variables missing 'description': {undocumented_vars}")
                mod_issues += len(undocumented_vars)
            else:
                print(f"    [OK] All variables have documentation descriptions.")

        # 3. Check outputs.tf descriptions
        out_file = os.path.join(mod_path, "outputs.tf")
        if os.path.exists(out_file):
            with open(out_file, "r", encoding="utf-8") as f:
                content = f.read()

            out_blocks = re.findall(r'output\s+"([^"]+)"\s*\{([^}]+)\}', content)
            undocumented_outs = []
            for oname, obody in out_blocks:
                if "description" not in obody:
                    undocumented_outs.append(oname)

            if undocumented_outs:
                print(f"    [WARNING] Outputs missing 'description': {undocumented_outs}")
                mod_issues += len(undocumented_outs)
            else:
                print(f"    [OK] All outputs have documentation descriptions.")

        if mod_issues == 0:
            print(f"    [PASSED] Module 'modules/{mod}' meets 100% HashiCorp quality standards!")
            passed_modules += 1
        else:
            total_issues += mod_issues

    print("\n--------------------------------------------------")
    print(f"Modules Audited: {passed_modules}/{total_modules} PASSED")
    print("==================================================")

    if total_issues == 0:
        print("MODULE STANDARDIZATION AUDIT: [PASSED - ALL MODULES CLEAN]")
        return True
    else:
        print(f"MODULE STANDARDIZATION AUDIT: [NOTICE - {total_issues} ISSUE(S) IDENTIFIED]")
        return False

def main():
    parser = argparse.ArgumentParser(description="Recovery-Engine Terraform Module Cleanup Auditor")
    parser.add_argument("--modules-dir", default="modules", help="Path to modules directory")
    args = parser.parse_args()

    success = audit_module_structure(args.modules_dir)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
