# Fetch backend stack resources/outputs
data "aws_cloudformation_stack" "backend" {
  name = "${var.project_name}-backend"
}

data "aws_secretsmanager_secret_version" "db" {
  secret_id = data.aws_cloudformation_stack.backend.outputs["DbSecretArn"]
}

# In-VPC Gateway Endpoint for S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = "vpc-00184e0c352436f02"
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = ["rtb-0cacfc1b04928b2d3"]

  tags = {
    PROJECT_NAME = var.project_name
  }
}

# SQS Queues
resource "aws_sqs_queue" "reports_dlq" {
  name = "${var.project_name}-report-requests-dlq"

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_sqs_queue" "reports_requests" {
  name                       = "${var.project_name}-report-requests"
  visibility_timeout_seconds = 360

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.reports_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    PROJECT_NAME = var.project_name
  }
}

# Builder IAM Role
resource "aws_iam_role" "builder" {
  name = "meetings-reports-BuilderRole-0OwToWcigSAF"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "builder_vpc" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "builder_s3_sqs" {
  name = "S3AndSqsAccess"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::${var.project_name}-reports-${data.aws_caller_identity.current.account_id}/reports/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.reports_requests.arn
      }
    ]
  })
}

# Builder Lambda Function
resource "aws_lambda_function" "builder" {
  function_name = "${var.project_name}-report-builder"
  package_type  = "Image"
  image_uri     = var.image_uri
  role          = aws_iam_role.builder.arn
  timeout       = 60
  memory_size   = 512
  architectures = [var.architecture]

  image_config {
    command = ["app.reports.lambda_handler.handler"]
  }

  vpc_config {
    subnet_ids         = ["subnet-03a62f84f459d57c6", "subnet-0526fc184b6e7beb1"]
    security_group_ids = ["sg-00a337bd60210977b"]
  }

  environment {
    variables = {
      DB_HOST        = data.aws_cloudformation_stack.backend.outputs["DbEndpoint"]
      DB_PORT        = "5432"
      DB_NAME        = "meetings"
      DB_USER        = "meetings"
      DB_PASSWORD    = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)["password"]
      DB_NULL_POOL   = "true"
      REPORTS_BUCKET = "${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"
    }
  }

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_lambda_event_source_mapping" "builder" {
  event_source_arn = aws_sqs_queue.reports_requests.arn
  function_name    = aws_lambda_function.builder.arn
  batch_size       = 1
  enabled          = true
}

# EventBridge Scheduler Role & Schedule
resource "aws_iam_role" "scheduler" {
  name = "meetings-reports-SchedulerRole-eWWpgVFaMCyL"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_iam_role_policy" "scheduler_sqs" {
  name = "SqsSendMessage"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.reports_requests.arn
    }]
  })
}

resource "aws_scheduler_schedule" "weekly" {
  name                         = "${var.project_name}-weekly-report"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.reports_requests.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ week = null, source = "schedule" })
  }
}

# Mailer IAM Role
resource "aws_iam_role" "mailer" {
  name = "meetings-reports-MailerRole-8O4rXtwz3gFv"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "mailer_basic" {
  role       = aws_iam_role.mailer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "mailer_s3_ses" {
  name = "S3AndSesAccess"
  role = aws_iam_role.mailer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.project_name}-reports-${data.aws_caller_identity.current.account_id}/reports/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      }
    ]
  })
}

# Inline Python code for Mailer Lambda
data "archive_file" "mailer_zip" {
  type        = "zip"
  output_path = "${path.module}/mailer_lambda.zip"

  source {
    content  = <<-PY
import json
import os
import urllib.parse
from email.message import EmailMessage
import boto3

s3 = boto3.client("s3")
ses = boto3.client("ses")

def handler(event, context):
    print("report-mailer triggered: trigger=s3")
    records = event.get("Records", [])
    for record in records:
        bucket = record["s3"]["bucket"]["name"]
        raw_key = record["s3"]["object"]["key"]
        key = urllib.parse.unquote_plus(raw_key)
        print(f"report-mailer processing s3 object: trigger=s3 bucket={bucket} key={key}")

        resp = s3.get_object(Bucket=bucket, Key=key)
        csv_content = resp["Body"].read()

        filename = key.split("/")[-1]
        week_name = filename.replace(".csv", "")

        sender = os.environ.get("REPORT_SENDER")
        recipient = os.environ.get("REPORT_RECIPIENT")

        msg = EmailMessage()
        msg["Subject"] = f"Weekly Meetings Report - {week_name}"
        msg["From"] = sender
        msg["To"] = recipient
        msg.set_content(
            f"Hello,\n\nPlease find attached the weekly meetings report for {week_name}.\n\n"
            f"Generated automatically by the Meetings App report pipeline."
        )
        msg.add_attachment(
            csv_content,
            maintype="text",
            subtype="csv",
            filename=filename,
        )

        print(f"Sending email from {sender} to {recipient} for {key} via SES")
        ses.send_raw_email(
            Source=sender,
            Destinations=[r.strip() for r in recipient.split(",") if r.strip()],
            RawMessage={"Data": msg.as_bytes()},
        )
        print(f"Email sent successfully for {key}")
    return {"status": "ok"}
PY
    filename = "index.py"
  }
}

resource "aws_lambda_function" "mailer" {
  function_name    = "${var.project_name}-report-mailer"
  runtime          = "python3.12"
  handler          = "index.handler"
  role             = aws_iam_role.mailer.arn
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.mailer_zip.output_path
  source_code_hash = data.archive_file.mailer_zip.output_base64sha256

  environment {
    variables = {
      REPORT_SENDER    = var.sender_email
      REPORT_RECIPIENT = var.recipient_email
    }
  }

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_lambda_permission" "mailer_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mailer.arn
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"
}

# Reports S3 Bucket
resource "aws_s3_bucket" "reports" {
  bucket = "${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "DeleteAfter90Days"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_notification" "reports" {
  bucket = aws_s3_bucket.reports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.mailer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.mailer_s3]
}

# SES Email Identity
resource "aws_ses_email_identity" "ses" {
  email = var.recipient_email
}
