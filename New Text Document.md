▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
 > analyze this whole folder (insted of relyion only on scipts and readme and project_report scan all files and folders included then  ) 
   and give me full deployment steps in details i will be deploying this project through ubuntu virtualized os provide each step with    
   why to do it and if there are some requirements that i have to downliodwe provide steps to download it [i dont have domain so provide 
   steps accordingly and in simple languade]                                                                                             
▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
✦ Since you do not have a domain name, we will adapt the deployment to use the AWS-provided Load Balancer URLs. This allows you to see
  the project working for free without buying a domain.

  Here are the detailed steps to deploy this on your Ubuntu Virtual Machine.

  ---

  Step 1: Install the Required Tools
  Your Ubuntu VM needs four main "helpers" to build this system.

  1. Update Ubuntu
   * Command: sudo apt update && sudo apt upgrade -y
   * Why: Ensures your system is secure and ready for new software.

  2. Install Python (The Orchestrator)
   * Command: sudo apt install python3 python3-pip -y
   * Why: The deploy.py script is the "brain" that runs everything.
   * Download Check: Type python3 --version to confirm.

  3. Install Docker (The Container)
   * Command: 

   1     sudo apt install docker.io -y
   2     sudo usermod -aG docker $USER
   3     # IMPORTANT: Close your terminal and reopen it now to apply this!
   * Why: Your website app is packed into a "Docker Image" so it runs exactly the same on AWS as it does on your machine.

  4. Install Terraform (The Builder)
   * Download Steps:

   1     wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
   2     echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs)
     main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   3     sudo apt update && sudo apt install terraform -y
   * Why: Terraform reads the files in the terraform/ folder and automatically builds the network, servers, and databases on AWS.

  5. Install AWS CLI (The Communicator)
   * Command: sudo apt install awscli -y
   * Why: This allows your Ubuntu VM to "talk" to your AWS account securely.

  ---

  Step 2: Get Your AWS Credentials
  You need to tell Ubuntu which AWS account to use.
   1. Log into your AWS Console.
   2. Go to IAM -> Users -> Your User -> Security Credentials.
   3. Create an Access Key.
   4. On Ubuntu, type: aws configure
   5. Paste your Access Key ID, Secret Key, and set the region to ap-south-1.

  ---

  Step 3: Prepare the Project Code
   1. Clone the project: git clone <your-repo-link> && cd aws-multi-region-dr
   2. Install Python requirements: pip3 install boto3 pyyaml requests
   3. Handle the "No Domain" issue:
       * Open the config file: nano config.yaml
       * Look for domain: <YOUR_DOMAIN>.
       * Change it to something fake like: domain: my-test-dr.local
       * Why: The script expects a domain name to exist. By putting a fake one, the script will finish its work, but we will use the AWS
         ALB URL (a long string like dr-app-alb-12345.ap-south-1.elb.amazonaws.com) to actually view our website.

  ---

  Step 4: Run the Deployment
  Now, we start the automatic process.

   * Command: python3 deploy.py
   * What will happen?
       * It will build your app (Docker).
       * It will create a "Safe Box" (S3) for your data.
       * It will build the Mumbai servers and Singapore servers.
   * Wait Time: This takes about 15 to 20 minutes because AWS is setting up a real database (RDS) for you.

  ---

  Step 5: How to see your website (Without a Domain)
  Since you don't have a domain, the "Phase 6 DNS Check" might fail or wait forever. Don't worry. 

   1. Look at the terminal output for a line like: Mumbai ALB: dr-app-alb-....amazonaws.com.
   2. Copy that long URL.
   3. Paste it into your web browser.
   4. You are now viewing your live app!

  ---

  Step 6: Testing the "Disaster"
  This is the most important part of the project.

   1. Open the Mumbai URL in your browser. You will see "Region: ap-south-1".
   2. On Ubuntu, run: python3 deploy.py --failover-test
       * Why: This script manually "kills" the Mumbai servers to see if the system is smart enough to survive.
   3. Now, find the Singapore ALB URL in your logs or AWS Console.
   4. Open the Singapore URL. You will see "Region: ap-southeast-1".
   5. Success: Even though the first region "died," your website is still alive in the second region!

  ---

  Step 7: Cleanup (Save Money!)
  AWS charges you by the hour. Since this is a test, you should scale it down when finished.

   * Command: python3 deploy.py --teardown
   * Why: This reduces your servers to 1 in Mumbai and 0 in Singapore, keeping your cost very low (a few cents) while you aren't using
     it.
   * To delete everything permanently: Go to the AWS Console and manually delete the RDS Database and the Load Balancers if you never
     plan to use them again.

  ---

  Summary of "No Domain" Hack
   * Normally: People use www.myweb.com which points to Mumbai or Singapore automatically.
   * Your Case: You will have two URLs (one for Mumbai, one for Singapore). You can visit either one directly to prove that the databases
     are syncing and the app is running in both places!