# Vault LDAP Credentials Display Application

A simple Python Flask web application that displays LDAP credentials delivered by HashiCorp Vault Secrets Operator.

## Features

- Displays LDAP credentials (username, password, DN) from environment variables
- Clean, responsive web interface
- Health check endpoint for Kubernetes probes
- Runs as non-root user for security
- Lightweight Docker image based on Python 3.11-slim

## Environment Variables

The application expects the following environment variables to be set (typically injected by Vault Secrets Operator):

- `LDAP_USERNAME` - The LDAP username
- `LDAP_PASSWORD` - The current LDAP password (rotated by Vault)
- `LDAP_DN` - The distinguished name for the LDAP account
- `LDAP_LAST_VAULT_PASSWORD` - The last Vault password (for tracking rotations)

## Running Locally

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export LDAP_USERNAME="demo-user"
export LDAP_PASSWORD="demo-password"
export LDAP_DN="CN=demo-user,CN=Users,DC=mydomain,DC=local"
export LDAP_LAST_VAULT_PASSWORD="previous-password"

# Run the application
python app.py
```

Visit http://localhost:8080 to view the application.

## Building the Docker Image

```bash
docker build -t vault-ldap-demo:latest .
```

## Running with Docker

```bash
docker run -p 8080:8080 \
  -e LDAP_USERNAME="demo-user" \
  -e LDAP_PASSWORD="demo-password" \
  -e LDAP_DN="CN=demo-user,CN=Users,DC=mydomain,DC=local" \
  -e LDAP_LAST_VAULT_PASSWORD="previous-password" \
  vault-ldap-demo:latest
```

## Kubernetes Deployment

This application is designed to be deployed on Kubernetes with Vault Secrets Operator managing the LDAP credentials. See the `kube2` module in the parent Terraform stack for the Kubernetes deployment configuration.

## Endpoints

- `/` - Main page displaying LDAP credentials
- `/health` - Health check endpoint (returns 200 OK with JSON status)

## Security

- Runs as non-root user (UID 1000)
- Uses multi-stage Docker build for smaller attack surface
- No sensitive data is logged
- Credentials are only read from environment variables (not files)
