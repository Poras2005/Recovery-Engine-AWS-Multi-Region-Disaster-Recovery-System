#!/usr/bin/env python3
"""
Recovery-Engine: Real-time Multi-Region CloudWatch Telemetry & Metrics Monitor
=============================================================================
Fetches live CloudWatch metrics (ReplicaLag, CPUUtilization, DatabaseConnections)
and CloudWatch Alarms status across Primary (Mumbai) and Secondary (Singapore) regions.

Usage:
    python3 scripts/monitor_dr.py
    python3 scripts/monitor_dr.py --watch --interval 10
"""

import argparse
import datetime
import os
import sys
import time
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
        "global": {"environment": "dev", "target_rpo_minutes": 5},
        "regions": {
            "primary": {"region": "ap-south-1"},
            "secondary": {"region": "ap-southeast-1"}
        },
        "database": {
            "primary_id": "recovery-engine-primary-db-dev",
            "replica_id": "recovery-engine-replica-db-dev"
        }
    }

def get_metric_stat(cw_client, namespace, metric_name, dimensions, stat="Average", period=300):
    now = datetime.datetime.now(datetime.timezone.utc)
    start = now - datetime.timedelta(seconds=period * 3)
    try:
        res = cw_client.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=dimensions,
            StartTime=start,
            EndTime=now,
            Period=period,
            Statistics=[stat]
        )
        datapoints = res.get("Datapoints", [])
        if datapoints:
            latest = sorted(datapoints, key=lambda x: x["Timestamp"])[-1]
            return latest.get(stat, 0.0)
    except Exception:
        pass
    return None

def fetch_telemetry(config):
    env = config.get("global", {}).get("environment", "dev")
    primary_region = config.get("regions", {}).get("primary", {}).get("region", "ap-south-1")
    secondary_region = config.get("regions", {}).get("secondary", {}).get("region", "ap-southeast-1")
    primary_id = config.get("database", {}).get("primary_id", f"recovery-engine-primary-db-{env}")
    replica_id = config.get("database", {}).get("replica_id", f"recovery-engine-replica-db-{env}")
    target_rpo = config.get("global", {}).get("target_rpo_minutes", 5)

    cw_primary = boto3.client("cloudwatch", region_name=primary_region)
    cw_secondary = boto3.client("cloudwatch", region_name=secondary_region)

    # 1. Fetch Metrics
    p_cpu = get_metric_stat(cw_primary, "AWS/RDS", "CPUUtilization", [{"Name": "DBInstanceIdentifier", "Value": primary_id}], "Average", 60)
    s_cpu = get_metric_stat(cw_secondary, "AWS/RDS", "CPUUtilization", [{"Name": "DBInstanceIdentifier", "Value": replica_id}], "Average", 60)
    replica_lag = get_metric_stat(cw_secondary, "AWS/RDS", "ReplicaLag", [{"Name": "DBInstanceIdentifier", "Value": replica_id}], "Maximum", 60)

    # 2. Fetch Alarms
    alarms_info = []
    try:
        resp = cw_primary.describe_alarms(AlarmNamePrefix=f"recovery-engine-")
        for a in resp.get("MetricAlarms", []):
            alarms_info.append({
                "name": a["AlarmName"],
                "state": a["StateValue"],
                "region": primary_region
            })
    except Exception:
        pass

    try:
        resp = cw_secondary.describe_alarms(AlarmNamePrefix=f"recovery-engine-")
        for a in resp.get("MetricAlarms", []):
            alarms_info.append({
                "name": a["AlarmName"],
                "state": a["StateValue"],
                "region": secondary_region
            })
    except Exception:
        pass

    return {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "primary_id": primary_id,
        "primary_cpu": p_cpu,
        "replica_id": replica_id,
        "replica_cpu": s_cpu,
        "replica_lag": replica_lag if replica_lag is not None else 0.0,
        "target_rpo_sec": target_rpo * 60,
        "alarms": alarms_info
    }

def print_dashboard(data):
    os.system('cls' if os.name == 'nt' else 'clear')
    print("==================================================================")
    print("   RECOVERY-ENGINE: REAL-TIME CLOUDWATCH TELEMETRY DASHBOARD    ")
    print("==================================================================")
    print(f"Timestamp (UTC): {data['timestamp']}")
    print("------------------------------------------------------------------")
    print(" 📊 REAL-TIME METRICS")
    print("------------------------------------------------------------------")
    
    p_cpu_str = f"{data['primary_cpu']:.2f}%" if data['primary_cpu'] is not None else "N/A (Idle/Init)"
    s_cpu_str = f"{data['replica_cpu']:.2f}%" if data['replica_cpu'] is not None else "N/A (Idle/Init)"
    lag_val = data['replica_lag']
    rpo_limit = data['target_rpo_sec']

    print(f" Primary DB ({data['primary_id']}):")
    print(f"   └── CPU Utilization:   {p_cpu_str}")
    print(f" Secondary DB ({data['replica_id']}):")
    print(f"   └── CPU Utilization:   {s_cpu_str}")
    print(f" Cross-Region Replication Lag:")
    print(f"   └── Current Lag:       {lag_val:.2f} seconds")
    print(f"   └── Target RPO Limit:  {rpo_limit} seconds (5 mins)")
    print(f"   └── RPO Status:        {'[HEALTHY - SLO MET]' if lag_val <= rpo_limit else '[ALARM - RPO BREACHED]'}")

    print("------------------------------------------------------------------")
    print(" 🚨 CLOUDWATCH ALARMS AUDIT")
    print("------------------------------------------------------------------")
    if data['alarms']:
        for a in data['alarms']:
            state_icon = "[OK]" if a['state'] == "OK" else f"[{a['state']}]"
            print(f" [{a['region']}] {a['name']} -> {state_icon}")
    else:
        print(" No CloudWatch alarms found matching prefix 'recovery-engine-'.")

    print("==================================================================")

def main():
    parser = argparse.ArgumentParser(description="Recovery-Engine Real-Time Telemetry Dashboard")
    parser.add_argument("--config", default="config/recovery-engine.yaml", help="Path to config file")
    parser.add_argument("--watch", action="store_true", help="Continuously auto-refresh dashboard")
    parser.add_argument("--interval", type=int, default=5, help="Refresh interval in seconds (default: 5)")
    args = parser.parse_args()

    config = load_config(args.config)

    if args.watch:
        try:
            while True:
                data = fetch_telemetry(config)
                print_dashboard(data)
                print(f"Auto-refreshing every {args.interval}s... Press Ctrl+C to exit.")
                time.sleep(args.interval)
        except KeyboardInterrupt:
            print("\nExiting telemetry monitor.")
            sys.exit(0)
    else:
        data = fetch_telemetry(config)
        print_dashboard(data)

if __name__ == "__main__":
    main()
