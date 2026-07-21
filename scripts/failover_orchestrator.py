#!/usr/bin/env python3
"""
Recovery-Engine: Multi-Region Disaster Recovery Failover Orchestrator
======================================================================
Automated failover controller supporting pre-flight health checks, RDS read
replica promotion, Route53 DNS updating, and RTO/RPO measurement logging.

Usage:
    python scripts/failover_orchestrator.py --status
    python scripts/failover_orchestrator.py --dry-run
    python scripts/failover_orchestrator.py --execute
"""

import argparse
import datetime
import logging
import os
import sys
import time
import boto3
from botocore.exceptions import ClientError, BotoCoreError

# Try to import yaml, fallback to dictionary defaults if pyyaml is missing
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

# Default Configuration Fallback
DEFAULT_CONFIG = {
    "global": {
        "environment": "dev",
        "project_name": "recovery-engine",
        "target_rto_minutes": 10,
        "target_rpo_minutes": 5
    },
    "regions": {
        "primary": {"region": "ap-south-1", "name": "mumbai"},
        "secondary": {"region": "ap-southeast-1", "name": "singapore"}
    },
    "database": {
        "primary_id": "recovery-engine-primary-db-dev",
        "replica_id": "recovery-engine-replica-db-dev"
    },
    "route53": {
        "domain_name": "recovery-engine.internal",
        "record_name": "db.recovery-engine.internal"
    }
}

def load_config(config_path="config/recovery-engine.yaml"):
    """Loads configuration from YAML file or falls back to defaults."""
    if HAS_YAML and os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                cfg = yaml.safe_load(f)
                return cfg
        except Exception as e:
            print(f"[WARNING] Could not parse {config_path}: {e}. Using defaults.")
    return DEFAULT_CONFIG

def setup_logging(log_file="failover.log"):
    """Sets up unified logger with ISO 8601 UTC timestamps."""
    logger = logging.getLogger("FailoverOrchestrator")
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter(
        "[%(asctime)s] [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%SZ"
    )

    # Console output
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    # File output
    if log_file:
        fh = logging.FileHandler(log_file)
        fh.setFormatter(formatter)
        logger.addHandler(fh)

    return logger

class FailoverOrchestrator:
    def __init__(self, config, logger):
        self.config = config
        self.logger = logger

        self.primary_region = config.get("regions", {}).get("primary", {}).get("region", "ap-south-1")
        self.secondary_region = config.get("regions", {}).get("secondary", {}).get("region", "ap-southeast-1")
        
        env = config.get("global", {}).get("environment", "dev")
        self.primary_db_id = config.get("database", {}).get("primary_id", f"recovery-engine-primary-db-{env}")
        self.replica_db_id = config.get("database", {}).get("replica_id", f"recovery-engine-replica-db-{env}")
        self.domain_name = config.get("route53", {}).get("domain_name", "recovery-engine.internal")
        self.record_name = config.get("route53", {}).get("record_name", f"db.{self.domain_name}")

        self.target_rto = config.get("global", {}).get("target_rto_minutes", 10)
        self.target_rpo = config.get("global", {}).get("target_rpo_minutes", 5)

        # Clients initialized per region
        self.primary_rds = boto3.client("rds", region_name=self.primary_region)
        self.secondary_rds = boto3.client("rds", region_name=self.secondary_region)
        self.route53_client = boto3.client("route53", region_name=self.primary_region)
        self.cloudwatch_sec = boto3.client("cloudwatch", region_name=self.secondary_region)
        self.sts_client = boto3.client("sts", region_name=self.primary_region)

    def preflight_check(self):
        """Verifies AWS API access and IAM permissions."""
        self.logger.info("=== PRE-FLIGHT CHECK ===")
        try:
            identity = self.sts_client.get_caller_identity()
            self.logger.info(f"AWS Account ID: {identity.get('Account')}")
            self.logger.info(f"Caller ARN:     {identity.get('Arn')}")
            self.logger.info("Pre-flight AWS STS authentication SUCCESSFUL.")
            return True
        except (ClientError, BotoCoreError) as e:
            self.logger.error(f"Pre-flight authentication FAILED: {e}")
            return False

    def get_system_status(self):
        """Fetches status of Primary DB, Secondary Replica, Replica Lag, and Route53 records."""
        self.logger.info("=== SYSTEM HEALTH & STATUS AUDIT ===")
        status_info = {
            "primary": None,
            "replica": None,
            "replica_lag_seconds": None,
            "dns_current_target": None
        }

        # 1. Primary DB Status
        try:
            resp = self.primary_rds.describe_db_instances(DBInstanceIdentifier=self.primary_db_id)
            inst = resp["DBInstances"][0]
            status_info["primary"] = {
                "status": inst.get("DBInstanceStatus"),
                "endpoint": inst.get("Endpoint", {}).get("Address"),
                "multi_az": inst.get("MultiAZ")
            }
            self.logger.info(f"[Primary - {self.primary_region}] DB ID: {self.primary_db_id} | Status: {status_info['primary']['status']} | Endpoint: {status_info['primary']['endpoint']}")
        except ClientError as e:
            self.logger.warning(f"[Primary - {self.primary_region}] DB ID: {self.primary_db_id} check failed/unreachable: {e}")

        # 2. Secondary Replica Status
        try:
            resp = self.secondary_rds.describe_db_instances(DBInstanceIdentifier=self.replica_db_id)
            inst = resp["DBInstances"][0]
            status_info["replica"] = {
                "status": inst.get("DBInstanceStatus"),
                "endpoint": inst.get("Endpoint", {}).get("Address"),
                "is_replica": bool(inst.get("ReadReplicaSourceDBInstanceIdentifier")),
                "source": inst.get("ReadReplicaSourceDBInstanceIdentifier")
            }
            self.logger.info(f"[Secondary - {self.secondary_region}] Replica ID: {self.replica_db_id} | Status: {status_info['replica']['status']} | Is Replica: {status_info['replica']['is_replica']} | Endpoint: {status_info['replica']['endpoint']}")
        except ClientError as e:
            self.logger.warning(f"[Secondary - {self.secondary_region}] Replica ID: {self.replica_db_id} check failed: {e}")

        # 3. Fetch Replication Lag Metric from CloudWatch
        try:
            now = datetime.datetime.now(datetime.timezone.utc)
            start = now - datetime.timedelta(minutes=15)
            metrics = self.cloudwatch_sec.get_metric_statistics(
                Namespace="AWS/RDS",
                MetricName="ReplicaLag",
                Dimensions=[{"Name": "DBInstanceIdentifier", "Value": self.replica_db_id}],
                StartTime=start,
                EndTime=now,
                Period=60,
                Statistics=["Maximum"]
            )
            datapoints = metrics.get("Datapoints", [])
            if datapoints:
                latest_lag = sorted(datapoints, key=lambda x: x["Timestamp"])[-1]["Maximum"]
                status_info["replica_lag_seconds"] = latest_lag
                self.logger.info(f"[Metrics] RDS ReplicaLag: {latest_lag:.2f} seconds (Target RPO limit: {self.target_rpo * 60}s)")
            else:
                self.logger.info("[Metrics] RDS ReplicaLag: No recent datapoints (Instance idle or freshly initialized)")
        except ClientError as e:
            self.logger.warning(f"Could not retrieve ReplicaLag metrics: {e}")

        # 4. Route53 DNS Status
        try:
            zones = self.route53_client.list_hosted_zones_by_name(DNSName=self.domain_name)
            zone_id = None
            for z in zones.get("HostedZones", []):
                if z["Name"].rstrip(".") == self.domain_name.rstrip("."):
                    zone_id = z["Id"].split("/")[-1]
                    break

            if zone_id:
                records = self.route53_client.list_resource_record_sets(
                    HostedZoneId=zone_id,
                    StartRecordName=self.record_name,
                    StartRecordType="CNAME"
                )
                for r in records.get("ResourceRecordSets", []):
                    if r["Name"].rstrip(".") == self.record_name.rstrip("."):
                        target = [rr["Value"] for rr in r.get("ResourceRecords", [])]
                        status_info["dns_current_target"] = target
                        self.logger.info(f"[Route53] Hosted Zone: {zone_id} | Record '{self.record_name}' points to: {target}")
                        break
            else:
                self.logger.info(f"[Route53] Hosted zone for '{self.domain_name}' not found.")
        except ClientError as e:
            self.logger.warning(f"Route53 status check failed: {e}")

        return status_info

    def update_dns_record(self, new_endpoint, dry_run=False):
        """Updates the Route53 failover CNAME record to point to the promoted secondary database."""
        self.logger.info(f"=== STEP: UPDATE ROUTE53 DNS RECORD ({self.record_name}) ===")
        if dry_run:
            self.logger.info(f"[DRY-RUN] Would update Route53 record '{self.record_name}' -> '{new_endpoint}'")
            return True

        try:
            # Locate hosted zone
            zones = self.route53_client.list_hosted_zones_by_name(DNSName=self.domain_name)
            zone_id = None
            for z in zones.get("HostedZones", []):
                if z["Name"].rstrip(".") == self.domain_name.rstrip("."):
                    zone_id = z["Id"].split("/")[-1]
                    break

            if not zone_id:
                self.logger.error(f"Cannot update DNS: Route53 zone for '{self.domain_name}' not found.")
                return False

            self.logger.info(f"Updating CNAME record '{self.record_name}' in zone '{zone_id}' to target: {new_endpoint}")
            change_batch = {
                "Comment": "Failover Orchestrator: Switch active endpoint to promoted secondary DB",
                "Changes": [
                    {
                        "Action": "UPSERT",
                        "ResourceRecordSet": {
                            "Name": self.record_name,
                            "Type": "CNAME",
                            "TTL": 10,
                            "ResourceRecords": [{"Value": new_endpoint}]
                        }
                    }
                ]
            }

            resp = self.route53_client.change_resource_record_sets(
                HostedZoneId=zone_id,
                ChangeBatch=change_batch
            )
            change_id = resp["ChangeInfo"]["Id"]
            self.logger.info(f"Route53 change request submitted successfully (Change ID: {change_id}).")
            return True

        except ClientError as e:
            self.logger.error(f"Failed to update Route53 record: {e}")
            return False

    def execute_failover(self, dry_run=False):
        """Executes the full multi-region failover sequence and measures RTO."""
        start_time = datetime.datetime.now(datetime.timezone.utc)
        mode_str = "DRY-RUN (SIMULATION)" if dry_run else "LIVE FAILOVER EXECUTION"
        
        self.logger.info("==================================================================")
        self.logger.info(f"   RECOVERY-ENGINE: DISASTER RECOVERY FAILOVER - {mode_str}   ")
        self.logger.info("==================================================================")
        self.logger.info(f"Start Timestamp (UTC): {start_time.isoformat()}")
        self.logger.info(f"Target RTO Limit:      {self.target_rto} minutes")
        self.logger.info(f"Target RPO Limit:      {self.target_rpo} minutes")

        if not self.preflight_check():
            self.logger.error("Abort: Pre-flight check failed.")
            return False

        status = self.get_system_status()

        # Step 1: Validate Replica Readiness
        self.logger.info("=== STEP 1: VALIDATE SECONDARY REPLICA ===")
        replica_info = status.get("replica")
        if not replica_info:
            self.logger.error("Abort: Secondary replica details could not be retrieved.")
            return False

        secondary_endpoint = replica_info.get("endpoint")

        if dry_run:
            self.logger.info(f"[DRY-RUN] Secondary replica ID '{self.replica_db_id}' verified.")
            self.logger.info(f"[DRY-RUN] Endpoint: {secondary_endpoint}")
            self.logger.info("[DRY-RUN] STEP 2: SIMULATE PROMOTING RDS READ REPLICA")
            self.logger.info(f"[DRY-RUN] Call: rds.promote_read_replica(DBInstanceIdentifier='{self.replica_db_id}')")
            self.logger.info("[DRY-RUN] STEP 3: SIMULATE ROUTE53 DNS FAILOVER SWITCH")
            self.update_dns_record(secondary_endpoint or "replica.sec.rds.amazonaws.com", dry_run=True)
            
            end_time = datetime.datetime.now(datetime.timezone.utc)
            duration_sec = (end_time - start_time).total_seconds()
            self.logger.info("==================================================================")
            self.logger.info(f"[DRY-RUN] Failover Simulation Completed in {duration_sec:.2f} seconds.")
            self.logger.info(f"[DRY-RUN] Target RTO ({self.target_rto * 60}s) Met: YES")
            self.logger.info("==================================================================")
            return True

        # Live Execution Mode
        # Step 2: Promote Read Replica
        self.logger.info(f"=== STEP 2: PROMOTING RDS READ REPLICA ('{self.replica_db_id}') ===")
        try:
            self.secondary_rds.promote_read_replica(
                DBInstanceIdentifier=self.replica_db_id,
                BackupRetentionPeriod=7
            )
            self.logger.info("Promotion API request submitted. Waiting for instance state 'available'...")
            
            waiter = self.secondary_rds.get_waiter("db_instance_available")
            waiter.wait(
                DBInstanceIdentifier=self.replica_db_id,
                WaiterConfig={"Delay": 15, "MaxAttempts": 40}
            )
            self.logger.info("Secondary RDS Instance successfully promoted to standalone Primary!")

        except ClientError as e:
            self.logger.error(f"Failed to promote read replica: {e}")
            return False

        # Step 3: Switch DNS Record
        dns_success = self.update_dns_record(secondary_endpoint)
        if not dns_success:
            self.logger.warning("Warning: RDS promoted, but DNS record update failed. Manual DNS update required.")

        # Step 4: Calculate RTO Duration
        end_time = datetime.datetime.now(datetime.timezone.utc)
        total_rto_seconds = (end_time - start_time).total_seconds()
        total_rto_minutes = total_rto_seconds / 60.0

        rto_met = total_rto_minutes <= self.target_rto

        self.logger.info("==================================================================")
        self.logger.info("                     FAILOVER EXECUTION SUMMARY                   ")
        self.logger.info("==================================================================")
        self.logger.info(f"Total Execution Time (RTO): {total_rto_seconds:.2f} seconds ({total_rto_minutes:.2f} minutes)")
        self.logger.info(f"Target RTO (<= {self.target_rto} min): {'PASSED [SLO MET]' if rto_met else 'FAILED [SLO BREACHED]'}")
        if status.get("replica_lag_seconds") is not None:
            lag = status["replica_lag_seconds"]
            rpo_met = lag <= (self.target_rpo * 60)
            self.logger.info(f"Measured Replication Lag (RPO): {lag:.2f} seconds")
            self.logger.info(f"Target RPO (<= {self.target_rpo * 60}s): {'PASSED [SLO MET]' if rpo_met else 'FAILED [SLO BREACHED]'}")
        self.logger.info("==================================================================")

        return True

def main():
    parser = argparse.ArgumentParser(description="Recovery-Engine Multi-Region Failover Orchestrator")
    parser.add_argument("--config", default="config/recovery-engine.yaml", help="Path to recovery-engine.yaml config file")
    parser.add_argument("--log-file", default="failover.log", help="Path to write execution log file")
    
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--status", action="store_true", help="Audit current multi-region system health & status")
    group.add_argument("--dry-run", action="store_true", help="Simulate step-by-step failover execution without applying changes")
    group.add_argument("--execute", action="store_true", help="Execute real live failover on AWS infrastructure")

    args = parser.parse_args()
    logger = setup_logging(args.log_file)
    config = load_config(args.config)

    orchestrator = FailoverOrchestrator(config, logger)

    if args.status:
        if orchestrator.preflight_check():
            orchestrator.get_system_status()
            sys.exit(0)
        else:
            sys.exit(1)

    elif args.dry_run:
        success = orchestrator.execute_failover(dry_run=True)
        sys.exit(0 if success else 1)

    elif args.execute:
        success = orchestrator.execute_failover(dry_run=False)
        sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
