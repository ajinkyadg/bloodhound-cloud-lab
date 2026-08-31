#!/usr/bin/env bash
# Run this BEFORE `terraform destroy` once your CRTE exam is done. Pulls the
# raw Neo4j + Postgres data directories off the instance (via SSM - no SSH
# needed) down to your local disk, so the destroy step below doesn't lose
# your ingested data. Restore by untarring back into /data/{postgres,neo4j}
# on a fresh deploy.
set -euo pipefail

cd "$(dirname "$0")/../terraform"

INSTANCE_ID=$(terraform output -raw instance_id)
BUCKET=$(terraform output -raw exports_bucket_name)

OUT_DIR="${1:-$HOME/bloodhound-export}"
mkdir -p "$OUT_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
OUT_FILE="$OUT_DIR/bloodhound-export-$STAMP.tar.gz"

echo "Checking instance is running..."
STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].State.Name" --output text)
if [ "$STATE" != "running" ]; then
  echo "Instance is '$STATE', not 'running'. Start it (via the landing page) before exporting." >&2
  exit 1
fi

echo "Stopping the BloodHound stack, tarring /data, uploading to s3://$BUCKET, restarting the stack..."
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --comment "bloodhound final-export" \
  --parameters 'commands=[
    "systemctl stop bloodhound.service",
    "tar -czf /tmp/bloodhound-export.tar.gz -C /data postgres neo4j",
    "aws s3 cp /tmp/bloodhound-export.tar.gz s3://'"$BUCKET"'/export.tar.gz",
    "rm -f /tmp/bloodhound-export.tar.gz",
    "systemctl start bloodhound.service"
  ]' \
  --query "Command.CommandId" --output text)

echo "Waiting for command $COMMAND_ID to finish (this can take a minute)..."
aws ssm wait command-executed --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" || true

STATUS=$(aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" --query "Status" --output text)
if [ "$STATUS" != "Success" ]; then
  echo "SSM command did not succeed (status: $STATUS). Output:" >&2
  aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
    --query "StandardErrorContent" --output text >&2
  exit 1
fi

echo "Downloading export to $OUT_FILE ..."
aws s3 cp "s3://$BUCKET/export.tar.gz" "$OUT_FILE"
aws s3 rm "s3://$BUCKET/export.tar.gz"

echo
echo "Done. Data saved locally at: $OUT_FILE"
echo "You can now safely run: terraform destroy"
