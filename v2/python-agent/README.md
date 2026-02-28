# Python Agent Documentation

## Implementation Summary

The Python app (`python-app/app.py`) supports all three secret delivery methods using the same Docker image.

## Mode Detection

The app detects its delivery method via the `SECRET_DELIVERY_METHOD` environment variable:

| Value | Behavior |
|-------|----------|
| `vault-secrets-operator` | Reads from K8s Secret env vars (VSO) |
| `vault-agent-sidecar` | Reads from key=value file at `SECRETS_FILE_PATH` |
| `vault-csi-driver` | Reads individual files from `SECRETS_FILE_PATH` directory |

## File Reading Logic

```python
# Vault Agent mode - single key=value file
if SECRET_DELIVERY_METHOD == "vault-agent-sidecar":
    with open(SECRETS_FILE_PATH) as f:
        for line in f:
            key, value = line.strip().split('=', 1)
            creds[key] = value

# CSI mode - individual files
if SECRET_DELIVERY_METHOD == "vault-csi-driver":
    creds['username'] = Path(f"{SECRETS_FILE_PATH}/username").read_text()
    creds['password'] = Path(f"{SECRETS_FILE_PATH}/password").read_text()
```

## UI Display

The `SECRET_DELIVERY_METHOD` value is displayed in the web UI header to identify which delivery method is active for each instance.

## Docker Image

Single image used across all deployments:
```
ghcr.io/andybaran/vault-ldap-demo:latest
```

Built from `python-app/Dockerfile` on push to main.
