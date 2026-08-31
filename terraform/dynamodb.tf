# Single-item table tracking when the landing page last heartbeat'd, so
# idle_check can decide whether to auto-stop the instance.
resource "aws_dynamodb_table" "heartbeat" {
  name         = "${var.project_name}-heartbeat"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}
