#!/usr/bin/env python3
"""
Recovery-Engine: Terraform Hardcoding & Security Scanner (Module 7 Task 2)
========================================================================
Scans all Terraform (.tf) files across modules/ and environments/ to verify
zero-hardcoding compliance (ensuring no hardcoded AWS Account IDs, ARNs, VPC IDs,
or Subnet IDs exist).

Usage:
    python3 scripts/audit_hardcoding.py
"""

import argparse
import os
import re
import sys

def scan_terraform_files(search_dirs=["modules", "environments"]):
    print("==================================================")
    print("   RECOVERY-ENGINE: TERRAFORM HARDCODING SCANNER  ")
    print("==================================================")

    patterns = {
        "AWS Account ID (12-digit number)": r"\b\d{12}\b",
        "Hardcoded IAM/RDS ARN": r"arn:aws:[a-z0-9\-]+:[a-z0-9\-]*:\d{12}:",
        "Hardcoded VPC ID": r"\bvpc-[a-f0-9]{8,17}\b",
        "Hardcoded Subnet ID": r"\bsubnet-[a-f0-9]{8,17}\b",
        "Hardcoded Security Group ID": r"\bsg-[a-f0-9]{8,17}\b"
    }

    issues_found = 0
    files_scanned = 0

    for s_dir in search_dirs:
        if not os.path.exists(s_dir):
            continue
        for root, _, files in os.walk(s_dir):
            for file in files:
                if file.endswith(".tf") and not file.endswith(".example"):
                    files_scanned += 1
                    filepath = os.path.join(root, file)
                    with open(filepath, "r", encoding="utf-8") as f:
                        lines = f.readlines()

                    for idx, line in enumerate(lines, 1):
                        # Skip comments
                        stripped = line.strip()
                        if stripped.startswith("#") or stripped.startswith("//"):
                            continue

                        for label, regex in patterns.items():
                            matches = re.findall(regex, line)
                            if matches:
                                print(f"    [VIOLATION] {filepath}:L{idx}")
                                print(f"                Type: {label}")
                                print(f"                Snippet: {stripped}")
                                issues_found += 1

    print("--------------------------------------------------")
    print(f"Total Terraform Files Scanned: {files_scanned}")
    print("==================================================")

    if issues_found == 0:
        print("ZERO-HARDCODING AUDIT RESULT: [PASSED - 100% CONFIG-DRIVEN]")
        return True
    else:
        print(f"ZERO-HARDCODING AUDIT RESULT: [FAILED - {issues_found} VIOLATION(S) FOUND]")
        return False

def main():
    parser = argparse.ArgumentParser(description="Recovery-Engine Terraform Hardcoding Scanner")
    parser.add_argument("--dirs", nargs="+", default=["modules", "environments"], help="Directories to scan")
    args = parser.parse_args()

    success = scan_terraform_files(args.dirs)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
