identity_token "aws" {
  audience = ["terraform-stacks-private-preview"]
}



deployment "developmnent" {
  inputs = {
    region = "us-east-2"
    customer_name = "fidelity"
    role_arn = "arn:aws:iam::851170382860:role/stacks"
    identity_token = identity_token.aws.jwt
  }
}