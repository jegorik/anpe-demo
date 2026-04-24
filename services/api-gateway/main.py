from fastapi import FastAPI, Response
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
import uvicorn

app = FastAPI(title="ANPE API Gateway")

REQUEST_COUNT = Counter("api_gateway_requests_total", "Total requests", ["method", "path"])

@app.get("/health")
def health():
    return {"status": "ok", "service": "api-gateway"}

@app.post("/tasks")
def create_task(payload: dict):
    REQUEST_COUNT.labels(method="POST", path="/tasks").inc()
    return {"task_id": "demo-001", "status": "queued"}

@app.get("/metrics")
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)