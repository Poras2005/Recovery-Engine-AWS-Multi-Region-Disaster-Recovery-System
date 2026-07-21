#!/usr/bin/env bash
# ==============================================================================
# Recovery-Engine: Multi-Region Disaster Recovery CLI Runner
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

print_usage() {
    echo "=================================================================="
    echo "   RECOVERY-ENGINE: DISASTER RECOVERY CLI RUNNER                "
    echo "=================================================================="
    echo "Usage: ./scripts/run_failover.sh [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  validate-config Audit YAML config against JSON schema & zero-hardcode checks"
    echo "  audit-tf        Scan Terraform code for hardcoded Account IDs, ARNs & VPCs"
    echo "  audit-modules   Audit Terraform modules for HashiCorp structure & descriptions"
    echo "  status          Audit multi-region RDS, Route53, and ReplicaLag metrics"
    echo "  check           Run pre/post health check on db.recovery-engine.internal"
    echo "  monitor         Launch real-time CloudWatch telemetry dashboard (--watch)"
    echo "  alarms          List all CloudWatch DR alarms & their current states"
    echo "  test-alert      Simulate firing a CloudWatch Alarm to test SNS alerts"
    echo "  reset-alerts    Reset all CloudWatch DR alarms back to OK state"
    echo "  chaos-db        Simulate Scenario 1: Primary Database Outage (Dry-Run)"
    echo "  chaos-lag       Simulate Scenario 2: Replication Lag Spike >300s (Dry-Run)"
    echo "  chaos-region    Simulate Scenario 3: Total Primary Region Outage (Dry-Run)"
    echo "  audit           Generate RTO & RPO compliance audit report (Markdown)"
    echo "  gameday         Run end-to-end automated Game-Day DR Drill (Dry-Run)"
    echo "  dry-run         Simulate failover workflow without changing infrastructure"
    echo "  execute         Execute real live multi-region failover"
    echo "  failback        Restore traffic back to primary region endpoint"
    echo "  help            Display this help message"
    echo "=================================================================="
}

COMMAND="${1:-help}"

case "$COMMAND" in
    validate-config)
        echo "[*] Validating YAML configuration and performing Zero-Hardcoding Audit..."
        python3 scripts/config_validator.py
        ;;
    audit-tf)
        echo "[*] Scanning Terraform modules & environments for hardcoded values..."
        python3 scripts/audit_hardcoding.py
        ;;
    audit-modules)
        echo "[*] Auditing Terraform module quality, file structures, and descriptions..."
        python3 scripts/module_cleanup_audit.py
        ;;
    status)
        echo "[*] Auditing multi-region status..."
        python3 scripts/failover_orchestrator.py --status
        ;;
    check)
        echo "[*] Executing health check..."
        python3 scripts/health_check.py
        ;;
    monitor)
        echo "[*] Launching real-time CloudWatch telemetry monitor..."
        python3 scripts/monitor_dr.py --watch --interval 5
        ;;
    alarms)
        echo "[*] Listing all CloudWatch DR alarms..."
        python3 scripts/simulate_alarm.py --list
        ;;
    test-alert)
        echo "[!] Simulating alarm state trigger on 'recovery-engine-primary-cpu-high-dev'..."
        python3 scripts/simulate_alarm.py --trigger recovery-engine-primary-cpu-high-dev --region ap-south-1
        ;;
    reset-alerts)
        echo "[*] Resetting all CloudWatch DR alarms back to OK state..."
        python3 scripts/simulate_alarm.py --reset-all
        ;;
    chaos-db)
        echo "[*] Simulating Chaos Scenario 1: Primary Database Outage..."
        python3 scripts/chaos_simulator.py --scenario db-outage --dry-run
        ;;
    chaos-lag)
        echo "[*] Simulating Chaos Scenario 2: Replication Lag Spike (>300s)..."
        python3 scripts/chaos_simulator.py --scenario lag-spike --dry-run
        ;;
    chaos-region)
        echo "[*] Simulating Chaos Scenario 3: Primary Region Total Outage..."
        python3 scripts/chaos_simulator.py --scenario region-outage --dry-run
        ;;
    audit)
        echo "[*] Generating RTO & RPO Benchmark Audit Report..."
        python3 scripts/rto_rpo_audit.py --report docs/RTO_RPO_Audit_Report.md
        ;;
    gameday)
        echo "[*] Launching end-to-end Game-Day DR Drill Simulation..."
        python3 scripts/run_dr_drill.py --dry-run
        ;;
    dry-run)
        echo "[*] Running dry-run failover simulation..."
        python3 scripts/failover_orchestrator.py --dry-run
        ;;
    execute)
        echo "[!] WARNING: Initiating LIVE Multi-Region Failover..."
        read -p "Are you sure you want to promote secondary RDS and switch DNS? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            python3 scripts/failover_orchestrator.py --execute
        else
            echo "Operation cancelled by user."
        fi
        ;;
    failback)
        echo "[!] Initiating Failback Sequence to Primary Region..."
        read -p "Are you sure you want to return traffic to Primary Region? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            python3 scripts/failback.py --execute
        else
            echo "Operation cancelled by user."
        fi
        ;;
    help|*)
        print_usage
        ;;
esac
