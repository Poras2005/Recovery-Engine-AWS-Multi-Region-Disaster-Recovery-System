#!/usr/bin/env python3
"""
Recovery-Engine: Pre & Post Failover Health Check Utility
=========================================================
Verifies endpoint TCP reachability, DNS CNAME resolution, and network latency
for primary and secondary database instances.

Usage:
    python scripts/health_check.py --config config/recovery-engine.yaml
    python scripts/health_check.py --target db.recovery-engine.internal --port 3306
"""

import argparse
import os
import socket
import sys
import time

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
        "route53": {"record_name": "db.recovery-engine.internal"},
        "database": {"port": 3306}
    }

def check_dns_resolution(hostname):
    """Resolves DNS hostname to IP address."""
    print(f"[*] DNS Resolution Check: {hostname} ...", end=" ")
    try:
        ip = socket.gethostbyname(hostname)
        print(f"[SUCCESS] Resolved to {ip}")
        return True, ip
    except socket.gaierror as e:
        print(f"[FAILED] Could not resolve hostname: {e}")
        return False, None

def check_tcp_port(host_or_ip, port=3306, timeout=5):
    """Checks if a TCP port is reachable on the target host."""
    print(f"[*] TCP Port Reachability: {host_or_ip}:{port} (Timeout: {timeout}s) ...", end=" ")
    start = time.time()
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((host_or_ip, port))
        latency_ms = (time.time() - start) * 1000
        sock.close()

        if result == 0:
            print(f"[HEALTHY] Connected in {latency_ms:.2f} ms")
            return True, latency_ms
        else:
            print(f"[UNHEALTHY] Connection failed (error code: {result})")
            return False, latency_ms
    except Exception as e:
        latency_ms = (time.time() - start) * 1000
        print(f"[ERROR] Exception during connection: {e}")
        return False, latency_ms

def main():
    parser = argparse.ArgumentParser(description="Recovery-Engine Health Check Utility")
    parser.add_argument("--config", default="config/recovery-engine.yaml", help="Path to recovery-engine.yaml config")
    parser.add_argument("--target", help="Specific hostname or IP to test (overrides config)")
    parser.add_argument("--port", type=int, default=3306, help="Port to check (default: 3306)")
    parser.add_argument("--timeout", type=int, default=5, help="Socket timeout in seconds (default: 5)")
    args = parser.parse_args()

    config = load_config(args.config)
    target_hostname = args.target or config.get("route53", {}).get("record_name", "db.recovery-engine.internal")
    port = args.port or config.get("database", {}).get("port", 3306)

    print("==================================================")
    print("   RECOVERY-ENGINE: ENDPOINT HEALTH CHECK AUDIT   ")
    print("==================================================")
    print(f"Target: {target_hostname}")
    print(f"Port:   {port}")
    print("--------------------------------------------------")

    dns_ok, ip = check_dns_resolution(target_hostname)
    tcp_ok, latency = check_tcp_port(ip or target_hostname, port, args.timeout)

    print("==================================================")
    if dns_ok and tcp_ok:
        print("OVERALL HEALTH STATUS: [PASSED - ALL ENDPOINTS HEALTHY]")
        sys.exit(0)
    else:
        print("OVERALL HEALTH STATUS: [FAILED - ENDPOINT UNHEALTHY]")
        sys.exit(1)

if __name__ == "__main__":
    main()
