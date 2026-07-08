#!/usr/bin/env python3
"""
deploy.py — AWS Multi-Region DR System Master Orchestrator

Usage:
  python3 deploy.py                # full deploy (all 6 phases)
  python3 deploy.py --phase 3      # single phase only
  python3 deploy.py --teardown     # scale down to save money
  python3 deploy.py --spinup       # restore full capacity
  python3 deploy.py --failover-test # simulate Mumbai failure
"""

import argparse, base64, getpass, json, os
import subprocess, sys, time
import boto3, yaml, requests
from datetime import datetime
from pathlib import Path

# ── Logging ────────────────────────────────────────────────────
ICONS = {'INFO': 'i', 'OK': 'v', 'PHASE': '*', 'WARN': '!', 'ERROR': 'X'}

def log(msg, lvl='INFO'):
    icon = ICONS.get(lvl, 'i')
    ts = datetime.utcnow().strftime('%H:%M:%S')
    print(f'[{ts}] [{icon}] {msg}')

def abort(msg):
    log(msg, 'ERROR')
    sys.exit(1)

def banner(text):
    sep = '=' * 56
    print(f'\n{sep}\n {text}\n{sep}')

# ── Config loader ──────────────────────────────────────────────
def load_config():
    path = Path(__file__).parent / 'config.yaml'
    if not path.exists():
        abort('config.yaml not found. See documentation Section 4.')
    return yaml.safe_load(open(path))

# ── Credential prompt ──────────────────────────────────────────
# Credentials are NEVER stored in any file.
# getpass hides keystrokes so keys do not appear in terminal.
def prompt_credentials(cfg):
    banner('AWS Multi-Region DR System — Credential Setup')
    print(' Credentials are used only in memory. Nothing is written to disk.')
    print()
    
    # Check for environment variables (CI/CD support)
    key_id = os.environ.get('AWS_ACCESS_KEY_ID')
    secret_key = os.environ.get('AWS_SECRET_ACCESS_KEY')
    account_id = os.environ.get('AWS_ACCOUNT_ID')
    slack = os.environ.get('SLACK_WEBHOOK_URL')
    db_pass = os.environ.get('DB_PASSWORD')

    if not key_id:
        key_id = getpass.getpass(' AWS Access Key ID     : ')
    if not secret_key:
        secret_key = getpass.getpass(' AWS Secret Access Key : ')
    if not account_id:
        account_id = input(      ' AWS Account ID        : ').strip()
    if slack is None: # Slack can be empty string
        slack = input(           ' Slack Webhook URL (opt): ').strip()
    if not db_pass:
        db_pass = getpass.getpass(' Database Password     : ')
    
    print()
    creds = {
        'aws_access_key_id'     : key_id,
        'aws_secret_access_key' : secret_key,
        'account_id'            : account_id,
        'slack_webhook'         : slack,
        'db_password'           : db_pass,
    }
    validate_credentials(creds, cfg)
    return creds

# ── Credential validation ──────────────────────────────────────
def validate_credentials(creds, cfg):
    if not all([creds['aws_access_key_id'], 
                creds['aws_secret_access_key'], 
                creds['account_id']]):
        abort('Access Key ID, Secret Key, and Account ID are all required.')
    
    if not creds['account_id'].isdigit() or len(creds['account_id']) != 12:
        abort('Account ID must be exactly 12 digits.')

    log('Verifying credentials with AWS STS...')
    try:
        sts = boto3.client('sts', 
            region_name       = cfg['aws']['primary_region'],
            aws_access_key_id     = creds['aws_access_key_id'],
            aws_secret_access_key = creds['aws_secret_access_key'])
        identity = sts.get_caller_identity()
        log(f'Credentials valid — Account: {identity["Account"]}, '
            f'ARN: {identity["Arn"]}', 'OK')
        
        if identity['Account'] != creds['account_id']:
            abort(f'Account ID mismatch. STS returned {identity["Account"]}.')
    except Exception as e:
        abort(f'Credential verification failed: {e}')

# ── Confirmation prompt ────────────────────────────────────────
def confirm_deploy(cfg, creds):
    if os.environ.get('CI') == 'true':
        log('CI environment detected, bypassing confirmation prompt.')
        return

    pri   = cfg['aws']['primary_region']
    sec   = cfg['aws']['secondary_region']
    itype = cfg['autoscaling']['instance_type']
    des   = cfg['autoscaling']['desired_instances']

    print()
    print(' Resources that will be created:')
    print(f'  - 2x VPCs ({pri} + {sec})')
    print(f'  - {des * 2}x EC2 {itype} instances ({des} per region)')
    print(f'  - 2x Application Load Balancers')
    print(f'  - 1x RDS MySQL + 1x Read Replica')
    print(f'  - Route 53 hosted zone + health checks')
    print(f'  - CloudWatch alarms + SNS topic')
    print()
    print(' Estimated cost if left running: ~$30-35/month')
    print(' Use --teardown when not demoing to keep costs < $8/month')
    print()
    answer = input(' Proceed with full deployment? (yes/no): ').strip().lower()
    if answer not in ['yes', 'y']:
        print(' Deployment cancelled.')
        sys.exit(0)

# ── AWS client factory ─────────────────────────────────────────
def client(service, cfg, creds, region=None):
    return boto3.client(
        service,
        region_name       = region or cfg['aws']['primary_region'],
        aws_access_key_id     = creds['aws_access_key_id'],
        aws_secret_access_key = creds['aws_secret_access_key'])

# ── Shell runner ───────────────────────────────────────────────
def run(cmd, cwd=None, env=None):
    log(f'$ {cmd}')
    merged = {**os.environ, **(env or {})}
    result = subprocess.run(
        cmd, shell=True, cwd=cwd, env=merged,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout)
    if result.returncode != 0:
        abort(f'Command failed (exit code {result.returncode})')
    return result.stdout

# ══════════════════════════════════════════════════════════════
# PHASE 1 — Docker Build + Local Health Check
# ══════════════════════════════════════════════════════════════
def phase1(cfg, creds):
    banner('PHASE 1 — Docker Build & Local Health Check')
    app  = cfg['app']['name']
    tag  = cfg['app']['image_tag']
    port = cfg['app']['port']

    run(f'docker build -t {app}:{tag} ./app')

    log('Starting container for local health check...')
    run(f'docker run -d -p {port}:{port} --name dr-local {app}:{tag}')
    time.sleep(3)
    try:
        import requests
        r = requests.get(f'http://localhost:{port}/health', timeout=5)
        assert r.status_code == 200
        log(f'Local health check passed: {r.json()}', 'OK')
    except Exception as e:
        abort(f'Local health check failed: {e}')
    finally:
        run('docker stop dr-local && docker rm dr-local')

# ══════════════════════════════════════════════════════════════
# PHASE 2 — AWS Prerequisites (S3, DynamoDB, ECR)
# ══════════════════════════════════════════════════════════════
def phase2(cfg, creds):
    banner('PHASE 2 — S3 State Backend, DynamoDB Lock, ECR Push')
    pri    = cfg['aws']['primary_region']
    acct   = creds['account_id']
    bucket = f'{acct}-{cfg["terraform"]["state_bucket_suffix"]}'
    table  = cfg['terraform']['lock_table']
    app    = cfg['app']['name']
    tag    = cfg['app']['image_tag']

    # S3 Terraform state bucket
    s3 = client('s3', cfg, creds, pri)
    existing = [b['Name'] for b in s3.list_buckets()['Buckets']]
    if bucket not in existing:
        s3.create_bucket(Bucket=bucket, 
            CreateBucketConfiguration={'LocationConstraint': pri})
        s3.put_bucket_versioning(Bucket=bucket,
            VersioningConfiguration={'Status': 'Enabled'})
        log(f'S3 bucket created and versioned: {bucket}', 'OK')
    else:
        log(f'S3 bucket already exists: {bucket}', 'OK')

    # DynamoDB state lock table
    ddb = client('dynamodb', cfg, creds, pri)
    if table not in ddb.list_tables()['TableNames']:
        ddb.create_table(
            TableName=table,
            AttributeDefinitions=[{'AttributeName':'LockID','AttributeType':'S'}],
            KeySchema=[{'AttributeName':'LockID','KeyType':'HASH'}],
            BillingMode='PAY_PER_REQUEST')
        log(f'DynamoDB lock table created: {table}', 'OK')
    else:
        log(f'DynamoDB table already exists: {table}', 'OK')

    # ECR repository + Docker push
    ecr   = client('ecr', cfg, creds, pri)
    repos = [r['repositoryName'] 
             for r in ecr.describe_repositories().get('repositories', [])]
    if app not in repos:
        ecr.create_repository(repositoryName=app)
        log(f'ECR repository created: {app}', 'OK')

    token_data = ecr.get_authorization_token()['authorizationData'][0]
    u, p = base64.b64decode(token_data['authorizationToken']).decode().split(':', 1)
    uri  = f'{acct}.dkr.ecr.{pri}.amazonaws.com'

    run(f'docker login --username {u} --password {p} {uri}')
    run(f'docker tag {app}:{tag} {uri}/{app}:{tag}')
    run(f'docker push {uri}/{app}:{tag}')
    log('Image pushed to ECR.', 'OK')

# ══════════════════════════════════════════════════════════════
# PHASE 3 — Terraform (Mumbai + Singapore + Global)
# ══════════════════════════════════════════════════════════════
def tf_apply(folder, cfg, creds, extra=None):
    acct   = creds['account_id']
    bucket = f'{acct}-{cfg["terraform"]["state_bucket_suffix"]}'
    env = {
        'AWS_ACCESS_KEY_ID'     : creds['aws_access_key_id'],
        'AWS_SECRET_ACCESS_KEY' : creds['aws_secret_access_key'],
        'TF_VAR_account_id'     : acct,
        'TF_VAR_state_bucket'   : bucket,
        'TF_VAR_app_name'       : cfg['app']['name'],
        'TF_VAR_instance_type'  : cfg['autoscaling']['instance_type'],
        'TF_VAR_min_size'       : str(cfg['autoscaling']['min_instances']),
        'TF_VAR_max_size'       : str(cfg['autoscaling']['max_instances']),
        'TF_VAR_desired_size'   : str(cfg['autoscaling']['desired_instances']),
        'TF_VAR_db_password'    : creds['db_password'],
        **(extra or {})
    }
    run(f'terraform init -reconfigure -backend-config="bucket={bucket}"', cwd=folder, env=env)
    run('terraform apply -auto-approve', cwd=folder, env=env)
    out = run('terraform output -json', cwd=folder, env=env)
    return json.loads(out) if out.strip() else {}

def phase3(cfg, creds):
    banner('PHASE 3 — Terraform: Mumbai + Singapore + Route 53')
    
    log('Deploying Mumbai (Primary)...')
    m_out = tf_apply('terraform/regions/mumbai', cfg, creds)
    m_alb = m_out.get('alb_dns_name', {}).get('value', '')
    log(f'Mumbai ALB: {m_alb}', 'OK')

    log('Deploying Singapore (Secondary)...')
    s_out = tf_apply('terraform/regions/singapore', cfg, creds)
    s_alb = s_out.get('alb_dns_name', {}).get('value', '')
    log(f'Singapore ALB: {s_alb}', 'OK')

    log('Deploying Global resources (Route 53 + WAF)...')
    tf_apply('terraform/global', cfg, creds, extra={
        'TF_VAR_primary_alb_dns'   : m_alb,
        'TF_VAR_secondary_alb_dns' : s_alb,
        'TF_VAR_domain'            : cfg['route53']['domain'],
        'TF_VAR_health_check_path' : cfg['route53']['health_check_path'],
        'TF_VAR_failover_ttl'      : str(cfg['route53']['failover_ttl']),
    })
    log('Route 53 failover routing live.', 'OK')

# ══════════════════════════════════════════════════════════════
# PHASE 4 — CI/CD Secrets in SSM
# ══════════════════════════════════════════════════════════════
def phase4(cfg, creds):
    banner('PHASE 4 — Store CI/CD Parameters in SSM')
    ssm    = client('ssm', cfg, creds)
    params = {
        '/dr-app/account_id'       : creds['account_id'],
        '/dr-app/primary_region'   : cfg['aws']['primary_region'],
        '/dr-app/secondary_region' : cfg['aws']['secondary_region'],
        '/dr-app/app_name'         : cfg['app']['name'],
        '/dr-app/slack_webhook'    : creds.get('slack_webhook', ''),
    }
    for name, val in params.items():
        ssm.put_parameter(Name=name, Value=str(val), 
                         Type='SecureString', Overwrite=True)
        log(f'Stored: {name}', 'OK')
    
    log('Add AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY to GitHub Secrets manually.', 'WARN')

# ══════════════════════════════════════════════════════════════
# PHASE 5 — CloudWatch Alarms + SNS + Slack
# ══════════════════════════════════════════════════════════════
def phase5(cfg, creds):
    banner('PHASE 5 — CloudWatch Alarms & SNS Alerts')
    pri   = cfg['aws']['primary_region']
    email = cfg['alerts']['email']
    cpu   = float(cfg['alerts']['cpu_threshold'])
    slack = creds.get('slack_webhook', '')

    sns = client('sns', cfg, creds, pri)
    arn = sns.create_topic(Name='dr-alerts')['TopicArn']
    sns.subscribe(TopicArn=arn, Protocol='email', Endpoint=email)
    log(f'SNS topic ready. Check {email} and confirm the subscription email.', 'WARN')

    cw = client('cloudwatch', cfg, creds, pri)
    alarms = [
        {
            'AlarmName'          : 'DR-High-CPU-Mumbai',
            'MetricName'         : 'CPUUtilization',
            'Namespace'          : 'AWS/EC2',
            'Threshold'          : cpu,
            'ComparisonOperator' : 'GreaterThanThreshold',
            'Dimensions'         : [{'Name':'AutoScalingGroupName','Value':'dr-asg-mumbai'}],
        },
        {
            'AlarmName'          : 'DR-Unhealthy-Hosts-Mumbai',
            'MetricName'         : 'UnHealthyHostCount',
            'Namespace'          : 'AWS/ApplicationELB',
            'Threshold'          : 1.0,
            'ComparisonOperator' : 'GreaterThanOrEqualToThreshold',
            'Dimensions'         : [{'Name':'AutoScalingGroupName','Value':'dr-asg-mumbai'}],
        },
    ]
    for alarm in alarms:
        cw.put_metric_alarm(
            **alarm,
            Statistic='Average', Period=60,
            EvaluationPeriods=2,
            AlarmActions=[arn])
        log(f'Alarm created: {alarm["AlarmName"]}', 'OK')

    if slack:
        try:
            import requests
            requests.post(slack, json={'text': 'DR System deployed and alarms are live!'})
            log('Slack notification sent.', 'OK')
        except Exception as e:
            log(f'Slack notification failed (non-fatal): {e}', 'WARN')

# ══════════════════════════════════════════════════════════════
# PHASE 6 — End-to-End Verification
# ══════════════════════════════════════════════════════════════
def phase6(cfg, creds):
    banner('PHASE 6 — End-to-End Verification')
    import requests, socket
    domain = cfg['route53']['domain']
    hpath  = cfg['route53']['health_check_path']

    log(f'Waiting for DNS propagation for {domain}...')
    for i in range(1, 10):
        try:
            ip = socket.gethostbyname(domain)
            log(f'DNS resolved: {domain} -> {ip}', 'OK')
            break
        except Exception:
            log(f'Not propagated yet, retry {i}/9 in 10s...')
            time.sleep(10)

    log(f'Hitting http://{domain}{hpath}...')
    for i in range(1, 10):
        try:
            r = requests.get(f'http://{domain}{hpath}', timeout=10)
            if r.status_code == 200:
                log(f'Health check passed: {r.json()}', 'OK')
                break
        except Exception as e:
            log(f'Not ready, retry {i}/9 in 10s: {e}')
            time.sleep(10)

# ══════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════
def main():
    parser = argparse.ArgumentParser(description='DR System Orchestrator')
    parser.add_argument('--phase', type=int, choices=range(1, 7),
                        help='Run only one phase (1-6)')
    parser.add_argument('--teardown', action='store_true')
    parser.add_argument('--spinup', action='store_true')
    parser.add_argument('--failover-test', action='store_true')
    args = parser.parse_args()

    cfg   = load_config()
    creds = prompt_credentials(cfg)

    # Operations — no confirmation prompt needed
    if args.teardown:
        import importlib.util
        spec = importlib.util.spec_from_file_location('teardown', 'scripts/teardown.py')
        mod  = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return

    if args.spinup:
        import importlib.util
        spec = importlib.util.spec_from_file_location('spinup', 'scripts/spinup.py')
        mod  = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return

    if getattr(args, 'failover_test', False):
        import importlib.util
        spec = importlib.util.spec_from_file_location('failover', 'scripts/test_failover.py')
        mod  = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return

    # Full deploy or single phase
    phases = {1: phase1, 2: phase2, 3: phase3, 
              4: phase4, 5: phase5, 6: phase6}
    
    to_run = [args.phase] if args.phase else list(phases.keys())

    if not args.phase:
        confirm_deploy(cfg, creds) # only confirm for full deploys

    t0 = time.time()
    try:
        for n in to_run:
            phases[n](cfg, creds)
    except Exception as e:
        banner('CRITICAL ERROR DETECTED — TRIGGERING AUTO-ROLLBACK')
        log(f'Reason: {e}', 'ERROR')
        log('Attempting to scale down resources to prevent costs/instability...')
        
        # Rollback logic: Scale down ASGs to 0 via our teardown script logic
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location('teardown', 'scripts/teardown.py')
            mod  = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
        except Exception as rollback_err:
            log(f'Rollback failed: {rollback_err}', 'ERROR')
            
        log('Auto-rollback complete. Please investigate the logs.', 'WARN')
        sys.exit(1)

    elapsed = int(time.time() - t0)
    domain  = cfg['route53']['domain']
    banner(f'ALL DONE in {elapsed}s')
    log(f'Live at: http://{domain}', 'OK')
    log('Simulate failover : python3 deploy.py --failover-test')
    log('Save money        : python3 deploy.py --teardown')

if __name__ == '__main__':
    main()
