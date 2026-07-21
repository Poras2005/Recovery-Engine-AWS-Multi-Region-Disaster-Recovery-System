# 🌍 Recovery-Engine-AWS: Multi-Region Disaster Recovery System

[![Terraform](https://img.shields.io/badge/Terraform-%E2%89%A5%201.5.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![Python](https://img.shields.io/badge/Python-3.9+-3776AB?logo=python)](https://www.python.org/)
[![AWS Provider](https://img.shields.io/badge/AWS%20Provider-~%3E%205.0-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Config-driven, production-grade **Active-Passive Multi-Region Disaster Recovery (DR) System** built on AWS, Terraform, and Python.

---

## 🎯 Target Service Level Objectives (SLOs)

* **Target RTO (Recovery Time Objective):** $\le 10$ minutes  
  *(Measured Live Execution Time: **4.46 seconds** — **PASSED [SLO MET]**)*
* **Target RPO (Recovery Point Objective):** $\le 5$ minutes  
  *(Measured Live Replication Lag: **0.00 seconds** — **PASSED [SLO MET]**)*

---

## 🏗️ Architecture Overview
<img width="1437" height="991" alt="diagram-export-7-22-2026-2_40_12-AM" src="https://github.com/user-attachments/assets/2402917f-1b97-4081-993e-23c20d502412" />


---

## 📁 Repository Structure

```text
├── config/                         # Centralized YAML & JSON Schema configurations
│   ├── recovery-engine.yaml        # Environment configuration parameters
│   └── schema.json                 # JSON Schema structural validator
├── docs/                           # Documentation, Runbooks & Reports
│   ├── Setup_Execution_Guide.md    # Master step-by-step installation & execution guide
│   ├── Architecture_Guide.md       # Architecture diagrams & operational runbooks
│   ├── Release_Checklist.md        # Production release verification checklist
│   └── RTO_RPO_Audit_Report.md     # Generated RTO/RPO benchmark audit report
├── environments/                   # Terraform environment configurations
│   ├── dev/                        # Primary development environment entrypoint
│   └── prod_example/               # Parameterized production reference template
├── modules/                        # Reusable, parameterized Terraform modules
│   ├── iam/                        # Least-privilege IAM baseline roles & policies
│   ├── monitoring/                 # SNS topic, CloudWatch alarms & DR dashboard
│   ├── networking/                 # Multi-region VPCs, subnets, and security groups
│   ├── rds_primary/                # Multi-AZ Primary RDS MySQL instance module
│   ├── rds_replica/                # Cross-Region Read Replica RDS module
│   └── route53_failover/           # Route 53 Private Zone & CNAME failover records
└── scripts/                        # Automation & Orchestration Python/Bash scripts
    ├── run_failover.sh             # Master CLI runner wrapper script
    ├── failover_orchestrator.py    # Main failover engine (status, dry-run, execute)
    ├── health_check.py             # Route 53 API & TCP port reachability auditor
    ├── failback.py                 # Traffic failback controller
    ├── monitor_dr.py               # Real-time CloudWatch terminal telemetry monitor
    ├── simulate_alarm.py           # Alarm trigger & SNS notification testing tool
    ├── chaos_simulator.py          # Chaos engineering scenario simulator
    ├── rto_rpo_audit.py            # RTO/RPO SLA measurement & report generator
    ├── run_dr_drill.py             # End-to-end automated Game-Day DR Drill runner
    ├── config_validator.py         # YAML config & zero-hardcoding auditor
    ├── audit_hardcoding.py         # Terraform hardcoding scanner
    └── module_cleanup_audit.py     # Terraform module quality & documentation auditor
```

---

## 📋 Completed Modules Roadmap

- [x] **Module 1 — Foundation & Networking:** Multi-region VPCs, subnets, IAM baseline, directory structure
- [x] **Module 2 — Data Layer:** RDS MySQL Primary (Mumbai) + Cross-Region Read Replica (Singapore) + promotion engine
- [x] **Module 3 — Failover Routing:** Route53 Private Hosted Zone + Failover routing policy & health checks
- [x] **Module 4 — Failover Orchestration:** Dry-run capable Python failover orchestrator, health checker & failback controller
- [x] **Module 5 — Monitoring & Alerting:** CloudWatch alarms, SNS topic, CloudWatch dashboard, and alarm simulation testing
- [x] **Module 6 — Validation:** Chaos scenario simulator, RTO/RPO audit reporter, and automated Game-Day DR drill orchestrator
- [x] **Module 7 — Config-Driven Packaging:** YAML loader, JSON Schema validator, zero-hardcoding scanner, & multi-environment reference packaging (`environments/prod_example`)
- [x] **Module 8 — Documentation & Polish:** Master setup guide ([`docs/Setup_Execution_Guide.md`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/docs/Setup_Execution_Guide.md)), architecture diagrams ([`docs/Architecture_Guide.md`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/docs/Architecture_Guide.md)), & release checklist ([`docs/Release_Checklist.md`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/docs/Release_Checklist.md))

---

## 🚀 Getting Started

### Prerequisites
* [Terraform](https://www.terraform.io/) $\ge$ 1.5.0
* [AWS CLI](https://aws.amazon.com/cli/) configured with valid IAM credentials
* [Python](https://www.python.org/) $\ge$ 3.9 + `boto3`, `pyyaml`, `jsonschema`

```bash
# 1. Install dependencies (Ubuntu)
sudo apt update && sudo apt install -y python3 python3-pip awscli terraform
pip3 install boto3 pyyaml jsonschema

# 2. Make CLI runner executable
chmod +x scripts/*.sh

# 3. Audit configuration and Terraform code
./scripts/run_failover.sh validate-config
./scripts/run_failover.sh audit-tf
./scripts/run_failover.sh audit-modules

# 4. Deploy Infrastructure (environments/dev)
cd environments/dev
terraform init
terraform apply -auto-approve
cd ../..
```

---

## 🕹️ CLI Runner Master Quick Reference

All system operations can be invoked using `./scripts/run_failover.sh`:

| Command | Category | Description |
| :--- | :--- | :--- |
| `./scripts/run_failover.sh validate-config` | **Security / Quality** | Validates `recovery-engine.yaml` against JSON Schema & zero-hardcoding rules |
| `./scripts/run_failover.sh audit-tf` | **Security / Quality** | Scans Terraform files for hardcoded account IDs, ARNs, or VPC IDs |
| `./scripts/run_failover.sh audit-modules` | **Security / Quality** | Audits all 6 Terraform modules for HashiCorp file structure & variable docs |
| `./scripts/run_failover.sh status` | **Status / Audit** | Audits AWS STS identity, Primary DB, Secondary Replica, & ReplicaLag |
| `./scripts/run_failover.sh check` | **Status / Audit** | Performs Route53 Private Hosted Zone API lookup & TCP port 3306 audit |
| `./scripts/run_failover.sh monitor` | **Telemetry** | Launches real-time auto-refreshing CloudWatch terminal telemetry monitor |
| `./scripts/run_failover.sh alarms` | **Alerting** | Lists all CloudWatch DR alarms & their current states (`OK`/`ALARM`) |
| `./scripts/run_failover.sh test-alert` | **Alerting** | Simulates firing a CloudWatch Alarm to test SNS alert notifications |
| `./scripts/run_failover.sh reset-alerts` | **Alerting** | Resets all CloudWatch DR alarms back to `OK` state |
| `./scripts/run_failover.sh chaos-db` | **Chaos / Drills** | Simulates Chaos Scenario 1: Primary Database Outage (Dry-Run) |
| `./scripts/run_failover.sh chaos-lag` | **Chaos / Drills** | Simulates Chaos Scenario 2: Replication Lag Spike > 300s (Dry-Run) |
| `./scripts/run_failover.sh chaos-region` | **Chaos / Drills** | Simulates Chaos Scenario 3: Total Primary Region Outage (Dry-Run) |
| `./scripts/run_failover.sh gameday` | **Chaos / Drills** | Executes end-to-end automated Game-Day DR Drill Simulation |
| `./scripts/run_failover.sh dry-run` | **Failover** | Simulates step-by-step failover execution without changing infrastructure |
| `./scripts/run_failover.sh execute` | **Failover** | Promotes secondary RDS & switches Route53 DNS target live |
| `./scripts/run_failover.sh failback` | **Failover** | Restores Route53 DNS traffic back to Primary Region (Mumbai) |
| `./scripts/run_failover.sh audit` | **SLA Reporting** | Calculates measured RTO/RPO & generates Markdown report at `docs/RTO_RPO_Audit_Report.md` |

---

## 🧹 Infrastructure Teardown

To avoid unnecessary AWS sandbox charges after testing:

```bash
cd environments/dev
terraform destroy -auto-approve
```

---


