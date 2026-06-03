# Fly Trajectory Dashboard

An interactive browser-based dashboard for visualizing Drosophila walking trajectories from free-walking experiments.

## Overview

The dashboard displays per-fly trajectories grouped by protocol and experimental cycle. It supports:

- Grid view of all flies across all cycles, or probe cycles only
- Click-to-expand detail view for individual fly trajectories
- Overlay mode to compare trajectories across selected flies and cycles
- SVG export of overlaid trajectories
- Keyboard navigation between flies

## Files

| File | Description |
|------|-------------|
| `index.html` | Self-contained dashboard UI (no build step required) |
| `extract_fullres.py` | Python script to extract trajectory data from raw `.mat` files and produce per-protocol JSON |
| `manifest.json` | Metadata index listing protocols, experiment counts, and fly counts |

## Generating Data

The `P*.json` data files are not included in this repository due to their size (30–170 MB each). Generate them from your local analysis data:

```bash
# Install dependencies
pip install numpy scipy h5py

# Generate data for specific protocols
python3 extract_fullres.py P008 P010 P013

# Or regenerate all protocols
python3 extract_fullres.py --all

# Point to a custom data directory
python3 extract_fullres.py P023 --analysis-dir /path/to/analysisdatalocal
```

The script reads `trx.mat`, `arena_calib_*.mat`, `LED_detector_*.mat`, and `original_metadata.txt` from each experiment folder and writes `P<NNN>.json` files alongside `index.html`.

## Running the Dashboard

Open `index.html` directly in a browser. Because it loads local JSON files, you may need to serve it over HTTP rather than `file://`:

```bash
python3 -m http.server 8000
# then open http://localhost:8000
```

## Data Source

Raw tracking data comes from [FlyDisco](https://github.com/kristinbranson/FlyDiscoAnalysis) output: `trx.mat` files containing per-fly x/y coordinates at 25 fps, paired with arena calibration and LED stimulus metadata.
