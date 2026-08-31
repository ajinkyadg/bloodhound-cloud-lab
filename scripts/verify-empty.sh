#!/usr/bin/env bash
# Read-only. Run after `terraform destroy` to confirm nothing tagged for this
# project is still running/billing in your AWS account. Terraform state can
# miss things (a resource created out-of-band, a CloudFront distribution
# stuck disabling) - this is the independent second check.
set -euo pipefail

cd "$(dirname "$0")/../terraform"
PROJECT_NAME="crte-bloodhound"
# Prefer the value from terraform.tfvars if present, otherwise the default project_name.
if [ -f terraform.tfvars ] && grep -q '^project_name' terraform.tfvars; then
  PROJECT_NAME=$(grep '^project_name' terraform.tfvars | sed -E 's/.*=\s*"([^"]+)".*/\1/')
fi

echo "Checking for any remaining resources tagged Project=${PROJECT_NAME} ..."
echo

FOUND=0

TAGGED=$(aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=Project,Values=${PROJECT_NAME}" \
  --query "ResourceTagMappingList[].ResourceARN" --output text)

if [ -n "$TAGGED" ]; then
  echo "Still tagged and present:"
  echo "$TAGGED" | tr '\t' '\n' | sed 's/^/  - /'
  FOUND=1
else
  echo "No tagged resources found via Resource Groups Tagging API."
fi

echo
echo "Checking EC2 instances by tag (terminated instances are expected to linger briefly and are not billed):"
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=${PROJECT_NAME}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].[InstanceId,State.Name]" --output text | tee /tmp/bh-instances.txt
if [ -s /tmp/bh-instances.txt ]; then
  FOUND=1
fi

echo
echo "Checking AWS Budgets (not covered by the tagging API):"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUDGETS=$(aws budgets describe-budgets --account-id "$ACCOUNT_ID" \
  --query "Budgets[?starts_with(BudgetName, '${PROJECT_NAME}')].BudgetName" --output text)
if [ -n "$BUDGETS" ]; then
  echo "Still present: $BUDGETS"
  FOUND=1
else
  echo "None found."
fi

echo
if [ "$FOUND" -eq 0 ]; then
  echo "Clean. No ${PROJECT_NAME} resources remain."
else
  echo "Resources still remain - re-run 'terraform destroy' in terraform/, or remove the above manually." >&2
  exit 1
fi
