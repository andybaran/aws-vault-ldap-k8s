#!/usr/bin/env python3
"""
Simple Flask web application to display LDAP credentials from Vault.
Supports two modes:
- Single-account: credentials read from env vars (delivered by VSO)
- Dual-account: credentials polled directly from Vault API for real-time display
"""

import os
import time
import json
import logging
from datetime import datetime
from flask import Flask, render_template_string, jsonify

APP_VERSION = "2.2.0"
try:
    import requests as http_requests
except ImportError:
    http_requests = None

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class VaultClient:
    """Handles authentication and API calls to Vault using Kubernetes auth."""

    def __init__(self, vault_addr, auth_role, mount="kubernetes"):
        self.vault_addr = vault_addr.rstrip("/")
        self.auth_role = auth_role
        self.auth_mount = mount
        self._token = None
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
        """Authenticate to Vault using Kubernetes auth method."""
        jwt = self._read_sa_token()
        if not jwt:
            return False

        url = f"{self.vault_addr}/v1/auth/{self.auth_mount}/login"
        payload = {"role": self.auth_role, "jwt": jwt}

        try:
            resp = http_requests.post(url, json=payload, timeout=5)
            resp.raise_for_status()
            data = resp.json()
            self._token = data["auth"]["client_token"]
            lease_duration = data["auth"].get("lease_duration", 600)
            # Renew at 80% of lease duration
            self._token_expires_at = time.time() + (lease_duration * 0.8)
            logger.info("Vault login successful, token valid for %ds", lease_duration)
            return True
        except Exception as e:
            logger.error("Vault login failed: %s", e)
            self._token = None
            return False

    def get_token(self):
        """Get a valid Vault token, refreshing if necessary."""
        if self._token and time.time() < self._token_expires_at:
            return self._token
        if self._login():
            return self._token
        return None

    def read_static_creds(self, mount, role_name):
        """Read static credentials from Vault."""
        token = self.get_token()
        if not token:
            return None

        url = f"{self.vault_addr}/v1/{mount}/static-cred/{role_name}"
        headers = {"X-Vault-Token": token}

        try:
            resp = http_requests.get(url, headers=headers, timeout=5)
            resp.raise_for_status()
            return resp.json().get("data", {})
        except Exception as e:
            logger.error("Failed to read static creds: %s", e)
            return None


# Initialize Vault client if config is available
vault_client = None
vault_addr = os.getenv("VAULT_ADDR", "")
vault_auth_role = os.getenv("VAULT_AUTH_ROLE", "")
if vault_addr and vault_auth_role and http_requests:
    vault_client = VaultClient(vault_addr, vault_auth_role)
    logger.info("VaultClient initialized: addr=%s role=%s", vault_addr, vault_auth_role)


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


@app.route('/')
def index():
    """Display LDAP credentials."""
    dual_account_mode = os.getenv('DUAL_ACCOUNT_MODE', '').lower() == 'true'

    if dual_account_mode:
        # Dual-account mode — page is rendered with JS that polls /api/credentials
        return render_template_string(DUAL_ACCOUNT_HTML_TEMPLATE, version=APP_VERSION)
    else:
        # Single-account mode — same env-var-based behavior as before
        credentials = {
            'username': os.getenv('LDAP_USERNAME', 'Not configured'),
            'password': os.getenv('LDAP_PASSWORD', 'Not configured'),
            'last_vault_password': os.getenv('LDAP_LAST_VAULT_PASSWORD', 'Not configured'),
            'rotation_period': int(os.getenv('ROTATION_PERIOD', '30')),
            'rotation_ttl': int(os.getenv('ROTATION_TTL', '0')),
            'current_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
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
