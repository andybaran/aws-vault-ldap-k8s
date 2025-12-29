store varset "aws_creds" {
  id = "varset-oUu39eyQUoDbmxE1"
  category = "env"
}

deployment "developmnent" {
  inputs = {
    region = "us-east-2"
    customer_name = "fidelity"
  }

}