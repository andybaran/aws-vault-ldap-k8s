#!/usr/bin/env python3
"""
Tests for the Flask LDAP credentials demo application.
Tests cover multiple secret delivery methods: vault-secrets-operator,
vault-agent-sidecar, and vault-csi-driver.
"""

import os
import sys
import pytest
from unittest.mock import MagicMock

# Patch hvac import before importing app module
sys.modules['hvac'] = MagicMock()

# Set minimal env vars before importing app
os.environ.setdefault('SECRET_DELIVERY_METHOD', 'vault-secrets-operator')


class TestHealthEndpoint:
    """Tests for the /health endpoint."""

    def test_health_returns_200(self, client):
        """Health endpoint returns 200 with expected fields."""
        response = client.get('/health')
        assert response.status_code == 200
        data = response.get_json()
        assert 'status' in data
        assert data['status'] == 'healthy'
        assert 'timestamp' in data

    def test_health_timestamp_format(self, client):
        """Health endpoint returns ISO format timestamp."""
        response = client.get('/health')
        data = response.get_json()
        # ISO format contains 'T' separator
        assert 'T' in data['timestamp']


class TestFileCredentialCacheAgentMode:
    """Tests for FileCredentialCache with vault-agent-sidecar delivery."""

    def test_parse_key_value_file(self, tmp_path):
        """FileCredentialCache correctly parses key=value file (agent mode)."""
        # Create a credentials file in key=value format
        creds_file = tmp_path / "ldap-creds"
        creds_file.write_text(
            "LDAP_USERNAME=svc-rotate-a\n"
            "LDAP_PASSWORD=secret123\n"
            "LDAP_LAST_VAULT_PASSWORD=oldsecret\n"
            "ROTATION_PERIOD=300\n"
            "ROTATION_TTL=250\n"
        )

        import app as app_module
        # Patch the module-level constant
        original = app_module.VAULT_AGENT_CREDS_FILE
        app_module.VAULT_AGENT_CREDS_FILE = str(creds_file)
        try:
            cache = app_module.FileCredentialCache('vault-agent-sidecar')
            cache._read_credentials()
            creds = cache.get_credentials()

            assert creds['LDAP_USERNAME'] == 'svc-rotate-a'
            assert creds['LDAP_PASSWORD'] == 'secret123'
            assert creds['LDAP_LAST_VAULT_PASSWORD'] == 'oldsecret'
            assert creds['ROTATION_PERIOD'] == '300'
            assert creds['ROTATION_TTL'] == '250'
        finally:
            app_module.VAULT_AGENT_CREDS_FILE = original

    def test_parse_key_value_with_comments(self, tmp_path):
        """FileCredentialCache ignores comment lines."""
        creds_file = tmp_path / "ldap-creds"
        creds_file.write_text(
            "# This is a comment\n"
            "LDAP_USERNAME=testuser\n"
            "# Another comment\n"
            "LDAP_PASSWORD=testpass\n"
        )

        import app as app_module
        original = app_module.VAULT_AGENT_CREDS_FILE
        app_module.VAULT_AGENT_CREDS_FILE = str(creds_file)
        try:
            cache = app_module.FileCredentialCache('vault-agent-sidecar')
            cache._read_credentials()
            creds = cache.get_credentials()

            assert creds['LDAP_USERNAME'] == 'testuser'
            assert creds['LDAP_PASSWORD'] == 'testpass'
            assert len(creds) == 2
        finally:
            app_module.VAULT_AGENT_CREDS_FILE = original

    def test_handles_missing_file(self, tmp_path):
        """FileCredentialCache handles missing credentials file gracefully."""
        missing_file = tmp_path / "nonexistent"

        import app as app_module
        original = app_module.VAULT_AGENT_CREDS_FILE
        app_module.VAULT_AGENT_CREDS_FILE = str(missing_file)
        try:
            cache = app_module.FileCredentialCache('vault-agent-sidecar')
            cache._read_credentials()
            creds = cache.get_credentials()
            assert creds == {}
        finally:
            app_module.VAULT_AGENT_CREDS_FILE = original

    def test_handles_empty_lines(self, tmp_path):
        """FileCredentialCache handles empty lines in file."""
        creds_file = tmp_path / "ldap-creds"
        creds_file.write_text(
            "\n"
            "LDAP_USERNAME=user1\n"
            "\n"
            "LDAP_PASSWORD=pass1\n"
            "\n"
        )

        import app as app_module
        original = app_module.VAULT_AGENT_CREDS_FILE
        app_module.VAULT_AGENT_CREDS_FILE = str(creds_file)
        try:
            cache = app_module.FileCredentialCache('vault-agent-sidecar')
            cache._read_credentials()
            creds = cache.get_credentials()
            assert creds['LDAP_USERNAME'] == 'user1'
            assert creds['LDAP_PASSWORD'] == 'pass1'
        finally:
            app_module.VAULT_AGENT_CREDS_FILE = original


class TestFileCredentialCacheCSIMode:
    """Tests for FileCredentialCache with vault-csi-driver delivery."""

    def test_read_directory_files(self, tmp_path):
        """FileCredentialCache correctly reads individual files from directory (CSI mode)."""
        # Create individual secret files as CSI driver would
        (tmp_path / "username").write_text("svc-csi-user")
        (tmp_path / "password").write_text("csi-secret-456")
        (tmp_path / "rotation_period").write_text("600")

        import app as app_module
        original = app_module.VAULT_CSI_SECRETS_DIR
        app_module.VAULT_CSI_SECRETS_DIR = str(tmp_path)
        try:
            cache = app_module.FileCredentialCache('vault-csi-driver')
            cache._read_credentials()
            creds = cache.get_credentials()

            assert creds['username'] == 'svc-csi-user'
            assert creds['password'] == 'csi-secret-456'
            assert creds['rotation_period'] == '600'
        finally:
            app_module.VAULT_CSI_SECRETS_DIR = original

    def test_handles_missing_directory(self, tmp_path):
        """FileCredentialCache handles missing directory gracefully."""
        missing_dir = tmp_path / "nonexistent-dir"

        import app as app_module
        original = app_module.VAULT_CSI_SECRETS_DIR
        app_module.VAULT_CSI_SECRETS_DIR = str(missing_dir)
        try:
            cache = app_module.FileCredentialCache('vault-csi-driver')
            cache._read_credentials()
            creds = cache.get_credentials()
            assert creds == {}
        finally:
            app_module.VAULT_CSI_SECRETS_DIR = original

    def test_ignores_subdirectories(self, tmp_path):
        """FileCredentialCache only reads files, not subdirectories."""
        (tmp_path / "username").write_text("testuser")
        subdir = tmp_path / "subdir"
        subdir.mkdir()
        (subdir / "nested").write_text("should-be-ignored")

        import app as app_module
        original = app_module.VAULT_CSI_SECRETS_DIR
        app_module.VAULT_CSI_SECRETS_DIR = str(tmp_path)
        try:
            cache = app_module.FileCredentialCache('vault-csi-driver')
            cache._read_credentials()
            creds = cache.get_credentials()

            assert creds['username'] == 'testuser'
            assert 'subdir' not in creds
            assert 'nested' not in creds
        finally:
            app_module.VAULT_CSI_SECRETS_DIR = original

    def test_strips_whitespace_from_file_content(self, tmp_path):
        """FileCredentialCache strips whitespace from file content."""
        (tmp_path / "username").write_text("  spaceduser  \n")
        (tmp_path / "password").write_text("\tpassword123\t")

        import app as app_module
        original = app_module.VAULT_CSI_SECRETS_DIR
        app_module.VAULT_CSI_SECRETS_DIR = str(tmp_path)
        try:
            cache = app_module.FileCredentialCache('vault-csi-driver')
            cache._read_credentials()
            creds = cache.get_credentials()

            assert creds['username'] == 'spaceduser'
            assert creds['password'] == 'password123'
        finally:
            app_module.VAULT_CSI_SECRETS_DIR = original


class TestVaultClient:
    """Tests for VaultClient class (mocked - no actual Vault connectivity)."""

    def test_vault_client_init(self):
        """VaultClient initializes with correct parameters."""
        from app import VaultClient
        client = VaultClient(
            vault_addr="http://vault.local:8200",
            auth_role="test-role",
            mount="kubernetes"
        )
        assert client.vault_addr == "http://vault.local:8200"
        assert client.auth_role == "test-role"
        assert client.auth_mount == "kubernetes"

    def test_vault_client_strips_trailing_slash(self):
        """VaultClient strips trailing slash from vault_addr."""
        from app import VaultClient
        client = VaultClient(
            vault_addr="http://vault.local:8200/",
            auth_role="test-role"
        )
        assert client.vault_addr == "http://vault.local:8200"

    def test_read_sa_token_missing_file(self):
        """VaultClient handles missing SA token file."""
        from app import VaultClient
        client = VaultClient(
            vault_addr="http://vault:8200",
            auth_role="test"
        )
        client._sa_token_path = "/nonexistent/token"
        result = client._read_sa_token()
        assert result is None

    def test_read_sa_token_success(self, tmp_path):
        """VaultClient reads SA token from file."""
        token_file = tmp_path / "token"
        token_file.write_text("my-jwt-token-here\n")

        from app import VaultClient
        client = VaultClient(
            vault_addr="http://vault:8200",
            auth_role="test"
        )
        client._sa_token_path = str(token_file)
        result = client._read_sa_token()
        assert result == "my-jwt-token-here"


class TestMainPage:
    """Tests for the main page (/) endpoint."""

    def test_main_page_returns_200(self, client):
        """Main page returns 200 status."""
        response = client.get('/')
        assert response.status_code == 200

    def test_main_page_contains_version(self, client):
        """Main page contains version number."""
        response = client.get('/')
        assert b'3.0.0' in response.data or b'v3.0.0' in response.data

    def test_main_page_vso_mode_shows_delivery_badge(self, client_vso):
        """Main page shows delivery method badge for VSO mode."""
        response = client_vso.get('/')
        assert response.status_code == 200
        assert b'Vault Secrets Operator' in response.data

    def test_main_page_agent_mode_shows_delivery_badge(self, client_agent):
        """Main page shows delivery method badge for agent mode."""
        response = client_agent.get('/')
        assert response.status_code == 200
        assert b'Vault Agent Sidecar' in response.data

    def test_main_page_csi_mode_shows_delivery_badge(self, client_csi):
        """Main page shows delivery method badge for CSI mode."""
        response = client_csi.get('/')
        assert response.status_code == 200
        assert b'Vault CSI Driver' in response.data


class TestApiCredentialsEndpoint:
    """Tests for the /api/credentials endpoint."""

    def test_api_credentials_returns_json(self, client):
        """API credentials endpoint returns JSON."""
        response = client.get('/api/credentials')
        assert response.status_code == 200
        assert response.content_type == 'application/json'

    def test_api_credentials_has_expected_structure(self, client):
        """API credentials endpoint returns expected JSON structure."""
        response = client.get('/api/credentials')
        data = response.get_json()
        
        # Core fields that should always be present
        assert 'username' in data
        assert 'password' in data
        assert 'rotation_period' in data
        assert 'ttl' in data

    def test_api_credentials_fallback_values(self, client):
        """API credentials returns fallback values when Vault unavailable."""
        response = client.get('/api/credentials')
        data = response.get_json()
        
        # Should have fallback/default values
        assert 'dual_account_mode' in data
        assert isinstance(data['rotation_period'], int)


# ─── Fixtures ───────────────────────────────────────────────────────────────

@pytest.fixture
def client(monkeypatch, tmp_path):
    """Create Flask test client with default (VSO) delivery method."""
    monkeypatch.setenv('SECRET_DELIVERY_METHOD', 'vault-secrets-operator')
    monkeypatch.setenv('LDAP_USERNAME', 'test-user')
    monkeypatch.setenv('LDAP_PASSWORD', 'test-pass')
    monkeypatch.setenv('LDAP_LAST_VAULT_PASSWORD', 'old-pass')
    monkeypatch.setenv('ROTATION_PERIOD', '300')
    monkeypatch.setenv('ROTATION_TTL', '150')
    
    # Force reimport to pick up env changes
    import importlib
    import app as app_module
    importlib.reload(app_module)
    
    app_module.app.config['TESTING'] = True
    with app_module.app.test_client() as test_client:
        yield test_client


@pytest.fixture
def client_vso(monkeypatch, tmp_path):
    """Create Flask test client configured for vault-secrets-operator mode."""
    monkeypatch.setenv('SECRET_DELIVERY_METHOD', 'vault-secrets-operator')
    monkeypatch.setenv('LDAP_USERNAME', 'vso-user')
    monkeypatch.setenv('LDAP_PASSWORD', 'vso-pass')
    monkeypatch.setenv('ROTATION_PERIOD', '300')
    monkeypatch.setenv('ROTATION_TTL', '200')
    
    import importlib
    import app as app_module
    importlib.reload(app_module)
    
    app_module.app.config['TESTING'] = True
    with app_module.app.test_client() as test_client:
        yield test_client


@pytest.fixture
def client_agent(monkeypatch, tmp_path):
    """Create Flask test client configured for vault-agent-sidecar mode."""
    # Create credentials file
    creds_file = tmp_path / "ldap-creds"
    creds_file.write_text(
        "LDAP_USERNAME=agent-user\n"
        "LDAP_PASSWORD=agent-pass\n"
        "LDAP_LAST_VAULT_PASSWORD=agent-old\n"
        "ROTATION_PERIOD=300\n"
        "ROTATION_TTL=180\n"
    )
    
    monkeypatch.setenv('SECRET_DELIVERY_METHOD', 'vault-agent-sidecar')
    monkeypatch.setenv('VAULT_AGENT_CREDS_FILE', str(creds_file))
    
    import importlib
    import app as app_module
    importlib.reload(app_module)
    
    app_module.app.config['TESTING'] = True
    with app_module.app.test_client() as test_client:
        yield test_client


@pytest.fixture
def client_csi(monkeypatch, tmp_path):
    """Create Flask test client configured for vault-csi-driver mode."""
    # Create secrets directory with individual files
    (tmp_path / "LDAP_USERNAME").write_text("csi-user")
    (tmp_path / "LDAP_PASSWORD").write_text("csi-pass")
    (tmp_path / "LDAP_LAST_VAULT_PASSWORD").write_text("csi-old")
    (tmp_path / "ROTATION_PERIOD").write_text("300")
    (tmp_path / "ROTATION_TTL").write_text("120")
    
    monkeypatch.setenv('SECRET_DELIVERY_METHOD', 'vault-csi-driver')
    monkeypatch.setenv('VAULT_CSI_SECRETS_DIR', str(tmp_path))
    
    import importlib
    import app as app_module
    importlib.reload(app_module)
    
    app_module.app.config['TESTING'] = True
    with app_module.app.test_client() as test_client:
        yield test_client
