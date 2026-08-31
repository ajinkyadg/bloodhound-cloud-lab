import json
import os
import time

import boto3
from botocore.exceptions import ClientError

ec2 = boto3.client("ec2")
dynamodb = boto3.resource("dynamodb")

INSTANCE_ID = os.environ["INSTANCE_ID"]
SECURITY_GROUP_ID = os.environ["SECURITY_GROUP_ID"]
BLOODHOUND_PORT = int(os.environ["BLOODHOUND_PORT"])
TABLE_NAME = os.environ["TABLE_NAME"]


def handler(event, context):
    source_ip = event["requestContext"]["http"]["sourceIp"]
    cidr = f"{source_ip}/32"

    instance = ec2.describe_instances(InstanceIds=[INSTANCE_ID])["Reservations"][0]["Instances"][0]
    state = instance["State"]["Name"]

    if state == "stopped":
        ec2.start_instances(InstanceIds=[INSTANCE_ID])
    elif state not in ("running", "pending"):
        # stopping / shutting-down / terminated: nothing sensible to do, report back
        return _response(409, {"error": f"instance is in state '{state}', try again shortly"})

    _authorize_ip(cidr)
    _touch_heartbeat()

    return _response(200, {"state": "starting", "message": "Instance is starting. Poll /status."})


def _authorize_ip(cidr):
    try:
        ec2.authorize_security_group_ingress(
            GroupId=SECURITY_GROUP_ID,
            IpPermissions=[
                {
                    "IpProtocol": "tcp",
                    "FromPort": BLOODHOUND_PORT,
                    "ToPort": BLOODHOUND_PORT,
                    "IpRanges": [{"CidrIp": cidr, "Description": "bloodhound-client"}],
                }
            ],
        )
    except ClientError as e:
        if e.response["Error"]["Code"] != "InvalidPermission.Duplicate":
            raise


def _touch_heartbeat():
    dynamodb.Table(TABLE_NAME).put_item(Item={"id": "session", "last_heartbeat": int(time.time())})


def _response(code, body):
    return {"statusCode": code, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}
