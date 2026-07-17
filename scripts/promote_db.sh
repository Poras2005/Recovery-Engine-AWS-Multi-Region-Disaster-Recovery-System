#!/usr/bin/env bash
# scripts/promote_db.sh

# Load config
CONFIG_FILE="config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then CONFIG_FILE="../config.yaml"; fi
if [ ! -f "$CONFIG_FILE" ]; then echo "[ERROR] config.yaml not found!"; exit 1; fi

parse_yaml() {
    python3 -c "import yaml; print(yaml.safe_load(open('$1'))$2)" 2>/dev/null
}

APP_NAME=$(parse_yaml "$CONFIG_FILE" "['app']['name']")
SECONDARY_REGION=$(parse_yaml "$CONFIG_FILE" "['aws']['secondary_region']")
DB_IDENTIFIER="${APP_NAME}-db-${SECONDARY_REGION}"

echo "========================================================"
echo " 🌍 Promoting RDS Read Replica in $SECONDARY_REGION"
echo "========================================================\n"

# Verify credentials
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Enter AWS Credentials to authorize promotion:"
    read -rsp " AWS Access Key ID     : " AWS_ACCESS_KEY_ID
    echo ""
    read -rsp " AWS Secret Access Key : " AWS_SECRET_ACCESS_KEY
    echo ""
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
fi

echo "Promoting RDS Read Replica ($DB_IDENTIFIER) in $SECONDARY_REGION to standalone master..."
if aws rds promote-read-replica --db-instance-identifier "$DB_IDENTIFIER" --region "$SECONDARY_REGION"; then
    echo " [SUCCESS] RDS promotion initiated. The DB will restart and become read-write."
else
    echo " [ERROR] Failed to promote database."
    exit 1
fi
