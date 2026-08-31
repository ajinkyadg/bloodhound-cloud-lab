#!/usr/bin/env bash
# Applies the Terraform stack, then builds and publishes the frontend config
# from its outputs. Safe to re-run any time you change frontend/ or terraform/.
set -euo pipefail

cd "$(dirname "$0")/../terraform"

if [ ! -f terraform.tfvars ]; then
  echo "terraform/terraform.tfvars not found. Copy terraform.tfvars.example and fill in admin_email first." >&2
  exit 1
fi

terraform init -upgrade=false
terraform apply

API_BASE=$(terraform output -raw api_base_url)
COGNITO_DOMAIN=$(terraform output -raw cognito_hosted_ui_domain)
CLIENT_ID=$(terraform output -raw cognito_app_client_id)
BUCKET=$(terraform output -raw frontend_bucket_name)
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
LANDING_URL=$(terraform output -raw landing_page_url)

cd ../frontend

cat > config.js <<EOF
window.BLOODHOUND_CONFIG = {
  API_BASE: "${API_BASE}",
  COGNITO_DOMAIN: "${COGNITO_DOMAIN}",
  CLIENT_ID: "${CLIENT_ID}",
};
EOF

aws s3 sync . "s3://${BUCKET}" --delete --exclude "config.example.js"
aws cloudfront create-invalidation --distribution-id "${DISTRIBUTION_ID}" --paths "/*" >/dev/null

echo
echo "Deployed. Landing page: ${LANDING_URL}"
echo "Cognito emailed a temporary password to your admin_email - use it on first login."
