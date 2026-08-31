import json
import os

import boto3

ec2 = boto3.client("ec2")

INSTANCE_ID = os.environ["INSTANCE_ID"]
SECURITY_GROUP_ID = os.environ["SECURITY_GROUP_ID"]


def handler(event, context):
    _revoke_all_ingress()
    ec2.stop_instances(InstanceIds=[INSTANCE_ID])
    return {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": json.dumps({"state": "stopping"})}


def _revoke_all_ingress():
    sg = ec2.describe_security_groups(GroupIds=[SECURITY_GROUP_ID])["SecurityGroups"][0]
    perms = sg.get("IpPermissions", [])
    if perms:
        ec2.revoke_security_group_ingress(GroupId=SECURITY_GROUP_ID, IpPermissions=perms)
