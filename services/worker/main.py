import signal
import sys
from prometheus_client import Counter, start_http_server
import time

TASKS_PROCESSED = Counter("worker_tasks_processed_total", "Tasks processed", ["status"])


def handle_shutdown(_signum, _frame):
    print("Worker shutting down gracefully...")
    sys.exit(0)


def run():
    signal.signal(signal.SIGTERM, handle_shutdown)
    signal.signal(signal.SIGINT, handle_shutdown)
    start_http_server(9090)
    print("Worker started. Metrics on :9090/metrics")
    while True:
        TASKS_PROCESSED.labels(status="done").inc()
        print("Processing task...")
        time.sleep(5)


if __name__ == "__main__":
    run()
