from fastapi import FastAPI
from prometheus_client import Counter, make_asgi_app
import uvicorn

app = FastAPI(title="ANPE API Gateway")
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

REQUEST_COUNT = Counter("api_gateway_requests_total", "Total requests", ["method", "path"])

@app.get("/health")
def health():
    return {"status": "ok", "service": "api-gateway"}

@app.post("/tasks")
def create_task(payload: dict):
    REQUEST_COUNT.labels(method="POST", path="/tasks").inc()
    return {"task_id": "demo-001", "status": "queued"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
