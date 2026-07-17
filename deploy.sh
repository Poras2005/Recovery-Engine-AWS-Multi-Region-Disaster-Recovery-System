#!/usr/bin/env bash
# deploy.sh — AWS Multi-Region DR System Master Orchestrator in Bash

set -e

# Helper to print formatting
log() {
    local lvl="$2"
    [ -z "$lvl" ] && lvl="INFO"
    local ts=$(date -u +%H:%M:%S)
    local icon="i"
    case "$lvl" in
        "OK")    icon="v" ;;
        "WARN")  icon="!" ;;
        "ERROR") icon="X" ;;
        "PHASE") icon="*" ;;
    esac
    echo "[$ts] [$icon] $1"
}

banner() {
    local sep="========================================================"
    echo -e "\n$sep\n $1\n$sep"
}

abort() {
    log "$1" "ERROR"
    exit 1
}

# Config parser helper using Python (since python3 is installed)
parse_yaml() {
    local out
    if ! out=$(python3 -c "import yaml; print(yaml.safe_load(open('$1'))$2)" 2>&1); then
        echo "[ERROR] Failed to parse YAML for query '$2' in file '$1':" >&2
        echo "$out" >&2
        return 1
    fi
    echo "$out"
}

CONFIG_FILE="config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    abort "config.yaml not found. Check repository."
fi

# Load configs
PRIMARY_REGION=$(parse_yaml "$CONFIG_FILE" "['aws']['primary_region']")
SECONDARY_REGION=$(parse_yaml "$CONFIG_FILE" "['aws']['secondary_region']")
APP_NAME=$(parse_yaml "$CONFIG_FILE" "['app']['name']")
IMAGE_TAG=$(parse_yaml "$CONFIG_FILE" "['app']['image_tag']")
PORT=$(parse_yaml "$CONFIG_FILE" "['app']['port']")
STATE_SUFFIX=$(parse_yaml "$CONFIG_FILE" "['terraform']['state_bucket_suffix']")
LOCK_TABLE=$(parse_yaml "$CONFIG_FILE" "['terraform']['lock_table']")

# Parse CLI arguments
PHASE=""
TEARDOWN=false
SPINUP=false
FAILOVER_TEST=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --phase) PHASE="$2"; shift ;;
        --teardown) TEARDOWN=true ;;
        --spinup) SPINUP=true ;;
        --failover-test) FAILOVER_TEST=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Credentials Prompt
prompt_credentials() {
    banner "AWS Multi-Region DR System — Credential Setup"
    echo " Credentials are used only in memory. Nothing is written to disk."
    echo ""
    
    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        read -rsp " AWS Access Key ID     : " AWS_ACCESS_KEY_ID
        echo ""
    fi
    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        read -rsp " AWS Secret Access Key : " AWS_SECRET_ACCESS_KEY
        echo ""
    fi
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        read -rp " AWS Account ID        : " AWS_ACCOUNT_ID
    fi
    if [ -z "$DB_PASSWORD" ]; then
        read -rsp " Database Password     : " DB_PASSWORD
        echo ""
    fi
    
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_ACCOUNT_ID
    export DB_PASSWORD
    
    # Optional Slack Webhook
    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        SLACK_WEBHOOK_URL=$(parse_yaml "$CONFIG_FILE" "['alerts']['slack_webhook']")
    fi
    export SLACK_WEBHOOK_URL
}

validate_credentials() {
    log "Verifying credentials with AWS STS..."
    if ! caller_identity=$(aws sts get-caller-identity --query "Account" --output text 2>&1); then
        abort "Credential verification failed: $caller_identity"
    fi
    if [ "$caller_identity" != "$AWS_ACCOUNT_ID" ]; then
        abort "Account ID mismatch. STS returned $caller_identity but expected $AWS_ACCOUNT_ID."
    fi
    log "Credentials valid — Account: $caller_identity" "OK"
}

# Operations routes
if [ "$TEARDOWN" = true ]; then
    prompt_credentials
    validate_credentials
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_ACCOUNT_ID
    export DB_PASSWORD
    chmod +x ./scripts/teardown.sh
    ./scripts/teardown.sh
    exit 0
fi

if [ "$SPINUP" = true ]; then
    prompt_credentials
    validate_credentials
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    chmod +x ./scripts/spinup.sh
    ./scripts/spinup.sh
    exit 0
fi

if [ "$FAILOVER_TEST" = true ]; then
    prompt_credentials
    validate_credentials
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    chmod +x ./scripts/test_failover.sh
    ./scripts/test_failover.sh
    exit 0
fi

# Full deploy confirmation
confirm_deploy() {
    local des=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['desired_instances']")
    local itype=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['instance_type']")
    
    echo ""
    echo " Resources that will be created:"
    echo "  - 2x VPCs ($PRIMARY_REGION + $SECONDARY_REGION)"
    echo "  - $((des * 2))x EC2 $itype instances ($des per region)"
    echo "  - 2x Application Load Balancers"
    echo "  - 1x RDS MySQL + 1x Read Replica"
    echo "  - CloudFront Origin Group (or Route 53 hosted zone)"
    echo "  - CloudWatch alarms + SNS topic"
    echo ""
    echo " Estimated cost if left running: ~$12-15/month (Multi-region replica database)"
    echo " Use ./deploy.sh --teardown when not demoing to delete all resources."
    echo ""
    read -rp " Proceed with full deployment? (yes/no): " answer
    if [ "$answer" != "yes" ] && [ "$answer" != "y" ]; then
        echo " Deployment cancelled."
        exit 0
    fi
}

# Phases definition
phase1() {
    banner "PHASE 1 — Docker Build & Local Health Check"
    docker build -t "${APP_NAME}:${IMAGE_TAG}" ./app
    log "Starting container for local health check..."
    docker run -d -p "${PORT}:${PORT}" --name dr-local "${APP_NAME}:${IMAGE_TAG}"
    
    log "Waiting for local container to start..."
    local healthy=false
    for i in {1..10}; do
        sleep 2
        if curl -sf "http://localhost:${PORT}/health" >/dev/null; then
            healthy=true
            break
        fi
        log "Container not ready yet, retrying check ($i/10)..."
    done

    if [ "$healthy" = true ]; then
        log "Local health check passed." "OK"
    else
        log "Printing container logs for debugging:" "WARN"
        docker logs dr-local || true
        docker stop dr-local && docker rm dr-local
        abort "Local health check failed."
    fi
    docker stop dr-local && docker rm dr-local
}

phase2() {
    banner "PHASE 2 — S3 State Backend, DynamoDB Lock, ECR Push"
    local bucket="${AWS_ACCOUNT_ID}-${STATE_SUFFIX}"
    
    # Check S3 State Bucket
    if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
        log "Creating S3 bucket: $bucket in $PRIMARY_REGION..."
        aws s3api create-bucket \
            --bucket "$bucket" \
            --region "$PRIMARY_REGION" \
            --create-bucket-configuration LocationConstraint="$PRIMARY_REGION"
        aws s3api put-bucket-versioning \
            --bucket "$bucket" \
            --versioning-configuration Status=Enabled
        log "S3 bucket created and versioned." "OK"
    else
        log "S3 bucket already exists: $bucket" "OK"
    fi

    # Check DynamoDB Lock Table
    if ! aws dynamodb describe-table --table-name "$LOCK_TABLE" --region "$PRIMARY_REGION" >/dev/null 2>&1; then
        log "Creating DynamoDB table: $LOCK_TABLE..."
        aws dynamodb create-table \
            --table-name "$LOCK_TABLE" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region "$PRIMARY_REGION"
        log "DynamoDB lock table created." "OK"
    else
        log "DynamoDB table already exists: $LOCK_TABLE" "OK"
    fi

    # Check ECR Repository
    if ! aws ecr describe-repositories --repository-names "$APP_NAME" --region "$PRIMARY_REGION" >/dev/null 2>&1; then
        log "Creating ECR repository: $APP_NAME..."
        aws ecr create-repository --repository-name "$APP_NAME" --region "$PRIMARY_REGION"
        log "ECR repository created." "OK"
    else
        log "ECR repository already exists: $APP_NAME" "OK"
    fi

    # ECR Push
    local uri="${AWS_ACCOUNT_ID}.dkr.ecr.${PRIMARY_REGION}.amazonaws.com"
    aws ecr get-login-password --region "$PRIMARY_REGION" | docker login --username AWS --password-stdin "$uri"
    docker tag "${APP_NAME}:${IMAGE_TAG}" "${uri}/${APP_NAME}:${IMAGE_TAG}"
    docker push "${uri}/${APP_NAME}:${IMAGE_TAG}"
    log "Image pushed to ECR." "OK"
}

tf_apply() {
    local folder="$1"
    local bucket="${AWS_ACCOUNT_ID}-${STATE_SUFFIX}"
    
    export TF_VAR_account_id="$AWS_ACCOUNT_ID"
    export TF_VAR_state_bucket="$bucket"
    export TF_VAR_app_name="$APP_NAME"
    export TF_VAR_instance_type=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['instance_type']")
    export TF_VAR_min_size=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['min_instances']")
    export TF_VAR_max_size=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['max_instances']")
    export TF_VAR_desired_size=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['desired_instances']")
    export TF_VAR_db_password="$DB_PASSWORD"
    
    # Inject extra vars passed as arguments
    if [ -n "$2" ]; then
        eval "$2"
    fi
    
    cd "$folder"
    terraform init -reconfigure -backend-config="bucket=${bucket}"
    terraform apply -auto-approve
    local out=$(terraform output -json)
    cd ../.. || cd ../../..
    echo "$out"
}

phase3() {
    banner "PHASE 3 — Terraform: Mumbai + Singapore + Global Routing"
    
    log "Deploying Mumbai (Primary)..."
    local m_out=$(tf_apply "terraform/regions/mumbai")
    local m_alb=$(echo "$m_out" | python3 -c "import sys, json; print(json.load(sys.stdin).get('alb_dns_name', {}).get('value', ''))" 2>/dev/null)
    log "Mumbai ALB: $m_alb" "OK"

    log "Deploying Singapore (Secondary)..."
    local s_out=$(tf_apply "terraform/regions/singapore")
    local s_alb=$(echo "$s_out" | python3 -c "import sys, json; print(json.load(sys.stdin).get('alb_dns_name', {}).get('value', ''))" 2>/dev/null)
    log "Singapore ALB: $s_alb" "OK"

    log "Deploying Global resources (Route 53 / CloudFront)..."
    local domain=$(parse_yaml "$CONFIG_FILE" "['route53']['domain']")
    local hpath=$(parse_yaml "$CONFIG_FILE" "['route53']['health_check_path']")
    local ttl=$(parse_yaml "$CONFIG_FILE" "['route53']['failover_ttl']")
    
    local g_out=$(tf_apply "terraform/global" "export TF_VAR_primary_alb_dns='$m_alb' TF_VAR_secondary_alb_dns='$s_alb' TF_VAR_domain='$domain' TF_VAR_health_check_path='$hpath' TF_VAR_failover_ttl='$ttl'")
    
    local has_domain=$(echo "$g_out" | python3 -c "import sys, json; print(json.load(sys.stdin).get('has_domain', {}).get('value', False))" 2>/dev/null)
    if [ "$has_domain" = "True" ]; then
        log "Route 53 failover routing live." "OK"
    else
        local cf_dns=$(echo "$g_out" | python3 -c "import sys, json; print(json.load(sys.stdin).get('cloudfront_dns_name', {}).get('value', ''))" 2>/dev/null)
        log "CloudFront failover routing live at: https://$cf_dns" "OK"
    fi
}

phase4() {
    banner "PHASE 4 — Store CI/CD Parameters in SSM"
    local params=(
        "/dr-app/account_id:$AWS_ACCOUNT_ID"
        "/dr-app/primary_region:$PRIMARY_REGION"
        "/dr-app/secondary_region:$SECONDARY_REGION"
        "/dr-app/app_name:$APP_NAME"
        "/dr-app/slack_webhook:$SLACK_WEBHOOK_URL"
    )
    for p in "${params[@]}"; do
        local name="${p%%:*}"
        local val="${p#*:}"
        if [ -z "$val" ]; then
            val="none"
        fi
        aws ssm put-parameter --name "$name" --value "$val" --type "SecureString" --overwrite --region "$PRIMARY_REGION"
        log "Stored: $name" "OK"
    done
    log "SSM parameters saved securely." "OK"
}

phase5() {
    banner "PHASE 5 — CloudWatch Alarms & SNS Alerts"
    local email=$(parse_yaml "$CONFIG_FILE" "['alerts']['email']")
    local cpu=$(parse_yaml "$CONFIG_FILE" "['alerts']['cpu_threshold']")
    
    # Check if email is valid or placeholder
    if [ -z "$email" ] || [ "$email" = "null" ] || [ "$email" = "<YOUR_EMAIL>" ] || [[ "$email" == *"<"* ]]; then
        log "No alert email configured or placeholder found. Skipping SNS & CloudWatch alarms." "WARN"
        return
    fi

    # Create SNS Topic
    log "Creating SNS Topic dr-alerts in $PRIMARY_REGION..."
    local topic_arn=$(aws sns create-topic --name dr-alerts --region "$PRIMARY_REGION" --query "TopicArn" --output text)
    aws sns subscribe --topic-arn "$topic_arn" --protocol email --notification-endpoint "$email" --region "$PRIMARY_REGION"
    log "SNS topic ready. Check email ($email) to confirm subscription." "WARN"

    # Create CloudWatch Alarms
    log "Creating High CPU alarm for Mumbai..."
    aws cloudwatch put-metric-alarm \
        --alarm-name "DR-High-CPU-Mumbai" \
        --metric-name "CPUUtilization" \
        --namespace "AWS/EC2" \
        --threshold "$cpu" \
        --comparison-operator "GreaterThanThreshold" \
        --dimensions "Name=AutoScalingGroupName,Value=dr-asg-mumbai" \
        --statistic "Average" --period 60 --evaluation-periods 2 \
        --alarm-actions "$topic_arn" --region "$PRIMARY_REGION"

    log "Creating Unhealthy Host alarm for Mumbai..."
    aws cloudwatch put-metric-alarm \
        --alarm-name "DR-Unhealthy-Hosts-Mumbai" \
        --metric-name "UnHealthyHostCount" \
        --namespace "AWS/ApplicationELB" \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --dimensions "Name=AutoScalingGroupName,Value=dr-asg-mumbai" \
        --statistic "Average" --period 60 --evaluation-periods 2 \
        --alarm-actions "$topic_arn" --region "$PRIMARY_REGION"
        
    log "SNS & Alarms configured." "OK"
}

phase6() {
    banner "PHASE 6 — End-to-End Verification"
    
    # Get outputs
    cd terraform/global
    local g_out=$(terraform output -json 2>/dev/null || echo "{}")
    cd ../..
    
    local has_domain=$(echo "$g_out" | python3 -c "import sys, json; print(json.load(sys.stdin).get('has_domain', {}).get('value', False))" 2>/dev/null)
    local hpath=$(parse_yaml "$CONFIG_FILE" "['route53']['health_check_path']")
    
    if [ "$has_domain" = "True" ]; then
        local endpoint=$(echo "$g_out" | python3 -c "import sys, json; print(json.load(sys.stdin).get('route53_domain', {}).get('value', ''))" 2>/dev/null)
        local url="http://${endpoint}"
        log "Waiting for DNS propagation for $endpoint..."
        for i in {1..9}; do
            if host "$endpoint" >/dev/null 2>&1; then
                log "DNS resolved successfully." "OK"
                break
            fi
            log "Not propagated yet, retry $i/9 in 10s..."
            sleep 10
        done
    else
        local cf_dns=$(echo "$g_out" | python3 -c "import sys, json; print(json.load(sys.stdin).get('cloudfront_dns_name', {}).get('value', ''))" 2>/dev/null)
        if [ -z "$cf_dns" ]; then
            log "No global endpoint found. Skipping global verification." "WARN"
            return
        fi
        local url="https://${cf_dns}"
        log "Verifying CloudFront endpoint: $url" "OK"
        # Wait a few seconds for CloudFront to be reachable
        sleep 5
    fi

    log "Hitting ${url}${hpath}..."
    for i in {1..12}; do
        if res=$(curl -sf "${url}${hpath}" 2>&1); then
            log "Health check passed: $res" "OK"
            break
        fi
        log "Not ready, retry $i/12 in 10s..."
        sleep 10
    done
}

# Main Execution Flow
prompt_credentials
validate_credentials

if [ -z "$PHASE" ]; then
    confirm_deploy
    t0=$(date +%s)
    phase1
    phase2
    phase3
    phase4
    phase5
    phase6
    t1=$(date +%s)
    elapsed=$((t1 - t0))
    
    cd terraform/global
    g_out=$(terraform output -json 2>/dev/null || echo "{}")
    cd ../..
    has_domain=$(echo "$g_out" | python3 -c "import sys, json; print(json.load(sys.stdin).get('has_domain', {}).get('value', False))" 2>/dev/null)
    if [ "$has_domain" = "True" ]; then
        live_url="http://$(echo "$g_out" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("route53_domain", {}).get("value", ""))' 2>/dev/null)"
    else
        live_url="https://$(echo "$g_out" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("cloudfront_dns_name", {}).get("value", ""))' 2>/dev/null)"
    fi
    
    banner "ALL DONE in ${elapsed}s"
    log "Live at: $live_url" "OK"
    log "Simulate failover : ./deploy.sh --failover-test"
    log "Teardown (Nuke)   : ./deploy.sh --teardown"
else
    case $PHASE in
        1) phase1 ;;
        2) phase2 ;;
        3) phase3 ;;
        4) phase4 ;;
        5) phase5 ;;
        6) phase6 ;;
        *) echo "Invalid phase: $PHASE"; exit 1 ;;
    esac
fi
