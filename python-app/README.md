# Vault LDAP Credentials Display Application

Python Flask web application (v3.0.0) that displays LDAP credentials delivered by HashiCorp Vault. Supports three secret delivery methods and dual-account (blue/green) rotation visualization.

## Features

- **Three delivery methods** — Vault Secrets Operator, Vault Agent sidecar, Vault CSI Driver
- **Direct Vault polling** — uses the `hvac` library to read live rotation state from Vault's LDAP secrets engine
- **Dual-account timeline UI** — HDS-styled visualization showing Account A/B rotation phases (Active=blue, Grace=yellow, Inactive=red) with a live countdown timer
- **Delivery method badge** — identifies which delivery method is active
- **Health check endpoint** for Kubernetes liveness/readiness probes
- Runs as non-root user (UID 1000), multi-stage Docker build

## Secret Delivery Methods

Set `SECRET_DELIVERY_METHOD` to control how the app reads credentials:

| Value | Source | Notes |
|-------|--------|-------|
| `vault-secrets-operator` (default) | K8s Secret env vars injected by VSO; direct Vault API polling for live rotation state | Requires `VAULT_ADDR`, `VAULT_AUTH_ROLE`, `LDAP_MOUNT_PATH`, `LDAP_STATIC_ROLE_NAME` |
| `vault-agent-sidecar` | Key=value file rendered by Vault Agent at `VAULT_AGENT_CREDS_FILE` | File refreshed every 5 s by background thread |
| `vault-csi-driver` | Individual files mounted at `VAULT_CSI_SECRETS_DIR` by the CSI Driver | Files refreshed every 5 s by background thread |

## Environment Variables

### Common

| Variable | Description | Default |
|----------|-------------|---------|
| `SECRET_DELIVERY_METHOD` | Delivery method (see above) | `vault-secrets-operator` |

### VSO / Env-var Mode

These are typically injected from the `ldap-credentials` K8s Secret by VSO:

| Variable | Description |
|----------|-------------|
| `LDAP_USERNAME` | Active AD account username |
| `LDAP_PASSWORD` | Current rotated password |
| `ROTATION_PERIOD` | Rotation interval in seconds |
| `ROTATION_TTL` | Seconds until next rotation |
| `DUAL_ACCOUNT_MODE` | `"true"` to enable dual-account display |
| `ACTIVE_ACCOUNT` | Which account is currently active (`a` or `b`) |
| `ROTATION_STATE` | Current rotation state from the plugin |
| `STANDBY_USERNAME` | Standby account username (during grace period) |
| `STANDBY_PASSWORD` | Standby account password (during grace period) |
| `GRACE_PERIOD` | Grace period duration in seconds |
| `GRACE_PERIOD_END` | Unix timestamp when grace period ends |

For direct Vault polling (dual-account VSO mode):

| Variable | Description |
|----------|-------------|
| `VAULT_ADDR` | Vault API address (e.g., `http://vault.default.svc.cluster.local:8200`) |
| `VAULT_AUTH_ROLE` | Vault K8s auth role (e.g., `ldap-app-role`) |
| `LDAP_MOUNT_PATH` | LDAP secrets engine mount path (e.g., `ldap`) |
| `LDAP_STATIC_ROLE_NAME` | Static role name (e.g., `dual-rotation-demo`) |

### Vault Agent Sidecar Mode

| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_AGENT_CREDS_FILE` | `/vault/secrets/ldap-creds` | Path to the key=value credentials file rendered by Vault Agent |

### CSI Driver Mode

| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_CSI_SECRETS_DIR` | `/vault/secrets` | Directory containing individual secret files mounted by the CSI Driver |

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Main page — HDS-styled credentials display with timeline |
| `/api/credentials` | GET | JSON API — live credential data, rotation state, TTL |
| `/health` | GET | Health check (returns `{"status": "healthy"}`) |

## Running Locally

```bash
# Install dependencies
pip install -r requirements.txt

# VSO mode (env vars)
export SECRET_DELIVERY_METHOD=vault-secrets-operator
export LDAP_USERNAME=svc-rotate-a
export LDAP_PASSWORD=demo-password
export ROTATION_PERIOD=100
export ROTATION_TTL=75
python app.py
```

Visit http://localhost:8080.

## Running Tests

```bash
pip install -r requirements.txt
pytest test_app.py -v
```

## Building the Docker Image

```bash
docker build -t vault-ldap-demo:latest .
```

## Running with Docker

```bash
# VSO / env-var mode
docker run -p 8080:8080 \
  -e SECRET_DELIVERY_METHOD=vault-secrets-operator \
  -e LDAP_USERNAME=svc-rotate-a \
  -e LDAP_PASSWORD=demo-password \
  -e ROTATION_PERIOD=100 \
  vault-ldap-demo:latest

# Vault Agent sidecar mode (file-based)
docker run -p 8080:8080 \
  -e SECRET_DELIVERY_METHOD=vault-agent-sidecar \
  -v /path/to/secrets:/vault/secrets \
  vault-ldap-demo:latest
```

## Kubernetes Deployment

Three separate Kubernetes Deployments are created by the `ldap_app` Terraform module — one per delivery method. See [`modules/ldap_app/`](../modules/ldap_app/README.md) for configuration details.

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Flask | 3.1.0 | Web framework |
| Werkzeug | 3.1.3 | WSGI utilities |
| hvac | 2.3.0 | HashiCorp Vault Python client (direct Vault API polling) |
| pytest | ≥8.0.0 | Testing |

## Security

- Runs as non-root user (UID 1000)
- Multi-stage Docker build (smaller attack surface)
- No credentials are logged
- Vault tokens are cached with 80% lease renewal and refreshed automatically

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

This application is designed to be deployed on Kubernetes with Vault Secrets Operator managing the LDAP credentials. See the `ldap_app` module in the parent Terraform stack for the Kubernetes deployment configuration.

## Endpoints

- `/` - Main page displaying LDAP credentials
- `/health` - Health check endpoint (returns 200 OK with JSON status)

## Security

- Runs as non-root user (UID 1000)
- Uses multi-stage Docker build for smaller attack surface
- No sensitive data is logged
- Credentials are only read from environment variables (not files)
