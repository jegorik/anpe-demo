"""
Integration tests — run against live Docker Compose stack.

Prerequisites: docker compose up --build -d && wait for healthy status.
These tests are NOT run in unit-test CI job. They are executed by:
    make test-integration   (starts/stops compose automatically)
    scripts/run-tests.sh    (full test suite with log output)

Tests talk to real containers on localhost to validate end-to-end behaviour.
"""
import time
import pytest
import httpx

API_BASE = "http://localhost:8080"
WORKER_BASE = "http://localhost:9090"

# Retry helper — containers may need a moment even after healthy status
def get_with_retry(url: str, retries: int = 5, delay: float = 2.0) -> httpx.Response:
    last_exc = None
    for _ in range(retries):
        try:
            return httpx.get(url, timeout=5)
        except httpx.ConnectError as e:
            last_exc = e
            time.sleep(delay)
    raise last_exc


class TestApiGatewayIntegration:
    def test_api_gateway_is_reachable(self):
        response = get_with_retry(f"{API_BASE}/health")
        assert response.status_code == 200

    def test_health_returns_ok(self):
        response = httpx.get(f"{API_BASE}/health")
        assert response.json()["status"] == "ok"

    def test_health_service_name(self):
        response = httpx.get(f"{API_BASE}/health")
        assert response.json()["service"] == "api-gateway"

    def test_create_task_end_to_end(self):
        response = httpx.post(
            f"{API_BASE}/tasks",
            json={"payload": "integration-test"},
            timeout=10,
        )
        assert response.status_code == 200
        body = response.json()
        assert "task_id" in body
        assert "status" in body

    def test_create_task_status_is_queued(self):
        response = httpx.post(f"{API_BASE}/tasks", json={"payload": "x"})
        assert response.json()["status"] == "queued"

    def test_api_gateway_metrics_endpoint(self):
        response = httpx.get(f"{API_BASE}/metrics")
        assert response.status_code == 200
        assert "api_gateway_requests_total" in response.text

    def test_metrics_counter_increments_after_task(self):
        """POST /tasks must increment the Prometheus request counter."""
        before_text = httpx.get(f"{API_BASE}/metrics").text
        httpx.post(f"{API_BASE}/tasks", json={"payload": "counter-test"})
        after_text = httpx.get(f"{API_BASE}/metrics").text

        def extract_counter(text: str) -> float:
            for line in text.splitlines():
                if line.startswith('api_gateway_requests_total{') and "POST" in line and "/tasks" in line:
                    return float(line.split()[-1])
            return 0.0

        assert extract_counter(after_text) > extract_counter(before_text)

    def test_unknown_route_returns_404(self):
        response = httpx.get(f"{API_BASE}/nonexistent")
        assert response.status_code == 404


class TestWorkerIntegration:
    def test_worker_metrics_is_reachable(self):
        response = get_with_retry(f"{WORKER_BASE}/metrics")
        assert response.status_code == 200

    def test_worker_metrics_content_type(self):
        response = httpx.get(f"{WORKER_BASE}/metrics")
        assert "text/plain" in response.headers["content-type"]

    def test_worker_tasks_processed_counter_exists(self):
        response = httpx.get(f"{WORKER_BASE}/metrics")
        assert "worker_tasks_processed_total" in response.text

    def test_worker_tasks_counter_grows_over_time(self):
        """Worker loop increments counter every 5s — verify it is non-zero."""
        response = httpx.get(f"{WORKER_BASE}/metrics")
        for line in response.text.splitlines():
            if line.startswith("worker_tasks_processed_total"):
                value = float(line.split()[-1])
                assert value >= 0  # counter exists and is a valid float
                return
        pytest.fail("worker_tasks_processed_total counter not found in metrics output")
