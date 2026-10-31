locals {
  google_enabled = var.google_client_id != ""
}

data "aws_caller_identity" "current" {}

resource "aws_cognito_user_pool" "main" {
  name                     = "${var.project_name}-users"
  user_pool_tier           = "ESSENTIALS"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  username_configuration {
    case_sensitive = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_uppercase                = false
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = false
    mutable             = true
  }

  tags = {
    PROJECT_NAME = var.project_name
  }

  lifecycle {
    ignore_changes = [schema]
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain                = "${var.project_name}-${data.aws_caller_identity.current.account_id}"
  user_pool_id          = aws_cognito_user_pool.main.id
  managed_login_version = 2
}

resource "aws_cognito_identity_provider" "google" {
  count         = local.google_enabled ? 1 : 0
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }

  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
    username       = "sub"
  }

  lifecycle {
    ignore_changes = [
      provider_details
    ]
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 30

  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }

  supported_identity_providers = local.google_enabled ? ["COGNITO", "Google"] : ["COGNITO"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls

  depends_on = [aws_cognito_identity_provider.google]
}

resource "aws_cognito_managed_login_branding" "main" {
  user_pool_id                = aws_cognito_user_pool.main.id
  client_id                   = aws_cognito_user_pool_client.main.id
  use_cognito_provided_values = true
}
