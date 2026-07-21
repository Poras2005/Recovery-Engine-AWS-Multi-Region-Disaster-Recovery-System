# Recovery-Engine-AWS: Multi-Region Disaster Recovery System

Config-driven multi-region disaster recovery reference implementation built with AWS, Terraform, and Python.

## 🎯 Target Service Level Objectives (SLOs)
* **Target RTO (Recovery Time Objective):** $\le$ 10 minutes (Time to detect, promote replica, update DNS, restore reachability)
* **Target RPO (Recovery Point Objective):** $\le$ 5 minutes (Maximum acceptable data loss window based on replication lag)

---

## 🏗️ Architecture Overview

```
+------------------------------------+           +------------------------------------+
|   PRIMARY REGION (ap-south-1)      |           |    SECONDARY REGION (ap-southeast-1)|
|              (Mumbai)              |           |            (Singapore)             |
|                                    |           |                                    |
|   +----------------------------+   |  Async    |   +----------------------------+   |
|   | RDS Primary (Multi-AZ)     |===|===========|==>| RDS Cross-Region Replica   |   |
|   +----------------------------+   |  Repl.    |   +----------------------------+   |
|                 ^                  |           |                 ^                  |
|                 |                  |           |                 |                  |
|   +----------------------------+   |           |   +----------------------------+   |
|   | Primary VPC (Subnets, SGs) |   |           |   | Secondary VPC(Subnets, SGs)|   |
|   +----------------------------+   |           |   +----------------------------+   |
+------------------------------------+           +------------------------------------+
                   ^                                                ^
                   |               Route53 Private Zone             |
                   +------------------ (Failover) ------------------+
                                             |
                                 +-----------------------+
                                 |  Python Orchestrator  |
                                 +-----------------------+
```

---

## 📁 Repository Structure

```text
├── config/                # YAML configuration files for the recovery engine
├── docs/                  # Architecture & RTO/RPO report documentation
├── environments/          # Terraform environment configurations
│   └── dev/               # Development environment entrypoint
├── modules/               # Reusable, parameterized Terraform modules
│   ├── iam/               # IAM baseline roles & permissions
│   └── networking/        # Multi-region VPCs, subnets, and security groups
└── scripts/               # Failover orchestrator & helper Python scripts
```

---

## 🚀 Getting Started

### Prerequisites
* [Terraform](https://www.terraform.io/) $\ge$ 1.5.0
* [AWS CLI](https://aws.amazon.com/cli/) configured with valid credentials
* [Python](https://www.python.org/) $\ge$ 3.9 + `boto3`

---

## 📋 Project Modules Roadmap

- [x] **Module 1 — Foundation & Networking:** Multi-region VPCs, subnets, IAM baseline, directory structure
- [x] **Module 2 — Data Layer:** RDS MySQL/PostgreSQL Primary + Cross-Region Read Replica & promotion script
- [x] **Module 3 — Failover Routing:** Route53 Private Hosted Zone + Failover routing policy & health checks
- [x] **Module 4 — Failover Orchestration:** Dry-run capable Python failover orchestrator & CLI runner
- [ ] **Module 5 — Monitoring & Alerting:** CloudWatch alarms, SNS alerting, and Grafana dashboard
- [ ] **Module 6 — Validation:** Chaos scenario execution & RTO/RPO calculation report
- [ ] **Module 7 — Config-Driven Packaging:** YAML loader, schema validation, zero-hardcode audit
- [ ] **Module 8 — Documentation & Polish:** Demo walk-through & final release

---

### 🕹️ Orchestration & CLI Execution
```bash
# 1. Audit status across Mumbai & Singapore
./scripts/run_failover.sh status

# 2. Run socket TCP & DNS health check
./scripts/run_failover.sh check

# 3. Simulate step-by-step dry-run failover
./scripts/run_failover.sh dry-run

# 4. Trigger live failover execution
./scripts/run_failover.sh execute

# 5. Failback traffic to primary region
./scripts/run_failover.sh failback
```




