"""gw-webapp API (middle tier).

A small JSON API in front of PostgreSQL. It signs in to PostgreSQL with
the VM's managed identity, using an Entra ID token as the password, so
there are no database passwords anywhere.

Runs on the API VM under systemd (see ansible/roles/api). All routes are
under /api/ because the frontend's nginx forwards /api/ here unchanged.
"""

import os

import psycopg
from azure.identity import ManagedIdentityCredential
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

DB_HOST = os.environ["DB_HOST"]
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
TOKEN_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"

# The credential caches tokens (valid ~1 hour) and refreshes them itself
credential = ManagedIdentityCredential(client_id=os.environ["AZURE_CLIENT_ID"])

app = FastAPI(title="gw-webapp API")
_schema_ready = False


def connect() -> psycopg.Connection:
    token = credential.get_token(TOKEN_SCOPE).token
    return psycopg.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=token,
        sslmode="require",
        connect_timeout=5,
    )


def ensure_schema() -> None:
    # Created on first use rather than at startup, so the API comes up
    # (and /api/health works) even while the database isn't reachable yet.
    global _schema_ready
    if _schema_ready:
        return
    with connect() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS items (
                id         serial PRIMARY KEY,
                name       text NOT NULL,
                created_at timestamptz NOT NULL DEFAULT now()
            )
            """
        )
    _schema_ready = True


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)


def to_item(row: tuple) -> dict:
    return {"id": row[0], "name": row[1], "created_at": row[2].isoformat()}


@app.get("/api/health")
def health() -> dict:
    return {"status": "ok", "tier": "api", "host": os.uname().nodename}


@app.get("/api/health/db")
def health_db() -> dict:
    try:
        with connect() as conn:
            version = conn.execute("SELECT version()").fetchone()[0]
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"database unavailable: {type(exc).__name__}") from exc
    return {"status": "ok", "tier": "database", "version": version}


@app.get("/api/items")
def list_items() -> list[dict]:
    ensure_schema()
    with connect() as conn:
        rows = conn.execute("SELECT id, name, created_at FROM items ORDER BY id DESC LIMIT 50").fetchall()
    return [to_item(r) for r in rows]


@app.post("/api/items", status_code=201)
def add_item(item: ItemIn) -> dict:
    ensure_schema()
    with connect() as conn:
        row = conn.execute(
            "INSERT INTO items (name) VALUES (%s) RETURNING id, name, created_at",
            (item.name,),
        ).fetchone()
    return to_item(row)
