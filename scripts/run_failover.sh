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
    echo "  status       Audit multi-region RDS, Route53, and ReplicaLag metrics"
    echo "  check        Run pre/post health check on db.recovery-engine.internal"
    echo "  dry-run      Simulate failover workflow without changing infrastructure"
    echo "  execute      Execute real live multi-region failover"
    echo "  failback     Restore traffic back to primary region endpoint"
    echo "  help         Display this help message"
    echo "=================================================================="
}

COMMAND="${1:-help}"

case "$COMMAND" in
    status)
        echo "[*] Auditing multi-region status..."
        python3 scripts/failover_orchestrator.py --status
        ;;
    check)
        echo "[*] Executing health check..."
        python3 scripts/health_check.py
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
