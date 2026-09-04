import json
import os
import time

import boto3

ssm = boto3.client("ssm")

INSTANCE_ID = os.environ["INSTANCE_ID"]

# Reuses the same SSM RunCommand pattern as scripts/final-export.sh - no SSH,
# nothing new added to our own AWS-side storage.
#
# Reads /opt/bloodhound/.env rather than grepping live container logs: the
# "Initial Password Set To" line only ever appears on the very first boot,
# when the admin account doesn't exist yet in the (persisted) database. Every
# boot after that has no such line - user_data.sh.tftpl captures it once, on
# first boot, into .env precisely so this keeps working across every
# subsequent stop/start.
COMMANDS = [
    "grep -E '^BLOODHOUND_ADMIN_(USERNAME|PASSWORD)=' /opt/bloodhound/.env",
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
            "No stored credentials found on the instance. Either BloodHound "
            "hasn't finished its first boot yet, or you've since changed the "
            "admin password yourself in BloodHound's UI (in which case use "
            "that new one - this button only ever shows the original)."
        )
    return _response(200, {"output": output})


def _response(code, body):
    return {"statusCode": code, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}
