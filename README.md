# AWS Multi-Region Disaster Recovery System

A cloud-native disaster recovery platform built on AWS to simulate multi-region failover, automated infrastructure provisioning, and resilient application deployment using Infrastructure as Code (IaC) and DevOps practices.

This project demonstrates practical implementation of:
- Multi-region deployment architecture
- Route 53 DNS or CloudFront Origin Group failover
- Cross-region database replication
- Infrastructure automation with Terraform
- Containerized microservices
- CI/CD security validation
- Cloud monitoring and failover testing


---

# Architecture Overview

The system deploys application infrastructure across two AWS regions in an active-passive disaster recovery setup.

## Core Components

- AWS EC2 instances for application hosting (Free Tier optimized, no NAT Gateway costs)
- Auto Scaling Groups for workload resilience
- Elastic Load Balancers for traffic distribution
- CloudFront Origin Groups or Route 53 health checks & DNS failover
- Cross-region Single-AZ Amazon RDS replication
- Dockerized Flask microservice
- Terraform-based infrastructure provisioning
- GitHub Actions CI/CD workflows
- CloudWatch monitoring and alerting


---

# Tech Stack

| Category | Technologies |
|---|---|
| Cloud Platform | AWS |
| Infrastructure as Code | Terraform |
| Containerization | Docker |
| Backend | Flask (Python) |
| CI/CD | GitHub Actions |
| Security Scanning | Checkov, Trivy |
| Monitoring | AWS CloudWatch |
| DNS & Failover | Route53 |
| Database | Amazon RDS |

---

# Key Features

## Multi-Region Failover

Implemented CloudFront Origin Group failover (domain-less) and Route 53 DNS failover (custom domain) between primary and secondary AWS regions using automated health checks and traffic redirection.


## Infrastructure Automation

Provisioned AWS infrastructure using reusable Terraform modules for networking, compute, database, and monitoring resources.

## Containerized Application Deployment

Built and deployed a Dockerized Flask microservice with:
- Region-aware API responses
- Health-check endpoints
- Structured application logging
- Database-backed request simulation

## CI/CD Validation Pipeline

Integrated GitHub Actions workflows for:
- Terraform validation
- Security scanning using Checkov
- Container vulnerability scanning using Trivy
- Automated deployment workflows

## Monitoring & Observability

Configured CloudWatch monitoring for:
- EC2 instance health
- Application availability
- Infrastructure events
- Failover simulation testing

---

# Project Structure

```bash
.
├── terraform/
│   ├── global/         # Route 53 & CloudFront global config
│   ├── modules/        # Reusable VPC, EC2, RDS, Monitoring modules
│   └── regions/        # Regional configs (mumbai, singapore)
│
├── app/
│   ├── Dockerfile
│   ├── app.py          # Flask app code
│   └── requirements.txt
│
├── deploy.sh           # Master deployment orchestrator (Bash)
├── config.yaml         # Configuration parameters
│
├── .github/workflows/  # CI/CD pipelines
│
└── scripts/            # Operational Bash scripts (teardown, spinup, failover, promotion)
```

---

# Deployment Workflow

1. Provision AWS infrastructure using Terraform
2. Build and containerize Flask application
3. Deploy workloads to primary AWS region (Mumbai)
4. Configure CloudFront Origin Group (or Route 53 failover)
5. Enable cross-region RDS replication (Singapore replica)
6. Validate failover using simulated outages (ASG scale-down)


---

# Disaster Recovery Workflow

## Normal Operation
- Primary region handles application traffic
- Secondary region remains on standby
- Route53 continuously monitors endpoint health

## Failover Scenario
- CloudFront/Route 53 detects application failure
- Traffic automatically redirects to the secondary region (Singapore)
- Secondary infrastructure serves application traffic


---

# Validation & Testing

The project was tested using simulated application and infrastructure failures.

### Tested Scenarios

- EC2 application shutdown
- Health-check failure simulation
- CloudFront Origin Group / Route 53 failover behavior
- Terraform infrastructure recreation
- CI/CD security validation workflows


### Observations

- DNS failover response observed within approximately 45–70 seconds depending on DNS propagation behavior
- Infrastructure redeployment successfully validated using Terraform automation
- Security scans detected vulnerable container dependencies during CI/CD testing

---

# Security Practices

Implemented several foundational cloud security practices:

- IAM role-based access control
- AWS Secrets Manager integration
- Infrastructure security scanning using Checkov
- Container image vulnerability scanning using Trivy
- Principle of least privilege for service permissions

---

# Current Limitations

This project is designed as a learning-focused disaster recovery implementation and has several limitations:

- Uses active-passive failover instead of active-active architecture
- Terraform state is currently stored locally
- Limited application-level observability
- Database replication lag may affect immediate consistency during failover
- Failover timing depends on DNS TTL and health-check intervals

---

# Future Improvements

Potential enhancements include:

- Remote Terraform state management using S3 + DynamoDB locking
- Kubernetes-based deployment architecture
- Centralized logging with Grafana Loki or ELK Stack
- Blue/Green deployment strategy
- Automated rollback workflows
- Chaos engineering-based failure testing
- Prometheus and Grafana integration

---

- GitHub: https://github.com/Poras2005
- LinkedIn: [Add LinkedIn URL]
