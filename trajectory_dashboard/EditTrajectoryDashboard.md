# Editing the Trajectory Dashboard

---

## Part 1 — Adding a new protocol

### Step 1 — Check that the data is ready

Before running the script, each experiment folder inside `/Users/rathores/Documents/analysisdatalocal/<PROTOCOL>/` must contain:

| File | Where |
|------|-------|
| `trx.mat` | experiment root |
| `arena_calib_*.mat` | `analysis/` subfolder |
| `LED_detector_*.mat` | `analysis/` subfolder |
| `original_metadata.txt` | experiment root |

If `arena_calib_*.mat` is missing the script will skip that experiment and print `SKIP <name>: no arena_calib`. Run the arena calibration step in the analysis pipeline first, then re-run the script.

### Step 2 — Run the extraction script

```bash
cd /Users/rathores/Documents/codes/freewalkinganalysislocal/trajectory_dashboard
python3 extract_fullres.py P033
```

For multiple protocols at once:
```bash
python3 extract_fullres.py P033 P034 P035
```

The script will:
- Read all experiment folders inside `analysisdatalocal/<PROTOCOL>/` that contain a `_Rig` suffix
- Write `P033.json` (or update it if it already exists)
- Update `manifest.json` with experiment and fly counts
- Update the protocol dropdown in `index.html`

The terminal output shows which experiments were found, how many flies and cycles each had, and the final file size. If an experiment is skipped it says why.

### Step 3 — Re-extract a protocol from scratch

If you added corrected files and want to overwrite existing data completely:

```bash
rm trajectory_dashboard/P033.json
python3 extract_fullres.py P033
```

Deleting the JSON first prevents the script from merging with old data.

### Step 4 — Check the dashboard locally

```bash
cd /Users/rathores/Documents/codes/freewalkinganalysislocal/trajectory_dashboard
python3 -m http.server 8000
# open http://localhost:8000 in your browser
```

Confirm the new protocol appears in the dropdown and trajectories look correct.

### Step 5 — Commit and push

```bash
cd /Users/rathores/Documents/codes/freewalkinganalysislocal
git add trajectory_dashboard/manifest.json trajectory_dashboard/index.html
git commit -m "Add P033 to trajectory dashboard"
git push origin dev
```

> **Note:** `P*.json` data files are excluded by `.gitignore` — they are too large for GitHub and stay local only. Only `manifest.json` and `index.html` need to be committed when adding or updating protocols.

---

## Part 2 — Updating existing protocols

When you add corrected experiment files to `analysisdatalocal`:

```bash
cd /Users/rathores/Documents/codes/freewalkinganalysislocal/trajectory_dashboard

# Option A: merge new experiments in (keeps existing ones)
python3 extract_fullres.py P025

# Option B: full clean re-extract (wipe and rebuild)
rm P025.json
python3 extract_fullres.py P025
```

Then commit:
```bash
cd /Users/rathores/Documents/codes/freewalkinganalysislocal
git add trajectory_dashboard/manifest.json trajectory_dashboard/index.html
git commit -m "Update P025 with corrected experiments"
git push origin dev
```

---

## Part 3 — Common errors and fixes

| Error message | Cause | Fix |
|---|---|---|
| `SKIP <exp>: no arena_calib` | `analysis/arena_calib_*.mat` missing | Run arena calibration in pipeline first |
| `SKIP <exp>: no LED_detector` | `analysis/LED_detector_*.mat` missing | Run LED detection step in pipeline |
| `SKIP <exp>: no trx.mat` | Tracking not done | Run FlyDisco tracking first |
| `SKIP <exp>: LED_detector has no cycles` | Empty LED timing data | Check LED detector output for that experiment |
| `P033: directory not found` | Wrong protocol name or folder missing | Check spelling and confirm folder exists in `analysisdatalocal/` |
| Preprobe/probe shows no safe zone (green arc missing) | `original_metadata.txt` missing or unparseable | Check that the metadata file exists and contains a `Randomized Orientation Log` section |
| New experiments not appearing in dropdown after re-extraction | Browser has cached the old `P*.json` | The dashboard appends `?v=timestamp` to every JSON fetch to bypass this automatically — just open a fresh tab at `http://localhost:8000` |

---

## Part 4 — Repository structure

| File | Description |
|------|-------------|
| `index.html` | Self-contained dashboard UI — open this in a browser |
| `extract_fullres.py` | Python script that generates per-protocol JSON from raw `.mat` files |
| `manifest.json` | Index of all protocols with experiment and fly counts — committed to git |
| `P*.json` | Per-protocol data files — local only, not tracked by git |
| `EditTrajectoryDashboard.md` | This file |

---

## Part 5 — Script options reference

```
python3 extract_fullres.py [protocols] [options]

Arguments:
  P024 P025 ...          One or more protocol names to extract
  --all                  Discover and extract all protocols in analysisdatalocal/
  --analysis-dir PATH    Override the default data directory
                         (default: /Users/rathores/Documents/analysisdatalocal)
  --output-dir PATH      Override where JSON files are written
                         (default: the trajectory_dashboard/ folder)

Examples:
  python3 extract_fullres.py P033
  python3 extract_fullres.py P033 P034 P035
  python3 extract_fullres.py --all
  python3 extract_fullres.py P033 --analysis-dir /Volumes/external/analysisdata
```
