import json
import os
import ssl
import urllib.request

import boto3

ec2 = boto3.client("ec2")

INSTANCE_ID = os.environ["INSTANCE_ID"]
BLOODHOUND_PORT = os.environ["BLOODHOUND_PORT"]


def handler(event, context):
    instance = ec2.describe_instances(InstanceIds=[INSTANCE_ID])["Reservations"][0]["Instances"][0]
    state = instance["State"]["Name"]
    public_ip = instance.get("PublicIpAddress")

    ready = state == "running" and bool(public_ip) and _health_check(public_ip)

    body = {"state": state, "ready": ready}
    if ready:
        body["url"] = f"https://{public_ip}:{BLOODHOUND_PORT}"

    return _response(200, body)


def _health_check(ip):
    # BloodHound holds a self-signed cert (see terraform/templates/Caddyfile.tftpl);
    # this only proves the service is up, not that it's genuinely this instance -
    # that's fine here since the caller's IP was just allowlisted for this exact box.
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        with urllib.request.urlopen(f"https://{ip}:{BLOODHOUND_PORT}/ui/login", timeout=3, context=ctx):
            return True
    except Exception:
        return False


def _response(code, body):
    return {"statusCode": code, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}
