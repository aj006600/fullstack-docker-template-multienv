from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_message_reports_env():
    response = client.get("/api/message")
    assert response.status_code == 200
    body = response.json()
    assert "message" in body
    assert "env" in body
