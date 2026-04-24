from prometheus_client import Counter, start_http_server
import time

TASKS_PROCESSED = Counter("worker_tasks_processed_total", "Tasks processed", ["status"])

def run():
    start_http_server(9090)
    print("Worker started. Metrics on :9090/metrics")
    while True:
        TASKS_PROCESSED.labels(status="done").inc()
        print("Processing task...")
        time.sleep(5)

if __name__ == "__main__":
    run()
