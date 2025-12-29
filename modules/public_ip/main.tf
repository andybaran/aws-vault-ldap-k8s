data "http" "my_public_ip" {
  url = "http://ipv4.icanhazip.com"
}

locals {
  ip = trimspace(data.http.my_public_ip.response_body)
}
