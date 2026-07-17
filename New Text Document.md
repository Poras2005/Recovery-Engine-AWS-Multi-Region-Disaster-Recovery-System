# 🌍 Multi-Region DR System Deployment Guide (Ubuntu VM)

This guide provides detailed instructions to deploy and test the Cloud Guard Disaster Recovery system on an Ubuntu Virtual Machine. It is fully optimized for the **AWS Free Tier** and operates **without requiring a custom domain**.

---

### Step 1: Install Required Tools
Run the following commands on your Ubuntu VM to set up Python, Docker, Terraform, and the AWS CLI:

1. **Update System Packages**
   * **Command:** `sudo apt update && sudo apt upgrade -y`
   * **Why:** Ensures your system is secure and ready for new software.

2. **Install Python and PyYAML**
   * **Command:** `sudo apt install python3 python3-pip -y && pip3 install pyyaml`
   * **Why:** Used for parsing settings from `config.yaml`.

3. **Install Docker**
   * **Command:**
     ```bash
     sudo apt install docker.io -y
     sudo usermod -aG docker $USER
     ```
   * **Why:** The app is containerized.
   * **CRITICAL:** Log out of your VM session and log back in (or close and reopen your terminal) to apply the new Docker group membership!

4. **Install Terraform**
   * **Command:**
     ```bash
     wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
     echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
     sudo apt update && sudo apt install terraform -y
     ```
   * **Why:** Terraform reads your configuration and builds your AWS network, servers, and databases automatically.

5. **Install AWS CLI**
   * **Command:** `sudo apt install awscli -y`
   * **Why:** Allows your VM to communicate with your AWS account securely.

---

### Step 2: Configure AWS Credentials
You need to tell the AWS CLI which account to use.
1. Log into your AWS Console.
2. Go to **IAM** -> **Users** -> **Select Your User** -> **Security Credentials**.
3. Create an **Access Key**.
4. On your Ubuntu VM, run:
   ```bash
   aws configure
   ```
5. Paste your **Access Key ID**, **Secret Access Key**, and set the default region to `ap-south-1`.

---

### Step 3: Configure config.yaml
1. Open the configuration file in nano:
   ```bash
   nano config.yaml
   ```
2. Look for `route53: domain`.
3. Set the domain to `none` (this is the default):
   ```yaml
   route53:
     domain: none
   ```
   * **Why:** Setting it to `none` tells the orchestrator to deploy an **AWS CloudFront Distribution with an Origin Group** instead of Route 53. This gives you a free `cloudfront.net` domain name that performs dynamic region failover without buying a domain!

---

### Step 4: Run the Deployment
Start the automatic deployment script:
1. Make the scripts executable:
   ```bash
   chmod +x deploy.sh scripts/*.sh
   ```
2. Run the deployment:
   ```bash
   ./deploy.sh
   ```
* **What happens:** The script builds the Flask app Docker image locally, pushes it to ECR, provisions VPC networks in Mumbai and Singapore, starts the EC2 instances in public subnets (saving you NAT Gateway costs), sets up the single-AZ RDS database in Mumbai with a read replica in Singapore, and configures the CloudFront failover distribution.
* **Wait Time:** This takes around 10 to 15 minutes (mainly due to RDS database provisioning).
* **Completion:** Once done, it will output:
  `Live at: https://xxxxxx.cloudfront.net`

---

### Step 5: How to Access Your App
Copy the CloudFront URL printed at the end of the deployment (e.g., `https://xxxxxx.cloudfront.net`) and paste it into your browser. 
* You will see a JSON response stating `"region": "ap-south-1"`, meaning your traffic is routed to the primary region (Mumbai).
* You can write a message by sending a POST request to `https://xxxxxx.cloudfront.net/message` with JSON body `{"content": "Hello World!"}`.

---

### Step 6: Testing the "Disaster" (Failover)
This is the core verification of the disaster recovery setup:

1. **Trigger simulated outage:**
   Run the failover test script:
   ```bash
   ./deploy.sh --failover-test
   ```
   * **What it does:** It scales the Mumbai Auto Scaling Group down to 0, terminating the primary servers.
2. **Observe region switching:**
   The script will begin polling the CloudFront endpoint every 10 seconds. You will see it transition from `ap-south-1` to `ap-southeast-1` within seconds!
3. **Verify in browser:**
   Refresh your browser at the CloudFront URL. You will see `"region": "ap-southeast-1"`, confirming that traffic has failed over to Singapore.
4. **Promote the database replica (Optional):**
   Since the Singapore database is a read replica, writes will fail with a read-only warning. To promote the database to primary and enable writes in Singapore, run:
   ```bash
   ./scripts/promote_db.sh
   ```
   * The database will reboot and become read-write in 2-3 minutes.
5. **Restore the system:**
   To spin the Mumbai region back up and restore default DR capacity, run:
   ```bash
   ./deploy.sh --spinup
   ```

---

### Step 7: Clean Up (Save Money!)
AWS charges for active resources. When you are done demonstrating the project, run:
```bash
./deploy.sh --teardown
```
* **Why:** This runs a complete nuke. It deletes all VPCs, ALBs, databases, CloudFront configurations, ECR repositories, DynamoDB tables, and S3 state buckets in a single, non-interactive command, returning your AWS account to a completely clean state.