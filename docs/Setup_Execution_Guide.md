# 📖 Recovery-Engine-AWS: Complete Setup & Execution Master Guide

This comprehensive guide covers the complete setup, deployment, testing, monitoring, chaos engineering, failover execution, failback, and teardown of the **AWS Multi-Region Disaster Recovery System (`Recovery-Engine-AWS`)**.

---

## 🏛️ System Architecture Summary

* **Primary Region:** Mumbai (`ap-south-1`) — Active Workload & Multi-AZ Primary RDS MySQL.
* **Secondary (DR) Region:** Singapore (`ap-southeast-1`) — Standby Workload & Cross-Region Read Replica.
* **DNS Failover:** Route 53 Private Hosted Zone (`recovery-engine.internal`).
* **Target SLOs:**
  * **RTO (Recovery Time Objective):** $\le 10$ minutes *(Live Verified: **4.46s**)*
  * **RPO (Recovery Point Objective):** $\le 5$ minutes *(Live Verified: **0.00s**)*

---

## 💻 1. Prerequisites & Tooling Installation (Ubuntu VM)

Open your Ubuntu OS terminal and run:

```bash
# 1. Update system packages
sudo apt update && sudo apt upgrade -y

# 2. Install Python 3, pip, and required libraries
sudo apt install -y python3 python3-pip
pip3 install boto3 pyyaml jsonschema

# 3. Install AWS CLI
sudo apt install -y awscli

# 4. Install HashiCorp Terraform (>= 1.5.0)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
```

---

## 🔑 2. Configure AWS Credentials

Configure your AWS IAM credentials in the shell:

```bash
aws configure
```
* **AWS Access Key ID:** `[Your Access Key]`
* **AWS Secret Access Key:** `[Your Secret Key]`
* **Default region name:** `ap-south-1`
* **Default output format:** `json`

Verify authentication using AWS STS:
```bash
aws sts get-caller-identity
```

---

## 🔍 3. Pre-Deployment Configuration & Quality Audits

Navigate to the project root and make all scripts executable:

```bash
chmod +x scripts/*.sh
```

### Audit 1: Validate YAML Configuration against JSON Schema
Validates `config/recovery-engine.yaml` against `config/schema.json`:
```bash
./scripts/run_failover.sh validate-config
```

### Audit 2: Scan Terraform Code for Zero-Hardcoding
Scans all `.tf` files to ensure no hardcoded Account IDs, ARNs, or VPC IDs exist:
```bash
./scripts/run_failover.sh audit-tf
```

### Audit 3: Audit Terraform Module Quality & Hygiene
Verifies file structures (`main.tf`, `variables.tf`, `outputs.tf`) and variable descriptions across all 6 modules:
```bash
./scripts/run_failover.sh audit-modules
```

---

## 🏗️ 4. Deploy Infrastructure (Modules 1, 2, 3 & 5)

Navigate to the development environment folder and apply Terraform:

```bash
cd environments/dev

# Initialize Terraform plugins
terraform init

# Review infrastructure plan
terraform plan

# Deploy Multi-Region Infrastructure
terraform apply -auto-approve
```

> **Note:** Provisioning multi-region VPCs, RDS Primary (Mumbai), Cross-Region Read Replica (Singapore), Route53 Private Hosted Zone, CloudWatch Alarms, and Dashboard takes **10–12 minutes**.

Navigate back to the project root:
```bash
cd ../..
```

---

## 📊 5. Audit Multi-Region System Status & Health

### 1. Multi-Region Status & Replication Lag Audit
Checks AWS STS identity, Primary DB status, Secondary Replica status, and CloudWatch `ReplicaLag`:
```bash
./scripts/run_failover.sh status
```

### 2. Route53 Private Hosted Zone & Endpoint Health Check
Queries Route53 API and verifies private zone records:
```bash
./scripts/run_failover.sh check
```

---

## 📈 6. Monitoring, Telemetry & Alarm Simulation

### 1. Launch Real-Time CLI Telemetry Dashboard
Launches a live auto-refreshing terminal dashboard:
```bash
./scripts/run_failover.sh monitor
```
*(Press `Ctrl+C` to exit)*

### 2. List All CloudWatch DR Alarms
```bash
./scripts/run_failover.sh alarms
```

### 3. Simulate Firing a CloudWatch Alarm (Tests SNS Alerts)
```bash
./scripts/run_failover.sh test-alert
```

### 4. Reset All Alarms Back to Normal (`OK`)
```bash
./scripts/run_failover.sh reset-alerts
```

---

## 🧪 7. Chaos Engineering & Game-Day DR Drills

### 1. Chaos Scenario 1: Primary Database Outage Simulation
```bash
./scripts/run_failover.sh chaos-db
```

### 2. Chaos Scenario 2: Replication Lag Spike Simulation (> 300s)
```bash
./scripts/run_failover.sh chaos-lag
```

### 3. Chaos Scenario 3: Total Primary Region Outage Simulation
```bash
./scripts/run_failover.sh chaos-region
```

### 4. Run Automated End-to-End Game-Day DR Drill
Executes pre-flight check, chaos injection, failover cutover, RTO audit, and failback in a single pipeline:
```bash
./scripts/run_failover.sh gameday
```

---

## 🚀 8. Failover Execution, Failback & RTO/RPO Audit

### 1. Run Dry-Run Failover Simulation
```bash
./scripts/run_failover.sh dry-run
```

### 2. Execute Live Production Failover
Promotes secondary replica in Singapore and switches Route 53 CNAME target:
```bash
./scripts/run_failover.sh execute
```

### 3. Verify Post-Failover Reachability
```bash
./scripts/run_failover.sh check
```

### 4. Execute Failback (Restore Traffic to Primary Region)
Returns Route 53 CNAME target back to Mumbai:
```bash
./scripts/run_failover.sh failback
```

### 5. Generate RTO & RPO Benchmark Audit Report
Calculates exact RTO/RPO timing and generates a Markdown report at `docs/RTO_RPO_Audit_Report.md`:
```bash
./scripts/run_failover.sh audit
```

---

## 🧹 9. Clean Teardown (Prevent AWS Charges)

When you finish your testing or demo session, destroy all AWS resources to keep your account free of unexpected charges:

```bash
cd environments/dev
terraform destroy -auto-approve
```

---

### 📋 CLI Quick Reference Card

| Command | Action |
| :--- | :--- |
| `./scripts/run_failover.sh validate-config` | Validates YAML config against JSON Schema |
| `./scripts/run_failover.sh audit-tf` | Scans Terraform code for zero-hardcoding compliance |
| `./scripts/run_failover.sh audit-modules` | Audits Terraform modules for HashiCorp quality |
| `./scripts/run_failover.sh status` | Audits AWS STS identity, RDS status & ReplicaLag |
| `./scripts/run_failover.sh check` | Performs Route 53 API private zone lookup & TCP audit |
| `./scripts/run_failover.sh monitor` | Launches live CloudWatch telemetry dashboard |
| `./scripts/run_failover.sh alarms` | Lists all CloudWatch DR alarms & their states |
| `./scripts/run_failover.sh test-alert` | Simulates CloudWatch alarm trigger to test SNS alerts |
| `./scripts/run_failover.sh reset-alerts` | Resets all CloudWatch DR alarms back to `OK` state |
| `./scripts/run_failover.sh chaos-db` | Simulates Primary DB outage (Scenario 1) |
| `./scripts/run_failover.sh chaos-lag` | Simulates Replication Lag Spike >300s (Scenario 2) |
| `./scripts/run_failover.sh chaos-region` | Simulates Total Primary Region outage (Scenario 3) |
| `./scripts/run_failover.sh gameday` | Executes end-to-end automated Game-Day DR Drill |
| `./scripts/run_failover.sh dry-run` | Simulates step-by-step failover execution |
| `./scripts/run_failover.sh execute` | Promotes secondary RDS & switches Route 53 DNS live |
| `./scripts/run_failover.sh failback` | Restores Route 53 DNS traffic back to Primary Region |
| `./scripts/run_failover.sh audit` | Generates RTO & RPO compliance audit report (Markdown) |
