#!/usr/bin/env bash
# scripts/spinup.sh

CONFIG_FILE="config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then CONFIG_FILE="../config.yaml"; fi
if [ ! -f "$CONFIG_FILE" ]; then echo "[ERROR] config.yaml not found!"; exit 1; fi

parse_yaml() {
    python3 -c "import yaml; print(yaml.safe_load(open('$1'))$2)" 2>/dev/null
}

PRIMARY_REGION=$(parse_yaml "$CONFIG_FILE" "['aws']['primary_region']")
SECONDARY_REGION=$(parse_yaml "$CONFIG_FILE" "['aws']['secondary_region']")
DESIRED=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['desired_instances']")
MIN=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['min_instances']")
MAX=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['max_instances']")

echo "========================================================"
echo " 🌍 Spinning up both regions to full DR Capacity"
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

# Scale Mumbai
echo "Spinning up Mumbai ($PRIMARY_REGION) ASG to desired=$DESIRED..."
aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "dr-asg-mumbai" \
    --min-size "$MIN" \
    --max-size "$MAX" \
    --desired-capacity "$DESIRED" \
    --region "$PRIMARY_REGION"

# Scale Singapore
echo "Spinning up Singapore ($SECONDARY_REGION) ASG to desired=$DESIRED..."
aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "dr-asg-singapore" \
    --min-size "$MIN" \
    --max-size "$MAX" \
    --desired-capacity "$DESIRED" \
    --region "$SECONDARY_REGION"

echo "Waiting for instances to become healthy (InService)..."
# Simple poll
for i in {1..18}; do
    M_HEALTH=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "dr-asg-mumbai" --region "$PRIMARY_REGION" --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" --output text | wc -w)
    S_HEALTH=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "dr-asg-singapore" --region "$SECONDARY_REGION" --query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" --output text | wc -w)
    echo " Mumbai: $M_HEALTH/$DESIRED InService | Singapore: $S_HEALTH/$DESIRED InService"
    if [ "$M_HEALTH" -ge "$DESIRED" ] && [ "$S_HEALTH" -ge "$DESIRED" ]; then
        echo " [SUCCESS] Full DR Capacity restored!"
        break
    fi
    sleep 10
done
