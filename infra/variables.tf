variable "project_name" {
  type        = string
  default     = "meetings"
  description = "Name prefix for all resources"
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "callback_urls" {
  type = list(string)
  default = [
    "http://localhost:3000/auth/callback",
    "http://localhost:5173/auth/callback",
    "https://d1ba8tbsejcok2.cloudfront.net/auth/callback"
  ]
  description = "Where the Hosted UI may send users back after sign-in"
}

variable "logout_urls" {
  type = list(string)
  default = [
    "http://localhost:3000/",
    "http://localhost:5173/",
    "https://d1ba8tbsejcok2.cloudfront.net/"
  ]
  description = "Where the Hosted UI may send users after signing out"
}

variable "google_client_id" {
  type        = string
  default     = "532698219081-06sma0vq3gg31v8shfcbopodomb0v72j.apps.googleusercontent.com"
  description = "OAuth client ID from Google Cloud"
}

variable "google_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "OAuth client secret from Google Cloud"
}

variable "image_uri" {
  type        = string
  default     = "561721572034.dkr.ecr.us-east-1.amazonaws.com/meetings-backend:3676d6f-dirty-20261029184417"
  description = "Backend container image URI reused for report-builder and agenda-parser"
}

variable "architecture" {
  type        = string
  default     = "x86_64"
  description = "CPU architecture matching the backend container image"
}

variable "sender_email" {
  type        = string
  default     = "vlasyuk.pn@ucu.edu.ua"
  description = "Verified SES email address used as From: in reports"
}

variable "recipient_email" {
  type        = string
  default     = "vlasyuk.pn@ucu.edu.ua"
  description = "Verified SES email address used as To: for reports"
}

variable "schedule_expression" {
  type        = string
  default     = "cron(0 7 ? * MON *)"
  description = "Cron schedule expression for the weekly report"
}

variable "schedule_timezone" {
  type        = string
  default     = "Europe/Kyiv"
  description = "Timezone for the EventBridge schedule"
}

variable "parser_model" {
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  description = "Bedrock model ID for agenda parsing"
}

variable "cors_origins" {
  type = list(string)
  default = [
    "http://localhost:3000",
    "http://localhost:5173",
    "https://d1ba8tbsejcok2.cloudfront.net"
  ]
  description = "Allowed origins for Function URL CORS"
}
