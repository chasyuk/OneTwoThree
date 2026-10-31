resource "aws_iam_role" "agenda_parser" {
  name = "${var.project_name}-agenda-parser-role"

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

resource "aws_iam_role_policy_attachment" "agenda_parser_basic" {
  role       = aws_iam_role.agenda_parser.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "agenda_parser_bedrock" {
  name = "BedrockAccess"
  role = aws_iam_role.agenda_parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock-mantle:CreateInference",
        "bedrock:GetInferenceProfile",
        "bedrock:ListInferenceProfiles"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "agenda_parser" {
  function_name = "${var.project_name}-agenda-parser"
  package_type  = "Image"
  image_uri     = var.image_uri
  role          = aws_iam_role.agenda_parser.arn
  timeout       = 30
  memory_size   = 512
  architectures = [var.architecture]

  image_config {
    command = ["app.ai.agenda_lambda.handler"]
  }

  environment {
    variables = {
      PARSER_MODEL         = var.parser_model
      COGNITO_REGION       = var.region
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.main.id
      COGNITO_JWKS         = ""
    }
  }

  tags = {
    PROJECT_NAME = var.project_name
  }
}

resource "aws_lambda_function_url" "agenda_parser" {
  function_name      = aws_lambda_function.agenda_parser.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_headers     = ["authorization", "content-type"]
    allow_methods     = ["POST"]
    allow_origins     = var.cors_origins
    max_age           = 0
  }
}

resource "aws_lambda_permission" "agenda_parser_public" {
  statement_id           = "FunctionURLAllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.agenda_parser.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
