# BloodHound Lab (CRTE)

On-demand BloodHound CE in AWS: a Cognito-gated landing page starts/stops the
instance, an idle timer auto-stops it (and revokes access) after inactivity,
and your ingested data survives every stop/start because it lives on a
separate EBS volume. Built for the duration of a CRTE exam; the last step is
tearing everything down.

## Architecture

See [`../.claude/plans` if you still have it, or just read the .tf files] -
short version: dedicated VPC, one EC2 instance (Docker Compose: Postgres +
Neo4j + BloodHound + a Caddy TLS sidecar on `bloodhound_port`), a security
group with no static ingress (Lambda opens/closes it per caller IP), Cognito
Hosted UI in front of a static S3+CloudFront landing page, API Gateway HTTP
API with a Cognito JWT authorizer backed by five small Lambdas
(`launch`/`status`/`heartbeat`/`stop`/`idle-check`), a DynamoDB heartbeat
table, and an AWS Budget for spend alerts.

## One-time setup

1. Install Terraform and the AWS CLI (already done if you're reading this
   after the initial build).
2. Create/attach a scoped IAM policy for whichever identity runs Terraform -
   `scripts/bootstrap-iam-policy.json` is provided; it's **not**
   `AdministratorAccess`, only the services this project touches.
3. `cd terraform && cp terraform.tfvars.example terraform.tfvars` and fill in
   `admin_email`. Adjust `instance_type`, `idle_timeout_minutes`,
   `monthly_budget_usd`, etc. if you want different defaults.
4. **Verify the BloodHound CE Docker Compose file** in
   `terraform/templates/docker-compose.yml.tftpl` against the current
   upstream quickstart before your first deploy:
   https://github.com/SpecterOps/BloodHound/blob/main/examples/docker-compose/docker-compose.yml
   Image tags and env var names have moved before.

## Deploy / redeploy

```
./scripts/deploy.sh
```

This runs `terraform apply`, then generates `frontend/config.js` from the
Terraform outputs and syncs `frontend/` to S3 + invalidates CloudFront. Safe
to re-run after any change to `terraform/` or `frontend/`.

First run: Cognito emails a temporary password to `admin_email`. Use it to
log in through the hosted UI on first visit; you'll be forced to set a real
password and can enable TOTP MFA.

## Day-to-day exam use

1. Open the `landing_page_url` Terraform output.
2. Log in (Cognito).
3. Click **Launch BloodHound** - the page polls until the instance is up,
   then shows an **Open BloodHound** link (self-signed cert; click through
   the browser warning - it's expected, see below).
4. Log into BloodHound itself with the credentials from its first-boot logs
   (see below) or whatever admin account you've since created.
5. Leave the tab open while you work - it heartbeats every 60s. Close it or
   walk away and after `idle_timeout_minutes` (default 20) the instance
   auto-stops and your IP's access is revoked. Your ingested data is
   untouched - it's on a separate EBS volume that isn't destroyed by a stop.
6. Or click **Log out & stop now** to end the session immediately.

**Retrieving BloodHound's first-boot admin credentials** (no SSH; use SSM):

```
aws ssm start-session --target "$(cd terraform && terraform output -raw instance_id)"
sudo docker compose -f /opt/bloodhound/docker-compose.yml logs bloodhound | grep -i password
```

**Why the browser cert warning:** BloodHound is reached over `https://<ip>:<port>`
with a Caddy-issued self-signed cert (no domain name was set up for a
short-lived exam lab). Access is already restricted to your current public IP
by the security group, so this is accepted risk for this deployment - not
appropriate for anything longer-lived or multi-user.

## If you change instances/rebuild mid-exam

Stopping/starting preserves data automatically (separate EBS volume). If you
ever need to replace the instance itself (e.g. change `instance_type`),
`terraform apply` will recreate `aws_instance.bloodhound` but the *data*
volume (`aws_ebs_volume.data`) is a separate resource and will reattach -
your Neo4j/Postgres data survives. Run `scripts/final-export.sh` first anyway
if you want a local safety copy before any risky change.

## Exam finished: full teardown

```
./scripts/final-export.sh            # pulls a tar of /data/{postgres,neo4j} to ~/bloodhound-export/
cd terraform && terraform destroy    # removes every AWS resource this project created
cd .. && ./scripts/verify-empty.sh   # independent check: confirms nothing tagged is still around
```

Then, since the dedicated/bootstrap IAM policy is no longer needed:
delete the inline policy from the IAM user (or delete the access keys /
the user itself, if you created one solely for this).

## Account-safety notes

- `panther-admin` (or whichever IAM user runs Terraform) should carry only
  `scripts/bootstrap-iam-policy.json`, not full admin access, for the
  duration of this project.
- The AWS Budget (`monthly_budget_usd`, default $20) emails `admin_email` at
  50/80/100% of the monthly cap. It's account-wide, not scoped to just this
  project's spend (AWS Budgets can't filter by tag without first activating
  Cost Allocation Tags manually in Billing settings).
- Enable MFA on your AWS root account and don't use root for day-to-day
  access, independent of this project.
- Nothing in this project opens SSH (port 22). Admin access to the instance
  is via SSM Session Manager only, using an instance role scoped to
  `AmazonSSMManagedInstanceCore` and nothing else.
- The BloodHound port is never open to the internet at large - the security
  group has no static ingress rules; `launch` authorizes only the calling
  browser's current IP, and `stop`/`idle-check` revoke it.

## Cost (rough, us-east-1, default sizing)

Idle-heavy usage (a few hours/day during exam prep) lands well under the
default $20/mo budget: EC2 t3.medium is ~$0.0416/hr only while *running*, EBS
gp3 storage is ~$0.08/GB-mo continuously (~$3.20/mo for both 20GB volumes
even while stopped), CloudFront/S3/Lambda/API Gateway/DynamoDB/Cognito are
all effectively free at this scale. The instance is the only meaningful
variable cost, and it's zero while stopped.
