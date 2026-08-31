output "landing_page_url" {
  value = "https://${aws_cloudfront_distribution.frontend.domain_name}/"
}

output "api_base_url" {
  value = aws_apigatewayv2_api.this.api_endpoint
}

output "cognito_hosted_ui_domain" {
  value = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.spa.id
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.frontend.id
}

output "instance_id" {
  value = aws_instance.bloodhound.id
}

output "security_group_id" {
  value = aws_security_group.bloodhound.id
}
