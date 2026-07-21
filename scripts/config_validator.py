#!/usr/bin/env python3
"""
Recovery-Engine: Configuration Loader & Schema Validator (Module 7 Task 1)
==========================================================================
Validates recovery-engine.yaml against JSON Schema and performs a Zero-Hardcoding
Audit to ensure parameters are properly configured before infrastructure deployment.

Usage:
    python3 scripts/config_validator.py
    python3 scripts/config_validator.py --config config/recovery-engine.yaml
"""

import argparse
import json
import os
import re
import sys

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

try:
    import jsonschema
    HAS_JSONSCHEMA = True
except ImportError:
    HAS_JSONSCHEMA = False

def load_yaml(config_path):
    if not os.path.exists(config_path):
        print(f"[ERROR] Config file '{config_path}' not found.")
        sys.exit(1)

    if not HAS_YAML:
        print("[WARNING] PyYAML not installed. Performing basic validation.")
        return None

    try:
        with open(config_path, "r") as f:
            return yaml.safe_load(f)
    except Exception as e:
        print(f"[ERROR] Invalid YAML syntax in '{config_path}': {e}")
        sys.exit(1)

def load_schema(schema_path="config/schema.json"):
    if not os.path.exists(schema_path):
        print(f"[WARNING] Schema file '{schema_path}' not found.")
        return None
    try:
        with open(schema_path, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"[WARNING] Could not parse schema '{schema_path}': {e}")
        return None

def validate_schema(data, schema):
    print("[*] Validating Configuration against JSON Schema...")
    if HAS_JSONSCHEMA and schema and data:
        try:
            jsonschema.validate(instance=data, schema=schema)
            print("    [PASSED] JSON Schema Validation Successful!")
            return True
        except jsonschema.exceptions.ValidationError as e:
            print(f"    [FAILED] Schema Validation Error: {e.message}")
            return False

    # Manual structural fallback
    required_sections = ["version", "global", "regions", "database", "route53"]
    missing = [s for s in required_sections if s not in (data or {})]
    if missing:
        print(f"    [FAILED] Missing required YAML sections: {missing}")
        return False

    print("    [PASSED] Fallback Structural Validation Successful!")
    return True

def audit_zero_hardcoding(data):
    print("[*] Performing Zero-Hardcoding & Safety Audit...")
    errors = 0

    if not data:
        return True

    # 1. AWS Region format check
    p_region = data.get("regions", {}).get("primary", {}).get("region", "")
    s_region = data.get("regions", {}).get("secondary", {}).get("region", "")
    region_regex = r"^[a-z]{2}-[a-z]+-\d+$"

    if not re.match(region_regex, p_region):
        print(f"    [ERROR] Invalid Primary AWS Region format: '{p_region}'")
        errors += 1
    else:
        print(f"    [OK] Primary Region: '{p_region}'")

    if not re.match(region_regex, s_region):
        print(f"    [ERROR] Invalid Secondary AWS Region format: '{s_region}'")
        errors += 1
    else:
        print(f"    [OK] Secondary Region: '{s_region}'")

    if p_region == s_region:
        print(f"    [ERROR] Primary and Secondary regions must be different for multi-region DR! (Both set to '{p_region}')")
        errors += 1

    # 2. CIDR collision check
    p_cidr = data.get("regions", {}).get("primary", {}).get("vpc_cidr", "")
    s_cidr = data.get("regions", {}).get("secondary", {}).get("vpc_cidr", "")
    if p_cidr and s_cidr and p_cidr == s_cidr:
        print(f"    [WARNING] Primary and Secondary VPC CIDRs match ({p_cidr}). Ensure VPC Peering routes do not collide.")

    # 3. Domain format check
    domain = data.get("route53", {}).get("domain_name", "")
    if not domain or "." not in domain:
        print(f"    [ERROR] Invalid Route53 Domain Name: '{domain}'")
        errors += 1
    else:
        print(f"    [OK] Hosted Zone Domain: '{domain}'")

    if errors == 0:
        print("    [PASSED] Zero-Hardcoding & Safety Audit PASSED with 0 errors!")
        return True
    else:
        print(f"    [FAILED] Audit found {errors} configuration error(s).")
        return False

def main():
    parser = argparse.ArgumentParser(description="Recovery-Engine Config Validator & Schema Auditor")
    parser.add_argument("--config", default="config/recovery-engine.yaml", help="Path to config file")
    parser.add_argument("--schema", default="config/schema.json", help="Path to schema file")
    args = parser.parse_args()

    print("==================================================")
    print("   RECOVERY-ENGINE: CONFIG VALIDATOR & AUDITOR    ")
    print("==================================================")
    print(f"Target Config: {args.config}")
    print("--------------------------------------------------")

    data = load_yaml(args.config)
    schema = load_schema(args.schema)

    schema_ok = validate_schema(data, schema)
    audit_ok = audit_zero_hardcoding(data)

    print("==================================================")
    if schema_ok and audit_ok:
        print("OVERALL CONFIG AUDIT STATUS: [PASSED - CONFIGURATION VALID]")
        sys.exit(0)
    else:
        print("OVERALL CONFIG AUDIT STATUS: [FAILED - FIX CONFIG ERRORS]")
        sys.exit(1)

if __name__ == "__main__":
    main()
