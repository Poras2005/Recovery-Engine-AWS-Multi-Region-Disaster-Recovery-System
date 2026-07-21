#!/usr/bin/env python3
"""
RDS Cross-Region Replica Promotion Script
================--------------------------
Promotes a read replica in the secondary/DR region to a standalone read-write primary DB.

Usage:
    python promote_replica.py --replica-id recovery-engine-replica-db-dev --region ap-southeast-1 --dry-run
    python promote_replica.py --replica-id recovery-engine-replica-db-dev --region ap-southeast-1 --execute
"""

import argparse
import datetime
import logging
import sys
import time
import boto3
from botocore.exceptions import ClientError

def setup_logging(log_filename=None):
    """Configures console and file logging with exact ISO timestamps."""
    logger = logging.getLogger("ReplicaPromoter")
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%Y-%m-%dT%H:%M:%SZ")

    # Console Handler
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    # File Handler
    if log_filename:
        fh = logging.FileHandler(log_filename)
        fh.setFormatter(formatter)
        logger.addHandler(fh)

    return logger

def get_rds_client(region_name):
    """Returns a boto3 RDS client for the specified AWS region."""
    return boto3.client("rds", region_name=region_name)

def describe_replica(rds_client, replica_id, logger):
    """Fetches and logs the current status of the RDS instance."""
    try:
        response = rds_client.describe_db_instances(DBInstanceIdentifier=replica_id)
        instances = response.get("DBInstances", [])
        if not instances:
            logger.error(f"RDS instance '{replica_id}' not found.")
            return None

        instance = instances[0]
        status = instance.get("DBInstanceStatus")
        is_replica = bool(instance.get("ReadReplicaSourceDBInstanceIdentifier"))
        engine = instance.get("Engine")
        endpoint = instance.get("Endpoint", {}).get("Address")

        logger.info(f"Target DB Identifier: {replica_id}")
        logger.info(f"Current Status: {status}")
        logger.info(f"Is Read Replica: {is_replica}")
        logger.info(f"Source DB Identifier: {instance.get('ReadReplicaSourceDBInstanceIdentifier', 'N/A')}")
        logger.info(f"Engine: {engine}")
        logger.info(f"Endpoint: {endpoint}")

        return instance
    except ClientError as e:
        logger.error(f"AWS API Error describing DB instance: {e}")
        return None

def promote_replica(rds_client, replica_id, backup_retention_period, dry_run, logger):
    """Executes or simulates promotion of the read replica to standalone primary."""
    start_time = datetime.datetime.now(datetime.timezone.utc)
    logger.info(f"Initiating replica promotion workflow at {start_time.isoformat()}...")

    instance = describe_replica(rds_client, replica_id, logger)
    if not instance:
        logger.error("Abort: Unable to describe target replica instance.")
        return False

    status = instance.get("DBInstanceStatus")
    if status != "available":
        logger.warning(f"Warning: Target replica status is '{status}'. Instance must be 'available' for promotion.")

    is_replica = bool(instance.get("ReadReplicaSourceDBInstanceIdentifier"))
    if not is_replica:
        logger.warning(f"Notice: Instance '{replica_id}' does not currently list a source DB. It may already be promoted!")
        if dry_run:
            logger.info("[DRY-RUN] Aborting simulated promotion because instance is already standalone.")
            return True

    if dry_run:
        logger.info(f"[DRY-RUN] SIMULATION ONLY: Would invoke rds.promote_read_replica for '{replica_id}'")
        logger.info(f"[DRY-RUN] Target Region: {rds_client.meta.region_name}")
        logger.info(f"[DRY-RUN] Backup Retention Period: {backup_retention_period} days")
        logger.info("[DRY-RUN] Simulation finished successfully. No changes made.")
        return True

    try:
        logger.info(f"Executing boto3 promote_read_replica for '{replica_id}'...")
        response = rds_client.promote_read_replica(
            DBInstanceIdentifier=replica_id,
            BackupRetentionPeriod=backup_retention_period
        )
        
        promoted_instance = response.get("DBInstance", {})
        logger.info(f"Promotion request accepted. Current DB status: {promoted_instance.get('DBInstanceStatus')}")

        # Wait for promotion completion
        logger.info("Waiting for instance status to transition to 'available' as standalone primary...")
        waiter = rds_client.get_waiter("db_instance_available")
        waiter.wait(
            DBInstanceIdentifier=replica_id,
            WaiterConfig={"Delay": 15, "MaxAttempts": 40}
        )

        end_time = datetime.datetime.now(datetime.timezone.utc)
        duration_seconds = (end_time - start_time).total_seconds()
        logger.info(f"SUCCESS: RDS Instance '{replica_id}' promoted to standalone primary in {duration_seconds:.2f} seconds.")
        return True

    except ClientError as e:
        logger.error(f"FAILURE during replica promotion: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description="Promote RDS Cross-Region Read Replica to Primary DB")
    parser.add_argument("--replica-id", required=True, help="DB Instance Identifier of the replica (e.g. recovery-engine-replica-db-dev)")
    parser.add_argument("--region", required=True, help="AWS Region of the replica (e.g. ap-southeast-1)")
    parser.add_argument("--backup-retention", type=int, default=7, help="Backup retention period in days for the promoted primary (default: 7)")
    parser.add_argument("--log-file", default="promotion.log", help="Path to write execution log file")
    
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--dry-run", action="store_true", help="Simulate promotion without applying changes")
    group.add_argument("--execute", action="store_true", help="Execute real promotion on AWS")

    args = parser.parse_args()
    logger = setup_logging(args.log_file)

    logger.info("==================================================")
    logger.info("   RECOVERY-ENGINE: RDS REPLICA PROMOTION SCRIPT  ")
    logger.info("==================================================")
    logger.info(f"Mode: {'DRY-RUN (Simulation)' if args.dry_run else 'EXECUTE (Live Production Action)'}")

    rds_client = get_rds_client(args.region)
    success = promote_replica(rds_client, args.replica_id, args.backup_retention, args.dry_run, logger)

    if success:
        logger.info("Workflow completed successfully.")
        sys.exit(0)
    else:
        logger.error("Workflow failed.")
        sys.exit(1)

if __name__ == "__main__":
    main()
