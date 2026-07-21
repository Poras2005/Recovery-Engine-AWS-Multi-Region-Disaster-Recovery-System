# Recovery-Engine-AWS: Multi-Region Disaster Recovery System
### Solo Project Plan & Module Breakdown

---

## 0. Locked MVP Scope (read this first)

Do NOT build all of these at once: DynamoDB DR + S3 CRR + EBS snapshots + Step Functions + chaos engineering + CLI + Helm chart + compliance PDF generator. That is a team-sized scope. As a solo builder, cut to this:

| Pillar | In scope for v1 | Deferred to "Roadmap" section |
|---|---|---|
| Data layer | RDS Multi-AZ + cross-region read replica | DynamoDB Global Tables, S3 CRR |
| Failover | Route53 health-check DNS failover | Step Functions orchestration |
| Orchestration | Python controller script | Full state machine |
| Detection | CloudWatch alarms + SNS | Custom Prometheus exporters (nice-to-have, not required) |
| Validation | 1 chaos scenario + RTO/RPO measurement | Automated scheduled game-days |
| Packaging | Terraform modules + YAML config | CLI tool, Helm chart |

Documenting the deferred items as a clear "Phase 2 Roadmap" in your README is itself a positive signal — it shows scoping discipline, which is what senior engineers actually check for.

**Honest positioning note:** This is a **config-driven reference implementation**, not a proven "reusable framework." It's been built and tested by you, in your own sandbox account, and has not been run by anyone else. Don't claim "reusable for any user" anywhere — claim that it's parameterized and hardcoding-free by design, which is true and still a strong signal on its own. See the interview prep doc for exact wording.

**Target RTO:** ≤ 10 minutes (time to restore service)
**Target RPO:** ≤ 5 minutes (max acceptable data loss)
Define these BEFORE building failover — without a target, you can't prove you hit anything.

---

## 1. Harsh Risk Review

- **Cost risk:** cross-region read replicas + NAT gateways + data transfer charges add up fast. Set a AWS Budget alarm at $15-20 before you start, use `db.t3.micro`/`t4g.micro` only, and tear down infra after each work session (`terraform destroy`) rather than leaving it running.
- **Don't claim "reusable for anyone" — you haven't proven that.** No one else has run this. What you CAN honestly claim: every module takes inputs via `variables.tf` and a top-level `recovery-engine.yaml`, with zero hardcoded ARNs/account IDs/VPC IDs. That's a real, verifiable design choice — "config-driven by design," not "proven reusable."
- **Chaos testing on your own sandbox account only** — never simulate outages against anything with real traffic. Use a dedicated AWS Free Tier / sandbox account.
- **RTO/RPO numbers must come from actual test runs, not estimates.** Log real timestamps: alarm fired → replica promoted → DNS updated → app reachable. Fabricated numbers are the single fastest way to lose credibility in an interview.
- **Don't over-engineer the orchestration.** A well-logged Python script that does the failover sequence correctly beats a half-built Step Functions state machine every time for a solo v1.

---

## 2. Suggested Timeline (solo, ~10-15 hrs/week)

| Week | Focus |
|---|---|
| 1 | Module 1: Foundation (networking, IAM, base Terraform structure) |
| 2 | Module 2: RDS primary + replica setup |
| 3 | Module 3: Route53 failover + health checks |
| 4 | Module 4: Failover orchestration script |
| 5 | Module 5: Monitoring & alerting |
| 6 | Module 6: Chaos test + RTO/RPO measurement |
| 7 | Module 7: Config-driven packaging (YAML + module cleanup) |
| 8 | Module 8: Docs, README, dashboard polish, demo recording |

~8 weeks part-time. Compress to ~4 weeks if full-time.

---

## 3. Module Breakdown

### Module 1 — Foundation & Networking
**Goal:** A clean, parameterized Terraform base every other module builds on.

**Tasks:**
1. **Repo structure setup**
   - Create `modules/`, `environments/`, `scripts/`, `config/`, `docs/` folders
   - Set up remote state (S3 backend + DynamoDB lock table) — ironically your first real use of DynamoDB in this project
   - Add `.gitignore`, `terraform.tfvars.example`, README skeleton
2. **Networking module**
   - VPC + subnets in primary region (parameterized CIDR via variables)
   - VPC + subnets in secondary/DR region
   - Security groups for RDS, bastion/SSM access
3. **IAM baseline**
   - Least-privilege IAM role for the failover Lambda/script
   - IAM role for GitHub Actions (OIDC, not long-lived keys)

**Deliverable:** `terraform apply` stands up networking in two regions from one config file, zero hardcoded values.

---

### Module 2 — Data Layer (RDS Cross-Region Replication)
**Goal:** Primary RDS instance with a working cross-region read replica.

**Tasks:**
1. **Primary RDS module**
   - Multi-AZ RDS instance (MySQL or Postgres — pick one, your call given SQL background)
   - Parameterized instance class, storage, backup retention via variables
   - Enable automated backups (required for cross-region replica creation)
2. **Cross-region replica module**
   - Read replica in DR region, created via Terraform (`aws_db_instance` with `replicate_source_db`)
   - Validate replication lag via CloudWatch metric `ReplicaLag`
3. **Promotion logic (script, not just console)**
   - Python/boto3 script: `promote_replica.py` — promotes replica to standalone primary
   - Test manually once before wiring into orchestration (Module 4)

**Deliverable:** Working primary + replica, promotion script tested manually with logged before/after state.

---

### Module 3 — Failover Routing (Route53)
**Goal:** DNS automatically points at whichever region is healthy.

**No public domain required.** Use a Route53 **private hosted zone** — resolves only inside your VPC, costs ~$0.50/month, and proves the exact same failover mechanics as a public domain would. Note this choice explicitly in the README as a deliberate, cost-conscious design decision, not a limitation.

**Tasks:**
1. **Private hosted zone setup**
   - Create a private hosted zone (e.g., `recovery-engine.internal`) via Terraform (`aws_route53_zone` with `vpc` block)
   - Associate it with both the primary and DR region VPCs (cross-region VPC association requires an authorization step — `aws_route53_vpc_association_authorization` in the owning region, then `aws_route53_zone_association` in the associating region)
2. **Health checks**
   - Route53 health check hitting an app-layer or RDS-proxy endpoint (not just ping — check something that reflects real DB availability)
   - Configure failure threshold / interval (balance false positives vs detection speed)
3. **Failover routing policy**
   - Primary + secondary record sets with `failover` routing policy inside the private zone
   - Test resolution from an EC2/SSM session inside the VPC using `dig` or `nslookup` (public DNS tools won't see this zone — that's expected)
   - Test failover by manually failing the health check endpoint and timing the DNS switch
4. **Terraform module packaging**
   - `modules/route53-failover` — takes primary/secondary endpoint + zone ID as variables, no hardcoded values
   - Add a variable/flag so someone WITH a public domain can swap in a public hosted zone instead — a design choice that keeps the module flexible, not proof it's been used that way

**Deliverable:** Killing the primary endpoint causes DNS to switch to secondary within your defined RTO window, verified via `dig` from inside the VPC — timed and logged. README notes: "tested via Route53 private hosted zone; swap in a public hosted zone for production use with an owned domain."

---

### Module 4 — Failover Orchestration
**Goal:** One script that sequences the whole failover safely, with a dry-run mode.

**Tasks:**
1. **Orchestrator script (Python)**
   - Step sequence: detect failure → validate secondary health → promote replica → update Route53 → send notification
   - Each step logs a timestamp (this is your RTO/RPO data source)
2. **Dry-run mode**
   - `--dry-run` flag: logs what would happen without executing (critical for demoing safely and for interview walkthroughs)
3. **Idempotency & safety checks**
   - Prevent double-promotion (check current replica state before acting)
   - Rollback/abort path if a step fails mid-sequence

**Deliverable:** `python orchestrator.py --dry-run` and `python orchestrator.py --execute` both work and produce a timestamped log file.

---

### Module 5 — Monitoring, Alerting & Dashboard
**Goal:** Visibility into DR posture at all times, not just during a test.

**Tasks:**
1. **CloudWatch alarms**
   - RDS replication lag threshold alarm
   - Primary instance health/CPU/connection alarms
   - Route53 health check status alarm
2. **SNS notification pipeline**
   - SNS topic → email/Slack webhook
   - Templated message with severity (INFO/WARN/CRITICAL)
3. **Grafana dashboard**
   - Panels: replication lag over time, last successful backup age, failover history log, current active region indicator
   - Data source: CloudWatch (via Grafana's CloudWatch plugin) — no need for a separate Prometheus exporter unless you want the extra polish later

**Deliverable:** A screenshot-able Grafana dashboard + a test alert that actually fires and reaches Slack/email.

---

### Module 6 — Validation: Chaos Test & RTO/RPO Report
**Goal:** Prove the system works with real, logged numbers. This is the module that makes the whole project credible.

**Tasks:**
1. **Chaos scenario design**
   - Pick ONE scenario: e.g., stop the primary RDS instance (in sandbox account only)
   - Document expected vs actual behavior before running
2. **Execute & measure**
   - Run the failure injection
   - Capture timestamps: failure induced → alarm fired → orchestrator triggered → replica promoted → DNS updated → app reachable in DR region
3. **RTO/RPO calculator**
   - Small script that parses the orchestrator log and computes actual RTO (time to recover) and RPO (data loss window, based on last replicated transaction vs failure time)
   - Output a simple markdown/JSON report

**Deliverable:** A real report: "Target RTO: 10 min / Actual RTO: X min. Target RPO: 5 min / Actual RPO: Y min." This single artifact is your best resume bullet.

---

### Module 7 — Config-Driven Packaging
**Goal:** Make the config-driven design explicit and demonstrable — not to prove it's reusable (you can't prove that alone), but to show the pattern clearly enough that the intent is obvious.

**Tasks:**
1. **`recovery-engine.yaml` schema**
   - User defines: regions, VPC CIDRs, RDS engine/size, notification endpoints, RTO/RPO targets
   - Write a small Python loader that validates the YAML against a schema before generating `terraform.tfvars`
2. **Module cleanup audit**
   - Go through every `.tf` file, confirm zero hardcoded ARNs/IDs — everything flows from variables
   - Add `README.md` per module explaining inputs/outputs
3. **Example environment**
   - `environments/example/` showing a fictitious company's config, to illustrate how the pattern would be adapted (illustrative only — you haven't verified it works end-to-end for a real third party)

**Deliverable:** A YAML-driven config layer where the intended adaptation path is clear from the code and docs. Frame this in your README/resume as "designed for portability" — not as a validated claim that others have used it.

---

### Module 8 — Documentation, Demo & Polish
**Goal:** Package the work so it reads well to a recruiter/interviewer in under 2 minutes.

**Tasks:**
1. **README**
   - Architecture diagram (draw.io or similar — primary/secondary region, RDS, Route53, monitoring flow)
   - Setup instructions, RTO/RPO results front and center, "Phase 2 Roadmap" section
2. **Demo**
   - 2-3 min screen recording: trigger failover, show DNS switch, show dashboard, show RTO/RPO report
3. **Resume bullet drafting**
   - e.g., "Built config-driven multi-region DR framework on AWS (RDS, Route53, CloudWatch); automated failover reduced recovery time to X min against a 10-min target, validated via chaos testing"
   - Only use numbers you actually measured in Module 6 — no fabricated metrics

**Deliverable:** Repo is interview-ready; you can walk through it live without opening a single file mid-conversation to "check how it works."

---

## 4. Tech Stack Mapping (your existing skills → module)

| Skill | Where it's used |
|---|---|
| Terraform | Modules 1, 2, 3, 7 |
| Python | Modules 2 (promotion script), 4 (orchestrator), 6 (RTO/RPO calculator), 7 (YAML validator) |
| Bash | Wrapper scripts, CI triggers |
| GitHub Actions | Optional: CI to lint/validate Terraform on push, run dry-run failover on schedule |
| CloudWatch, SNS | Module 5 |
| Grafana | Module 5 |
| RDS, SQL | Module 2 |
| Git | Throughout — commit per module, tag releases |

Kubernetes/Docker/Helm are intentionally NOT in the v1 scope — don't force them in just because they're in your skillset; an unused Helm chart bolted onto a DR project reads as scope-padding, not depth. Add them honestly in Phase 2 if you extend to EKS-based workloads.

---

## 5. Definition of Done (checklist before calling it "complete")

- [ ] Zero hardcoded account-specific values anywhere in Terraform
- [ ] Actual measured RTO and RPO numbers, not estimates
- [ ] Dry-run mode works and is demoable without real failover
- [ ] Dashboard shows live replication lag and failover history
- [ ] One real chaos test executed and logged
- [ ] README has architecture diagram + Phase 2 roadmap
- [ ] Repo is clearly structured so the *intended* adaptation path (YAML config + README) is obvious — without claiming a stranger has actually run it successfully, since no one has
