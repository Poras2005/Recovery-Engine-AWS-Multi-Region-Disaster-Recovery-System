#!/usr/bin/env bash
# scripts/teardown.sh

CONFIG_FILE="config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then CONFIG_FILE="../config.yaml"; fi
if [ ! -f "$CONFIG_FILE" ]; then echo "[ERROR] config.yaml not found!"; exit 1; fi

parse_yaml() {
    python3 -c "import yaml; print(yaml.safe_load(open('$1'))$2)" 2>/dev/null
}

PRIMARY_REGION=$(parse_yaml "$CONFIG_FILE" "['aws']['primary_region']")
SECONDARY_REGION=$(parse_yaml "$CONFIG_FILE" "['aws']['secondary_region']")
APP_NAME=$(parse_yaml "$CONFIG_FILE" "['app']['name']")
LOCK_TABLE=$(parse_yaml "$CONFIG_FILE" "['terraform']['lock_table']")
STATE_SUFFIX=$(parse_yaml "$CONFIG_FILE" "['terraform']['state_bucket_suffix']")

echo "========================================================"
echo " 🌍 AWS Multi-Region DR — COMPLETE INFRASTRUCTURE TEARDOWN"
echo "========================================================\n"
echo " Warning: This will completely destroy all databases, VPCs,"
echo " servers, ECR images, and backend storage created for this project."
echo ""

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$DB_PASSWORD" ]; then
    echo "Enter Credentials to authorize teardown:"
    read -rsp " AWS Access Key ID     : " AWS_ACCESS_KEY_ID
    echo ""
    read -rsp " AWS Secret Access Key : " AWS_SECRET_ACCESS_KEY
    echo ""
    read -rp " AWS Account ID        : " AWS_ACCOUNT_ID
    read -rsp " Database Password     : " DB_PASSWORD
    echo ""
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_ACCOUNT_ID
    export DB_PASSWORD
fi

BUCKET="${AWS_ACCOUNT_ID}-${STATE_SUFFIX}"

# Set up Terraform Environment Variables
export TF_VAR_account_id="$AWS_ACCOUNT_ID"
export TF_VAR_state_bucket="$BUCKET"
export TF_VAR_app_name="$APP_NAME"
export TF_VAR_instance_type=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['instance_type']")
export TF_VAR_min_size=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['min_instances']")
export TF_VAR_max_size=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['max_instances']")
export TF_VAR_desired_size=$(parse_yaml "$CONFIG_FILE" "['autoscaling']['desired_instances']")
export TF_VAR_db_password="$DB_PASSWORD"
export TF_VAR_primary_alb_dns="none"
export TF_VAR_secondary_alb_dns="none"
export TF_VAR_domain=$(parse_yaml "$CONFIG_FILE" "['route53']['domain']")
export TF_VAR_health_check_path=$(parse_yaml "$CONFIG_FILE" "['route53']['health_check_path']")
export TF_VAR_failover_ttl=$(parse_yaml "$CONFIG_FILE" "['route53']['failover_ttl']")

# 1. Destroy Global
echo -e "\n--- 1. Destroying Global Routing & WAF ---"
cd terraform/global || cd ../terraform/global
terraform init -reconfigure -backend-config="bucket=${BUCKET}"
terraform destroy -auto-approve
cd ../..

# 2. Destroy Singapore
echo -e "\n--- 2. Destroying Singapore Standby Region ---"
cd terraform/regions/singapore || cd ../terraform/regions/singapore
terraform init -reconfigure -backend-config="bucket=${BUCKET}"
terraform destroy -auto-approve
cd ../../..

# 3. Destroy Mumbai
echo -e "\n--- 3. Destroying Mumbai Primary Region ---"
cd terraform/regions/mumbai || cd ../terraform/regions/mumbai
terraform init -reconfigure -backend-config="bucket=${BUCKET}"
terraform destroy -auto-approve
cd ../../..

# 4. Delete ECR Repository
echo -e "\n--- 4. Deleting ECR Repository ---"
aws ecr delete-repository --repository-name "$APP_NAME" --force --region "$PRIMARY_REGION" || true

# 5. Delete DynamoDB Lock Table
echo -e "\n--- 5. Deleting DynamoDB Lock Table ---"
aws dynamodb delete-table --table-name "$LOCK_TABLE" --region "$PRIMARY_REGION" || true

# 6. Delete SSM Parameters
echo -e "\n--- 6. Deleting SSM Parameters ---"
aws ssm delete-parameters --names "/dr-app/account_id" "/dr-app/primary_region" "/dr-app/secondary_region" "/dr-app/app_name" "/dr-app/slack_webhook" --region "$PRIMARY_REGION" || true

# 7. Delete CloudWatch Alarms
echo -e "\n--- 7. Deleting CloudWatch Alarms ---"
aws cloudwatch delete-alarms --alarm-names "DR-High-CPU-Mumbai" "DR-Unhealthy-Hosts-Mumbai" --region "$PRIMARY_REGION" || true

# 8. Delete SNS Topic
echo -e "\n--- 8. Deleting SNS Topic ---"
aws sns delete-topic --topic-arn "arn:aws:sns:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:dr-alerts" --region "$PRIMARY_REGION" || true

# 9. Delete S3 State Bucket
echo -e "\n--- 9. Deleting S3 State Bucket ---"
echo " Listing and deleting all objects/versions in $BUCKET..."
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    python3 -c "
import boto3
s3 = boto3.client('s3')
bucket = '$BUCKET'
try:
    paginator = s3.get_paginator('list_object_versions')
    for page in paginator.paginate(Bucket=bucket):
        objs = []
        for v in page.get('Versions', []):
            objs.append({'Key': v['Key'], 'VersionId': v['VersionId']})
        for m in page.get('DeleteMarkers', []):
            objs.append({'Key': m['Key'], 'VersionId': m['VersionId']})
        if objs:
            s3.delete_objects(Bucket=bucket, Delete={'Objects': objs})
except Exception as e:
    print('Error version nuke:', e)
"
    aws s3api delete-bucket --bucket "$BUCKET" --region "$PRIMARY_REGION" || true
    echo " [SUCCESS] State S3 bucket deleted."
else
    echo " Bucket does not exist or already deleted."
fi

echo -e "\n========================================================"
echo " TEARDOWN COMPLETE! All AWS resources have been destroyed."
echo "========================================================\n"
