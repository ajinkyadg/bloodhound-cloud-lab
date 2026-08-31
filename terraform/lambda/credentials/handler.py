import json
import os
import time

import boto3

ssm = boto3.client("ssm")

INSTANCE_ID = os.environ["INSTANCE_ID"]

# Reuses the same SSM RunCommand pattern as scripts/final-export.sh - no SSH,
# no persistent secret storage. The password only ever exists transiently in
# this response; nothing is written to disk or a database on our side.
COMMANDS = [
    "cd /opt/bloodhound",
    "docker compose logs bloodhound 2>/dev/null | grep -i password | tail -5",
]


def handler(event, context):
    command_id = ssm.send_command(
        InstanceIds=[INSTANCE_ID],
        DocumentName="AWS-RunShellScript",
        Comment="bloodhound fetch initial admin credentials",
        Parameters={"commands": COMMANDS},
    )["Command"]["CommandId"]

    result = None
    for _ in range(20):
        time.sleep(1)
        try:
            result = ssm.get_command_invocation(CommandId=command_id, InstanceId=INSTANCE_ID)
        except ssm.exceptions.InvocationDoesNotExist:
            continue
        if result["Status"] in ("Success", "Failed", "Cancelled", "TimedOut"):
            break
    else:
        return _response(504, {"error": "timed out waiting for the instance to run the command"})

    if result is None or result["Status"] != "Success":
        status = result["Status"] if result else "unknown"
        return _response(502, {"error": f"command did not succeed (status: {status})"})

    output = result.get("StandardOutputContent", "").strip()
    if not output:
        output = (
            "No password line found in the container logs. Either BloodHound "
            "hasn't finished starting yet, or the admin password was already "
            "rotated after a first login (in which case use that new one)."
        )
    return _response(200, {"output": output})


def _response(code, body):
    return {"statusCode": code, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}
