#!/usr/bin/env bash
# scripts/test_failover.sh

CONFIG_FILE="config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then CONFIG_FILE="../config.yaml"; fi
if [ ! -f "$CONFIG_FILE" ]; then echo "[ERROR] config.yaml not found!"; exit 1; fi

parse_yaml() {
    python3 -c "import yaml; print(yaml.safe_load(open('$1'))$2)" 2>/dev/null
}

PRIMARY_REGION=$(parse_yaml "$CONFIG_FILE" "['aws']['primary_region']")
SECONDARY_REGION=$(parse_yaml "$CONFIG_FILE" "['aws']['secondary_region']")
DOMAIN=$(parse_yaml "$CONFIG_FILE" "['route53']['domain']")
HPATH=$(parse_yaml "$CONFIG_FILE" "['route53']['health_check_path']")
APP_NAME=$(parse_yaml "$CONFIG_FILE" "['app']['name']")

echo "========================================================"
echo " 🌍 AWS Multi-Region DR — FAILOVER SIMULATION DRILL"
echo "========================================================\n"

# Verify credentials
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Enter AWS Credentials:"
    read -rsp " AWS Access Key ID     : " AWS_ACCESS_KEY_ID
    echo ""
    read -rsp " AWS Secret Access Key : " AWS_SECRET_ACCESS_KEY
    echo ""
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
fi

# Fetch Terraform outputs to determine endpoint
echo "Fetching active endpoint from Terraform..."
# Try running terraform output in global directory
cd terraform/global || cd ../terraform/global
TF_OUT=$(terraform output -json 2>/dev/null || echo "{}")
cd ../.. || cd ../..

HAS_DOMAIN=$(echo "$TF_OUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('has_domain', {}).get('value', False))" 2>/dev/null)
CF_DNS=$(echo "$TF_OUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('cloudfront_dns_name', {}).get('value', ''))" 2>/dev/null)

USE_ROUTE53=false
USE_CLOUDFRONT=false
USE_DIRECT_ALB=false

if [ "$HAS_DOMAIN" = "True" ]; then
    USE_ROUTE53=true
    TARGET_URL="http://${DOMAIN}"
    echo "[INFO] Using Route 53 Domain: ${DOMAIN}"
elif [ -n "$CF_DNS" ]; then
    USE_CLOUDFRONT=true
    TARGET_URL="https://${CF_DNS}"
    echo "[INFO] No custom domain. Using CloudFront Endpoint: ${TARGET_URL}"
else
    USE_DIRECT_ALB=true
    echo "[INFO] No global routing. Direct ALB-to-ALB monitoring."
    # Fetch ALB DNS names using AWS CLI
    MUMBAI_ALB=$(aws elbv2 describe-load-balancers --region "$PRIMARY_REGION" --query "LoadBalancers[?LoadBalancerName=='${APP_NAME}-alb-${PRIMARY_REGION}'].DNSName" --output text)
    SINGAPORE_ALB=$(aws elbv2 describe-load-balancers --region "$SECONDARY_REGION" --query "LoadBalancers[?LoadBalancerName=='${APP_NAME}-alb-${SECONDARY_REGION}'].DNSName" --output text)
    echo "  Mumbai ALB:    $MUMBAI_ALB"
    echo "  Singapore ALB: $SINGAPORE_ALB"
fi

check_endpoint() {
    curl -sf -o /dev/null -w "%{http_code}" "$1" 2>/dev/null || echo "000"
}

get_active_region() {
    curl -s "$1" | python3 -c "import sys, json; print(json.load(sys.stdin).get('region', 'unknown'))" 2>/dev/null || echo "unreachable"
}

# Baseline Checks
echo -e "\n--- Running Baseline Health Checks ---"
if [ "$USE_DIRECT_ALB" = true ]; then
    M_STATUS=$(check_endpoint "http://${MUMBAI_ALB}${HPATH}")
    S_STATUS=$(check_endpoint "http://${SINGAPORE_ALB}${HPATH}")
    echo "Mumbai ALB HTTP=${M_STATUS} | Singapore ALB HTTP=${S_STATUS}"
else
    STATUS=$(check_endpoint "${TARGET_URL}${HPATH}")
    ACTIVE_REG=$(get_active_region "${TARGET_URL}/")
    echo "Active Region: ${ACTIVE_REG} | URL: ${TARGET_URL} | HTTP Status: ${STATUS}"
fi

# Scale down Mumbai ASG to 0
echo -e "\n[Failure Simulation] Scaling Mumbai ASG (dr-asg-mumbai) to 0..."
aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "dr-asg-mumbai" \
    --min-size 0 --max-size 0 --desired-capacity 0 \
    --region "$PRIMARY_REGION"
echo "Mumbai ASG scaled to 0. Monitoring failover routing..."

# Monitoring Loop
echo -e "\nMonitoring failover for 150 seconds (polling every 10s)...\n"
for i in {1..15}; do
    sleep 10
    TS=$(date -u +%H:%M:%S)
    
    if [ "$USE_DIRECT_ALB" = true ]; then
        M_STATUS=$(check_endpoint "http://${MUMBAI_ALB}${HPATH}")
        S_STATUS=$(check_endpoint "http://${SINGAPORE_ALB}${HPATH}")
        if [ "$M_STATUS" = "200" ]; then ROUTING="MUMBAI"; else ROUTING="SINGAPORE"; fi
        echo "[$TS] $((i*10))s | Client Route -> $ROUTING | Mumbai ALB: $M_STATUS | Singapore ALB: $S_STATUS"
    else
        STATUS=$(check_endpoint "${TARGET_URL}${HPATH}")
        ACTIVE_REG=$(get_active_region "${TARGET_URL}/")
        echo "[$TS] $((i*10))s | Active Region -> $ACTIVE_REG | HTTP=$STATUS"
    fi
done

echo -e "\nTest complete. Run './deploy.sh --spinup' or './scripts/spinup.sh' to restore."
