component "public_ip" {
    source = "./modules/public_ip"
    providers = {
        tls = provider.tls.this
        random = provider.random.this
        http = provider.http.this
    }
}