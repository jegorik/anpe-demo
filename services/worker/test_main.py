"""
Unit tests for worker service.

Worker doesn't expose an HTTP API — it runs a background loop and
exposes Prometheus metrics via prometheus_client.start_http_server.
Tests validate the business logic and metrics registration in isolation,
without actually starting the HTTP server or the infinite loop.

Run locally:
    cd services/worker
    pip install -r requirements.txt pytest
    pytest test_main.py -v

Run via Makefile (project root):
    make test-unit
"""
import pytest
from unittest.mock import patch, MagicMock


class TestWorkerMetrics:
    def test_tasks_processed_counter_exists(self):
        """TASKS_PROCESSED counter must be importable and be a Counter."""
        from prometheus_client import Counter
        from main import TASKS_PROCESSED
        assert isinstance(TASKS_PROCESSED, Counter)

    def test_tasks_processed_counter_name(self):
        # prometheus_client stores the base name without the _total suffix
        from main import TASKS_PROCESSED
        assert TASKS_PROCESSED._name == "worker_tasks_processed"

    def test_tasks_processed_has_status_label(self):
        from main import TASKS_PROCESSED
        assert "status" in TASKS_PROCESSED._labelnames

    def test_tasks_processed_increments(self):
        from main import TASKS_PROCESSED
        before = TASKS_PROCESSED.labels(status="done")._value.get()
        TASKS_PROCESSED.labels(status="done").inc()
        after = TASKS_PROCESSED.labels(status="done")._value.get()
        assert after == before + 1


class TestHandleShutdown:
    def test_shutdown_handler_calls_sys_exit(self):
        """handle_shutdown must exit the process — simulates SIGTERM."""
        from main import handle_shutdown
        with pytest.raises(SystemExit):
            handle_shutdown(15, None)  # 15 = SIGTERM


class TestRunFunction:
    def test_run_registers_signal_handlers(self):
        """run() must register SIGTERM and SIGINT handlers before looping."""
        import signal
        from main import handle_shutdown

        with patch("main.start_http_server"), \
             patch("main.time.sleep", side_effect=KeyboardInterrupt), \
             patch("signal.signal") as mock_signal:
            try:
                from main import run
                run()
            except (KeyboardInterrupt, SystemExit):
                pass

            calls = {args[0] for args, _ in mock_signal.call_args_list}
            assert signal.SIGTERM in calls
            assert signal.SIGINT in calls

    def test_run_starts_http_server_on_port_9090(self):
        """run() must start the Prometheus HTTP server on port 9090."""
        with patch("main.start_http_server") as mock_server, \
             patch("main.time.sleep", side_effect=KeyboardInterrupt), \
             patch("signal.signal"):
            try:
                from main import run
                run()
            except (KeyboardInterrupt, SystemExit):
                pass

            mock_server.assert_called_once_with(9090)
