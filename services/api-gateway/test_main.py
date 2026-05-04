"""
Unit tests for api-gateway service.

Run locally:
    cd services/api-gateway
    pip install -r requirements.txt pytest
    pytest test_main.py -v

Run via Makefile (project root):
    make test-unit
"""
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


class TestHealthEndpoint:
    def test_health_returns_200(self):
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_response_body(self):
        response = client.get("/health")
        body = response.json()
        assert body["status"] == "ok"
        assert body["service"] == "api-gateway"

    def test_health_content_type_is_json(self):
        response = client.get("/health")
        assert "application/json" in response.headers["content-type"]


class TestTasksEndpoint:
    def test_create_task_returns_200(self):
        response = client.post("/tasks", json={"payload": "test"})
        assert response.status_code == 200

    def test_create_task_returns_task_id(self):
        response = client.post("/tasks", json={"payload": "test"})
        body = response.json()
        assert "task_id" in body

    def test_create_task_returns_status(self):
        response = client.post("/tasks", json={"payload": "test"})
        body = response.json()
        assert "status" in body
        assert body["status"] == "queued"

    def test_create_task_accepts_arbitrary_payload(self):
        response = client.post("/tasks", json={"payload": "hello", "extra": 42})
        assert response.status_code == 200

    def test_create_task_without_body_returns_error(self):
        response = client.post("/tasks")
        assert response.status_code == 422


class TestMetricsEndpoint:
    def test_metrics_returns_200(self):
        response = client.get("/metrics")
        assert response.status_code == 200

    def test_metrics_content_type_is_prometheus(self):
        response = client.get("/metrics")
        assert "text/plain" in response.headers["content-type"]

    def test_metrics_contains_request_counter(self):
        # Hit /tasks first so the counter is non-zero
        client.post("/tasks", json={"payload": "metrics-test"})
        response = client.get("/metrics")
        assert "api_gateway_requests_total" in response.text

    def test_metrics_contains_python_info(self):
        response = client.get("/metrics")
        assert "python_info" in response.text


class TestUnknownRoutes:
    def test_unknown_get_returns_404(self):
        response = client.get("/nonexistent")
        assert response.status_code == 404

    def test_unknown_post_returns_404_or_405(self):
        response = client.post("/health")
        assert response.status_code in (404, 405)
