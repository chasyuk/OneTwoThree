project_name     = "meetings"
region           = "us-east-1"
google_client_id = "532698219081-06sma0vq3gg31v8shfcbopodomb0v72j.apps.googleusercontent.com"
callback_urls = [
  "http://localhost:3000/auth/callback",
  "http://localhost:5173/auth/callback",
  "https://d1ba8tbsejcok2.cloudfront.net/auth/callback"
]
logout_urls = [
  "http://localhost:3000/",
  "http://localhost:5173/",
  "https://d1ba8tbsejcok2.cloudfront.net/"
]
cors_origins = [
  "http://localhost:3000",
  "http://localhost:5173",
  "https://d1ba8tbsejcok2.cloudfront.net"
]
sender_email    = "vlasyuk.pn@ucu.edu.ua"
recipient_email = "vlasyuk.pn@ucu.edu.ua"
parser_model    = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
architecture    = "x86_64"
image_uri       = "561721572034.dkr.ecr.us-east-1.amazonaws.com/meetings-backend:3676d6f-dirty-20261029184417"
