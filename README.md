# Signal Lens

**Obstruction-aware cellular signal prediction for iOS.** Signal Lens doesn't just show you where towers are — it predicts what your signal *should* be at any point using physics (path loss + 3D building line-of-sight ray tracing + terrain shadowing), explains *why* a spot is a dead zone ("blocked by 2 buildings, 0.9 mi from tower"), and logs real-world measurements so a residual ML model can learn the gap between physics and reality.

Full design rationale: [docs/signal-lens-project-spec.md](docs/signal-lens-project-spec.md)

## How it works

```
predicted_dbm = path_loss_baseline − building_obstruction_penalty − terrain_penalty
```

1. **Path loss** — log-distance model anchored to Friis free-space loss at a reference distance, with an environment-tuned exponent.
2. **Building LOS ray trace** — the 3D segment from your phone (~1.5 m) to the tower antenna (~30 m) is intersected against real OSM building footprints (PostGIS spatial query); any building whose roof pierces the line adds a flat attenuation penalty.
3. **Terrain shadowing** — USGS 3DEP elevations are sampled along the path; terrain that rises into the line adds a knife-edge-style penalty.

Every prediction is logged with its physics inputs alongside actual measurements — the training schema for the Phase 2 ML residual/calibration model.

## Repo layout

- `backend/` — Python 3 / FastAPI + PostGIS. Physics engine, data ingestion (OpenCelliD towers, OSM buildings via Overpass, USGS terrain), REST API.
- `ios/` — SwiftUI app (iOS 17+). Map with towers + tap-to-predict, live proxy-signal readout, Field Test Mode calibration flow, walk-test recorder. Project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- `docs/` — the project spec.

## Backend setup

Requires PostgreSQL + PostGIS (`brew install postgis`) and Python 3.12+.

```bash
brew services start postgresql@18        # or your installed version
createdb signal_lens

cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cp .env.example .env                     # add your OpenCelliD API key
.venv/bin/python -m scripts.init_db      # PostGIS extension + tables
.venv/bin/python -m scripts.seed_allen_mckinney   # real towers + buildings for the MVP region
.venv/bin/uvicorn app.main:app --reload  # http://127.0.0.1:8000/docs
```

Try it:

```bash
curl 'http://127.0.0.1:8000/predict?lat=33.1032&lon=-96.6706'
```

Tests (no database needed — physics is pure):

```bash
.venv/bin/python -m pytest tests/
```

## iOS setup

```bash
brew install xcodegen
cd ios && xcodegen generate
open SignalLens.xcodeproj
```

Run on the simulator (backend at `127.0.0.1:8000` works out of the box) or a physical iPhone (set your Mac's LAN IP in the app's Settings tab and run uvicorn with `--host 0.0.0.0`).

**Tabs:** Map (tap anywhere for a prediction with the obstruction breakdown) · Walk Test (logs predicted vs. proxy-actual every 10 s) · Calibrate (enter real RSRP from Field Test Mode, `*3001#12345#*`) · Settings.

## Honest limitations (by design, see spec §9)

- **iOS exposes no raw dBm.** The live readout is a latency/throughput proxy corrected by your Field Test calibrations — a real but imperfect substitute.
- **Building attenuation is a flat per-building constant** (~13.5 dB); material data doesn't exist publicly. This is exactly what the ML residual layer is built to absorb.
- **OSM height tags are sparse** — heights fall back to `building:levels` × 3 m, then per-type defaults, and each building records which source was used.
- **No public "live signal at any point" API exists** (Mozilla Location Service is dead; OpenCelliD is historical tower positions). Ground truth comes from physically walking the MVP region (Allen/McKinney, TX).

## Roadmap

- **Phase 2:** ML residual model (gradient-boosted regressor on the logged schema), 3D obstruction visualization (RealityKit), route heatmaps.
- **Phase 3+:** multi-carrier comparison, mmWave/6G propagation profiles, crowdsourced measurements, Android.
