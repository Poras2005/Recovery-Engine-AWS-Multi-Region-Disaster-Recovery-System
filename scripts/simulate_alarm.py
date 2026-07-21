#!/usr/bin/env python3
"""
Recovery-Engine: CloudWatch Alarm Simulation & Alert Testing Utility
====================================================================
Simulates failure states on CloudWatch Alarms to test SNS notifications,
alert routing, and orchestrator alarm detection.

Usage:
    python3 scripts/simulate_alarm.py --list
    python3 scripts/simulate_alarm.py --trigger recovery-engine-replica-lag-rpo-alarm-dev --region ap-southeast-1
    python3 scripts/simulate_alarm.py --reset-all
"""

import argparse
import datetime
import os
import sys
import boto3
from botocore.exceptions import ClientError

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

def load_config(config_path="config/recovery-engine.yaml"):
    if HAS_YAML and os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                return yaml.safe_load(f)
        except Exception:
            pass
    return {
        "global": {"environment": "dev"},
        "regions": {
            "primary": {"region": "ap-south-1"},
            "secondary": {"region": "ap-southeast-1"}
        }
    }

def list_alarms(primary_region, secondary_region, env):
    cw_p = boto3.client("cloudwatch", region_name=primary_region)
    cw_s = boto3.client("cloudwatch", region_name=secondary_region)

    print("==================================================")
    print("      RECOVERY-ENGINE: CLOUDWATCH ALARMS LIST     ")
    print("==================================================")

    alarms = []
    # Primary Region
    try:
        res = cw_p.describe_alarms(AlarmNamePrefix=f"recovery-engine-")
        for a in res.get("MetricAlarms", []):
            alarms.append({"name": a["AlarmName"], "state": a["StateValue"], "region": primary_region})
    except Exception as e:
        print(f"Error describing primary region alarms: {e}")

    # Secondary Region
    try:
        res = cw_s.describe_alarms(AlarmNamePrefix=f"recovery-engine-")
        for a in res.get("MetricAlarms", []):
            alarms.append({"name": a["AlarmName"], "state": a["StateValue"], "region": secondary_region})
    except Exception as e:
        print(f"Error describing secondary region alarms: {e}")

    if alarms:
        for idx, a in enumerate(alarms, 1):
            state_str = f"[{a['state']}]"
            print(f"{idx}. [{a['region']}] {a['name']} -> {state_str}")
    else:
        print("No CloudWatch alarms found matching prefix 'recovery-engine-'.")

    return alarms

def set_alarm_state(alarm_name, state, region, reason="Manual Chaos/DR Drill Alarm Simulation"):
    cw = boto3.client("cloudwatch", region_name=region)
    print(f"[*] Setting alarm '{alarm_name}' in region '{region}' to state: {state} ...", end=" ")
    try:
        cw.set_alarm_state(
            AlarmName=alarm_name,
            StateValue=state,
            StateReason=reason,
            StateReasonData=f'{{"simulation_time": "{datetime.datetime.now(datetime.timezone.utc).isoformat()}"}}'
        )
        print("[SUCCESS]")
        return True
    except ClientError as e:
        print(f"[FAILED] {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description="Recovery-Engine Alarm Simulation & Testing Tool")
    parser.add_argument("--config", default="config/recovery-engine.yaml", help="Path to config file")
    parser.add_argument("--list", action="store_true", help="List all DR CloudWatch alarms")
    parser.add_argument("--trigger", help="Name of alarm to set to ALARM state")
    parser.add_argument("--reset", help="Name of alarm to reset back to OK state")
    parser.add_argument("--reset-all", action="store_true", help="Reset all DR alarms back to OK state")
    parser.add_argument("--region", help="AWS region of the target alarm (e.g. ap-south-1 or ap-southeast-1)")
    args = parser.parse_args()

    cfg = load_config(args.config)
    env = cfg.get("global", {}).get("environment", "dev")
    p_region = cfg.get("regions", {}).get("primary", {}).get("region", "ap-south-1")
    s_region = cfg.get("regions", {}).get("secondary", {}).get("region", "ap-southeast-1")

    if args.list:
        list_alarms(p_region, s_region, env)
        sys.exit(0)

    if args.trigger:
        region = args.region or (s_region if "replica" in args.trigger else p_region)
        set_alarm_state(args.trigger, "ALARM", region, "DR Chaos Drill Test Simulation")
        sys.exit(0)

    if args.reset:
        region = args.region or (s_region if "replica" in args.reset else p_region)
        set_alarm_state(args.reset, "OK", region, "Resetting alarm state after drill")
        sys.exit(0)

    if getattr(args, "reset_all", False):
        print("[*] Resetting all DR alarms back to OK state...")

        alarms = list_alarms(p_region, s_region, env)
        for a in alarms:
            set_alarm_state(a["name"], "OK", a["region"], "Post-drill state reset")
        sys.exit(0)

    parser.print_help()

if __name__ == "__main__":
    main()
