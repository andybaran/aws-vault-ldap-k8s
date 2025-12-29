identity_token "aws" {
  audience = ["terraform-stacks-private-preview"]
}



deployment "developmnent" {
  inputs = {
    region = "us-east-2"
    customer_name = "fidelity"
    aws_role = "arn:aws:iam::851170382860:role/stacks"
    aws_token = identity_token.aws.jwt
  }
}