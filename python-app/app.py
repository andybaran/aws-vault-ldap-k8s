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
# Styled with HashiCorp design system (Helios) principles
HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vault LDAP Credentials Demo</title>
    <style>
        /* HDS-inspired design tokens */
        :root {
            /* Colors - HashiCorp brand palette */
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

            /* Typography - HDS font stack */
            --font-family-text: -apple-system, BlinkMacSystemFont, "Segoe UI", "Roboto", "Oxygen", "Ubuntu", "Cantarell", "Fira Sans", "Droid Sans", "Helvetica Neue", sans-serif;
            --font-family-code: "SF Mono", Monaco, "Cascadia Mono", "Roboto Mono", Consolas, "Courier New", monospace;

            /* Typography scale */
            --font-size-display-500: 30px;
            --font-size-display-400: 24px;
            --font-size-display-300: 20px;
            --font-size-body-300: 16px;
            --font-size-body-200: 14px;
            --font-size-body-100: 12px;
            --line-height-display: 1.2;
            --line-height-body: 1.5;

            /* Font weights */
            --font-weight-regular: 400;
            --font-weight-medium: 500;
            --font-weight-semibold: 600;
            --font-weight-bold: 700;

            /* Spacing - HDS spacing scale */
            --spacing-050: 2px;
            --spacing-100: 4px;
            --spacing-200: 8px;
            --spacing-300: 12px;
            --spacing-400: 16px;
            --spacing-500: 24px;
            --spacing-600: 32px;
            --spacing-700: 40px;
            --spacing-800: 48px;

            /* Border radius */
            --radius-small: 4px;
            --radius-medium: 8px;
            --radius-large: 12px;

            /* Elevation */
            --elevation-mid: 0 8px 16px rgba(31, 45, 61, 0.12);
            --elevation-high: 0 12px 24px rgba(31, 45, 61, 0.16);
        }

        *, *::before, *::after {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: var(--font-family-text);
            background-color: var(--color-surface-strong);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: var(--spacing-500);
            color: var(--color-foreground-primary);
        }

        .container {
            background: var(--color-surface-primary);
            border-radius: var(--radius-large);
            box-shadow: var(--elevation-high);
            max-width: 900px;
            width: 100%;
            overflow: hidden;
        }

        /* Header section with Vault branding */
        .brand-header {
            background: var(--color-black);
            color: var(--color-surface-primary);
            padding: var(--spacing-600) var(--spacing-700);
            text-align: center;
            border-bottom: 3px solid var(--color-vault);
        }

        .brand-header-content {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: var(--spacing-400);
            margin-bottom: var(--spacing-400);
        }

        .vault-logo {
            width: 48px;
            height: 48px;
            flex-shrink: 0;
        }

        .brand-header h1 {
            font-size: var(--font-size-display-400);
            font-weight: var(--font-weight-semibold);
            line-height: var(--line-height-display);
            margin: 0;
            color: var(--color-surface-primary);
        }

        .brand-header p {
            font-size: var(--font-size-body-300);
            color: var(--color-surface-tertiary);
            margin: 0;
            line-height: var(--line-height-body);
        }

        .status-badge {
            display: inline-flex;
            align-items: center;
            gap: var(--spacing-100);
            background: var(--color-success);
            color: var(--color-surface-primary);
            padding: var(--spacing-100) var(--spacing-300);
            border-radius: var(--radius-large);
            font-size: var(--font-size-body-100);
            font-weight: var(--font-weight-semibold);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-top: var(--spacing-300);
        }

        .status-badge::before {
            content: '';
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: var(--color-surface-primary);
            animation: pulse 2s ease-in-out infinite;
        }

        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }

        /* Main content area */
        .content {
            padding: var(--spacing-700);
        }

        .section-title {
            font-size: var(--font-size-display-300);
            font-weight: var(--font-weight-semibold);
            color: var(--color-foreground-strong);
            margin-bottom: var(--spacing-500);
            padding-bottom: var(--spacing-300);
            border-bottom: 2px solid var(--color-surface-tertiary);
        }

        .credentials-grid {
            display: grid;
            gap: var(--spacing-400);
            margin-bottom: var(--spacing-600);
        }

        .credential-card {
            background: var(--color-surface-secondary);
            border: 1px solid var(--color-border-primary);
            border-radius: var(--radius-medium);
            padding: var(--spacing-500);
            transition: all 0.2s ease;
        }

        .credential-card:hover {
            border-color: var(--color-border-strong);
            box-shadow: var(--elevation-mid);
        }

        .credential-label {
            font-size: var(--font-size-body-100);
            font-weight: var(--font-weight-semibold);
            color: var(--color-foreground-faint);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: var(--spacing-200);
            display: flex;
            align-items: center;
            gap: var(--spacing-200);
        }

        .credential-label::before {
            content: '';
            width: 4px;
            height: 12px;
            background: var(--color-vault);
            border-radius: 2px;
        }

        .credential-value {
            font-family: var(--font-family-code);
            font-size: var(--font-size-body-200);
            color: var(--color-foreground-strong);
            background: var(--color-surface-primary);
            padding: var(--spacing-300);
            border-radius: var(--radius-small);
            border: 1px solid var(--color-border-primary);
            word-break: break-all;
            line-height: 1.6;
        }

        /* Countdown timer */
        .countdown-card {
            background: var(--color-surface-secondary);
            border: 1px solid var(--color-border-primary);
            border-radius: var(--radius-medium);
            padding: var(--spacing-500);
            margin-bottom: var(--spacing-600);
            text-align: center;
        }

        .countdown-label {
            font-size: var(--font-size-body-100);
            font-weight: var(--font-weight-semibold);
            color: var(--color-foreground-faint);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: var(--spacing-300);
        }

        .countdown-display {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: var(--spacing-400);
        }

        .countdown-value {
            font-family: var(--font-family-code);
            font-size: var(--font-size-display-500);
            font-weight: var(--font-weight-bold);
            color: var(--color-foreground-strong);
            min-width: 80px;
        }

        .countdown-unit {
            font-size: var(--font-size-body-200);
            color: var(--color-foreground-faint);
            font-weight: var(--font-weight-medium);
        }

        .countdown-bar-track {
            height: 6px;
            background: var(--color-surface-tertiary);
            border-radius: 3px;
            margin-top: var(--spacing-400);
            overflow: hidden;
        }

        .countdown-bar-fill {
            height: 100%;
            background: var(--color-vault);
            border-radius: 3px;
            transition: width 1s linear;
        }

        /* Info section */
        .info-section {
            background: var(--color-success-surface);
            border: 1px solid rgba(21, 131, 77, 0.3);
            border-radius: var(--radius-medium);
            padding: var(--spacing-500);
            margin-bottom: var(--spacing-500);
        }

        .info-section-title {
            font-size: var(--font-size-body-300);
            font-weight: var(--font-weight-semibold);
            color: var(--color-success);
            margin-bottom: var(--spacing-300);
            display: flex;
            align-items: center;
            gap: var(--spacing-200);
        }

        .info-section p {
            font-size: var(--font-size-body-200);
            color: var(--color-foreground-primary);
            line-height: var(--line-height-body);
            margin: 0;
        }

        /* Metadata section */
        .metadata {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: var(--spacing-500);
            background: var(--color-surface-secondary);
            border-top: 1px solid var(--color-border-primary);
            font-size: var(--font-size-body-200);
            color: var(--color-foreground-faint);
        }

        .metadata strong {
            color: var(--color-foreground-strong);
            font-weight: var(--font-weight-medium);
        }

        .powered-by {
            display: flex;
            align-items: center;
            gap: var(--spacing-200);
        }

        .powered-by a {
            color: var(--color-highlight);
            text-decoration: none;
            font-weight: var(--font-weight-medium);
            transition: color 0.2s ease;
        }

        .powered-by a:hover {
            color: var(--color-foreground-strong);
            text-decoration: underline;
        }

        /* Refresh button - hidden until countdown expires + 5s */
        .refresh-btn {
            display: none;
            margin-top: var(--spacing-400);
            padding: var(--spacing-300) var(--spacing-600);
            background: var(--color-vault);
            color: var(--color-black);
            border: none;
            border-radius: var(--radius-medium);
            font-family: var(--font-family-text);
            font-size: var(--font-size-body-300);
            font-weight: var(--font-weight-semibold);
            cursor: pointer;
            transition: all 0.2s ease;
        }

        .refresh-btn:hover {
            background: #e6c200;
            box-shadow: var(--elevation-mid);
        }

        .refresh-btn.visible {
            display: inline-block;
            animation: fadeIn 0.3s ease-in;
        }

        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(4px); }
            to   { opacity: 1; transform: translateY(0); }
        }

        @media (max-width: 640px) {
            body {
                padding: var(--spacing-300);
            }

            .brand-header {
                padding: var(--spacing-500);
            }

            .brand-header h1 {
                font-size: var(--font-size-display-300);
            }

            .content {
                padding: var(--spacing-500);
            }

            .metadata {
                flex-direction: column;
                gap: var(--spacing-300);
                text-align: center;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Header with Vault branding -->
        <div class="brand-header">
            <div class="brand-header-content">
                <svg class="vault-logo" viewBox="0 0 51 51" xmlns="http://www.w3.org/2000/svg">
                    <path fill="#FFD814" fill-rule="nonzero" d="M0,0 L25.4070312,51 L51,0 L0,0 Z M28.5,10.5 L31.5,10.5 L31.5,13.5 L28.5,13.5 L28.5,10.5 Z M22.5,22.5 L19.5,22.5 L19.5,19.5 L22.5,19.5 L22.5,22.5 Z M22.5,18 L19.5,18 L19.5,15 L22.5,15 L22.5,18 Z M22.5,13.5 L19.5,13.5 L19.5,10.5 L22.5,10.5 L22.5,13.5 Z M26.991018,27 L24,27 L24,24 L27,24 L26.991018,27 Z M26.991018,22.5 L24,22.5 L24,19.5 L27,19.5 L26.991018,22.5 Z M26.991018,18 L24,18 L24,15 L27,15 L26.991018,18 Z M26.991018,13.5 L24,13.5 L24,10.5 L27,10.5 L26.991018,13.5 Z M28.5,15 L31.5,15 L31.5,18 L28.5089552,18 L28.5,15 Z M28.5,22.5 L28.5,19.5 L31.5,19.5 L31.5,22.4601182 L28.5,22.5 Z"/>
                </svg>
                <h1>Vault LDAP Credentials</h1>
            </div>
            <p>Automatically rotated credentials managed by HashiCorp Vault</p>
            <div class="status-badge">Live Demo</div>
        </div>

        <!-- Main content -->
        <div class="content">
            <h2 class="section-title">Active Credentials</h2>

            <!-- Rotation countdown timer -->
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
                <p>
                    These credentials are automatically rotated by HashiCorp Vault's LDAP secrets engine every {{ rotation_period }} seconds.
                    The Vault Secrets Operator synchronizes the rotated credentials to Kubernetes secrets, which are
                    then injected into this application as environment variables. When credentials rotate, the application
                    automatically restarts with the new values.
                </p>
            </div>
        </div>

        <!-- Footer metadata -->
        <div class="metadata">
            <div><strong>Page loaded:</strong> {{ current_time }}</div>
            <div class="powered-by">
                Powered by
                <a href="https://developer.hashicorp.com/vault" target="_blank">HashiCorp Vault</a>
                +
                <a href="https://developer.hashicorp.com/vault/docs/platform/k8s/vso" target="_blank">VSO</a>
            </div>
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

                // Show refresh button 5 seconds after countdown reaches 0
                if (!buttonShown && remaining === 0) {
                    buttonShown = true;
                    setTimeout(function() {
                        refreshBtn.classList.add('visible');
                    }, 5000);
                }
            }

            update();
            setInterval(update, 1000);
        })();
    </script>
</body>
</html>
"""


@app.route('/')
def index():
    """Display LDAP credentials from environment variables."""
    credentials = {
        'username': os.getenv('LDAP_USERNAME', 'Not configured'),
        'password': os.getenv('LDAP_PASSWORD', 'Not configured'),
        'last_vault_password': os.getenv('LDAP_LAST_VAULT_PASSWORD', 'Not configured'),
        'rotation_period': int(os.getenv('ROTATION_PERIOD', '30')),
        'rotation_ttl': int(os.getenv('ROTATION_TTL', '0')),
        'current_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    }
    return render_template_string(HTML_TEMPLATE, **credentials)


@app.route('/health')
def health():
    """Health check endpoint for Kubernetes liveness/readiness probes."""
    return {'status': 'healthy', 'timestamp': datetime.now().isoformat()}, 200


if __name__ == '__main__':
    # Run on port 8080
    app.run(host='0.0.0.0', port=8080, debug=False)
