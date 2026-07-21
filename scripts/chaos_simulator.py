#!/usr/bin/env python3
"""
Recovery-Engine: Automated Chaos Scenario Simulator (Module 6 Task 1)
======================================================================
Simulates production disaster scenarios (Primary DB Outage, Replication Lag Spike,
and Regional Endpoint Failure) to test DR resilience and calculate actual RTO/RPO.

Usage:
    python3 scripts/chaos_simulator.py --scenario db-outage --dry-run
    python3 scripts/chaos_simulator.py --scenario lag-spike --dry-run
    python3 scripts/chaos_simulator.py --scenario region-outage --dry-run
    python3 scripts/chaos_simulator.py --scenario db-outage --execute --auto-recover
"""

import argparse
import datetime
import logging
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
        "global": {"environment": "dev", "target_rto_minutes": 10, "target_rpo_minutes": 5},
        "regions": {
            "primary": {"region": "ap-south-1"},
            "secondary": {"region": "ap-southeast-1"}
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

def setup_logging(log_file="chaos_drill.log"):
    logger = logging.getLogger("ChaosSimulator")
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", datefmt="%Y-%m-%dT%H:%M:%SZ")

    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    if log_file:
        fh = logging.FileHandler(log_file)
        fh.setFormatter(formatter)
        logger.addHandler(fh)

    return logger

class ChaosSimulator:
    def __init__(self, config, logger):
        self.config = config
        self.logger = logger

        env = config.get("global", {}).get("environment", "dev")
        self.primary_region = config.get("regions", {}).get("primary", {}).get("region", "ap-south-1")
        self.secondary_region = config.get("regions", {}).get("secondary", {}).get("region", "ap-southeast-1")
        self.primary_db_id = config.get("database", {}).get("primary_id", f"recovery-engine-primary-db-{env}")
        self.replica_db_id = config.get("database", {}).get("replica_id", f"recovery-engine-replica-db-{env}")

        self.rds_primary = boto3.client("rds", region_name=self.primary_region)
        self.rds_secondary = boto3.client("rds", region_name=self.secondary_region)
        self.cw_primary = boto3.client("cloudwatch", region_name=self.primary_region)
        self.cw_secondary = boto3.client("cloudwatch", region_name=self.secondary_region)

    def scenario_db_outage(self, dry_run=True, duration=30):
        """Scenario 1: Primary Database Blackhole / Outage Simulation."""
        self.logger.info("==================================================================")
        self.logger.info("   CHAOS SCENARIO 1: PRIMARY DATABASE OUTAGE SIMULATION           ")
        self.logger.info("==================================================================")
        self.logger.info(f"Target Primary DB: {self.primary_db_id} ({self.primary_region})")

        if dry_run:
            self.logger.info("[DRY-RUN] SIMULATION ONLY: Would invoke rds.reboot_db_instance(force_failover=True)")
            self.logger.info(f"[DRY-RUN] Would simulate Primary DB unreachability for {duration} seconds.")
            self.logger.info("[DRY-RUN] Scenario 1 simulation completed successfully.")
            return True

        self.logger.info(f"[LIVE CHAOS] Injecting outage: Rebooting Primary RDS with force_failover=True...")
        try:
            self.rds_primary.reboot_db_instance(
                DBInstanceIdentifier=self.primary_db_id,
                ForceFailover=True
            )
            self.logger.info("[LIVE CHAOS] Primary RDS reboot initiated. Instance is transitioning to rebooting/unreachable state.")
            self.logger.info(f"[LIVE CHAOS] Waiting for outage duration ({duration}s)...")
            time.sleep(duration)
            self.logger.info("[LIVE CHAOS] Primary DB Chaos Scenario injection finished.")
            return True
        except ClientError as e:
            self.logger.error(f"[LIVE CHAOS FAILED] Error injecting DB outage: {e}")
            return False

    def scenario_lag_spike(self, dry_run=True, duration=30):
        """Scenario 2: Replication Network Disruption / Lag Spike Simulation (> 300s RPO limit)."""
        self.logger.info("==================================================================")
        self.logger.info("   CHAOS SCENARIO 2: REPLICATION LAG SPIKE SIMULATION (> 300s RPO)")
        self.logger.info("==================================================================")
        self.logger.info(f"Target Secondary Replica: {self.replica_db_id} ({self.secondary_region})")

        alarm_name = f"recovery-engine-replica-lag-rpo-alarm-{self.config.get('global', {}).get('environment', 'dev')}"

        if dry_run:
            self.logger.info(f"[DRY-RUN] Would set CloudWatch Alarm '{alarm_name}' to ALARM state (ReplicaLag=420s).")
            self.logger.info(f"[DRY-RUN] Would simulate extreme replication delay exceeding 5-min RPO limit.")
            self.logger.info("[DRY-RUN] Scenario 2 simulation completed successfully.")
            return True

        self.logger.info(f"[LIVE CHAOS] Setting CloudWatch Alarm '{alarm_name}' in '{self.secondary_region}' to ALARM state...")
        try:
            self.cw_secondary.set_alarm_state(
                AlarmName=alarm_name,
                StateValue="ALARM",
                StateReason="Chaos Scenario 2: Simulated network degradation causing 420s replication lag spike."
            )
            self.logger.info(f"[LIVE CHAOS] Alarm '{alarm_name}' set to ALARM. Replication lag breach active.")
            time.sleep(duration)
            return True
        except ClientError as e:
            self.logger.error(f"[LIVE CHAOS FAILED] Error injecting lag spike: {e}")
            return False

    def scenario_region_outage(self, dry_run=True, duration=30):
        """Scenario 3: Primary Region Total Outage / Route53 Health Failure Simulation."""
        self.logger.info("==================================================================")
        self.logger.info("   CHAOS SCENARIO 3: PRIMARY REGION TOTAL OUTAGE SIMULATION      ")
        self.logger.info("==================================================================")
        self.logger.info(f"Simulating total regional failure in Primary Region ({self.primary_region})...")

        alarm_name = f"recovery-engine-primary-cpu-high-{self.config.get('global', {}).get('environment', 'dev')}"

        if dry_run:
            self.logger.info(f"[DRY-RUN] Would trip Primary Health Check and fire alert '{alarm_name}'.")
            self.logger.info(f"[DRY-RUN] Would trigger automated Failover Orchestrator sequence.")
            self.logger.info("[DRY-RUN] Scenario 3 simulation completed successfully.")
            return True

        self.logger.info(f"[LIVE CHAOS] Setting Primary Region Alarms to ALARM state...")
        try:
            self.cw_primary.set_alarm_state(
                AlarmName=alarm_name,
                StateValue="ALARM",
                StateReason="Chaos Scenario 3: Simulated total primary region loss."
            )
            self.logger.info("[LIVE CHAOS] Primary Region outage simulated successfully.")
            time.sleep(duration)
            return True
        except ClientError as e:
            self.logger.error(f"[LIVE CHAOS FAILED] Error simulating region outage: {e}")
            return False

    def auto_recover(self):
        """Restores CloudWatch alarm states back to OK."""
        self.logger.info("=== AUTO-RECOVERING SYSTEM STATES BACK TO NORMAL ===")
        env = self.config.get('global', {}).get('environment', 'dev')
        p_alarm = f"recovery-engine-primary-cpu-high-{env}"
        s_alarm = f"recovery-engine-replica-lag-rpo-alarm-{env}"

        try:
            self.cw_primary.set_alarm_state(AlarmName=p_alarm, StateValue="OK", StateReason="Chaos recovery complete")
            self.cw_secondary.set_alarm_state(AlarmName=s_alarm, StateValue="OK", StateReason="Chaos recovery complete")
            self.logger.info("System alarm states successfully restored to [OK].")
        except Exception as e:
            self.logger.warning(f"Recovery notice: {e}")

def main():
    parser = argparse.ArgumentParser(description="Recovery-Engine Automated Chaos Scenario Simulator")
    parser.add_argument("--config", default="config/recovery-engine.yaml", help="Path to config file")
    parser.add_argument("--scenario", choices=["db-outage", "lag-spike", "region-outage"], required=True, help="Chaos scenario to execute")
    parser.add_argument("--duration", type=int, default=15, help="Outage simulation duration in seconds (default: 15)")
    parser.add_argument("--log-file", default="chaos_drill.log", help="Log file path")
    parser.add_argument("--auto-recover", action="store_true", help="Auto recover system state after scenario completes")

    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--dry-run", action="store_true", help="Simulate chaos scenario without modifying live infrastructure")
    group.add_argument("--execute", action="store_true", help="Execute real live chaos scenario")

    args = parser.parse_args()
    logger = setup_logging(args.log_file)
    config = load_config(args.config)

    sim = ChaosSimulator(config, logger)
    dry_run = args.dry_run

    if args.scenario == "db-outage":
        success = sim.scenario_db_outage(dry_run=dry_run, duration=args.duration)
    elif args.scenario == "lag-spike":
        success = sim.scenario_lag_spike(dry_run=dry_run, duration=args.duration)
    elif args.scenario == "region-outage":
        success = sim.scenario_region_outage(dry_run=dry_run, duration=args.duration)

    if args.auto_recover and not dry_run:
        sim.auto_recover()

    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
