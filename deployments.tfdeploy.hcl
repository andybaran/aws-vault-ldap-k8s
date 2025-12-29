



deployment "developmnent" {
  inputs = {
    region = "us-east-2"
    customer_name = "fidelity"
  }
  store varset "aws_creds" {
    name = "doormat"
    category = "env"
  }
}