import json
import os
from datetime import datetime, timezone

import boto3

ec2 = boto3.client("ec2")

INSTANCE_ID = os.environ["INSTANCE_ID"]
BLOODHOUND_PORT = os.environ["BLOODHOUND_PORT"]

# The security group only ever allowlists the calling browser's IP (see
# launch/handler.py) - Lambda's own outbound path never matches that IP, so
# a real network health check from here is structurally impossible without
# opening the instance up more broadly (which we deliberately don't do).
# Instead, treat the instance as ready once it's been running long enough
# for Docker + the compose stack to come up. Conservative: covers a cold
# first boot (installing Docker, pulling images); a stop/start restart with
# cached images is ready well before this elapses.
BOOT_GRACE_SECONDS = int(os.environ.get("BOOT_GRACE_SECONDS", "180"))


def handler(event, context):
    instance = ec2.describe_instances(InstanceIds=[INSTANCE_ID])["Reservations"][0]["Instances"][0]
    state = instance["State"]["Name"]
    public_ip = instance.get("PublicIpAddress")
    launch_time = instance.get("LaunchTime")  # updates on every start, not just original creation

    booted_long_enough = bool(launch_time) and (
        datetime.now(timezone.utc) - launch_time
    ).total_seconds() > BOOT_GRACE_SECONDS

    ready = state == "running" and bool(public_ip) and booted_long_enough

    body = {"state": state, "ready": ready}
    if ready:
        body["url"] = f"https://{public_ip}:{BLOODHOUND_PORT}"

    return _response(200, body)


def _response(code, body):
    return {"statusCode": code, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}
