import json
import os
import time

import boto3

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["TABLE_NAME"]


def handler(event, context):
    dynamodb.Table(TABLE_NAME).put_item(Item={"id": "session", "last_heartbeat": int(time.time())})
    return {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": json.dumps({"ok": True})}
