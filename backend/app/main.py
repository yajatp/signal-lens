import logging

from fastapi import FastAPI

from app.routers import measurements, predict, towers

logging.basicConfig(level=logging.INFO)

app = FastAPI(
    title="Signal Lens API",
    description="Obstruction-aware RF signal prediction: physics-based path loss "
    "+ 3D building LOS ray tracing + terrain shadowing.",
    version="0.1.0",
)

app.include_router(predict.router)
app.include_router(towers.router)
app.include_router(measurements.router)


@app.get("/health")
def health():
    return {"status": "ok"}
