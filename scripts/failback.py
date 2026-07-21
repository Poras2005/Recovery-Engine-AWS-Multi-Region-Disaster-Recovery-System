#!/usr/bin/env python3
"""
Recovery-Engine: Disaster Recovery Failback Controller
======================================================
Restores traffic routing back to the primary region (Mumbai) after an outage
or completion of a DR drill.

Usage:
    python scripts/failback.py --dry-run
    python scripts/failback.py --execute
"""

import argparse
import datetime
import logging
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
        },
        "database": {"primary_id": "recovery-engine-primary-db-dev"},
        "route53": {
            "domain_name": "recovery-engine.internal",
            "record_name": "db.recovery-engine.internal"
        }
    }

def setup_logging():
    logger = logging.getLogger("FailbackController")
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%Y-%m-%dT%H:%M:%SZ")
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(formatter)
    logger.addHandler(ch)
    return logger

def main():
    parser = argparse.ArgumentParser(description="Recovery-Engine Failback Controller")
    parser.add_argument("--config", default="config/recovery-engine.yaml", help="Path to config file")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--dry-run", action="store_true", help="Simulate failback sequence")
    group.add_argument("--execute", action="store_true", help="Execute live failback")
    args = parser.parse_args()

    logger = setup_logging()
    cfg = load_config(args.config)

    primary_region = cfg.get("regions", {}).get("primary", {}).get("region", "ap-south-1")
    env = cfg.get("global", {}).get("environment", "dev")
    primary_db_id = cfg.get("database", {}).get("primary_id", f"recovery-engine-primary-db-{env}")
    domain_name = cfg.get("route53", {}).get("domain_name", "recovery-engine.internal")
    record_name = cfg.get("route53", {}).get("record_name", f"db.{domain_name}")

    logger.info("==================================================")
    logger.info("      RECOVERY-ENGINE: FAILBACK CONTROLLER       ")
    logger.info("==================================================")
    logger.info(f"Mode: {'DRY-RUN (Simulation)' if args.dry_run else 'LIVE EXECUTION'}")
    logger.info(f"Primary Region: {primary_region}")
    logger.info(f"Primary DB ID:  {primary_db_id}")

    rds_client = boto3.client("rds", region_name=primary_region)
    r53_client = boto3.client("route53", region_name=primary_region)

    # Step 1: Verify Primary DB Status
    logger.info("=== STEP 1: VERIFY PRIMARY DB ACCESSIBILITY ===")
    try:
        resp = rds_client.describe_db_instances(DBInstanceIdentifier=primary_db_id)
        inst = resp["DBInstances"][0]
        status = inst.get("DBInstanceStatus")
        endpoint = inst.get("Endpoint", {}).get("Address")
        logger.info(f"Primary DB Status: {status} | Endpoint: {endpoint}")

        if status != "available":
            logger.error(f"Abort: Primary DB status is '{status}'. Must be 'available' to perform failback.")
            sys.exit(1)
    except ClientError as e:
        logger.error(f"Abort: Unable to describe primary DB instance: {e}")
        sys.exit(1)

    # Step 2: Switch Route53 DNS Record back to Primary Endpoint
    logger.info("=== STEP 2: SWITCH ROUTE53 DNS RECORD BACK TO PRIMARY ===")
    if args.dry_run:
        logger.info(f"[DRY-RUN] Would update Route53 record '{record_name}' -> '{endpoint}'")
        logger.info("[DRY-RUN] Failback simulation completed successfully.")
        sys.exit(0)

    try:
        zones = r53_client.list_hosted_zones_by_name(DNSName=domain_name)
        zone_id = None
        for z in zones.get("HostedZones", []):
            if z["Name"].rstrip(".") == domain_name.rstrip("."):
                zone_id = z["Id"].split("/")[-1]
                break

        if not zone_id:
            logger.error(f"Route53 hosted zone for '{domain_name}' not found.")
            sys.exit(1)

        change_batch = {
            "Comment": "Failback: Switch traffic back to primary region DB",
            "Changes": [
                {
                    "Action": "UPSERT",
                    "ResourceRecordSet": {
                        "Name": record_name,
                        "Type": "CNAME",
                        "TTL": 10,
                        "ResourceRecords": [{"Value": endpoint}]
                    }
                }
            ]
        }

        resp = r53_client.change_resource_record_sets(HostedZoneId=zone_id, ChangeBatch=change_batch)
        logger.info(f"Route53 Failback DNS update submitted (Change ID: {resp['ChangeInfo']['Id']}).")
        logger.info("SUCCESS: Failback completed successfully.")
        sys.exit(0)

    except ClientError as e:
        logger.error(f"Failback DNS update failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
