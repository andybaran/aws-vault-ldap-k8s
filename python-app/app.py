#!/usr/bin/env python3
"""
Simple Flask web application to display LDAP credentials from Vault.
Credentials are delivered via Vault Secrets Operator and read from environment variables.
"""

import os
from datetime import datetime
from flask import Flask, render_template_string

app = Flask(__name__)

# HTML template for displaying credentials
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vault LDAP Credentials Demo</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 16px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            max-width: 800px;
            width: 100%;
            padding: 40px;
        }
        .header {
            text-align: center;
            margin-bottom: 40px;
        }
        .header h1 {
            color: #2d3748;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .header p {
            color: #718096;
            font-size: 1.1em;
        }
        .logo {
            text-align: center;
            margin-bottom: 30px;
        }
        .logo svg {
            width: 120px;
            height: 120px;
        }
        .credential-section {
            background: #f7fafc;
            border-radius: 8px;
            padding: 24px;
            margin-bottom: 20px;
            border-left: 4px solid #667eea;
        }
        .credential-label {
            color: #4a5568;
            font-size: 0.875em;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 8px;
        }
        .credential-value {
            color: #2d3748;
            font-size: 1.25em;
            font-family: 'Courier New', monospace;
            background: white;
            padding: 12px;
            border-radius: 4px;
            word-break: break-all;
        }
        .info-box {
            background: #ebf8ff;
            border-left: 4px solid #4299e1;
            border-radius: 8px;
            padding: 16px;
            margin-top: 24px;
        }
        .info-box p {
            color: #2c5282;
            font-size: 0.95em;
            line-height: 1.6;
        }
        .footer {
            text-align: center;
            margin-top: 32px;
            padding-top: 24px;
            border-top: 1px solid #e2e8f0;
        }
        .footer a {
            color: #667eea;
            text-decoration: none;
            font-weight: 500;
        }
        .footer a:hover {
            text-decoration: underline;
        }
        .timestamp {
            color: #718096;
            font-size: 0.875em;
            margin-top: 8px;
        }
        .status-badge {
            display: inline-block;
            background: #48bb78;
            color: white;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.875em;
            font-weight: 600;
            margin-left: 8px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">
            <svg viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">
                <rect fill="#000000" width="256" height="256" rx="24"/>
                <path fill="#FFFFFF" d="M128 40l96 55.5v111L128 262l-96-55.5v-111L128 40z"/>
                <path fill="#FFD814" d="M128 80l-64 37v74l64 37 64-37v-74l-64-37z"/>
                <path fill="#000000" d="M128 100l-48 28v56l48 28 48-28v-56l-48-28z"/>
            </svg>
        </div>
        
        <div class="header">
            <h1>Vault LDAP Credentials <span class="status-badge">LIVE</span></h1>
            <p>Credentials managed by HashiCorp Vault with automatic rotation</p>
        </div>

        <div class="credential-section">
            <div class="credential-label">Username</div>
            <div class="credential-value">{{ username }}</div>
        </div>

        <div class="credential-section">
            <div class="credential-label">Password</div>
            <div class="credential-value">{{ password }}</div>
        </div>

        <div class="credential-section">
            <div class="credential-label">Distinguished Name (DN)</div>
            <div class="credential-value">{{ dn }}</div>
        </div>

        <div class="credential-section">
            <div class="credential-label">Last Vault Password</div>
            <div class="credential-value">{{ last_vault_password }}</div>
        </div>

        <div class="info-box">
            <p>
                <strong>🔐 How it works:</strong> These credentials are automatically rotated by HashiCorp Vault's 
                LDAP secrets engine every 24 hours. The Vault Secrets Operator synchronizes the rotated credentials 
                to Kubernetes secrets, which are then injected into this application as environment variables. 
                When credentials rotate, the application automatically restarts with the new values.
            </p>
        </div>

        <div class="timestamp">
            <strong>Page loaded:</strong> {{ current_time }}
        </div>

        <div class="footer">
            <p>
                Powered by 
                <a href="https://developer.hashicorp.com/vault" target="_blank">HashiCorp Vault</a> + 
                <a href="https://developer.hashicorp.com/vault/docs/platform/k8s/vso" target="_blank">Vault Secrets Operator</a>
            </p>
        </div>
    </div>
</body>
</html>
"""


@app.route('/')
def index():
    """Display LDAP credentials from environment variables."""
    credentials = {
        'username': os.getenv('LDAP_USERNAME', 'Not configured'),
        'password': os.getenv('LDAP_PASSWORD', 'Not configured'),
        'dn': os.getenv('LDAP_DN', 'Not configured'),
        'last_vault_password': os.getenv('LDAP_LAST_VAULT_PASSWORD', 'Not configured'),
        'current_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    }
    return render_template_string(HTML_TEMPLATE, **credentials)


@app.route('/health')
def health():
    """Health check endpoint for Kubernetes liveness/readiness probes."""
    return {'status': 'healthy', 'timestamp': datetime.now().isoformat()}, 200


if __name__ == '__main__':
    # Run on port 8080 to match existing Go app configuration
    app.run(host='0.0.0.0', port=8080, debug=False)
