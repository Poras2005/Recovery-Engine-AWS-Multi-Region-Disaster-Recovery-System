# 🌍 Recovery-Engine-AWS: Architecture & Operational Runbook

Reference implementation for a production-grade **Active-Passive Multi-Region Disaster Recovery System** built on AWS, Terraform, and Python.

---

## 🎯 Target Service Level Objectives (SLOs)

* **Target RTO (Recovery Time Objective):** $\le 10$ minutes  
  *(Measured time from outage detection to database replica promotion, Route53 DNS cutover, and endpoint reachability restoration)*
* **Target RPO (Recovery Point Objective):** $\le 5$ minutes  
  *(Maximum acceptable data loss window based on RDS Cross-Region Replication lag)*

---

## 🏗️ System Architecture Diagrams

### 1. Multi-Region Active-Passive Architecture

```mermaid
flowchart TD
    Client[Application Client / User] --> R53[Route 53 Private Hosted Zone\ndb.recovery-engine.internal]
    
    subgraph MUM["Primary Region (ap-south-1: Mumbai)"]
        R53 -->|Primary CNAME Record| MUM_DB[(Primary RDS MySQL\nrecovery-engine-primary-db)]
        MUM_VPC[Mumbai VPC\n10.10.0.0/16] --- MUM_DB
        MUM_CW[CloudWatch Alarms\nCPU & FreeStorage] --- MUM_DB
    end

    subgraph SGP["Secondary DR Region (ap-southeast-1: Singapore)"]
        R53 -.->|Failover CNAME Record| SGP_DB[(Cross-Region Read Replica\nrecovery-engine-replica-db)]
        SGP_VPC[Singapore VPC\n10.20.0.0/16] --- SGP_DB
        SGP_CW[CloudWatch Alarm\nReplicaLag > 300s] --- SGP_DB
    end

    MUM_DB -.->|Async Cross-Region Replication| SGP_DB
    SNS[SNS DR Alert Topic\nrecovery-engine-dr-alerts] <--> MUM_CW
    SNS <--> SGP_CW
```

---

### 2. Disaster Recovery Failover Sequence

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant R53 as Route 53 DNS
    participant Primary as Primary RDS (Mumbai)
    participant Replica as Read Replica (Singapore)
    participant Orchestrator as Failover Orchestrator

    Client->>R53: Query db.recovery-engine.internal
    R53-->>Client: Returns Primary DB Endpoint (Mumbai)
    Client->>Primary: Read/Write Traffic

    Note over Primary: Primary Region Outage Occurs!
    Primary--xClient: Connection Timeout

    Orchestrator->>Primary: Audit Status & STS Pre-flight
    Orchestrator->>Replica: Check Replication Lag (RPO Check)
    Orchestrator->>Replica: Promote Read Replica to Standalone Primary
    Replica-->>Orchestrator: Instance Status: AVAILABLE

    Orchestrator->>R53: UPSERT CNAME db.recovery-engine.internal -> Singapore Endpoint
    R53-->>Orchestrator: Change Complete (RTO <= 10 min)

    Client->>R53: Query db.recovery-engine.internal
    R53-->>Client: Returns Secondary DB Endpoint (Singapore)
    Client->>Replica: Resume Traffic (DR Active)
```

---

## 📂 Repository Module Architecture

| Module | Location | Purpose & Features |
| :--- | :--- | :--- |
| **Module 1 — Foundation** | [`modules/networking`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/modules/networking), [`modules/iam`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/modules/iam) | Multi-Region VPCs, public/private subnets, IAM baseline roles & policies. |
| **Module 2 — Data Layer** | [`modules/rds_primary`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/modules/rds_primary), [`modules/rds_replica`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/modules/rds_replica) | RDS MySQL Primary (Mumbai) + Cross-Region Read Replica (Singapore). |
| **Module 3 — Failover Routing** | [`modules/route53_failover`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/modules/route53_failover) | Private Hosted Zone (`recovery-engine.internal`) & CNAME failover policy records. |
| **Module 4 — Orchestration** | [`scripts/failover_orchestrator.py`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/scripts/failover_orchestrator.py) | Live Python failover engine, health verification, and failback controller. |
| **Module 5 — Monitoring** | [`modules/monitoring`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/modules/monitoring) | SNS topic, CloudWatch CPU/Storage/ReplicaLag alarms & multi-region dashboard. |
| **Module 6 — Validation** | [`scripts/chaos_simulator.py`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/scripts/chaos_simulator.py) | Chaos scenario simulator, RTO/RPO audit reporter, and Game-Day drill orchestrator. |
| **Module 7 — Packaging** | [`config/schema.json`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/config/schema.json) | JSON Schema loader, zero-hardcoding scanner, and `environments/prod_example`. |

---

## 🕹️ Standard Operating Procedures (SOPs)

### 1. Pre-Deployment Validation
```bash
# Validate configuration schema and audit zero-hardcoding compliance
./scripts/run_failover.sh validate-config
./scripts/run_failover.sh audit-tf
./scripts/run_failover.sh audit-modules
```

### 2. Multi-Region Health Audit
```bash
./scripts/run_failover.sh status
./scripts/run_failover.sh check
```

### 3. Automated Game-Day DR Drill Simulation
```bash
./scripts/run_failover.sh gameday
```

### 4. RTO & RPO Benchmark Report Generation
```bash
./scripts/run_failover.sh audit
```
*(Generates markdown report at [`docs/RTO_RPO_Audit_Report.md`](file:///D:/Projects/Recovery-Engine-AWS%20Multi-Region%20Disaster%20Recovery%20System/docs/RTO_RPO_Audit_Report.md))*

---

## 💰 Cost Optimization & Teardown Policy

* **Database Engine:** `db.t4g.micro` (eligible for AWS Free Tier).
* **Teardown Command:** Always tear down sandbox infrastructure when drills complete:
  ```bash
  cd environments/dev
  terraform destroy -auto-approve
  ```
