resource "aws_apigatewayv2_api" "this" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://${aws_cloudfront_distribution.frontend.domain_name}"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project_name}-cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.spa.id]
    issuer   = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}

# ---------- routes: launch / status / heartbeat / stop ----------
locals {
  routes = {
    launch    = { method = "POST", path = "/launch", fn = aws_lambda_function.launch }
    status    = { method = "GET", path = "/status", fn = aws_lambda_function.status }
    heartbeat   = { method = "POST", path = "/heartbeat", fn = aws_lambda_function.heartbeat }
    stop        = { method = "POST", path = "/stop", fn = aws_lambda_function.stop }
    credentials = { method = "GET", path = "/credentials", fn = aws_lambda_function.credentials }
  }
}

resource "aws_apigatewayv2_integration" "this" {
  for_each = local.routes

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.fn.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.routes

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "${each.value.method} ${each.value.path}"
  target             = "integrations/${aws_apigatewayv2_integration.this[each.key].id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "apigw" {
  for_each = local.routes

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = each.value.fn.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
