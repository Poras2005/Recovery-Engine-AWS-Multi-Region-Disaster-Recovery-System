# 🌍 Project Report: AWS Multi-Region Disaster Recovery System
**Title:** Cloud Guard: Automated Business Continuity  
**Author:** Poras Ravindra Barhate (Implemented by Gemini CLI)  
**Target Audience:** Freshers, Recruiters, and Cloud Enthusiasts  

---

## 1. ❓ What is this project?
In simple terms, this project is a **"Safety Net"** for websites and applications. 

Imagine you have a shop in a city. If that city faces a power outage or a flood, your shop closes, and you lose customers. In the cloud world, a "city" is an **AWS Region** (like Mumbai). If the Mumbai region goes down (which has happened in the past), every website hosted only there disappears.

**This project builds a system that automatically "teleports" your website traffic to a second city (Singapore) in less than 60 seconds if the first one fails.**

---

## 2. 💡 Why was this project made? (The Problem)
Most beginners learn how to host a website in one place. But in the real world, big companies like Netflix, Amazon, or Banks cannot afford even 1 minute of "Downtime."

*   **The Risk:** AWS regions are powerful, but not invincible. Hardware failures, undersea cable cuts, or natural disasters can take them offline.
*   **The Cost:** For a big company, 1 hour of being offline can cost **millions of dollars**.
*   **The Solution:** This project uses **Automation** and **Infrastructure as Code** to ensure that if one part of the world fails, the business keeps running elsewhere.

---

## 3. 🏗️ How does it work? (The Architecture)
We use a strategy called **"Active-Passive"** failover:

1.  **Primary Region (Mumbai):** This is where the website lives normally. It handles 100% of the customers.
2.  **Secondary Region (Singapore):** This is a "Standby" version. It stays ready and keeps a copy of the data, but doesn't serve customers unless there is an emergency.
3.  **The Traffic Police (Route 53):** This is a smart DNS service. It constantly checks: *"Is Mumbai okay?"*. 
    *   If it's okay, traffic goes to Mumbai. 
    *   If Mumbai stops responding, it automatically redirects everyone to Singapore.

### Key Components:
*   **VPC:** A private, secure "bubble" for our servers.
*   **EC2 & Auto Scaling:** Servers that automatically grow or shrink based on how many people are visiting.
*   **RDS (Database):** A smart database that copies data from Mumbai to Singapore automatically.
*   **Terraform:** A tool that lets us write "code" to build all this hardware. Instead of clicking buttons in the AWS console, we run a script.

---

## 4. 🛡️ Why is this project "Production-Grade"?
What makes this different from a simple tutorial?

*   **Security (Zero-Config):** We never save AWS passwords on the computer. The script asks for them when it runs and keeps them only in the computer's temporary memory. This prevents hackers from stealing keys from the code.
*   **DevSecOps:** Every time we update the code, automated "security guards" (Trivy and Checkov) scan it for holes and vulnerabilities.
*   **Speed:** You can build or destroy this entire global system in just 5 minutes with one command.

---

## 5. 🏢 Real-World Use Cases
Who needs this?
1.  **Banking & Finance:** Apps like PayPal or Banking portals must be available 24/7.
2.  **Healthcare:** Systems holding patient records or emergency room data.
3.  **E-commerce:** If a site like Amazon goes down during a "Black Friday" sale, the losses are catastrophic.
4.  **Government:** Vital public services and emergency response systems.

---

## 6. 🚀 Why is this important for your career?
If you are a fresher, this project proves three major things:
1.  **You understand "The Big Picture":** You aren't just a coder; you understand how global businesses stay alive.
2.  **You know Automation:** Companies want engineers who can write scripts (`Python`, `Terraform`) to do the work of 10 people.
3.  **You are Security-First:** You understand that protecting credentials is more important than just making things work.

---

## 7. 🛠️ How to use this project?
It is designed to be **"Plug and Play"**:

1.  **Requirements:** You just need an AWS account and a computer with Bash shell and AWS CLI installed.
2.  **Configuration:** You put your email (for alerts) and your domain name in a small `config.yaml` file (or set domain to `none` to use free CloudFront failover).
3.  **Live at:** http://{domain} or https://{cloudfront_dns}
4.  **Simulate failover :** `./scripts/test_failover.sh`
5.  **Save money / Nuke :** `./scripts/teardown.sh`
6.  **The Result:** The script builds the network, the servers, the databases, and the security rules across two continents automatically.

---

## 9. 📂 The Blueprint: Understanding Each File
Every file in this project has a specific "Job" (Work) and a specific "Impact" (Influence) on the final system. Here is the breakdown:

### 🚀 Orchestration & Configuration
*   **`deploy.sh` (The Brain)**
    *   **Work:** This is the master script in Bash. It talks to AWS, checks your credentials, and runs the Terraform commands in the right order.
    *   **Influence:** It ensures the deployment is **Error-Free** and **Secure**. Without this, you would have to run 20+ manual commands perfectly.
*   **`config.yaml` (The Map)**
    *   **Work:** It holds the settings like your Region names, Email for alerts, and Domain name.
    *   **Influence:** It makes the project **Reusable**. Anyone can change this one file to deploy the same system for their own company.

### 🏗️ Infrastructure as Code (Terraform)
*   **`terraform/modules/vpc/` (The Foundation)**
    *   **Work:** Builds the isolated network (the "bubble") where our servers live.
    *   **Influence:** Provides **Security** by separating public internet traffic from private database traffic.
*   **`terraform/modules/alb/` (The Gatekeeper)**
    *   **Work:** Creates the Load Balancer that receives visitors and sends them to the healthy servers.
    *   **Influence:** Ensures **High Availability**. If one server crashes, the gatekeeper instantly sends traffic to another one.
*   **`terraform/modules/ec2/` (The Muscle)**
    *   **Work:** Sets up the Auto Scaling Group and the actual servers running our app.
    *   **Influence:** Provides **Scalability**. It ensures we have enough servers during a rush and zero wasted cost when it's quiet.
*   **`terraform/modules/rds/` (The Vault)**
    *   **Work:** Provisions the MySQL database and its regional replica.
    *   **Influence:** Ensures **Data Safety**. It makes sure that if Mumbai is destroyed, your data is already safe in Singapore.
*   **`terraform/global/` (The Bridge)**
    *   **Work:** Connects Mumbai and Singapore using Route 53 DNS.
    *   **Influence:** Enables **Automatic Failover**. This is the file that actually performs the "teleportation" of traffic during a disaster.

### 🐍 Operational Scripts
*   **`scripts/test_failover.sh` (The Drill)**
    *   **Work:** Intentionally shuts down the Mumbai servers (scales ASG to 0) to see if the system recovers and traffic fails over to Singapore.
    *   **Influence:** Provides **Confidence**. It proves the system works *before* a real disaster happens.
*   **`scripts/teardown.sh` & `scripts/spinup.sh` (Cost Savers & Cleanup)**
    *   **Work:** `teardown.sh` completely destroys all AWS resources to keep your account clean and costs at $0. `spinup.sh` scales servers up to default desired capacity.
    *   **Influence:** Saves **Money**. Ensures you only pay for what you use, and deletes everything in one command.

### 🌐 The Application
*   **`app/app.py` (The Product)**
    *   **Work:** A data-driven Flask microservice. It allows users to post messages, checks database health, and provides a failure simulation button.
    *   **Influence:** Provides **Proof of Persistence**. It allows you to prove that data saved in Mumbai is still available in Singapore after a failure.
*   **`app/requirements.txt`**
    *   **Work:** Lists Python drivers like `pymysql` needed to talk to the AWS database.
    *   **Influence:** Ensures the app has the **Database Connectivity** required for professional workloads.
*   **`app/Dockerfile` (The Package)**
    *   **Work:** Wraps the app into a "Container" so it runs exactly the same on any server.
    *   **Influence:** Ensures **Consistency**. It eliminates the "it worked on my machine" problem.

### 🤖 Automation (CI/CD)
*   **`.github/workflows/deploy.yml` (The Robot)**
    *   **Work:** Automatically runs security scans and deploys the code every time you save changes.
    *   **Influence:** Enables **DevSecOps**. It catches security holes before they ever reach the real world.

---

## 10. ✅ Frequently Asked Questions
*   **Is it expensive?** No. It uses "Free Tier" eligible parts where possible. It also has a `--teardown` command to delete everything and save money when you're done.
*   **Do I need to be an expert?** No. The `deploy.sh` script is like an "Easy Button." It handles the complex AWS commands for you.
*   **What happens to the data?** The database in Singapore is a "Read Replica." It stays perfectly in sync with Mumbai, so no data is lost during a failover.

---

## 11. 🌟 Advanced "Industry-Plus" Features
We have added 4 high-level features that are usually only found in senior-level engineering projects:

1.  **Secret Management+**: Instead of passing passwords around, the system now creates a **Secure Vault** (AWS Secrets Manager). The servers "call" this vault only when they need it.
2.  **Visual Dashboard**: A **CloudWatch Dashboard** is built automatically. It gives you a "One-Click" view of how your servers and load balancers are performing in both regions.
3.  **Auto-Rollback**: The "Brain" (`deploy.sh`) is now smarter. If it detects a failure during building, it **automatically tears down** resources to prevent huge AWS bills and keeps the environment clean.
4.  **Cost Ninja (Spot)**: In the Singapore (Standby) region, we use **Spot Instances**. These are spare AWS servers that cost **70-90% less** than normal servers, saving you massive amounts of money.

---
**Final Summary:** This project is a complete, professional-grade solution for the #1 problem in cloud computing: **Reliability.** It turns a complex global setup into a simple, secure, and automated process.
