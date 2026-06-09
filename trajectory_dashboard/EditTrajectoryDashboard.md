# Editing the Trajectory Dashboard

## Adding a new protocol (e.g. P024)

### Step 1 — Generate the JSON data
Run this from the `trajectory_dashboard/` folder:
```bash
cd /Users/rathores/Documents/codes/freewalkinganalysislocal/trajectory_dashboard
python3 extract_fullres.py P024
```
This reads from `/Users/rathores/Documents/analysisdatalocal/P024/`, writes `P024.json`, updates `manifest.json`, and updates the protocol dropdown in `index.html` — all automatically.

To add multiple protocols at once, list them:
```bash
python3 extract_fullres.py P024 P025 P026
```

### Step 2 — Check the dashboard locally
```bash
python3 -m http.server 8000
# open http://localhost:8000 in your browser
```

### Step 3 — Commit and push the updated files
```bash
cd /Users/rathores/Documents/codes/freewalkinganalysislocal
git add trajectory_dashboard/manifest.json trajectory_dashboard/index.html
git commit -m "Add P024 to trajectory dashboard"
git push origin dev
```

> **Note:** `P*.json` data files are excluded by `.gitignore` and stay local only — they are too large for GitHub. Only `manifest.json` and `index.html` need to be committed after adding a new protocol.

---

## Repository structure

| File | Description |
|------|-------------|
| `index.html` | Self-contained dashboard UI |
| `extract_fullres.py` | Generates per-protocol JSON from raw `.mat` files |
| `manifest.json` | Index of all protocols with experiment and fly counts |
| `P*.json` | Per-protocol data files (local only, not tracked by git) |

---

## Data source

The script reads the following files from each experiment folder inside `/Users/rathores/Documents/analysisdatalocal/<PROTOCOL>/`:
- `trx.mat` — per-fly x/y coordinates
- `analysis/arena_calib_*.mat` — arena geometry
- `analysis/LED_detector_*.mat` — stimulus timing
- `original_metadata.txt` — cycle labels and LED patterns
