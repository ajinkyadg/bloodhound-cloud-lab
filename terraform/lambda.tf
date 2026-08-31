locals {
  instance_arn       = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.bloodhound.id}"
  security_group_arn = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:security-group/${aws_security_group.bloodhound.id}"

  lambda_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  common_env = {
    INSTANCE_ID          = aws_instance.bloodhound.id
    SECURITY_GROUP_ID    = aws_security_group.bloodhound.id
    BLOODHOUND_PORT      = tostring(var.bloodhound_port)
    TABLE_NAME           = aws_dynamodb_table.heartbeat.name
    IDLE_TIMEOUT_MINUTES = tostring(var.idle_timeout_minutes)
  }

  # Scoped CloudWatch Logs statement, one per function name.
  log_statement = { for name in ["launch", "status", "heartbeat", "stop", "idle-check", "credentials"] : name => {
    Effect   = "Allow"
    Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-${name}*:*"
  } }
}

# ================= launch =================
resource "aws_iam_role" "launch" {
  name               = "${var.project_name}-launch-role"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "launch" {
  name = "${var.project_name}-launch-policy"
  role = aws_iam_role.launch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ec2:DescribeInstances"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:StartInstances"], Resource = local.instance_arn },
      { Effect = "Allow", Action = ["ec2:AuthorizeSecurityGroupIngress"], Resource = local.security_group_arn },
      { Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = aws_dynamodb_table.heartbeat.arn },
      local.log_statement["launch"],
    ]
  })
}

data "archive_file" "launch" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/launch"
  output_path = "${path.module}/build/launch.zip"
}

resource "aws_lambda_function" "launch" {
  function_name    = "${var.project_name}-launch"
  role             = aws_iam_role.launch.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.launch.output_path
  source_code_hash = data.archive_file.launch.output_base64sha256
  environment { variables = local.common_env }
}

# ================= status =================
resource "aws_iam_role" "status" {
  name               = "${var.project_name}-status-role"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "status" {
  name = "${var.project_name}-status-policy"
  role = aws_iam_role.status.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ec2:DescribeInstances"], Resource = "*" },
      local.log_statement["status"],
    ]
  })
}

data "archive_file" "status" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/status"
  output_path = "${path.module}/build/status.zip"
}

resource "aws_lambda_function" "status" {
  function_name    = "${var.project_name}-status"
  role             = aws_iam_role.status.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.status.output_path
  source_code_hash = data.archive_file.status.output_base64sha256
  environment { variables = local.common_env }
}

# ================= heartbeat =================
resource "aws_iam_role" "heartbeat" {
  name               = "${var.project_name}-heartbeat-role"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "heartbeat" {
  name = "${var.project_name}-heartbeat-policy"
  role = aws_iam_role.heartbeat.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = aws_dynamodb_table.heartbeat.arn },
      local.log_statement["heartbeat"],
    ]
  })
}

data "archive_file" "heartbeat" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/heartbeat"
  output_path = "${path.module}/build/heartbeat.zip"
}

resource "aws_lambda_function" "heartbeat" {
  function_name    = "${var.project_name}-heartbeat"
  role             = aws_iam_role.heartbeat.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 5
  filename         = data.archive_file.heartbeat.output_path
  source_code_hash = data.archive_file.heartbeat.output_base64sha256
  environment { variables = local.common_env }
}

# ================= stop =================
resource "aws_iam_role" "stop" {
  name               = "${var.project_name}-stop-role"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "stop" {
  name = "${var.project_name}-stop-policy"
  role = aws_iam_role.stop.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ec2:DescribeSecurityGroups"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:RevokeSecurityGroupIngress"], Resource = local.security_group_arn },
      { Effect = "Allow", Action = ["ec2:StopInstances"], Resource = local.instance_arn },
      local.log_statement["stop"],
    ]
  })
}

data "archive_file" "stop" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/stop"
  output_path = "${path.module}/build/stop.zip"
}

resource "aws_lambda_function" "stop" {
  function_name    = "${var.project_name}-stop"
  role             = aws_iam_role.stop.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.stop.output_path
  source_code_hash = data.archive_file.stop.output_base64sha256
  environment { variables = local.common_env }
}

# ================= idle-check =================
resource "aws_iam_role" "idle_check" {
  name               = "${var.project_name}-idle-check-role"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "idle_check" {
  name = "${var.project_name}-idle-check-policy"
  role = aws_iam_role.idle_check.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ec2:DescribeInstances", "ec2:DescribeSecurityGroups"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:RevokeSecurityGroupIngress"], Resource = local.security_group_arn },
      { Effect = "Allow", Action = ["ec2:StopInstances"], Resource = local.instance_arn },
      { Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = aws_dynamodb_table.heartbeat.arn },
      local.log_statement["idle-check"],
    ]
  })
}

data "archive_file" "idle_check" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/idle_check"
  output_path = "${path.module}/build/idle_check.zip"
}

resource "aws_lambda_function" "idle_check" {
  function_name    = "${var.project_name}-idle-check"
  role             = aws_iam_role.idle_check.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.idle_check.output_path
  source_code_hash = data.archive_file.idle_check.output_base64sha256
  environment { variables = local.common_env }
}

# ================= credentials =================
resource "aws_iam_role" "credentials" {
  name               = "${var.project_name}-credentials-role"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "credentials" {
  name = "${var.project_name}-credentials-policy"
  role = aws_iam_role.credentials.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:SendCommand"]
        Resource = [
          local.instance_arn,
          "arn:aws:ssm:${data.aws_region.current.name}::document/AWS-RunShellScript",
        ]
      },
      # GetCommandInvocation doesn't support resource-level restriction (AWS
      # limitation, same as the ec2:Describe* actions elsewhere in this file).
      { Effect = "Allow", Action = ["ssm:GetCommandInvocation"], Resource = "*" },
      local.log_statement["credentials"],
    ]
  })
}

data "archive_file" "credentials" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/credentials"
  output_path = "${path.module}/build/credentials.zip"
}

resource "aws_lambda_function" "credentials" {
  function_name    = "${var.project_name}-credentials"
  role             = aws_iam_role.credentials.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 25
  filename         = data.archive_file.credentials.output_path
  source_code_hash = data.archive_file.credentials.output_base64sha256
  environment { variables = local.common_env }
}

# EventBridge schedule driving idle-check every 5 minutes
resource "aws_cloudwatch_event_rule" "idle_check" {
  name                = "${var.project_name}-idle-check"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "idle_check" {
  rule = aws_cloudwatch_event_rule.idle_check.name
  arn  = aws_lambda_function.idle_check.arn
}

resource "aws_lambda_permission" "idle_check_events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.idle_check.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.idle_check.arn
}
