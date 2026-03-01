#!/usr/bin/env python3
"""
Simple Flask web application to display LDAP credentials from Vault.
Supports multiple secret delivery methods:
- vault-secrets-operator: credentials read from env vars (delivered by VSO)
- vault-agent-sidecar: credentials read from rendered file
- vault-csi-driver: credentials read from individual files
Also supports dual-account mode with direct Vault API polling.
"""

import os
import json
import time
import threading
import logging
from datetime import datetime
from flask import Flask, render_template_string, jsonify

APP_VERSION = "3.0.0"

# Try to import hvac for direct Vault API access
try:
    import hvac
except ImportError:
    hvac = None

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ─── Secret Delivery Method Configuration ───────────────────────────────────
SECRET_DELIVERY_METHOD = os.getenv('SECRET_DELIVERY_METHOD', 'vault-secrets-operator')
VAULT_AGENT_CREDS_FILE = os.getenv('VAULT_AGENT_CREDS_FILE', '/vault/secrets/ldap-creds')
VAULT_CSI_SECRETS_DIR = os.getenv('VAULT_CSI_SECRETS_DIR', '/vault/secrets')

# Human-friendly display names for delivery methods
DELIVERY_METHOD_DISPLAY = {
    'vault-secrets-operator': 'Vault Secrets Operator',
    'vault-agent-sidecar': 'Vault Agent Sidecar',
    'vault-csi-driver': 'Vault CSI Driver',
}


# ─── File-Based Credential Cache ────────────────────────────────────────────
class FileCredentialCache:
    """Periodically reads credentials from files for agent/CSI delivery methods."""

    def __init__(self, delivery_method, refresh_interval=5):
        self._delivery_method = delivery_method
        self._refresh_interval = refresh_interval
        self._credentials = {}
        self._lock = threading.Lock()
        self._running = False
        self._thread = None

    def start(self):
        """Start the background refresh thread."""
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._refresh_loop, daemon=True)
        self._thread.start()
        logger.info("FileCredentialCache started for method=%s", self._delivery_method)

    def stop(self):
        """Stop the background refresh thread."""
        self._running = False

    def get_credentials(self):
        """Get the cached credentials."""
        with self._lock:
            return self._credentials.copy()

    def _refresh_loop(self):
        """Background loop that refreshes credentials from files."""
        while self._running:
            try:
                self._read_credentials()
            except Exception as e:
                logger.error("Error reading credentials from files: %s", e)
            time.sleep(self._refresh_interval)

    def _read_credentials(self):
        """Read credentials based on delivery method."""
        creds = {}

        if self._delivery_method == 'vault-agent-sidecar':
            creds = self._read_agent_sidecar_file()
        elif self._delivery_method == 'vault-csi-driver':
            creds = self._read_csi_files()

        with self._lock:
            self._credentials = creds

    def _read_agent_sidecar_file(self):
        """Read credentials from Vault Agent rendered file (key=value format)."""
        creds = {}
        try:
            with open(VAULT_AGENT_CREDS_FILE, 'r') as f:
                for line in f:
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        key, value = line.split('=', 1)
                        creds[key.strip()] = value.strip()
            logger.debug("Read %d credentials from agent sidecar file", len(creds))
        except FileNotFoundError:
            logger.warning("Vault Agent creds file not found: %s", VAULT_AGENT_CREDS_FILE)
        except Exception as e:
            logger.error("Error reading agent sidecar file: %s", e)
        return creds

    def _read_csi_files(self):
        """Read credentials from Vault CSI Driver individual files."""
        creds = {}
        try:
            if not os.path.isdir(VAULT_CSI_SECRETS_DIR):
                logger.warning("Vault CSI secrets dir not found: %s", VAULT_CSI_SECRETS_DIR)
                return creds

            for filename in os.listdir(VAULT_CSI_SECRETS_DIR):
                filepath = os.path.join(VAULT_CSI_SECRETS_DIR, filename)
                if os.path.isfile(filepath):
                    try:
                        with open(filepath, 'r') as f:
                            creds[filename] = f.read().strip()
                    except Exception as e:
                        logger.error("Error reading CSI file %s: %s", filepath, e)
            logger.debug("Read %d credentials from CSI files", len(creds))
        except Exception as e:
            logger.error("Error reading CSI directory: %s", e)
        return creds


# Initialize file credential cache for file-based delivery methods
file_cred_cache = None
if SECRET_DELIVERY_METHOD in ('vault-agent-sidecar', 'vault-csi-driver'):
    file_cred_cache = FileCredentialCache(SECRET_DELIVERY_METHOD)
    file_cred_cache.start()


# ─── Vault Client (hvac-based) ──────────────────────────────────────────────
class VaultClient:
    """Handles authentication and API calls to Vault using Kubernetes auth via hvac."""

    def __init__(self, vault_addr, auth_role, mount="kubernetes"):
        self.vault_addr = vault_addr.rstrip("/")
        self.auth_role = auth_role
        self.auth_mount = mount
        self._client = None
        self._token_expires_at = 0
        self._sa_token_path = os.getenv(
            "VAULT_SA_TOKEN_PATH",
            "/var/run/secrets/vault/token"
        )

    def _read_sa_token(self):
        """Read the Kubernetes service account JWT token."""
        try:
            with open(self._sa_token_path, "r") as f:
                return f.read().strip()
        except FileNotFoundError:
            logger.error("K8s SA token not found at %s", self._sa_token_path)
            return None

    def _login(self):
        """Authenticate to Vault using Kubernetes auth method via hvac."""
        jwt = self._read_sa_token()
        if not jwt:
            return False

        try:
            self._client = hvac.Client(url=self.vault_addr)
            response = self._client.auth.kubernetes.login(
                role=self.auth_role,
                jwt=jwt,
                mount_point=self.auth_mount
            )
            lease_duration = response.get('auth', {}).get('lease_duration', 600)
            # Renew at 80% of lease duration
            self._token_expires_at = time.time() + (lease_duration * 0.8)
            logger.info("Vault login successful via hvac, token valid for %ds", lease_duration)
            return True
        except Exception as e:
            logger.error("Vault login failed: %s", e)
            self._client = None
            return False

    def _ensure_authenticated(self):
        """Ensure we have a valid authenticated client."""
        if self._client and self._client.is_authenticated() and time.time() < self._token_expires_at:
            return True
        return self._login()

    def read_static_creds(self, mount, role_name):
        """Read static credentials from Vault."""
        if not self._ensure_authenticated():
            return None

        try:
            response = self._client.read(f"{mount}/static-cred/{role_name}")
            if response:
                return response.get("data", {})
            return None
        except Exception as e:
            logger.error("Failed to read static creds: %s", e)
            return None


# Initialize Vault client if config is available
vault_client = None
vault_addr = os.getenv("VAULT_ADDR", "")
vault_auth_role = os.getenv("VAULT_AUTH_ROLE", "")
if vault_addr and vault_auth_role and hvac:
    vault_client = VaultClient(vault_addr, vault_auth_role)
    logger.info("VaultClient initialized with hvac: addr=%s role=%s", vault_addr, vault_auth_role)


# ─── Single-Account HTML Template (unchanged) ───────────────────────────────
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vault LDAP Credentials Demo</title>
    <style>
        :root {
            --color-vault: #FFD814;
            --color-black: #000000;
            --color-surface-primary: #FFFFFF;
            --color-surface-secondary: #F7F8FA;
            --color-surface-tertiary: #EBEEF2;
            --color-surface-strong: #000000;
            --color-foreground-primary: #1F2D3D;
            --color-foreground-strong: #000000;
            --color-foreground-faint: #5F6F84;
            --color-foreground-success: #15834D;
            --color-border-primary: #D9DEE5;
            --color-border-strong: #A7B1BF;
            --color-highlight: #5B3DE0;
            --color-success: #15834D;
            --color-success-surface: #DDF4E8;
            --font-family-text: -apple-system, BlinkMacSystemFont, "Segoe UI", "Roboto", "Oxygen", "Ubuntu", "Cantarell", "Fira Sans", "Droid Sans", "Helvetica Neue", sans-serif;
            --font-family-code: "SF Mono", Monaco, "Cascadia Mono", "Roboto Mono", Consolas, "Courier New", monospace;
            --font-size-display-500: 30px;
            --font-size-display-400: 24px;
            --font-size-display-300: 20px;
            --font-size-body-300: 16px;
            --font-size-body-200: 14px;
            --font-size-body-100: 12px;
            --line-height-display: 1.2;
            --line-height-body: 1.5;
            --font-weight-regular: 400;
            --font-weight-medium: 500;
            --font-weight-semibold: 600;
            --font-weight-bold: 700;
            --spacing-050: 2px;
            --spacing-100: 4px;
            --spacing-200: 8px;
            --spacing-300: 12px;
            --spacing-400: 16px;
            --spacing-500: 24px;
            --spacing-600: 32px;
            --spacing-700: 40px;
            --spacing-800: 48px;
            --radius-small: 4px;
            --radius-medium: 8px;
            --radius-large: 12px;
            --elevation-mid: 0 8px 16px rgba(31, 45, 61, 0.12);
            --elevation-high: 0 12px 24px rgba(31, 45, 61, 0.16);
        }
        *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: var(--font-family-text); background-color: var(--color-surface-strong); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: var(--spacing-500); color: var(--color-foreground-primary); }
        .container { background: var(--color-surface-primary); border-radius: var(--radius-large); box-shadow: var(--elevation-high); max-width: 900px; width: 100%; overflow: hidden; }
        .brand-header { background: var(--color-black); color: var(--color-surface-primary); padding: var(--spacing-600) var(--spacing-700); text-align: center; border-bottom: 3px solid var(--color-vault); position: relative; }
        .brand-header-content { display: flex; align-items: center; justify-content: center; gap: var(--spacing-400); margin-bottom: var(--spacing-400); }
        .vault-logo { width: 48px; height: 48px; flex-shrink: 0; }
        .brand-header h1 { font-size: var(--font-size-display-400); font-weight: var(--font-weight-semibold); line-height: var(--line-height-display); margin: 0; color: var(--color-surface-primary); }
        .brand-header p { font-size: var(--font-size-body-300); color: var(--color-surface-tertiary); margin: 0; line-height: var(--line-height-body); }
        .version-tag { position: absolute; top: var(--spacing-300); right: var(--spacing-400); font-size: 11px; color: var(--color-foreground-faint); font-family: var(--font-family-code); opacity: 0.7; }
        .status-badge { display: inline-flex; align-items: center; gap: var(--spacing-100); background: var(--color-success); color: var(--color-surface-primary); padding: var(--spacing-100) var(--spacing-300); border-radius: var(--radius-large); font-size: var(--font-size-body-100); font-weight: var(--font-weight-semibold); text-transform: uppercase; letter-spacing: 0.5px; margin-top: var(--spacing-300); }
        .status-badge::before { content: ''; width: 8px; height: 8px; border-radius: 50%; background: var(--color-surface-primary); animation: pulse 2s ease-in-out infinite; }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
        .content { padding: var(--spacing-700); }
        .section-title { font-size: var(--font-size-display-300); font-weight: var(--font-weight-semibold); color: var(--color-foreground-strong); margin-bottom: var(--spacing-500); padding-bottom: var(--spacing-300); border-bottom: 2px solid var(--color-surface-tertiary); }
        .credentials-grid { display: grid; gap: var(--spacing-400); margin-bottom: var(--spacing-600); }
        .credential-card { background: var(--color-surface-secondary); border: 1px solid var(--color-border-primary); border-radius: var(--radius-medium); padding: var(--spacing-500); transition: all 0.2s ease; }
        .credential-card:hover { border-color: var(--color-border-strong); box-shadow: var(--elevation-mid); }
        .credential-label { font-size: var(--font-size-body-100); font-weight: var(--font-weight-semibold); color: var(--color-foreground-faint); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: var(--spacing-200); display: flex; align-items: center; gap: var(--spacing-200); }
        .credential-label::before { content: ''; width: 4px; height: 12px; background: var(--color-vault); border-radius: 2px; }
        .credential-value { font-family: var(--font-family-code); font-size: var(--font-size-body-200); color: var(--color-foreground-strong); background: var(--color-surface-primary); padding: var(--spacing-300); border-radius: var(--radius-small); border: 1px solid var(--color-border-primary); word-break: break-all; line-height: 1.6; }
        .countdown-card { background: var(--color-surface-secondary); border: 1px solid var(--color-border-primary); border-radius: var(--radius-medium); padding: var(--spacing-500); margin-bottom: var(--spacing-600); text-align: center; }
        .countdown-label { font-size: var(--font-size-body-100); font-weight: var(--font-weight-semibold); color: var(--color-foreground-faint); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: var(--spacing-300); }
        .countdown-display { display: flex; align-items: center; justify-content: center; gap: var(--spacing-400); }
        .countdown-value { font-family: var(--font-family-code); font-size: var(--font-size-display-500); font-weight: var(--font-weight-bold); color: var(--color-foreground-strong); min-width: 80px; }
        .countdown-unit { font-size: var(--font-size-body-200); color: var(--color-foreground-faint); font-weight: var(--font-weight-medium); }
        .countdown-bar-track { height: 6px; background: var(--color-surface-tertiary); border-radius: 3px; margin-top: var(--spacing-400); overflow: hidden; }
        .countdown-bar-fill { height: 100%; background: var(--color-vault); border-radius: 3px; transition: width 1s linear; }
        .info-section { background: var(--color-success-surface); border: 1px solid rgba(21, 131, 77, 0.3); border-radius: var(--radius-medium); padding: var(--spacing-500); margin-bottom: var(--spacing-500); }
        .info-section-title { font-size: var(--font-size-body-300); font-weight: var(--font-weight-semibold); color: var(--color-success); margin-bottom: var(--spacing-300); display: flex; align-items: center; gap: var(--spacing-200); }
        .info-section p { font-size: var(--font-size-body-200); color: var(--color-foreground-primary); line-height: var(--line-height-body); margin: 0; }
        .metadata { display: flex; align-items: center; justify-content: space-between; padding: var(--spacing-500); background: var(--color-surface-secondary); border-top: 1px solid var(--color-border-primary); font-size: var(--font-size-body-200); color: var(--color-foreground-faint); }
        .metadata strong { color: var(--color-foreground-strong); font-weight: var(--font-weight-medium); }
        .powered-by { display: flex; align-items: center; gap: var(--spacing-200); }
        .powered-by a { color: var(--color-highlight); text-decoration: none; font-weight: var(--font-weight-medium); transition: color 0.2s ease; }
        .powered-by a:hover { color: var(--color-foreground-strong); text-decoration: underline; }
        .refresh-btn { display: none; margin-top: var(--spacing-400); padding: var(--spacing-300) var(--spacing-600); background: var(--color-vault); color: var(--color-black); border: none; border-radius: var(--radius-medium); font-family: var(--font-family-text); font-size: var(--font-size-body-300); font-weight: var(--font-weight-semibold); cursor: pointer; transition: all 0.2s ease; }
        .refresh-btn:hover { background: #e6c200; box-shadow: var(--elevation-mid); }
        .refresh-btn.visible { display: inline-block; animation: fadeIn 0.3s ease-in; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(4px); } to { opacity: 1; transform: translateY(0); } }
        .delivery-method-card { background: linear-gradient(135deg, var(--color-surface-secondary), var(--color-surface-tertiary)); border: 1px solid var(--color-vault); border-radius: var(--radius-medium); padding: var(--spacing-300) var(--spacing-500); margin-bottom: var(--spacing-500); text-align: center; }
        .delivery-method-label { font-size: var(--font-size-body-100); font-weight: var(--font-weight-semibold); color: var(--color-foreground-faint); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: var(--spacing-100); }
        .delivery-method-value { font-size: var(--font-size-body-300); font-weight: var(--font-weight-bold); color: var(--color-vault); }
        @media (max-width: 640px) { body { padding: var(--spacing-300); } .brand-header { padding: var(--spacing-500); } .brand-header h1 { font-size: var(--font-size-display-300); } .content { padding: var(--spacing-500); } .metadata { flex-direction: column; gap: var(--spacing-300); text-align: center; } }
    </style>
</head>
<body>
    <div class="container">
        <div class="brand-header">
            <div class="brand-header-content">
                <svg class="vault-logo" viewBox="0 0 51 51" xmlns="http://www.w3.org/2000/svg">
                    <path fill="#FFD814" fill-rule="nonzero" d="M0,0 L25.4070312,51 L51,0 L0,0 Z M28.5,10.5 L31.5,10.5 L31.5,13.5 L28.5,13.5 L28.5,10.5 Z M22.5,22.5 L19.5,22.5 L19.5,19.5 L22.5,19.5 L22.5,22.5 Z M22.5,18 L19.5,18 L19.5,15 L22.5,15 L22.5,18 Z M22.5,13.5 L19.5,13.5 L19.5,10.5 L22.5,10.5 L22.5,13.5 Z M26.991018,27 L24,27 L24,24 L27,24 L26.991018,27 Z M26.991018,22.5 L24,22.5 L24,19.5 L27,19.5 L26.991018,22.5 Z M26.991018,18 L24,18 L24,15 L27,15 L26.991018,18 Z M26.991018,13.5 L24,13.5 L24,10.5 L27,10.5 L26.991018,13.5 Z M28.5,15 L31.5,15 L31.5,18 L28.5089552,18 L28.5,15 Z M28.5,22.5 L28.5,19.5 L31.5,19.5 L31.5,22.4601182 L28.5,22.5 Z"/>
                </svg>
                <h1>Vault LDAP Credentials</h1>
            </div>
            <p>Automatically rotated credentials managed by HashiCorp Vault</p>
            <div class="status-badge">Live Demo</div>
            <span class="version-tag">v{{ version }}</span>
        </div>
        <div class="content">
            <h2 class="section-title">Active Credentials</h2>
            <div class="delivery-method-card">
                <div class="delivery-method-label">Secret Delivery Method</div>
                <div class="delivery-method-value">{{ delivery_method_display }}</div>
            </div>
            <div class="countdown-card" role="timer" aria-label="Time until next credential rotation">
                <div class="countdown-label">Next rotation in</div>
                <div class="countdown-display">
                    <span class="countdown-value" id="countdown-seconds">--</span>
                    <span class="countdown-unit">seconds</span>
                </div>
                <div class="countdown-bar-track">
                    <div class="countdown-bar-fill" id="countdown-bar" style="width: 100%"></div>
                </div>
                <button class="refresh-btn" id="refresh-btn" onclick="location.reload()">↻ Refresh Credentials</button>
            </div>
            <div class="credentials-grid">
                <div class="credential-card">
                    <div class="credential-label">Username</div>
                    <div class="credential-value">{{ username }}</div>
                </div>
                <div class="credential-card">
                    <div class="credential-label">Password</div>
                    <div class="credential-value">{{ password }}</div>
                </div>
                <div class="credential-card">
                    <div class="credential-label">Last Vault Rotation</div>
                    <div class="credential-value">{{ last_vault_password }}</div>
                </div>
            </div>
            <div class="info-section">
                <div class="info-section-title">How It Works</div>
                <p>These credentials are automatically rotated by HashiCorp Vault's LDAP secrets engine every {{ rotation_period }} seconds. The Vault Secrets Operator synchronizes the rotated credentials to Kubernetes secrets, which are then injected into this application as environment variables. When credentials rotate, the application automatically restarts with the new values.</p>
            </div>
        </div>
        <div class="metadata">
            <div><strong>Page loaded:</strong> {{ current_time }}</div>
            <div class="powered-by">Powered by <a href="https://developer.hashicorp.com/vault" target="_blank">HashiCorp Vault</a> + <a href="https://developer.hashicorp.com/vault/docs/platform/k8s/vso" target="_blank">VSO</a></div>
        </div>
    </div>
    <script>
        (function() {
            var rotationPeriod = {{ rotation_period }};
            var ttlAtLoad = {{ rotation_ttl }};
            var pageLoadedAt = Date.now();
            var countdownEl = document.getElementById('countdown-seconds');
            var barEl = document.getElementById('countdown-bar');
            var refreshBtn = document.getElementById('refresh-btn');
            var buttonShown = false;
            function getRemaining() {
                var elapsed = (Date.now() - pageLoadedAt) / 1000;
                return Math.max(0, Math.ceil(ttlAtLoad - elapsed));
            }
            function update() {
                var remaining = getRemaining();
                countdownEl.textContent = remaining;
                var pct = rotationPeriod > 0 ? (remaining / rotationPeriod) * 100 : 0;
                barEl.style.width = pct + '%';
                if (!buttonShown && remaining === 0) {
                    buttonShown = true;
                    setTimeout(function() { refreshBtn.classList.add('visible'); }, 5000);
                }
            }
            update();
            setInterval(update, 1000);
        })();
    </script>
</body>
</html>
"""

# ─── Dual-Account HTML Template with Timeline UI ────────────────────────────
DUAL_ACCOUNT_HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vault LDAP Credentials Demo - Dual Account</title>
    <style>
        :root {
            --color-vault: #FFD814;
            --color-black: #000000;
            --color-surface-primary: #FFFFFF;
            --color-surface-secondary: #F7F8FA;
            --color-surface-tertiary: #EBEEF2;
            --color-surface-strong: #000000;
            --color-foreground-primary: #1F2D3D;
            --color-foreground-strong: #000000;
            --color-foreground-faint: #5F6F84;
            --color-border-primary: #D9DEE5;
            --color-border-strong: #A7B1BF;
            --color-highlight: #5B3DE0;
            --color-success: #15834D;
            --color-success-surface: #DDF4E8;
            /* Timeline colors matching reference SVG */
            --color-active: #B3D9FF;
            --color-grace: #FFFFCC;
            --color-inactive: #FFB3B3;
            --color-active-text: #1a5276;
            --color-grace-text: #7d6608;
            --color-inactive-text: #922b21;
            --font-family-text: -apple-system, BlinkMacSystemFont, "Segoe UI", "Roboto", "Oxygen", "Ubuntu", "Cantarell", "Fira Sans", "Droid Sans", "Helvetica Neue", sans-serif;
            --font-family-code: "SF Mono", Monaco, "Cascadia Mono", "Roboto Mono", Consolas, "Courier New", monospace;
            --font-size-display-500: 30px;
            --font-size-display-400: 24px;
            --font-size-display-300: 20px;
            --font-size-body-300: 16px;
            --font-size-body-200: 14px;
            --font-size-body-100: 12px;
            --line-height-display: 1.2;
            --line-height-body: 1.5;
            --font-weight-regular: 400;
            --font-weight-medium: 500;
            --font-weight-semibold: 600;
            --font-weight-bold: 700;
            --spacing-050: 2px;
            --spacing-100: 4px;
            --spacing-200: 8px;
            --spacing-300: 12px;
            --spacing-400: 16px;
            --spacing-500: 24px;
            --spacing-600: 32px;
            --spacing-700: 40px;
            --spacing-800: 48px;
            --radius-small: 4px;
            --radius-medium: 8px;
            --radius-large: 12px;
            --elevation-mid: 0 8px 16px rgba(31, 45, 61, 0.12);
            --elevation-high: 0 12px 24px rgba(31, 45, 61, 0.16);
        }
        *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: var(--font-family-text); background-color: var(--color-surface-strong); min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: var(--spacing-500); color: var(--color-foreground-primary); }
        .container { background: var(--color-surface-primary); border-radius: var(--radius-large); box-shadow: var(--elevation-high); max-width: 960px; width: 100%; overflow: hidden; }
        .brand-header { background: var(--color-black); color: var(--color-surface-primary); padding: var(--spacing-600) var(--spacing-700); text-align: center; border-bottom: 3px solid var(--color-vault); position: relative; }
        .brand-header-content { display: flex; align-items: center; justify-content: center; gap: var(--spacing-400); margin-bottom: var(--spacing-400); }
        .vault-logo { width: 48px; height: 48px; flex-shrink: 0; }
        .brand-header h1 { font-size: var(--font-size-display-400); font-weight: var(--font-weight-semibold); line-height: var(--line-height-display); margin: 0; color: var(--color-surface-primary); }
        .brand-header p { font-size: var(--font-size-body-300); color: var(--color-surface-tertiary); margin: 0; }
        .version-tag { position: absolute; top: var(--spacing-300); right: var(--spacing-400); font-size: 11px; color: var(--color-foreground-faint); font-family: var(--font-family-code); opacity: 0.7; }
        .status-badge { display: inline-flex; align-items: center; gap: var(--spacing-100); padding: var(--spacing-100) var(--spacing-300); border-radius: var(--radius-large); font-size: var(--font-size-body-100); font-weight: var(--font-weight-semibold); text-transform: uppercase; letter-spacing: 0.5px; margin-top: var(--spacing-300); }
        .status-badge-active { background: var(--color-success); color: #fff; }
        .status-badge-grace { background: var(--color-vault); color: var(--color-black); }
        .status-badge::before { content: ''; width: 8px; height: 8px; border-radius: 50%; background: currentColor; opacity: 0.6; animation: pulse 2s ease-in-out infinite; }
        @keyframes pulse { 0%, 100% { opacity: 0.6; } 50% { opacity: 0.2; } }

        .content { padding: var(--spacing-600) var(--spacing-700); }

        /* ── Rotation Timeline ── */

        /* ── Countdown timers ── */
        .timers-row { display: flex; gap: var(--spacing-400); margin-bottom: var(--spacing-600); }
        .timer-card { flex: 1; background: var(--color-surface-secondary); border: 1px solid var(--color-border-primary); border-radius: var(--radius-medium); padding: var(--spacing-500); text-align: center; }
        .timer-card-grace { border-color: #d4a500; background: var(--color-grace); }
        .countdown-label { font-size: var(--font-size-body-100); font-weight: var(--font-weight-semibold); color: var(--color-foreground-faint); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: var(--spacing-200); }
        .countdown-value { font-family: var(--font-family-code); font-size: var(--font-size-display-500); font-weight: var(--font-weight-bold); color: var(--color-foreground-strong); }
        .countdown-unit { font-size: var(--font-size-body-200); color: var(--color-foreground-faint); margin-left: var(--spacing-200); }
        .countdown-bar-track { height: 6px; background: var(--color-surface-tertiary); border-radius: 3px; margin-top: var(--spacing-300); overflow: hidden; }
        .countdown-bar-fill { height: 100%; border-radius: 3px; transition: width 1s linear; }
        .bar-fill-vault { background: var(--color-vault); }
        .bar-fill-grace { background: #d4a500; }

        /* ── Credential cards ── */
        .section-title { font-size: var(--font-size-display-300); font-weight: var(--font-weight-semibold); color: var(--color-foreground-strong); margin-bottom: var(--spacing-500); padding-bottom: var(--spacing-300); border-bottom: 2px solid var(--color-surface-tertiary); }
        .account-cards { display: grid; grid-template-columns: 1fr 1fr; gap: var(--spacing-400); margin-bottom: var(--spacing-600); }
        .account-card { border-radius: var(--radius-medium); padding: var(--spacing-500); border: 1px solid var(--color-border-primary); }
        .account-card-active { background: #eaf4ff; border-left: 4px solid #5dade2; }
        .account-card-standby { background: var(--color-grace); border-left: 4px solid #d4a500; }
        .account-card-hidden { background: var(--color-surface-secondary); border-left: 4px solid var(--color-border-primary); opacity: 0.5; }
        .account-card-header { display: flex; align-items: center; gap: var(--spacing-200); font-weight: var(--font-weight-semibold); margin-bottom: var(--spacing-400); font-size: var(--font-size-body-300); }
        .account-indicator { display: inline-flex; align-items: center; justify-content: center; width: 28px; height: 28px; border-radius: 50%; font-size: var(--font-size-body-100); font-weight: var(--font-weight-bold); }
        .indicator-active { background: var(--color-active); color: var(--color-active-text); }
        .indicator-standby { background: var(--color-grace); color: var(--color-grace-text); border: 2px solid #d4a500; }
        .indicator-hidden { background: var(--color-inactive); color: var(--color-inactive-text); }
        .credential-row { display: grid; grid-template-columns: 1fr 1fr; gap: var(--spacing-300); }
        .credential-item { }
        .credential-label { font-size: var(--font-size-body-100); font-weight: var(--font-weight-semibold); color: var(--color-foreground-faint); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: var(--spacing-100); display: flex; align-items: center; gap: var(--spacing-200); }
        .credential-label::before { content: ''; width: 4px; height: 12px; background: var(--color-vault); border-radius: 2px; }
        .credential-value { font-family: var(--font-family-code); font-size: var(--font-size-body-200); color: var(--color-foreground-strong); background: var(--color-surface-primary); padding: var(--spacing-200) var(--spacing-300); border-radius: var(--radius-small); border: 1px solid var(--color-border-primary); word-break: break-all; }

        .info-section { background: var(--color-success-surface); border: 1px solid rgba(21, 131, 77, 0.3); border-radius: var(--radius-medium); padding: var(--spacing-500); margin-bottom: var(--spacing-500); }
        .info-section-title { font-size: var(--font-size-body-300); font-weight: var(--font-weight-semibold); color: var(--color-success); margin-bottom: var(--spacing-300); }
        .info-section p { font-size: var(--font-size-body-200); color: var(--color-foreground-primary); line-height: var(--line-height-body); margin: 0; }

        .metadata { display: flex; align-items: center; justify-content: space-between; padding: var(--spacing-500); background: var(--color-surface-secondary); border-top: 1px solid var(--color-border-primary); font-size: var(--font-size-body-200); color: var(--color-foreground-faint); }
        .metadata strong { color: var(--color-foreground-strong); font-weight: var(--font-weight-medium); }
        .powered-by { display: flex; align-items: center; gap: var(--spacing-200); }
        .powered-by a { color: var(--color-highlight); text-decoration: none; font-weight: var(--font-weight-medium); }
        .powered-by a:hover { color: var(--color-foreground-strong); text-decoration: underline; }

        .error-banner { background: #fdecea; border: 1px solid #e74c3c; border-radius: var(--radius-medium); padding: var(--spacing-400); margin-bottom: var(--spacing-500); color: #922b21; font-size: var(--font-size-body-200); display: none; }

        .delivery-method-card { background: linear-gradient(135deg, var(--color-surface-secondary), var(--color-surface-tertiary)); border: 1px solid var(--color-vault); border-radius: var(--radius-medium); padding: var(--spacing-300) var(--spacing-500); margin-bottom: var(--spacing-500); text-align: center; }
        .delivery-method-label { font-size: var(--font-size-body-100); font-weight: var(--font-weight-semibold); color: var(--color-foreground-faint); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: var(--spacing-100); }
        .delivery-method-value { font-size: var(--font-size-body-300); font-weight: var(--font-weight-bold); color: var(--color-vault); }

        @media (max-width: 768px) {
            body { padding: var(--spacing-300); }
            .content { padding: var(--spacing-500); }
            .account-cards { grid-template-columns: 1fr; }
            .timers-row { flex-direction: column; }
            .credential-row { grid-template-columns: 1fr; }
            .metadata { flex-direction: column; gap: var(--spacing-300); text-align: center; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="brand-header">
            <div class="brand-header-content">
                <svg class="vault-logo" viewBox="0 0 51 51" xmlns="http://www.w3.org/2000/svg">
                    <path fill="#FFD814" fill-rule="nonzero" d="M0,0 L25.4070312,51 L51,0 L0,0 Z M28.5,10.5 L31.5,10.5 L31.5,13.5 L28.5,13.5 L28.5,10.5 Z M22.5,22.5 L19.5,22.5 L19.5,19.5 L22.5,19.5 L22.5,22.5 Z M22.5,18 L19.5,18 L19.5,15 L22.5,15 L22.5,18 Z M22.5,13.5 L19.5,13.5 L19.5,10.5 L22.5,10.5 L22.5,13.5 Z M26.991018,27 L24,27 L24,24 L27,24 L26.991018,27 Z M26.991018,22.5 L24,22.5 L24,19.5 L27,19.5 L26.991018,22.5 Z M26.991018,18 L24,18 L24,15 L27,15 L26.991018,18 Z M26.991018,13.5 L24,13.5 L24,10.5 L27,10.5 L26.991018,13.5 Z M28.5,15 L31.5,15 L31.5,18 L28.5089552,18 L28.5,15 Z M28.5,22.5 L28.5,19.5 L31.5,19.5 L31.5,22.4601182 L28.5,22.5 Z"/>
                </svg>
                <h1>Vault LDAP Credentials</h1>
            </div>
            <p>Dual-Account (Blue/Green) Credential Rotation</p>
            <span class="status-badge status-badge-active" id="state-badge">● Live</span>
            <span class="version-tag">v{{ version }}</span>
        </div>

        <div class="content">
            <div id="error-banner" class="error-banner"></div>

            <!-- Secret Delivery Method Badge -->
            <div class="delivery-method-card">
                <div class="delivery-method-label">Secret Delivery Method</div>
                <div class="delivery-method-value">{{ delivery_method_display }}</div>
            </div>

            <!-- Countdown timers -->
            <div class="timers-row">
                <div class="timer-card">
                    <div class="countdown-label">Next Rotation In</div>
                    <div><span class="countdown-value" id="ttl-value">--</span><span class="countdown-unit">seconds</span></div>
                    <div class="countdown-bar-track">
                        <div class="countdown-bar-fill bar-fill-vault" id="ttl-bar" style="width: 100%;"></div>
                    </div>
                </div>
                <div class="timer-card" id="grace-timer-card" style="display: none;">
                    <div class="countdown-label">Grace Period Remaining</div>
                    <div><span class="countdown-value" id="grace-value">--</span><span class="countdown-unit">seconds</span></div>
                    <div class="countdown-bar-track">
                        <div class="countdown-bar-fill bar-fill-grace" id="grace-bar" style="width: 100%;"></div>
                    </div>
                </div>
            </div>

            <!-- Account credential cards -->
            <h2 class="section-title">Credentials</h2>
            <div class="account-cards" id="account-cards">
                <div class="account-card account-card-active" id="active-card">
                    <div class="account-card-header">
                        <span class="account-indicator indicator-active" id="active-indicator">A</span>
                        <span id="active-card-title">Active Account</span>
                    </div>
                    <div class="credential-row">
                        <div class="credential-item">
                            <div class="credential-label">Username</div>
                            <div class="credential-value" id="active-username">--</div>
                        </div>
                        <div class="credential-item">
                            <div class="credential-label">Password</div>
                            <div class="credential-value" id="active-password">--</div>
                        </div>
                    </div>
                </div>
                <div class="account-card account-card-hidden" id="standby-card">
                    <div class="account-card-header">
                        <span class="account-indicator indicator-hidden" id="standby-indicator">B</span>
                        <span id="standby-card-title">Standby Account</span>
                    </div>
                    <div class="credential-row">
                        <div class="credential-item">
                            <div class="credential-label">Username</div>
                            <div class="credential-value" id="standby-username">--</div>
                        </div>
                        <div class="credential-item">
                            <div class="credential-label">Password</div>
                            <div class="credential-value" id="standby-password">●●●●●●●●</div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="info-section">
                <div class="info-section-title">How It Works</div>
                <p>
                    Two AD service accounts are managed simultaneously with blue/green rotation.
                    When a rotation occurs, the standby account's password is changed and it becomes
                    the new active account. During the grace period, both credentials are valid —
                    giving applications time to switch. This app polls Vault directly every second
                    for real-time data. The timeline above shows the current position in the rotation cycle.
                </p>
            </div>
        </div>

        <div class="metadata">
            <div><strong>Last poll:</strong> <span id="last-poll-time">--</span></div>
            <div class="powered-by">Powered by <a href="https://developer.hashicorp.com/vault" target="_blank">HashiCorp Vault</a> + <a href="https://github.com/andybaran/vault-plugin-secrets-openldap" target="_blank">Custom Plugin</a></div>
        </div>
    </div>

    <script>
    (function() {
        var rotationPeriod = 0;
        var gracePeriod = 0;
        var lastData = null;

        function formatTime(s) { return Math.max(0, Math.ceil(s)); }

        function updateUI(data) {
            lastData = data;
            rotationPeriod = data.rotation_period || 100;
            gracePeriod = data.grace_period || 20;
            var ttl = data.ttl || 0;
            var state = data.rotation_state || 'active';
            var activeAcct = (data.active_account || 'a').toUpperCase();
            var standbyAcct = activeAcct === 'A' ? 'B' : 'A';

            // TTL countdown
            document.getElementById('ttl-value').textContent = formatTime(ttl);
            var ttlPct = rotationPeriod > 0 ? (ttl / rotationPeriod) * 100 : 0;
            document.getElementById('ttl-bar').style.width = ttlPct + '%';

            // Grace period timer
            var graceTimerCard = document.getElementById('grace-timer-card');
            var stateBadge = document.getElementById('state-badge');
            if (state === 'grace_period') {
                graceTimerCard.style.display = '';
                graceTimerCard.className = 'timer-card timer-card-grace';
                var graceEnd = data.grace_period_end ? new Date(data.grace_period_end).getTime() : 0;
                var graceRemaining = graceEnd > 0 ? Math.max(0, (graceEnd - Date.now()) / 1000) : 0;
                document.getElementById('grace-value').textContent = formatTime(graceRemaining);
                var gracePctRemaining = gracePeriod > 0 ? (graceRemaining / gracePeriod) * 100 : 0;
                document.getElementById('grace-bar').style.width = gracePctRemaining + '%';
                stateBadge.className = 'status-badge status-badge-grace';
                stateBadge.textContent = '● Grace Period';
            } else {
                graceTimerCard.style.display = 'none';
                stateBadge.className = 'status-badge status-badge-active';
                stateBadge.textContent = '● Active';
            }

            // Active credential card
            document.getElementById('active-indicator').textContent = activeAcct;
            document.getElementById('active-card-title').textContent = 'Active Account (' + activeAcct + ')';
            document.getElementById('active-username').textContent = data.username || '--';
            document.getElementById('active-password').textContent = data.password || '--';

            // Standby credential card
            var standbyCard = document.getElementById('standby-card');
            document.getElementById('standby-indicator').textContent = standbyAcct;
            if (state === 'grace_period' && data.standby_username) {
                standbyCard.className = 'account-card account-card-standby';
                document.getElementById('standby-indicator').className = 'account-indicator indicator-standby';
                document.getElementById('standby-card-title').textContent = 'Standby Account (' + standbyAcct + ') — Password Changed';
                document.getElementById('standby-username').textContent = data.standby_username || '--';
                document.getElementById('standby-password').textContent = data.standby_password || '--';
            } else {
                standbyCard.className = 'account-card account-card-hidden';
                document.getElementById('standby-indicator').className = 'account-indicator indicator-hidden';
                document.getElementById('standby-card-title').textContent = 'Standby Account (' + standbyAcct + ')';
                document.getElementById('standby-username').textContent = '--';
                document.getElementById('standby-password').textContent = '●●●●●●●●';
            }

            // Last poll time
            document.getElementById('last-poll-time').textContent = new Date().toLocaleTimeString();

            // Hide error banner on success
            document.getElementById('error-banner').style.display = 'none';
        }

        function showError(msg) {
            var banner = document.getElementById('error-banner');
            banner.textContent = 'Vault polling error: ' + msg;
            banner.style.display = 'block';
        }

        // Interpolate TTL between polls
        var lastPollTime = 0;
        var lastTTL = 0;
        function interpolateTick() {
            if (!lastData) return;
            var elapsed = (Date.now() - lastPollTime) / 1000;
            var currentTTL = Math.max(0, lastTTL - elapsed);
            document.getElementById('ttl-value').textContent = formatTime(currentTTL);
            var ttlPct = rotationPeriod > 0 ? (currentTTL / rotationPeriod) * 100 : 0;
            document.getElementById('ttl-bar').style.width = ttlPct + '%';

            // Update grace countdown if in grace period
            if (lastData.rotation_state === 'grace_period' && lastData.grace_period_end) {
                var graceEnd = new Date(lastData.grace_period_end).getTime();
                var gr = Math.max(0, (graceEnd - Date.now()) / 1000);
                document.getElementById('grace-value').textContent = formatTime(gr);
                var gPct = gracePeriod > 0 ? (gr / gracePeriod) * 100 : 0;
                document.getElementById('grace-bar').style.width = gPct + '%';
            }
        }

        function poll() {
            fetch('/api/credentials')
                .then(function(r) { return r.json(); })
                .then(function(data) {
                    if (data.error) { showError(data.error); return; }
                    lastPollTime = Date.now();
                    lastTTL = data.ttl || 0;
                    updateUI(data);
                })
                .catch(function(e) { showError(e.message); });
        }

        // Initial poll, then every 5 seconds for fresh Vault data
        poll();
        setInterval(poll, 5000);
        // Smooth interpolation every second between polls
        setInterval(interpolateTick, 1000);
    })();
    </script>
</body>
</html>
"""


def _get_credentials_from_source():
    """Get credentials based on the configured SECRET_DELIVERY_METHOD.
    
    Returns a dict with keys: username, password, last_vault_password, 
    rotation_period, rotation_ttl
    """
    # For file-based methods, use cached credentials
    if file_cred_cache and SECRET_DELIVERY_METHOD in ('vault-agent-sidecar', 'vault-csi-driver'):
        creds = file_cred_cache.get_credentials()
        
        # Map file keys to expected credential keys
        # For vault-agent-sidecar (key=value file format): LDAP_USERNAME, LDAP_PASSWORD, etc.
        # For vault-csi-driver (individual files): username, password, etc. OR LDAP_USERNAME, etc.
        username = creds.get('LDAP_USERNAME') or creds.get('username') or 'Not configured'
        password = creds.get('LDAP_PASSWORD') or creds.get('password') or 'Not configured'
        last_vault_password = (creds.get('LDAP_LAST_VAULT_PASSWORD') or 
                              creds.get('last_vault_password') or 'Not configured')
        rotation_period = int(creds.get('ROTATION_PERIOD') or 
                             creds.get('rotation_period') or 
                             os.getenv('ROTATION_PERIOD', '30'))
        rotation_ttl = int(creds.get('ROTATION_TTL') or 
                          creds.get('rotation_ttl') or 
                          os.getenv('ROTATION_TTL', '0'))
        
        return {
            'username': username,
            'password': password,
            'last_vault_password': last_vault_password,
            'rotation_period': rotation_period,
            'rotation_ttl': rotation_ttl,
        }
    
    # Default: read from environment variables (vault-secrets-operator mode)
    return {
        'username': os.getenv('LDAP_USERNAME', 'Not configured'),
        'password': os.getenv('LDAP_PASSWORD', 'Not configured'),
        'last_vault_password': os.getenv('LDAP_LAST_VAULT_PASSWORD', 'Not configured'),
        'rotation_period': int(os.getenv('ROTATION_PERIOD', '30')),
        'rotation_ttl': int(os.getenv('ROTATION_TTL', '0')),
    }


@app.route('/')
def index():
    """Display LDAP credentials."""
    dual_account_mode = os.getenv('DUAL_ACCOUNT_MODE', '').lower() == 'true'
    delivery_method_display = DELIVERY_METHOD_DISPLAY.get(
        SECRET_DELIVERY_METHOD, SECRET_DELIVERY_METHOD)

    if dual_account_mode:
        # Dual-account mode — page is rendered with JS that polls /api/credentials
        return render_template_string(
            DUAL_ACCOUNT_HTML_TEMPLATE, 
            version=APP_VERSION,
            delivery_method_display=delivery_method_display
        )
    else:
        # Single-account mode — read credentials based on delivery method
        creds = _get_credentials_from_source()
        credentials = {
            'username': creds['username'],
            'password': creds['password'],
            'last_vault_password': creds['last_vault_password'],
            'rotation_period': creds['rotation_period'],
            'rotation_ttl': creds['rotation_ttl'],
            'current_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC'),
            'delivery_method_display': delivery_method_display,
        }
        return render_template_string(HTML_TEMPLATE, version=APP_VERSION, **credentials)


@app.route('/api/credentials')
def api_credentials():
    """Return live credential data from Vault (dual-account mode only)."""
    mount_path = os.getenv('LDAP_MOUNT_PATH', 'ldap')
    role_name = os.getenv('LDAP_STATIC_ROLE_NAME', 'dual-rotation-demo')
    rotation_period = int(os.getenv('ROTATION_PERIOD', '300'))
    grace_period = int(os.getenv('GRACE_PERIOD', '60'))

    # Try direct Vault polling first
    if vault_client:
        data = vault_client.read_static_creds(mount_path, role_name)
        if data:
            return jsonify({
                'username': data.get('username', ''),
                'password': data.get('password', ''),
                'dn': data.get('dn', ''),
                'active_account': data.get('active_account', 'a'),
                'rotation_state': data.get('rotation_state', 'active'),
                'dual_account_mode': data.get('dual_account_mode', True),
                'rotation_period': data.get('rotation_period', rotation_period),
                'ttl': data.get('ttl', 0),
                'last_vault_rotation': data.get('last_vault_rotation', ''),
                'grace_period': grace_period,
                'grace_period_end': data.get('grace_period_end', ''),
                'standby_username': data.get('standby_username', ''),
                'standby_password': data.get('standby_password', ''),
                'standby_dn': data.get('standby_dn', ''),
            })

    # Fallback to file-based credentials (agent sidecar / CSI driver)
    if file_cred_cache:
        creds = file_cred_cache.get_credentials()
        if creds:
            # Parse JSON blob for CSI full-response mode
            json_blob = creds.get('ldap-creds.json', '')
            if json_blob:
                try:
                    parsed = json.loads(json_blob)
                    creds.update(parsed)
                except (json.JSONDecodeError, TypeError):
                    pass

            username = creds.get('LDAP_USERNAME') or creds.get('username', '')
            password = creds.get('LDAP_PASSWORD') or creds.get('password', '')
            return jsonify({
                'username': username,
                'password': password,
                'active_account': creds.get('ACTIVE_ACCOUNT') or creds.get('active_account', 'a'),
                'rotation_state': creds.get('ROTATION_STATE') or creds.get('rotation_state', 'active'),
                'dual_account_mode': True,
                'rotation_period': int(creds.get('ROTATION_PERIOD') or creds.get('rotation_period', rotation_period)),
                'ttl': int(creds.get('ROTATION_TTL') or creds.get('ttl', 0)),
                'last_vault_rotation': creds.get('LDAP_LAST_VAULT_PASSWORD') or creds.get('last_vault_rotation', ''),
                'grace_period': grace_period,
                'grace_period_end': creds.get('GRACE_PERIOD_END') or creds.get('grace_period_end', ''),
                'standby_username': creds.get('STANDBY_USERNAME') or creds.get('standby_username', ''),
                'standby_password': creds.get('STANDBY_PASSWORD') or creds.get('standby_password', ''),
                'source': 'file_cache_fallback',
            })
    # Fallback to env vars
    return jsonify({
        'username': os.getenv('LDAP_USERNAME', 'Not configured'),
        'password': os.getenv('LDAP_PASSWORD', 'Not configured'),
        'active_account': os.getenv('ACTIVE_ACCOUNT', 'a'),
        'rotation_state': os.getenv('ROTATION_STATE', 'active'),
        'dual_account_mode': True,
        'rotation_period': rotation_period,
        'ttl': int(os.getenv('ROTATION_TTL', '0')),
        'grace_period': grace_period,
        'grace_period_end': os.getenv('GRACE_PERIOD_END', ''),
        'standby_username': os.getenv('STANDBY_USERNAME', ''),
        'standby_password': os.getenv('STANDBY_PASSWORD', ''),
        'error': 'Vault client not available, showing env var fallback'
    })


@app.route('/health')
def health():
    """Health check endpoint for Kubernetes liveness/readiness probes."""
    return {'status': 'healthy', 'timestamp': datetime.now().isoformat()}, 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
