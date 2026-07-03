# Signal Lens — Project Specification
*RF signal prediction & obstruction-aware coverage mapping for iOS*

> This document is the full project context: problem statement, competitive landscape, architecture decisions (with rationale), data pipeline, physics model, ML groundwork, iOS app design, MVP scope, and expansion roadmap.

---

## 1. Problem Statement

Consumer cell-signal apps (OpenSignal, CellMapper, Network Cell Info) show you *where towers are* and *what your signal currently is*. None of them tell you **why** your signal is what it is, or **predict** what it should be at a location you haven't been to yet. Carriers' own propagation models suffer the same gap — RF signal predictions "are sometimes imprecise and result in locations being erroneously reported as having acceptable signal levels when actual coverage is inadequate" (this is a documented, acknowledged industry problem, not a solved one).

**Signal Lens** predicts expected cellular signal strength at any point using 3D building geometry, terrain, and tower geometry (line-of-sight ray tracing), compares that prediction against real measured data, and — over time — learns the residual gap between physics and reality using ML. It explains *why* a location is a dead zone (blocked by Building X, too far from tower, terrain shadow) instead of just reporting that it is one.

**Target user (MVP):** yourself and a small test group in Allen/McKinney, TX, validating the model on foot/by car. **Long-term user:** anyone evaluating signal quality for home-buying, RV/rural connectivity, business site selection, or telecom-adjacent research — a real, underserved niche building materials data alone doesn't solve.

---

## 2. Competitive Landscape (already researched — don't re-litigate)

| App | Has tower map | Has live dBm (Android only) | Has predictive/obstruction modeling |
|---|---|---|---|
| OpenSignal | ✅ | ✅ | ❌ |
| CellMapper | ✅ (40M+ towers) | ✅ | ❌ |
| Network Cell Info | ✅ | ✅ | ❌ |
| Carrier coverage maps | ✅ (self-reported) | N/A | ⚠️ Static, coarse, no per-building granularity |

**Nobody does real-time obstruction-aware ray tracing on a consumer device.** This is the wedge. It's genuinely closer to research-grade telecom tooling than a consumer app, which is exactly the "wow factor" for a portfolio piece.

---

## 3. Platform & Architecture Decisions (locked in, with rationale)

### 3.1 Why iOS-native, not Flutter/cross-platform
User has Mac + iPhone only, no Android device on hand. Since there's no near-term Android testing capability, cross-platform (Flutter) adds abstraction overhead for zero present-day benefit. **Decision: native Swift/SwiftUI.** If Android becomes viable later, this is a deliberate v2 rewrite, not a retrofit — acceptable tradeoff given current constraints.

### 3.2 Critical iOS constraint — read this before writing any networking code
**There is no supported iOS API for real-time raw signal strength (dBm/RSRP/RSRQ).** Confirmed directly by Apple DTS engineers on the developer forums, repeatedly, over 10+ years — this is a deliberate Apple design decision, not a gap that will be patched. `MetricKit`'s `MXCellularConditionMetric` only exposes a coarse 24-hour histogram of signal *bars* (1–4), not dBm, and isn't real-time.

**Workaround architecture (this is load-bearing, don't skip it):**
1. **Primary live signal proxy:** `NWPathMonitor` (Network framework) + active throughput/latency probes (periodic small downloads + ping-style round-trip timing) as the real-time "actual condition" signal.
2. **Ground-truth calibration:** iOS Field Test Mode (`*3001#12345#*`) exposes real RSRP/RSRQ on a hidden diagnostic screen. Build a manual **Calibration Mode** in-app: user reads the Field Test value and enters it at a logged location/timestamp. This calibration point is used to correct the throughput→signal-quality mapping locally.
3. This is a *stronger* engineering story than raw API access would have been — it's sensor fusion + model calibration under real platform constraints, not just an API call.

### 3.3 Backend: Python/FastAPI (recommended over Vapor/Swift)
**Rationale:** The hard part of this project is geospatial computation and ML, not web serving. Python's ecosystem for this is dramatically more mature than Swift's:
- `shapely`, `geopandas`, `osmnx` — building footprint geometry & OSM ingestion
- `rasterio`, `pyproj` — terrain elevation (DEM) processing
- `numpy`/`scipy` — ray-tracing math, path-loss calculations
- `scikit-learn` / `PyTorch` — the ML calibration layer (Phase 2+)
- This also directly reuses the ML/research background from the UNT and UTD lab work (STDP models, Prolog reasoning) — a stronger, more legible narrative thread for a portfolio than "I also learned Vapor."

Swift stays purely on-device for UI, sensor access, and Field Test calibration UX — a clean separation of concerns.

### 3.4 Geographic scope: hybrid (validated + honest caveat)
**Primary MVP scope: Allen/McKinney, TX.** This is where real ground-truth walks/drives with Field Test Mode calibration happen. Real, physically-collected data first — this is what makes the model defensible.

**Secondary scope: broader city building/terrain data via OSM + OpenCelliD, for model generalization testing** (e.g., downtown Dallas, or dense high-rise metros like NYC/SF where building geometry is well-documented in OSM).

**Important honest correction to the original idea:** there is **no public API that returns "live current signal strength at an arbitrary pinpoint location right now."** OpenCelliD gives you *tower positions* (derived from historical crowdsourced measurements, not live per-point readings), and Mozilla Location Service — which used to do something adjacent — **was fully retired and archived in 2024** and no longer operates. So the plan is NOT "pull live signal for downtown Dallas from an oracle API." Instead: use OSM/OpenCelliD for tower + building geometry in other cities to test whether the *physics model* generalizes geometrically, while real signal ground-truth stays limited to where you can physically go. Be upfront about this scope limitation in any writeup — it's honest and it's also a great "identified expansion pathway" (crowdsourcing your own data over time, Phase 3+).

### 3.5 ML scope for MVP
Physics-first for v1 (deterministic, explainable, testable against real walks). But the **data schema and pipeline are built from day one** to support a calibration layer: every prediction is logged alongside the physics inputs (distance, obstruction count/type, terrain delta) AND the eventual real measurement, so a residual-learning model can be trained the moment there's enough data — no retrofit needed.

---

## 4. System Architecture

```
┌───────────────────────────────────────────────────────────┐
│                     iOS App (SwiftUI)                     │
│  - MapKit (3D display only — NOT a geometry data source)  │
│  - RealityKit/SceneKit (optional obstruction visualization)│
│  - Core Location (GPS)                                    │
│  - NWPathMonitor + throughput probes (live proxy signal)  │
│  - Manual Field Test Mode calibration entry UI            │
└────────────────────────┬──────────────────────────────────┘
                         │ REST/JSON
┌────────────────────────┼──────────────────────────────────┐
│                 FastAPI Backend (Python)                  │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Tower Lookup│  │ Ray-Trace /  │  │ ML Calibration   │  │
│  │ (OpenCelliD)│  │ Path-Loss    │  │ Layer (Phase 2+) │  │
│  │             │  │ Engine       │  │                  │  │
│  └─────────────┘  └──────────────┘  └──────────────────┘  │
└────────────────────────┬──────────────────────────────────┘
                         │
┌────────────────────────┼──────────────────────────────────┐
│              PostgreSQL + PostGIS (geospatial DB)         │
│  - Building footprints (OSM/Microsoft Building Footprints)│
│  - Terrain elevation cache (USGS 3DEP tiles)              │
│  - Tower locations (OpenCelliD, refreshed periodically)   │
│  - Measurement log (physics prediction + actual + delta)  │
└───────────────────────────────────────────────────────────┘
```

---

## 5. Data Pipeline

| Data | Source | Access method | Notes |
|---|---|---|---|
| Cell tower locations | OpenCelliD | REST API, free tier | Refresh weekly for test region |
| Building footprints + height | OpenStreetMap | Overpass API | Height tag coverage varies — fallback to estimated height by building type/levels tag |
| Building footprints + height (fallback/denser) | Microsoft Building Footprints | Bulk GeoJSON download | Better US coverage in some regions |
| Terrain elevation | USGS 3DEP | REST API / bulk DEM tiles | For terrain shadowing calculation |
| Actual signal (proxy) | On-device NWPathMonitor + throughput probes | Native iOS | Real-time |
| Actual signal (ground truth) | Manual Field Test Mode entry | User input in-app | Calibration anchor points |

**Note on MapKit:** confirmed there is no API to extract building height/mesh data from Apple's MapKit — it's a renderer, not a geometry data source. Use it only for the user-facing map display; all geometry computation runs on OSM/Microsoft Building Footprints data server-side.

---

## 6. Physics Model (MVP core)

### 6.1 Free-space path loss (baseline)
Standard log-distance path loss model:
```
PL(d) = PL(d0) + 10 * n * log10(d / d0) + Xσ
```
Where `n` is the path-loss exponent (empirically tuned per environment: ~2 for free space, 2.7–3.5 for urban), and `Xσ` is a shadowing term you'll initially set to 0 and later replace with the ML residual.

### 6.2 Line-of-sight (LOS) obstruction check
For a given (user location, tower location) pair:
1. Compute the 3D line segment between user height (assume ~1.5m unless floor-level input is added later) and tower height.
2. Query all building footprints intersecting the 2D projection of that line (PostGIS spatial query).
3. For each intersecting building, check whether its height exceeds the line's elevation at that point — binary obstruction flag.
4. Apply a per-obstruction attenuation penalty (start with a flat ~12–15 dB per building, refine later — real material-based attenuation isn't available data, and this is an explicit documented limitation, not a hidden gap).
5. Sum terrain elevation profile (USGS DEM) along the same path for terrain shadowing.

### 6.3 Output
`predicted_dbm = free_space_baseline - obstruction_penalty - terrain_penalty`

This is intentionally simple and explainable for MVP — the "wow factor" is the 3D geometric reasoning pipeline existing at all, not the sophistication of the attenuation constants (those are exactly what the ML layer improves later).

---

## 7. ML Calibration Layer — groundwork only (build now, train later)

**Schema (build this from day 1, regardless of when the model itself is trained):**

```sql
CREATE TABLE measurements (
    id UUID PRIMARY KEY,
    timestamp TIMESTAMPTZ,
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    device_height_estimate FLOAT,
    tower_id TEXT,
    tower_distance_m FLOAT,
    obstruction_count INT,
    obstruction_total_height_penalty FLOAT,
    terrain_penalty FLOAT,
    predicted_dbm FLOAT,          -- physics model output
    actual_proxy_signal FLOAT,     -- throughput/latency-derived
    actual_field_test_dbm FLOAT,   -- nullable, only present on manual calibration entries
    source TEXT                    -- 'walk_test' | 'calibration' | 'passive'
);
```

**Phase 2 model concept:** a gradient-boosted regressor (start here — interpretable, works on small data) trained to predict `residual = actual_field_test_dbm - predicted_dbm` from the geometric features (obstruction count, distance, terrain penalty, building density nearby). This is explicitly a *residual/calibration* model, not a replacement for the physics model — a stronger and more accurate framing than "train an ML model to predict signal" from scratch, and it's honest about the sparse-data reality of a single-person data collection effort.

**Phase 3+ concept (the "6G" tie-in):** once clarified what specifically the 6G/wavelength research involves, this is the natural integration point — e.g., if it involves higher-frequency propagation characteristics (mmWave-style attenuation is far more sensitive to obstruction and rain than sub-6GHz), that could become a second physics profile the model switches between, or a research-flavored extension section of the same pipeline. **Flag for follow-up:** get specifics from the user before scoping it further — don't guess at technical claims here.

---

## 8. iOS App — MVP Feature Scope

**Phase 1 (Core MVP):**
- Map view (MapKit) showing user location + nearby towers
- Tap-to-predict: shows predicted signal at any point on the map, with obstruction breakdown ("Blocked by 2 buildings, 0.3mi from tower")
- Live proxy signal reading (throughput/latency-based)
- Manual Field Test Mode calibration entry flow
- Walk-test mode: continuous logging of predicted vs. proxy-actual along a route, saved locally

**Phase 2:**
- 3D obstruction visualization (RealityKit) — see literally which buildings are blocking you
- ML residual calibration model integrated server-side, retrained periodically
- Historical heatmap of a user's walked routes

**Phase 3+ (expansion pathways):**
- Multi-carrier comparison
- 6G/mmWave propagation profile (pending clarification on existing research)
- Crowdsourced data collection from multiple test users (turns sparse single-person data into a real dataset)
- Android port (only once device access exists) — architecture is already backend-agnostic, so this is additive, not a rewrite of the hard parts

---

## 9. Known Risks / Honest Caveats (keep these visible, don't quietly drop them)

1. No raw dBm on iOS — proxy signal (throughput/latency) is a real but imperfect substitute. Calibration mode mitigates but doesn't eliminate this.
2. No live "signal strength right now at any pinpoint" public API exists anywhere (MLS is dead, OpenCelliD is historical tower positions, not live readings). Cross-city validation is geometry-only, not signal-ground-truth, until crowdsourcing exists.
3. Building material data isn't available — obstruction penalty starts as a flat constant, not material-aware. This is a documented, explicit limitation, not a silent shortcut.
4. OSM building height tag coverage is inconsistent — expect gaps, especially outside dense urban cores; fallback estimation logic needed.

---

## 10. Open Questions for the User (resolve before deep implementation)

1. What specifically is the "6G wavelength work" referenced — is there existing research, data, or a specific propagation model to integrate, or is this more of a directional interest for Phase 3?
2. Do you want the walk-test data collection to double as a personal research dataset (i.e., built with an eye toward a research paper/poster, matching the UNT/UTD lab pattern), or purely as an app validation tool?
