"""Unit tests for the API. PostgreSQL and Entra ID are faked, so these run
anywhere; the post-deploy smoke test in api.yml checks the real database."""

import datetime
import os

import pytest

os.environ.update(
    DB_HOST="db.example.test",
    DB_NAME="webapp",
    DB_USER="api",
    AZURE_CLIENT_ID="00000000-0000-0000-0000-000000000000",
)

# main reads the environment above when it's imported.
from fastapi.testclient import TestClient

import main

CREATED = datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC)


class FakeConnection:
    """Stands in for a psycopg connection: answers each query with a canned row."""

    def __init__(self, rows):
        self.rows = rows
        self.queries = []

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, query, params=None):
        self.queries.append((query, params))
        return self

    def fetchone(self):
        return self.rows[0]

    def fetchall(self):
        return self.rows


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(main, "_schema_ready", True)
    return TestClient(main.app)


def use_rows(monkeypatch, rows):
    conn = FakeConnection(rows)
    monkeypatch.setattr(main, "connect", lambda: conn)
    return conn


def test_health_needs_no_database(client, monkeypatch):
    monkeypatch.setattr(main, "connect", lambda: pytest.fail("health must not touch the database"))

    response = client.get("/api/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_health_db_reports_version(client, monkeypatch):
    use_rows(monkeypatch, [("PostgreSQL 16.0",)])

    response = client.get("/api/health/db")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "tier": "database", "version": "PostgreSQL 16.0"}


def test_health_db_returns_503_without_details(client, monkeypatch):
    def broken():
        raise OSError("connection refused: secret-host:5432")

    monkeypatch.setattr(main, "connect", broken)

    response = client.get("/api/health/db")

    assert response.status_code == 503
    # Only the exception type is shown, never its message.
    assert response.json()["detail"] == "database unavailable: OSError"


def test_list_items(client, monkeypatch):
    use_rows(monkeypatch, [(2, "second", CREATED), (1, "first", CREATED)])

    response = client.get("/api/items")

    assert response.status_code == 200
    assert [item["name"] for item in response.json()] == ["second", "first"]


def test_add_item_uses_a_query_parameter(client, monkeypatch):
    conn = use_rows(monkeypatch, [(1, "Robert'); DROP TABLE items;--", CREATED)])

    response = client.post("/api/items", json={"name": "Robert'); DROP TABLE items;--"})

    assert response.status_code == 201
    query, params = conn.queries[-1]
    assert "%s" in query
    assert params == ("Robert'); DROP TABLE items;--",)


@pytest.mark.parametrize("name", ["", "x" * 101])
def test_add_item_rejects_bad_names(client, monkeypatch, name):
    use_rows(monkeypatch, [])

    response = client.post("/api/items", json={"name": name})

    assert response.status_code == 422
