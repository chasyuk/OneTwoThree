output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "Cognito User Pool ID"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "Cognito User Pool App Client ID"
}

output "cognito_hosted_ui_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "Cognito Hosted UI Domain prefix"
}

output "cognito_issuer" {
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  description = "Cognito Token Issuer"
}

output "reports_bucket_name" {
  value       = aws_s3_bucket.reports.bucket
  description = "S3 Bucket storing weekly CSV reports"
}

output "report_requests_queue_url" {
  value       = aws_sqs_queue.reports_requests.url
  description = "SQS Queue URL for report requests"
}

output "report_requests_queue_arn" {
  value       = aws_sqs_queue.reports_requests.arn
  description = "SQS Queue ARN"
}

output "report_requests_dlq_url" {
  value       = aws_sqs_queue.reports_dlq.url
  description = "SQS Dead-Letter Queue URL"
}

output "builder_function_name" {
  value       = aws_lambda_function.builder.function_name
  description = "Lambda Function Name for Report Builder"
}

output "mailer_function_name" {
  value       = aws_lambda_function.mailer.function_name
  description = "Lambda Function Name for Report Mailer"
}

output "schedule_name" {
  value       = aws_scheduler_schedule.weekly.name
  description = "EventBridge Schedule Name"
}

output "parser_function_arn" {
  value       = aws_lambda_function.agenda_parser.arn
  description = "Agenda parser Lambda function ARN"
}

output "parser_url" {
  value       = aws_lambda_function_url.agenda_parser.function_url
  description = "Agenda parser Function URL"
}

output "google_enabled" {
  value       = local.google_enabled ? "true" : "false"
  description = "Whether Google sign-in is enabled"
}
