import os
import time

import boto3

ec2 = boto3.client("ec2")
dynamodb = boto3.resource("dynamodb")

INSTANCE_ID = os.environ["INSTANCE_ID"]
SECURITY_GROUP_ID = os.environ["SECURITY_GROUP_ID"]
TABLE_NAME = os.environ["TABLE_NAME"]
IDLE_TIMEOUT_MINUTES = int(os.environ["IDLE_TIMEOUT_MINUTES"])


def handler(event, context):
    instance = ec2.describe_instances(InstanceIds=[INSTANCE_ID])["Reservations"][0]["Instances"][0]
    if instance["State"]["Name"] != "running":
        return {"skipped": "not running"}

    item = dynamodb.Table(TABLE_NAME).get_item(Key={"id": "session"}).get("Item")
    last_heartbeat = item["last_heartbeat"] if item else 0
    idle_seconds = time.time() - last_heartbeat

    if idle_seconds > IDLE_TIMEOUT_MINUTES * 60:
        _revoke_all_ingress()
        ec2.stop_instances(InstanceIds=[INSTANCE_ID])
        return {"stopped": True, "idle_seconds": idle_seconds}

    return {"stopped": False, "idle_seconds": idle_seconds}


def _revoke_all_ingress():
    sg = ec2.describe_security_groups(GroupIds=[SECURITY_GROUP_ID])["SecurityGroups"][0]
    perms = sg.get("IpPermissions", [])
    if perms:
        ec2.revoke_security_group_ingress(GroupId=SECURITY_GROUP_ID, IpPermissions=perms)
