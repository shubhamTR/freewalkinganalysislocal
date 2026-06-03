# Protocol Support Update — P001–P025

**Date:** 2026-04-13 (updated 2026-06-02)

## 2026-06-02 — Pipeline Robustness: TARGET_PROTOCOLS, QPI ylim Fix, Destination-Based Copy

### copy_and_organize_flydisco_local.m — Destination-Based Incremental Copy (REWRITE)

**File modified:** `copy_and_organize_flydisco_local.m`

**Problem:** The copy script used a `.copy_tracking.mat` file to remember which experiments had been copied. If a copy failed partway (folder created but files incomplete), the tracking database still marked it as copied — the experiment was permanently skipped on subsequent runs. The only fix was manually deleting `.copy_tracking.mat`, which also forced re-scanning every experiment.

**Fix:** Removed the tracking database entirely. The script now checks the destination directly for each source experiment: if the destination folder exists AND contains all required target files (trx.mat, movie-bg.mat, movie-calibration.mat, movie-params.mat), skip. If the folder exists but is incomplete, delete and re-copy. If the folder doesn't exist, copy.

This is fully idempotent — run it any number of times and it always does the right thing. No state file to corrupt, no stale entries to clean up. The `IncrementalMode` parameter has been removed.

**Usage:**
```matlab
copy_and_organize_flydisco_local( ...
    '/Volumes/ReiserLab/Shubham/Projects/Feature learning/2026/board4/videos', ...
    '/Users/rathores/Documents/analysisdatalocal')
```

### TARGET_PROTOCOLS Support Added to All Batch Scripts

**Problem:** Running any batch script processed ALL protocols (15+), taking ~20 minutes even when only one or two protocols needed updating. There was no way to limit processing to specific protocols without editing the script.

**Fix:** Added `TARGET_PROTOCOLS` support to every batch/runner script. Set `TARGET_PROTOCOLS = {'P023'}` (or any cell array) before running a script to limit processing. Empty or unset = process all (default behavior unchanged). All scripts use `clearvars -except TARGET_PROTOCOLS` instead of `clear` so the variable survives across sequential script calls.

**Files modified (11 scripts):**

| Script | How protocols were discovered | Filter method |
|--------|-------------------------------|---------------|
| `batch_QPI_summary.m` | Hardcoded cell array | `ismember` filter on cell array |
| `batch_plot_QPI.m` | Hardcoded cell array | `ismember` filter on cell array |
| `batch_distance_summary.m` | `dir('P*')` on analysis dir | `ismember` filter on `{protocol_dirs.name}` |
| `batch_latency_summary.m` | `dir('P*')` on analysis dir | `ismember` filter on `{protocol_dirs.name}` |
| `batch_distance_to_safe_summary.m` | `dir('P*')` on analysis dir | `ismember` filter on `{protocol_dirs.name}` |
| `batch_onset_velocity.m` | `dir('P*')` on analysis dir | `ismember` filter on `{protocol_dirs.name}` |
| `run_speed.m` | Hardcoded cell array | `ismember` filter on cell array |
| `run_transit_density.m` | Hardcoded cell array | `ismember` filter on cell array |
| `summary_speed.m` | Hardcoded cell array | `ismember` filter on cell array |
| `plot_optomotor_trajectories.m` | Hardcoded cell array | `ismember` filter on cell array |
| `analyze_probe_visits.m` | Hardcoded cell array | `ismember` filter on cell array |
| `cumulative_occupancy.m` | Hardcoded cell array | `ismember` filter on cell array |

**Note:** `analyze_optomotor.m` is a function (not a script) — pass protocols directly: `analyze_optomotor({'P017', 'P019', 'P023'})`. `plot_protocol_comparison.m` also takes protocols as a function argument: `plot_protocol_comparison({'P017', 'P019', 'P023'})`.

**Usage pattern for targeted runs:**
```matlab
TARGET_PROTOCOLS = {'P017', 'P019', 'P023'};

% Step 7: Per-genotype summaries
summary_speed
analyze_optomotor({'P017', 'P019', 'P023'})
plot_optomotor_trajectories
analyze_probe_visits
cumulative_occupancy

% Step 8-10: Transit density, onset velocity, cross-protocol comparison
run_transit_density
batch_onset_velocity
plot_protocol_comparison({'P017', 'P019', 'P023'})
```

### QPI Plot ylim Fix for Single-Quadrant Protocols (BUG FIX)

**Files modified:** `plot_QPI_allcycles_local.m`, `plot_QPI_blocks_local.m`, `plot_QPI_probes_local.m`

**Problem:** All three QPI plotters hardcoded `ylim([0 1])`. For single-quadrant protocols (P013, P017, P019, P023), QPI values are signed and range from −1 to +1 (chance level = −0.5). Probe QPI values of −0.4 to −0.5 were entirely below the visible range, producing empty-looking plots. Training data that dipped below 0 was clipped.

**Fix:** Added `is_single_quadrant` detection via `isfield(cfg, 'led_to_quad') && ~isempty(cfg.led_to_quad)`. When true, ylim uses `[min(yl(1), -0.6) 1]` to show negative values. When false (diagonal-pair protocols), keeps `ylim([0 1])`. Applied in 6 locations total (per-genotype + overlay figure in each of the 3 plotters).

### Experiment Exclusion Updates

**File modified:** `get_exclude_experiments.m`

Added `L2A_Rig1_20260527_153048` (P023 — 40 cycles detected instead of expected 37). This experiment caused dimension mismatch errors in downstream summary scripts.

**File modified:** `batch_analyze_experiments_with_qc_local.m`

Added `get_exclude_experiments()` call and exclusion filtering in `collect_protocol_genotype_experiments`. This script was the only batch script missing exclusion list support — excluded experiments were still being preprocessed.

### Protocol List Updates

**Files modified:** `run_speed.m`, `run_transit_density.m`

Added P023, P024, P025 to the hardcoded protocol lists in both scripts so they are processed when running without `TARGET_PROTOCOLS`.

---

## 2026-06-01 — extract_fullres.py HDF5 Fix, P023 Dashboard, Pipeline Improvements

### extract_fullres.py — HDF5 v7.3 trx.mat Support (BUG FIX)

**File modified:** `trajectory_dashboard/extract_fullres.py`

**Problem:** `extract_fullres.py` loaded trx.mat via `scipy.io.loadmat()`, which only supports MATLAB v5 format. All trx.mat files in the pipeline are saved as v7.3 (HDF5), causing `NotImplementedError` and a silent crash — the script produced no output and no error message.

**Fix:** New `load_trx()` function with dual-format support:
- Tries `scipy.io.loadmat()` first (v5 path — direct struct field access)
- On `NotImplementedError`, falls back to `h5py.File()` (v7.3 HDF5 path)
- HDF5 path dereferences object references: `f[trx['x'][i, 0]][()].flatten()` to extract per-fly coordinate arrays
- Returns `(fly_x_list, fly_y_list, first_frames_list)` — same interface for both paths

**Arena calibration and LED detector** remain v5 format and continue using `scipy.io.loadmat()` via a separate `load_mat_v5()` helper. Fields accessed as `calib["arena_calib"].xc`, `.yc`, `.radius` and `led_data["LED_detector"].on_times`, `.off_times`.

**Dependencies added:** `h5py` (new), `numpy`, `scipy` (existing)

### extract_fullres.py — Dropdown ID Fix (BUG FIX)

**File modified:** `trajectory_dashboard/extract_fullres.py`

**Problem:** The `update_html_dropdown()` function searched for `<select id="protSel">` in index.html, but the actual dashboard uses `<select id="sel-prot">`. The dropdown was never updated — new protocols extracted by the script didn't appear in the UI.

**Fix:** Changed regex pattern from `id="protSel"` to `id="sel-prot"`.

### P023 Added to Trajectory Dashboard

**New file:** `trajectory_dashboard/P023.json` (46.5 MB, 7 experiments, 82 flies)

Generated via `python3 extract_fullres.py P023` after the HDF5 fix. All 7 P023 experiments extracted successfully:
- L2A_Rig1_20260526_135735: 11 flies, 37 cycles
- L2A_Rig1_20260526_143231: 12 flies, 37 cycles
- L2A_Rig1_20260526_151320: 12 flies, 37 cycles
- L2A_Rig1_20260527_133815: 12 flies, 37 cycles
- L2A_Rig1_20260527_141419: 12 flies, 37 cycles
- L2A_Rig1_20260527_144633: 11 flies, 37 cycles
- L2A_Rig1_20260527_153048: 12 flies, 40 cycles

`manifest.json` updated with P023 entry. Dashboard dropdown updated to include P023.

**Protocols now in dashboard:** P008, P010, P011, P013, P014, P015, P016, P017, P019, P023

### copy_and_organize_flydisco_local.m — trx.mat Pre-Check (FIX)

**File modified:** `copy_and_organize_flydisco_local.m`

**Problem:** The copy step was importing experiments from the network that had not yet been tracked (no trx.mat). These experiments were then immediately flagged as incomplete and removed in the cleanup step, producing noisy log output ("Removed 14 incomplete experiments") and wasting time on unnecessary file copies.

**Fix:** Added a pre-check before copying each experiment:
```matlab
% Skip untracked experiments (no trx.mat anywhere in source)
if isempty(dir(fullfile(source_path, '**', 'trx.mat')))
    fprintf('  → Not yet tracked (no trx.mat), skipping\n');
    fprintf(log_fid, '  SKIPPED: No trx.mat\n');
    nSkipped = nSkipped + 1;
    continue;
end
```

Experiments without trx.mat are now skipped at the copy stage rather than being copied and then deleted.

---

## New Protocol Support: P023, P024, P025 (2026-05-29)

Added three new protocols to `get_protocol_config.m` and `get_display_names.m`.

| Protocol | Cycles | Blocks | Arena coupling | LED intensity | Display name |
|---|---|---|---|---|---|
| P023 | 37 | 3 | Uncoupled (arena shifts opposite) | training=8, probe=6 | Uncoupled |
| P024 | 37 | 3 | Randomly decoupled (arena_ori ≠ led_ori) | training=8, probe=6 | Random Decoupled |
| P025 | 26 | 2 | Coupled (same as P017) | training=3, probe=1 (V5 attenuator) | Coupled (Low Intensity) |

All three use single-quadrant SBD patterns (1101/1011/0111/1110), `led_to_quad = [2,3,4,1]`, SBD brightness=6. P023 and P024 share the P013/P017 case block (37-cycle, 3-block structure). P025 has a new dedicated case with 2 blocks (26 cycles total: OM1 + PP + Ag + 2×(10 training + 1 probe) + OM2).

No changes needed to compute functions or plotters — they are already config-driven.

## Pipeline Redundancy Cleanup (2026-05-26)

Full audit of 125 .m files identified 9 categories of redundancy. Deleted 18 files, created 5 shared helpers, updated 30+ files. Pipeline now has 112 .m files.

### Files Deleted — P008/P010/P011-Specific Copies (9 files)

Generic versions already handle all protocols via `get_protocol_config`. These copies were preserved after generalization but are now fully superseded.

| Deleted file | Replaced by |
|---|---|
| `analyze_optomotor_P008.m` | `analyze_optomotor.m` (config-driven function) |
| `analyze_probe_visits_P008.m` | `analyze_probe_visits.m` |
| `cumulative_occupancy_P008.m` | `cumulative_occupancy.m` |
| `plot_optomotor_trajectories_P008.m` | `plot_optomotor_trajectories.m` |
| `run_speed_P008.m` | `run_speed.m` |
| `summary_speed_P008.m` | `summary_speed.m` |
| `run_QPI_P010.m` | `batch_QPI_summary.m` (use `TARGET_PROTOCOLS = {'P010'}`) |
| `run_cumulative_occupancy_P010.m` | `cumulative_occupancy.m` |
| `run_P011.m` | `run_all_analysis.m` |

### Files Deleted — Deprecated / Obsolete / Test (8 files)

| Deleted file | Reason |
|---|---|
| `LED_detection_v5.m` | Original 3-LED interactive script, superseded by `detect_LED_from_video.m` |
| `Postracking_Reorg_001.m` | 9-line stub, superseded by `initialize_pipelinelocal.m` |
| `Postracking_Reorg_local_002.m` | Early pipeline version, superseded by `initialize_pipelinelocal.m` |
| `Postracking_Reorg_local_003.m` | Early pipeline version, superseded by `initialize_pipelinelocal.m` |
| `test_QPI_dead_fly_removal.m` | Development test script, single hardcoded experiment |
| `test_heading_vs_theta_L2A.m` | Development diagnostic, single L2A experiment |
| `test_pairwise_cycles_L2A.m` | Development test, logic now in batch scripts |
| `test_speed_per_fly.m` | Development test, single hardcoded experiment |

### File Deleted — Redundant Runner (1 file)

| Deleted file | Reason |
|---|---|
| `run_all_protocols.m` | Strict subset of `run_all_analysis.m` |

### Refactors — Centralized Helpers (5 new files, 30+ files updated)

| New file | Replaced duplication in | Description |
|---|---|---|
| `get_exclude_experiments.m` | 7 batch files | Single source of truth for experiment exclusion list. Updated: `batch_QPI_summary.m`, `batch_distance_summary.m`, `batch_distance_to_safe_summary.m`, `batch_latency_summary.m`, `batch_onset_velocity.m`, `batch_plot_speed.m`, `run_speed.m` |
| `compute_fly_quad.m` | 7 files (4 more deleted) | Extracts the 12-line fly-to-quadrant mapping loop. Updated: `compute_QPI_summary_local.m`, `compute_latency_per_cycle_local.m`, `compute_distance_to_safe_local.m`, `analyze_probe_visits.m`, `cumulative_occupancy.m`, `diagnose_cycle.m`, `plot_quadrant_preference_local.m` |
| `get_display_names.m` + `map_or_default.m` | 3 files | Centralizes `prot_display`, `geno_display` maps and the `map_or_default` helper. Updated: `analyze_optomotor.m`, `plot_delta_distance_bar.m`, `plot_protocol_comparison.m` (removed local `map_or_default` subfunctions) |
| `load_fly_alive.m` | 6 compute files | Extracts the dead-fly loading fallback chain (passed-in → `dead_fly_report.mat` → inline detection). Updated: `compute_QPI_summary_local.m`, `compute_distance_per_cycle_local.m`, `compute_latency_per_cycle_local.m`, `compute_distance_to_safe_local.m`, `compute_onset_velocity_trace_local.m`, `compute_speed_per_cycle_local.m` |
| *(inline fix)* | 2 batch files | `batch_distance_summary.m` and `batch_distance_to_safe_summary.m`: replaced ~35-line inline pxpermm scanning loops with `get_mean_pxpermm()` calls |

---

## QPI Computation Bugfixes (2026-05-22)

**Modified files:** `compute_quadrant_preference_local.m`, `compute_QPI_summary_local.m`, `batch_QPI_summary.m`

### Bug 1: Probe safe-quadrant fallback in `compute_quadrant_preference_local.m`

For single-quadrant protocols (P013, P017, P019), probe cycles have `LED='1111'` (all on). The code used `quad_patterns` (actual LED patterns) to find the dark position, which fails for probes since there is no dark LED. It then fell back to a hardcoded `cfg.probe_target_quad = Q2`, which is wrong when the probe's actual safe quadrant is Q1, Q3, or Q4 (randomized per trial orientation).

**Fix:** Capture both outputs of `parse_metadata_led_patterns()` — `[quad_patterns, training_patterns]` — and use `training_patterns` (the paired training LED pattern) to determine the safe quadrant. Probes now resolve to the correct orientation-matched safe quadrant.

### Bug 2: `abs()` applied to single-quadrant QPI in `compute_QPI_summary_local.m`

The per-cycle QPI averaging used `mean(abs(qpi_frames))` for all protocols. For diagonal-pair protocols (P001–P016 except P013), `abs()` is correct because the sign depends on which diagonal pair is safe and needs normalization. For single-quadrant protocols, the sign is meaningful (positive = preference for safe quad, negative = avoidance/no preference), so `abs()` was masking the true signal — probe QPI values of −0.5 appeared as +0.5.

**Fix:** Conditional `abs()` — applied only when `~is_single_quadrant`. Single-quadrant protocols now report signed QPI values.

### Bug 3: `FORCE_RECOMPUTE` not wired in `batch_QPI_summary.m`

The `FORCE_RECOMPUTE` variable was declared but never checked in the skip logic. Re-running the batch would always skip experiments with existing rows, preserving stale data.

**Fix:** Skip condition now checks `~FORCE_RECOMPUTE`, and old rows are removed before recomputation when `FORCE_RECOMPUTE = true`.

## QPI Plotter Signature Refactor (2026-05-22, updated 2026-05-26)

**Modified files:** `plot_QPI_allcycles_local.m`, `plot_QPI_blocks_local.m`, `plot_QPI_probes_local.m`, `plot_QPI_intensity_local.m`, `batch_QPI_summary.m`

Changed all four QPI summary plotters from two-argument `(QPI_summary_table, protocol, ...)` to single-argument `(protocol, ...)` signatures. Each plotter now self-loads `QPI_summary_<protocol>.mat` from `AnalysisDir`, matching the convention used by `plot_protocol_comparison.m`. Updated all call sites in `batch_QPI_summary.m`. Removed the now-unused `loaded = load(...)` line from the plotting loop.

`plot_QPI_intensity_local.m` additionally updated: font sizes (tick 16, axis 18, title 20, legend 14), `ylim_auto` for negative QPI support, SVG+FIG export alongside PNG via `exportgraphics`.

## Protocol Comparison ylim Fix (2026-05-22)

**Modified file:** `plot_protocol_comparison.m`

`ylim_auto` helper previously hardcoded lower bound to 0, clipping negative QPI values for single-quadrant protocols. Now auto-scales to include negative data when present.

## Batch Script Improvements (2026-05-22)

**Modified files:** `batch_plot_QPI.m`, `batch_QPI_summary.m`

- Removed `clear` from `batch_plot_QPI.m` so `FORCE_REPLOT` and `TARGET_PROTOCOLS` can be set from the command line before running.
- Added `TARGET_PROTOCOLS` filter to both batch scripts to restrict processing to specified protocols (empty = all).
- `FORCE_REPLOT` in `batch_plot_QPI.m` now defaults via `if ~exist(...)` pattern.

## Trajectory Dashboard Overlay Mode (2026-05-22)

**Modified file:** `trajectory_dashboard/index.html`

Added "Overlay" display mode: select any number of flies and any cycles, preview the overlay live on canvas, and export as SVG. Fly colors use a 15-color muted palette (non-fluorescent). Each cycle gets a distinct line dash pattern (solid, dashed, dotted). SVG includes arena, safe-zone shading, trajectory paths, start/end markers, and a legend.

## Font Size Updates (2026-05-22)

**Modified files:** `plot_protocol_comparison.m`, `plot_delta_distance_bar.m`, `plot_optomotor_trajectories.m`, `plot_optomotor_trajectories_P008.m`

Increased font sizes to presentation-ready conventions (tick labels 16, axis labels 18, titles 20, legends 14) and added SVG export to optomotor trajectory scripts.

## Optomotor Analysis Refactor (2026-05-21)

**Modified file:** `analyze_optomotor.m`

Converted from a hardcoded script to a config-driven function. Key changes:

- **Signature:** `analyze_optomotor(protocols, varargin)` — required `protocols` cell array as first arg (e.g. `{'P008','P017','P019'}`). No hardcoded protocol list.
- **Config-driven:** Uses `get_protocol_config` to check `cfg.has_optomotor` and reads `cfg.om_cycles` for OM1/OM2 cycle indices. Protocols without optomotor are auto-skipped.
- **Dual trace output:** Produces both raw and smoothed (default 0.5 s movmean) angular velocity traces per experiment and per genotype. Controlled by `'SmoothWinSec'` parameter.
- **Per-experiment outputs** (in `<exp>/analysis/optomotor/`): `optomotor_<exp>.mat`, `_traces_raw.png/.svg/.fig`, `_traces_smooth.png/.svg/.fig`, `_summary.png/.svg/.fig`
- **Genotype summary outputs** (in `<protocol>/summary/optomotor/`): `summary_optomotor_<geno>.mat/.png/.svg/.fig`, `summary_optomotor_comparison_<geno>_raw.png/.svg/.fig`, `summary_optomotor_comparison_<geno>_smooth_*.png/.svg/.fig`
- **Plot formatting:** Square figures, font size 22 (axis labels/titles), 18 (xline labels), no grid on trace plots, box off, solid lines only, CW end (magenta) and CCW start (dark green) labels separated vertically to avoid overlap.
- **New parameters:** `'ForceRerun'` (logical), `'SmoothWinSec'` (default 0.5), `'ShowPlots'` (logical).
- **Saved .mat data** includes both `angvel_raw` and `angvel_smooth` per phase.

## Display Name Map Updates (2026-05-21)

**Modified files:** `plot_protocol_comparison.m`, `plot_delta_distance_bar.m`, `analyze_optomotor.m`

Updated `prot_display` maps across all scripts for consistent legend labels:

- P008 → Coupled
- P010 → Dark
- P011 → Uncoupled
- P017 → Coupled (unchanged)
- P019 → Dark (unchanged)

## Condition Comparison Merge (2026-05-21)

**Deleted file:** `plot_condition_comparison.m`

**Modified file:** `plot_protocol_comparison.m`

Merged the redundant `plot_condition_comparison.m` into `plot_protocol_comparison.m`. The merged script handles both per-protocol overlays and statistical comparisons (ANOVA, Tukey-Kramer, Bartlett/Levene/Brown-Forsythe, paired t-tests with Bonferroni). Statistics controlled by `'RunStats'` parameter (default true).

## Delta Distance Bar Refactor (2026-05-21)

**Modified file:** `plot_delta_distance_bar.m`

- Changed signature to `plot_delta_distance_bar(protocols, varargin)` — required `protocols` first arg, no defaults.
- Uses `get_protocol_config` for block layout (supports any protocol, not hardcoded to 4-block P008/P010/P011).
- Colors use `get_condition_shade` palette (matches `plot_protocol_comparison`).

## Speed Computation Bug Fix (2026-05-21)

**Modified file:** `compute_speed_per_cycle_local.m`

Fixed `pixels_per_mm` undefined error: moved the fprintf statement that referenced `pixels_per_mm` to after the trx loading and assignment block.

## Transit Density in Trajectory Dashboard (2026-05-21)

**Modified file:** `trajectory_dashboard/index.html`

Added transit density heatmap as a display option alongside existing trajectory plots. Client-side computation bins fly x/y positions into a grid and renders a blue-to-mustard-yellow heatmap. 20x20 bins for grid tiles, 40x40 for detail panel. No new MATLAB pipeline needed.

## Font Size & Export Updates for Protocol Comparison Scripts (2026-05-21)

**Modified files:** `plot_protocol_comparison.m`, `plot_delta_distance_bar.m`

Increased font sizes to match the QPI plotter conventions for presentation-ready figures:

- Tick labels: 16 pt (via `set(ax, 'FontSize', 16)`)
- Axis labels (xlabel/ylabel): 18 pt
- Titles: 20 pt
- Legends: 14 pt
- Annotation text (block labels, probe labels, agitation marker, preprobe marker): scaled proportionally (10→14, 8→12, 9→14)
- p-value text in delta distance bar: 9→14 pt

Both scripts already exported PNG + SVG + FIG; no changes needed for file formats.

---

## Distance-to-Safe Quadrant Analysis (NEW)

**New files:**
- `compute_distance_to_safe_local.m` — per-experiment compute function
- `batch_distance_to_safe_summary.m` — batch orchestrator with per-protocol pxpermm
- `plot_dist_to_safe_allcycles_local.m` — training all-cycles plotter
- `plot_dist_to_safe_blocks_local.m` — block-mean plotter
- `plot_dist_to_safe_probes_local.m` — probe plotter

New metric: cumulative frame-to-frame displacement (mm) from LED onset until a fly reaches a dark (safe) quadrant. Distinct from total distance travelled (`compute_distance_per_cycle_local.m`), which sums displacement over the entire LED-on period.

**Two variants:**
- **First entry** (`dist_to_safe_per_fly`): Accumulates displacement until the fly first enters a dark quadrant it wasn't already in. Uses per-quadrant logic from `compute_latency_to_dark.m` — for each dark quad, skip if fly is already there at onset, find first frame of entry, take the earliest across quads.
- **Last entry** (`dist_to_safe_last_per_fly`): Accumulates displacement until the last transition from a non-dark to a dark quadrant before stimulus turns off. Captures the full back-and-forth path if the fly leaves and re-enters safe zones.

**Safe zone occupancy** (`safe_zone_occupancy`): Fraction of stim frames each fly spends in any dark (correct) quadrant per cycle. Same logic as `plot_quadrant_occupancy_all.m`.

**Output .mat files:** `dist_to_safe_summary_<protocol>.mat` per protocol, containing:
- `dist_to_safe_summary` — table with columns: experiment, genotype, cycle, label, n_flies_alive, n_responded, n_already_correct, mean/sem/median_dist_to_safe_mm (first entry), n_responded_last, mean/sem/median_dist_to_safe_last_mm (last entry), mean/sem_safe_occupancy
- `dist_to_safe_per_fly_all` — struct array with raw per-fly matrices (dist_to_safe_per_fly, dist_to_safe_last_per_fly, safe_zone_occupancy, already_in_correct)
- `pixels_per_mm_used` — per-protocol calibration value

**Plots saved to** `<protocol>/dist_to_safe_summary/`: 12 variants total — mean and median × allcycles, blocks, probes × first entry and last entry. Same formatting conventions as distance/latency plotters (one figure per genotype, errorbar style, Wong 2011 palette, alternating block shading, Ag marker).

---

## All-Genotype Overlay Plots (NEW)

**Files modified (12 plotters):**
- `plot_QPI_allcycles_local.m`, `plot_QPI_blocks_local.m`, `plot_QPI_probes_local.m`
- `plot_distance_allcycles_local.m`, `plot_distance_blocks_local.m`, `plot_distance_probes_local.m`
- `plot_latency_allcycles_local.m`, `plot_latency_blocks_local.m`, `plot_latency_probes_local.m`
- `plot_dist_to_safe_allcycles_local.m`, `plot_dist_to_safe_blocks_local.m`, `plot_dist_to_safe_probes_local.m`

Each plotter now generates an additional overlay figure after the per-genotype loop. The overlay plots all genotypes on a single axes, each in its own Wong 2011 color, with a legend showing `genotype (n=X)`. SEM is displayed as a semi-transparent ribbon (`fill` with `FaceAlpha=0.2`) instead of error bars to reduce visual clutter when multiple traces overlap.

**Output:** `<plot_suffix>_<protocol>_overlay.png` (or `_<half_suffix>_overlay.png` for QPI) saved alongside the per-genotype PNGs. No batch script changes required — the overlay is generated automatically whenever the plotter is called.

---

## Per-Cycle Diagnostic Tool (NEW)

**New file:** `diagnose_cycle.m`

General-purpose diagnostic script for deep-diving into any single cycle across all experiments of a given genotype. Prints per-fly and aggregate stats for QPI, distance travelled, latency, quadrant occupancy, and quadrant path transitions.

**Usage:**
```matlab
diagnose_cycle('P008', 'L2A', 20, 'PixelsPerMM', 8.21)
```

**Per-fly output:**
- Alive/dead status at the target cycle
- Quadrant at LED onset and whether already in a correct (dark) quadrant
- Total distance travelled during stim (mm) — same logic as `compute_distance_per_cycle_local.m`
- Latency to first entry into a new dark quadrant (s) — same per-quadrant logic as `compute_latency_per_cycle_local.m`
- Compressed quadrant path showing transitions with frame counts (e.g. `Q2(45)>Q1(120)>Q4(30)`)
- Dark quadrant occupancy fraction — same logic as `plot_quadrant_occupancy_all.m`

**Aggregate output per experiment:**
- Mean/SEM/median distance and latency across alive flies
- Number of flies already in correct quadrant at onset vs. those that responded
- |QPI| for first half and second half of the cycle — same logic as `compute_QPI_summary_local.m`

All computation reuses existing pipeline logic (no new methods). Includes local copies of `parse_qpi_log`, `detect_dead_flies`, and `get_protocol_labels_lat` helpers. Supports all protocols P001–P009.

### Per-Fly Tracker: `diagnose_fly` (added to same file)

Second function in `diagnose_cycle.m` for tracking a single fly across ALL cycles in one experiment. Shows the full history of one fly from cycle 1 through the last cycle.

**Usage:**
```matlab
diagnose_fly('P008', 'L2A_Rig1_20260409_122638', 7, 'PixelsPerMM', 8.21)
```

**Per-cycle output for the target fly:**
- Cycle number and label (e.g. B2.6)
- Alive/dead status
- Quadrant at LED onset and whether already in a correct quadrant
- Total distance travelled (mm)
- Latency to dark quadrant (s)
- Dark quadrant occupancy fraction
- Full quadrant path with absolute frame numbers at each transition (e.g. `Q2(fr29372-29722, 351fr) > Q3(fr29723-30571, 849fr)`)

Also reports when/if the fly dies (first cycle flagged dead). Uses the original trx index as `fly_id` (matches the "Fly" column in `diagnose_cycle` output). Same pipeline logic as all other compute functions.

---

## Per-Experiment Latency & Distance Plots (NEW)

**New plotter files:**
- `plot_latency_per_experiment_local.m` — per-experiment latency plot (bar chart + per-fly heatmap)
- `plot_distance_per_experiment_local.m` — per-experiment distance plot (bar chart + per-fly heatmap)

**New batch scripts:**
- `batch_plot_latency.m` — iterates over all experiments, calls `plot_latency_per_experiment_local`
- `batch_plot_distance.m` — iterates over all experiments, calls `plot_distance_per_experiment_local`

Same pattern as the existing QPI pipeline (`plot_quadrant_preference_local.m` + `batch_plot_QPI.m`): each plotter takes a single experiment path, calls the corresponding compute function internally (`compute_latency_per_cycle_local` or `compute_distance_per_cycle_local`), generates a two-panel figure, and saves a PNG into the experiment's `analysis/` folder.

**Figure layout (per experiment):**
- **Top panel:** Per-cycle mean ± SEM as a color-coded bar chart (training=red, probe=grey, opto=grey, Ag=orange)
- **Bottom panel:** Per-fly heatmap (`imagesc`, `parula` colormap, NaN/dead=white) showing individual fly values across all cycles

**Output:**
- `latency_<exp_name>.png` saved in `<experiment>/analysis/`
- `distance_<exp_name>.png` saved in `<experiment>/analysis/`

Batch scripts use `FORCE_REPLOT` flag (same as `batch_plot_QPI.m`), per-protocol px/mm calibration, skip P004 (optomotor only), and filter out summary directories.

---

## Place Learning Block Plot — plot_QPI_blocks_local.m (NEW)

**New file:** `plot_QPI_blocks_local.m`
**Modified:** `batch_QPI_summary.m`

New cross-experiment plotter for place learning protocols (P003, P005–P009). Shows mean |QPI| per training block (averaged across 10 training flips) with preprobe at x=0 and blocks 1–4. Probe trials shown as open triangles offset to the right of each block.

Two subplots per figure: first half and second half of each trial.

Output: `QPI_blocks_<protocol>.png` saved in each protocol's data folder.

Called automatically by `batch_QPI_summary.m` for all protocols (non-PL protocols are skipped internally).

---

## QPI Summary: First-Half / Second-Half (replaces fixed 15s windows)

**Files changed:** `compute_QPI_summary_local.m`, `batch_QPI_summary.m`, `plot_QPI_intensity_local.m`

Previously, QPI summary computed the mean of the first 15s and last 15s of each cycle (hardcoded `WindowSec = 15`). This only worked well for 30s trials (P001/P002) and was wrong for 2s trials (P003) or 40s trials (P005–P009).

Now, each cycle is split at its midpoint using the actual LED on/off times:
- `mean_QPI_firsthalf` — mean |QPI| over the first half of the cycle
- `mean_QPI_secondhalf` — mean |QPI| over the second half of the cycle

This is protocol-agnostic — any trial duration works without script changes.

**Column renames:**
- `mean_QPI_first15` → `mean_QPI_firsthalf`
- `mean_QPI_last15` → `mean_QPI_secondhalf`

**Note:** Existing `.mat` summary files will have the old column names. Re-run `batch_QPI_summary.m` to regenerate them.

---

## Summary

Extended all analysis scripts to recognize protocols P001 through P009. Previously, most scripts only handled P001 and P002 (intensity-ramp protocols). P003–P009 (place learning and combined opto+place learning) were missing from most `get_protocol_labels` functions.

## Protocol Reference

| Protocol | Type | Cycles | Notes |
|----------|------|--------|-------|
| P001 | RGB intensity ramp | 42 | 3 colors × 14 intensity steps |
| P002 | Red-only 3-chunk ramp | 42 | 1 color × 14 steps × 3 reps |
| P003 | Place learning (slantslash) | 46 | Intensity=5, trial=2s |
| P004 | Optomotor only | — | No LED quadrants; skipped by all LED-based analyses |
| P005 | Place learning (slashcirc) | 46 | Intensity=12, trial=40s |
| P006 | Streaming opto + PL (slashcirc) | 48 | Opto1 + 46 PL + Opto2 |
| P007 | Mode 2 SD opto + PL (slashcirc) | 48 | Same structure as P006 |
| P008 | Mode 2 SD opto + inverted PL | 48 | Inverted bar pattern, paired |
| P009 | Mode 2 SD opto + inverted PL | 48 | Same as P008 but unpaired control |

## Changes by File

### Compute scripts (get_protocol_labels functions)

**compute_QPI_summary_local.m** — `get_protocol_labels_summary()`
- `case 'P005'` → `case {'P003', 'P005'}` (P003 shares 46-cycle PL structure)
- `case 'P006'` → `case {'P006', 'P007', 'P008', 'P009'}` (all share 48-cycle opto+PL structure)

**compute_distance_per_cycle_local.m** — `get_protocol_labels_dist()`
- Added `case {'P003', 'P005'}` with 46-cycle place learning labels/sections
- Added `case {'P006', 'P007', 'P008', 'P009'}` with 48-cycle opto+PL labels/sections

**compute_latency_per_cycle_local.m** — `get_protocol_labels_lat()`
- `case 'P005'` → `case {'P003', 'P005'}`
- `case 'P006'` → `case {'P006', 'P007', 'P008', 'P009'}`

**compute_onset_velocity_trace_local.m** — `get_protocol_labels_ovt()`
- Added `case {'P003', 'P005'}` with 46-cycle place learning labels/sections
- Added `case {'P006', 'P007', 'P008', 'P009'}` with 48-cycle opto+PL labels/sections

### Intensity-response plotters (switch on protocol)

These scripts plot QPI/distance/latency/velocity vs. intensity and only apply to variable-intensity ramp protocols (P001, P002). All other protocols now gracefully skip with a console message.

**plot_QPI_intensity_local.m**
- `case {'P005', 'P006'}` → `case {'P003', 'P004', 'P005', 'P006', 'P007', 'P008', 'P009'}`

**plot_distance_intensity_local.m**
- Added `case {'P003', 'P004', 'P005', 'P006', 'P007', 'P008', 'P009'}` — skip with message

**plot_latency_intensity_local.m**
- Added `case {'P003', 'P004', 'P005', 'P006', 'P007', 'P008', 'P009'}` — skip with message

**plot_onset_velocity_trace_local.m**
- Added `case {'P003', 'P004', 'P005', 'P006', 'P007', 'P008', 'P009'}` — skip with message

### Previously updated (no changes needed today)

**plot_quadrant_preference_local.m** — `get_protocol_labels()`
- Already had `case {'P003', 'P005'}` and `case {'P006', 'P007', 'P008', 'P009'}`

### Distance-to-safe scripts (new)

**compute_distance_to_safe_local.m**
- Combines quadrant-aware logic from `compute_latency_per_cycle_local.m` with frame-to-frame distance from `compute_distance_per_cycle_local.m`
- Computes first-entry distance, last-entry distance, and safe zone occupancy per fly per cycle
- Includes `get_protocol_labels_lat()` for quad patterns, `parse_qpi_log()` for dead fly status, `detect_dead_flies()` fallback
- Accepts `PixelsPerMM` parameter for per-protocol calibration

**batch_distance_to_safe_summary.m**
- Batch orchestrator with per-protocol pxpermm calibration (same `containers.Map` pattern as `batch_distance_summary.m`)
- Saves `dist_to_safe_summary_<protocol>.mat` per protocol
- Generates 12 plot variants (first/last entry × mean/median × allcycles/blocks/probes)

**plot_dist_to_safe_allcycles_local.m**, **plot_dist_to_safe_blocks_local.m**, **plot_dist_to_safe_probes_local.m**
- All accept `'Metric'` parameter — support first-entry (`mean_dist_to_safe_mm`) and last-entry (`mean_dist_to_safe_last_mm`) variants plus median versions
- Same formatting as distance/latency plotters (one figure per genotype, Wong 2011 palette, block shading, Ag marker)

### Batch scripts (no changes needed)

`batch_QPI_summary.m`, `batch_distance_summary.m`, `batch_latency_summary.m`, `batch_onset_velocity.m`
- All auto-discover protocols via `dir('P*')` — no hardcoded protocol lists

## Notes

- **P004** (optomotor only) has no LED quadrant patterns. It falls into the `otherwise` branch in compute scripts (returns empty labels) and is explicitly skipped in intensity plotters. This is correct behavior — QPI/latency/distance analysis is not applicable to optomotor-only experiments.
- **P009** (unpaired control) uses randomized LED assignment. The labels use the same cycle structure as P006–P008 but the quad_patterns may not reflect actual per-trial assignments (which are randomized at runtime).

---

## 2026-04-14 Updates

### CRITICAL FIX: LED Pattern-to-Quadrant Mapping Inversion

**Files changed:** `compute_latency_per_cycle_local.m`, `compute_distance_to_safe_local.m`, `diagnose_cycle.m`, `plot_quadrant_preference_local.m` (comments only)

The LED pattern-to-quadrant mapping was **inverted** in all compute functions. The code previously mapped:
- `'1010'` → lit=[1,3], correct=[2,4] **WRONG**
- `'0101'` → lit=[2,4], correct=[1,3] **WRONG**

The correct mapping (verified from `original_metadata.txt` files per experiment):
- `'1010'` → Q2,Q4 lit, Q1,Q3 dark/safe
- `'0101'` → Q1,Q3 lit, Q2,Q4 dark/safe

This universal mapping applies to all protocols. The inversion caused: (a) `already_in_correct` flagging flies in LIT quadrants as correct, (b) latency measuring time to enter LIT quadrants (which flies actively avoid), (c) massive NaN rates because flies escaping to real safe zones never entered the wrongly-assigned "correct" quadrants.

**Fix applied in 4 files:**
- `compute_latency_per_cycle_local.m` — swapped lit/correct for both protocol-defined path and fallback path
- `compute_distance_to_safe_local.m` — same swap in both paths
- `diagnose_cycle.m` — fixed in 3 locations (display text, diagnose_cycle logic, diagnose_fly logic)
- `plot_quadrant_preference_local.m` — comments only (the actual shading code was already correct)

**QPI is unaffected** — it measures (Q1+Q3 − Q2−Q4) raw preference without using correct_quads.

**Probe quadrant assignment:** PP and B1.P–B4.P use `'1111'` (all lit) with `correct_quads = [2,4]` hardcoded. This is correct — the assay is symmetric and Q2,Q4 is always the trained safe zone (same as trial 1, which uses `'0101'` → Q1,Q3 lit, Q2,Q4 safe).

---

### Per-Experiment Plotter Redesign (Latency & Distance)

**Files rewritten:** `plot_latency_per_experiment_local.m`, `plot_distance_per_experiment_local.m`

Replaced the old 2-panel layout (bar chart + heatmap) with a new 3-subplot layout:
- **Top:** Mean +/- SE (black errorbar markers) with individual fly scatter (jittered, colored by cycle type, alpha=0.4)
- **Middle:** Per-fly heatmap (imagesc, parula colormap, NaN = white patches)
- **Bottom:** Contributing flies stacked bar per cycle

For latency, the bottom panel shows: responded (blue), already correct (green), no entry (orange), dead (grey). For distance: measured (blue), alive but no data (orange), dead (grey).

Both plotters now also save **individual standalone plots** for each panel:
- `latency_scatter_<exp>.png/.fig` — mean +/- SE with scatter
- `latency_heatmap_<exp>.png/.fig` — per-fly heatmap
- `latency_contributing_<exp>.png/.fig` — contributing flies bar
- `distance_scatter_<exp>.png/.fig`, `distance_heatmap_<exp>.png/.fig`, `distance_contributing_<exp>.png/.fig`

Plus the combined 3-panel figure: `latency_<exp>.png/.fig`, `distance_<exp>.png/.fig`.

Function signatures changed to `function varargout = ...` to optionally return the summary struct for use by batch scripts.

---

### Optomotor Cycle Removal (OM1, OM2)

**Files changed:** `plot_latency_per_experiment_local.m`, `plot_distance_per_experiment_local.m`

Both per-experiment plotters now filter out OM1 and OM2 cycles before plotting. All three subplots (scatter+errorbar, heatmap, contributing flies) and all standalone individual plots exclude optomotor cycles. Cycles are re-indexed after filtering.

---

### Per-Protocol Summary Plots (NEW)

**Files changed:** `batch_plot_latency.m`, `batch_plot_distance.m`

Both batch scripts now generate one summary plot per protocol after processing all experiments. The summary plot shows:
- Individual fly scatter (small filled dots, alpha=0.25) pooled across all experiments
- Individual experiment means (larger open circles)
- Grand mean +/- SE across experiments (black errorbar)

OM1/OM2 are excluded. Saved to `<protocol>/summary/summary_latency_<prot>.png/.fig` and `summary_distance_<prot>.png/.fig`.

The batch scripts collect returned summaries from each per-experiment plotter call and pass them to local `plot_latency_summary` / `plot_distance_summary` functions.

---

### .mat Data Saving (NEW)

**Files changed:** `compute_latency_per_cycle_local.m`, `compute_distance_per_cycle_local.m`, `compute_distance_to_safe_local.m`

All three compute functions now save their output summary struct as a `.mat` file in the experiment's `analysis/` folder:
- `latency_<exp>.mat` — saved via `-struct` format (fields: experiment, genotype, protocol, num_flies_total, num_dead, fly_ids_original, latency_per_fly, already_in_correct, lit_quads, correct_quads, cycle_table)
- `distance_<exp>.mat` — saved via `-struct` format (fields: experiment, genotype, protocol, num_flies_total, num_dead, fly_ids_original, pixels_per_mm, distance_per_fly, cycle_table)
- `distance_to_safe_<exp>.mat` — saved via `-struct` format (fields: experiment, genotype, protocol, num_flies_total, num_dead, fly_ids_original, pixels_per_mm, dist_to_safe_per_fly, dist_to_safe_last_per_fly, safe_zone_occupancy, already_in_correct, lit_quads, correct_quads, cycle_table)

---

### .fig File Saving (NEW)

**Files changed:** All 20 plotter scripts and batch scripts that generate figures.

Every `exportgraphics` or `saveas` call in the codebase now has a corresponding `savefig(fig, <path>.fig)` call, saving MATLAB `.fig` files alongside the `.png` outputs for future interactive use.

**Per-experiment plotters:** 4 `.fig` files each (combined + scatter + heatmap + contributing)

**Batch summary plots:** 1 `.fig` file each (summary_latency, summary_distance)

**All other plotters (16 files):** `.fig` saved alongside `.png` for every figure generated — QPI plotters, distance block/allcycle/probe plotters, latency block/allcycle/probe plotters, dist-to-safe plotters, speed training, quadrant preference, arena calibration, tracking error reports, LED detection.

**Note:** MATLAB's built-in `savefig` may be shadowed by JAABA's `savefig.m` at `/Users/rathores/Documents/MATLAB/JAABA/spaceTime/toolbox/external/other/savefig.m`. Run `rmpath('/Users/rathores/Documents/MATLAB/JAABA/spaceTime/toolbox/external/other')` before batch scripts to use the correct MATLAB built-in.

---

### Speed Analysis Pipeline (NEW)

**New files:**
- `compute_speed_per_cycle_local.m` — per-experiment compute function
- `plot_speed_per_experiment_local.m` — per-experiment plotter
- `plot_speed_block_overlay.m` — block-averaged training + probe overlay plotter
- `batch_plot_speed.m` — batch script for all protocols
- `run_speed_P008.m` — P008-only runner script
- `summary_speed_P008.m` — per-genotype summary across P008 experiments
- `test_speed_per_fly.m` — original tester script (single experiment)

New metric: instantaneous locomotor speed (mm/s) per fly per LED cycle.

**Speed computation (`compute_speed_per_cycle_local.m`):**
- Euclidean frame-to-frame displacement: `dist = sqrt(dx² + dy²)` in mm (using per-protocol `PixelsPerMM`)
- Speed = `dist_per_frame × FPS` (default FPS = 30.1)
- 0.5s moving average smoothing (configurable via `SmoothWinSec`)
- Measurement window: 10s before LED onset through LED offset (configurable via `PreOnsetSec`)
- Dead fly detection via QPI log with internal fallback (same logic as latency/distance compute functions)
- OM1/OM2 cycles filtered out
- Saves `speed_<exp>.mat` in experiment's `analysis/` folder — contains per-cycle speed matrices (rows=alive flies, cols=time points), mean/SEM traces, time axis, fly IDs, metadata
- Supports all protocols P001–P009 via local `get_protocol_labels_speed()` helper

**Per-experiment plotter (`plot_speed_per_experiment_local.m`):**
- Calls `compute_speed_per_cycle_local` internally
- Per-cycle plots: grey individual fly traces (alpha=0.4) in background + blue mean ± SEM ribbon overlay + red/blue dashed lines for LED onset/offset
- Combined all-cycles subplot grid (8 columns × N rows): same style, saved as single `.fig` + `.png` for MATLAB interactive viewing
- Output per experiment: `speed_plots/speed_<exp>_cycle<NN>_<lbl>.png/.fig` (per cycle), `speed_plots/speed_<exp>_allcycles.fig/.png` (combined)
- Returns summary struct via `varargout` for use by batch scripts

**Block overlay plotter (`plot_speed_block_overlay.m`):**
- Takes summary struct, generates two figures per experiment:
  - **Training block overlay** (`speed_blocks_<exp>.png/.fig`): Blocks 1–4 overlaid on same axes. Each block = mean of 10 training trial traces, with SEM ribbon. Light-to-dark color gradient shows training progression.
  - **Probe overlay** (`speed_probes_<exp>.png/.fig`): PP and B1.P–B4.P overlaid with grey-to-dark gradient. Shows whether speed changes persist during probe trials (all quadrants lit).
- Only runs for place-learning protocols (P003, P005–P009); gracefully skips P001/P002

**Batch script (`batch_plot_speed.m`):**
- Same structure as `batch_plot_latency.m` / `batch_plot_distance.m`
- Iterates all protocols (skips P004), all experiments
- Per-protocol pxpermm calibration (P001–P005=9.20, P006–P009=8.21)
- Calls `plot_speed_per_experiment_local` then `plot_speed_block_overlay` for each experiment
- `FORCE_REPLOT` flag, required-file checks (trx.mat + LED_detector), try/catch with error logging, summary report

**P008-only runner (`run_speed_P008.m`):**
- Same as batch script but hardcoded to P008 only
- Includes `rmpath` for JAABA savefig shadow at the top

**Per-genotype summary (`summary_speed_P008.m`):**
- Loads pre-computed `speed_<exp>.mat` files from all P008 experiments
- Groups experiments by genotype (L0, L1, L2A, L3A, L3C)
- Averaging hierarchy: fly → experiment mean trace → genotype mean ± SEM (experiment = unit of replication)
- Three figures per genotype, saved to `P008/summary/speed/`:
  - `summary_speed_cycles_<geno>.png/.fig` — all 46 cycles as subplots, genotype mean ± SEM ribbon per cycle
  - `summary_speed_blocks_<geno>.png/.fig` — Blocks 1–4 overlaid. Per block: average 10 trial means within each experiment, then average across experiments.
  - `summary_speed_probes_<geno>.png/.fig` — PP and B1.P–B4.P overlaid across experiments
- Saves `summary_speed_<geno>.mat` per genotype with all computed data (means, SEMs, time axis, labels)
- Genotype-specific color ramps for blocks (blue/green/red/grey/orange) and probes

---

### Per-Protocol Summary Plots — Per-Genotype Fix

**Files changed:** `batch_plot_latency.m` (local function `plot_latency_summary`), `batch_plot_distance.m` (local function `plot_distance_summary`)

Summary plots were previously pooling all experiments regardless of genotype into a single scatter plot. For P008 this meant 17 experiments across 5 genotypes (L0, L1, L2A, L3A, L3C) were merged — completely incorrect.

**Fix:** Rewrote both summary functions to:
- Extract genotype from each experiment's summary struct
- Group experiments by genotype
- Generate one figure per genotype: `summary_latency_<prot>_<geno>.png/.fig`, `summary_distance_<prot>_<geno>.png/.fig`
- Each figure shows: individual fly scatter (small, alpha=0.25), experiment means (open circles), grand mean ± SE (black errorbar)

---

### Optomotor Response Analysis (NEW)

**New file:** `analyze_optomotor_P008.m`

Measures angular velocity (deg/s) from `theta` in `trx.mat` during OM1 (pre-learning) and OM2 (post-learning) phases. Uses `diff(unwrap(theta)) * FPS` to compute signed angular velocity, with 1.0s moving average smoothing.

**Timing sources:**
- **LED detector:** OM1/OM2 start (`on_times(1)`/`on_times(end)`) and end (`off_times(1)`/`off_times(end)`)
- **Metadata log (`original_metadata.txt`):** CW end and CCW start frame numbers parsed via regex on `"Phase1 CW end ... camera frame NNNN"` etc.

**Measurement windows:**
- OM1: from frame 1 (experiment start, ~13s pre-LED baseline) through 10s after CCW end/LED off
- OM2: from 10s before LED on (post-place-learning baseline) through 10s after CCW end (or end of recording)
- Time axis is relative to LED onset (t=0), so pre-LED baseline appears as negative time

**Optomotor stimulus structure (per phase):**
- CW rotation at +300 fps for ~100s
- 5s inter-direction pause
- CCW rotation at -300 fps for ~100s
- Pattern: SD card playback, 30px grating wavelength, 10 Hz temporal frequency, 50% duty cycle

**Cross-experiment timing consistency:** Phase1 CW end frame ranges from 3427 to 3445 across all 17 P008 experiments (18 frames / 0.6s spread, <0.3% variation). The outlier is `L1_Rig1_20260407_134314` at frame 3445; all others fall within 3427–3437 (10 frames / 0.33s). Negligible for analysis purposes.

**Per-experiment outputs** (saved to `<exp>/analysis/optomotor/`):
- `optomotor_<exp>.mat` — per-phase angular velocity matrices, sub-phase scalar means (CW/gap/CCW), per-fly traces
- `optomotor_<exp>_traces.png/.fig` — 2-panel figure (OM1, OM2) showing full continuous CW→gap→CCW trace with grey individual fly traces + mean ± SEM ribbon. Vertical markers: red solid = LED on/off, magenta dashed = CW end, green dashed = CCW start
- `optomotor_<exp>_summary.png/.fig` — 6-bar chart: OM1-CW, OM1-gap, OM1-CCW, OM2-CW, OM2-gap, OM2-CCW with fly scatter

**Per-genotype outputs** (saved to `P008/summary/optomotor/`):
- `summary_optomotor_<geno>.png/.fig` — 6-bar genotype summary (experiment means as scatter, genotype mean ± SEM)
- `summary_optomotor_comparison_<geno>.png/.fig` — OM1 (blue) vs OM2 (red) full traces overlaid on same axes with SEM ribbons, aligned to LED onset (t=0). Shows whether optomotor response changes after place learning.
- `summary_optomotor_<geno>.mat` — all computed data (traces, scalar means, time axes)

**Averaging hierarchy:** fly angular velocity → experiment mean trace → genotype mean ± SEM (experiment = unit of replication)

**trx.mat fields used:** `theta` (body orientation angle, ±π range, from ellipse fit), `x`/`y` (for fly filtering only). `theta` captures body turning including turning-in-place, which `atan2(dy,dx)` heading would miss.

---

### Comparison: batch_plot vs summary Scripts

| Feature | batch_plot_latency / batch_plot_distance | batch_latency_summary / batch_distance_summary | batch_distance_to_safe_summary |
|---------|------------------------------------------|------------------------------------------------|-------------------------------|
| **Compute function** | `compute_latency_per_cycle_local` / `compute_distance_per_cycle_local` | Same as batch_plot | `compute_distance_to_safe_local` (different metric) |
| **What it computes** | Latency to safe quad / Total distance during cycle | Same computation | Distance travelled until fly reaches safe quad |
| **Per-experiment output** | 4 PNG + 4 FIG + 1 MAT per experiment | No per-experiment plots | 1 MAT per experiment (via compute function) |
| **Protocol-level .mat** | No | Yes — `latency_summary_<prot>.mat` / `distance_summary_<prot>.mat` (long-format table + per-fly struct) | Yes — `dist_to_safe_summary_<prot>.mat` |
| **Protocol summary plot** | 1 PNG + 1 FIG per protocol (mean+/-SE + scatter, all experiments pooled regardless of genotype) | None directly; delegates to downstream plotters | None directly; delegates to downstream plotters |
| **Downstream plots** | None | allcycles, blocks, probes, intensity — mean + median variants, per-genotype + overlay (12+ plots) | allcycles, blocks, probes — first/last entry × mean/median, per-genotype + overlay (24+ plots) |
| **Averaging** | Grand mean +/- SE across experiment means (all genotypes pooled) | Long-format table; downstream plotters group by genotype then average experiment means | Same as batch_distance_summary |
| **Exclusion list** | None | Yes — `EXCLUDE_EXPERIMENTS` | Yes — `EXCLUDE_EXPERIMENTS` |
| **px/mm source** | Hardcoded `pxpermm_map` (P001-P005=9.20, P006-P009=8.21) | Reads `trx.pxpermm` from each experiment, averages per protocol | Same as batch_distance_summary |
| **.fig saved?** | Yes | No (downstream plotters save .png + .fig) | No (downstream plotters save .png + .fig) |

---

### Smoothing Removed (2026-04-14)

**Files changed:**
- `analyze_optomotor_P008.m` — `SMOOTH_WIN_SEC` changed from `1.0` to `0`
- `compute_speed_per_cycle_local.m` — default `SmoothWinSec` changed from `0.5` to `0`
- `test_heading_vs_theta_L2A.m` — `SMOOTH_WIN_SEC` set to `0`

All angular velocity and speed traces are now unsmoothed (raw frame-to-frame values averaged across flies). The `movmean` calls are still in the code but gated behind `if smooth_win > 1`, so setting the window to 0 disables them. Speed and optomotor `.mat` files must be recomputed to reflect this change.

**Re-run commands:**
```matlab
run_speed_P008        % recompute per-experiment speed data
summary_speed_P008    % regenerate per-genotype speed summaries
analyze_optomotor_P008  % regenerate optomotor plots
```

---

### Optomotor Mean Line Width Reduced (2026-04-14)

**File changed:** `analyze_optomotor_P008.m`

Mean angular velocity line width reduced from `2` to `1` in all plots (per-experiment traces and genotype OM1 vs OM2 overlay) for cleaner visualization with unsmoothed data.

---

### Fly Trajectory Overlay Plots (NEW)

**New file:** `plot_optomotor_trajectories_P008.m`

Plots fly X,Y trajectories from `trx.mat` overlaid on the arena background image during CW and CCW optomotor rotation.

**Fly selection:** Pools all alive flies across all experiments within a genotype. Computes mean |angular velocity| during OM1 CW+CCW per fly. Selects 3 flies closest to the genotype-wide median angular velocity. The **same 3 flies** (selected from OM1) are used for both OM1 and OM2 figures, matched by trx row index. For L2A and L3A, an offset of 3 is applied to pick different representative flies.

**Trajectory duration:** First 50 seconds of CW and first 50 seconds of CCW (configurable via `TRAJECTORY_SEC`).

**Figure layout:** 2 panels per figure (CW left, CCW right), each showing the arena background with 3 fly trajectories overlaid. Circle marker = start, square marker = end. Horizontal legend strip positioned between title and images.

**Fixed fly colors:** dark green, orange, purple (consistent between CW and CCW panels and between OM1 and OM2 figures for the same genotype).

**Output per genotype** (saved to `P008/summary/trajectories/`):
- `trajectories_P008_<geno>_OM1.png/.fig`
- `trajectories_P008_<geno>_OM2.png/.fig`

**Helper files:** `test_heading_vs_theta_L2A.m` — diagnostic comparison of theta-based vs heading-based (atan2(dy,dx)) angular velocity for one L2A experiment (`L2A_Rig1_20260409_122638`). Side-by-side 2×2 layout (OM1/OM2 × theta/heading) with linked Y axes. Output: `heading_vs_theta_<exp>.png` in experiment's optomotor folder.

---

### Legends Moved Outside Plots (2026-04-14)

**20 files changed** — all legend `Location` values moved from inside-plot positions to outside-plot positions across the entire analysis pipeline. This prevents legends from obscuring data.

**`'Location', 'best'` → `'Location', 'bestoutside'` (14 instances in 13 files):**
- `plot_QPI_allcycles_local.m`, `plot_QPI_blocks_local.m`, `plot_QPI_probes_local.m`
- `plot_distance_allcycles_local.m`, `plot_distance_blocks_local.m`, `plot_distance_probes_local.m`
- `plot_latency_allcycles_local.m`, `plot_latency_blocks_local.m`, `plot_latency_probes_local.m`
- `plot_dist_to_safe_allcycles_local.m`, `plot_dist_to_safe_blocks_local.m`, `plot_dist_to_safe_probes_local.m`
- `plot_quadrant_occupancy_all_local.m` (2 legend calls)

**`'Location', 'NorthEast'` → `'Location', 'NorthEastOutside'` (7 instances in 5 files):**
- `analyze_optomotor_P008.m` (genotype comparison overlay)
- `summary_speed_P008.m` (block overlay + probe overlay)
- `plot_speed_block_overlay.m` (block overlay + probe overlay)
- `plot_distance_per_experiment_local.m` (2 legend calls)
- `plot_latency_per_experiment_local.m` (2 legend calls)

**Not changed (already correct or not applicable):**
- `plot_optomotor_trajectories_P008.m` (manually positioned between title and images)
- `detect_duplicate_flies_local.m` (already `'bestoutside'`)
- `plot_speed_probes_local.m` (already `'northeastoutside'`)
- `detect_LED_from_video.m`, `plot_LED_events_all.m` (utility scripts, not analysis pipeline)

All summary plots must be regenerated to reflect this change.

---

### Probe Visit Analysis (NEW) (2026-04-14)

**New file:** `analyze_probe_visits_P008.m`

Counts the number of visits (entries) flies make to correct quadrants (Q2+Q4) and incorrect quadrants (Q1+Q3) during each probe trial (PP, B1.P–B4.P).

**Visit definition:** A visit = transition from not-in-target to in-target quadrant. Detected via `diff([0, in_target]) == 1`, where `in_target` is a binary vector indicating whether the fly is in the target quad pair at each frame. Uses arena calibration masks for quadrant lookup (same method as `compute_latency_per_cycle_local.m`).

**Metrics computed per fly per probe:**
- Number of visits to Q2+Q4 (correct)
- Number of visits to Q1+Q3 (incorrect)
- Time fraction in Q2+Q4
- Time fraction in Q1+Q3

**Averaging hierarchy:** fly → experiment mean → genotype mean ± SEM (experiment = unit of replication).

**Figures per genotype (saved to `P008/summary/probe_visits/`):**
- `probe_visits_P008_<geno>.png/.fig` — grouped bar chart: Q2+Q4 (blue) vs Q1+Q3 (orange) visit counts per probe
- `probe_time_P008_<geno>.png/.fig` — grouped bar chart: Q2+Q4 vs Q1+Q3 time fraction per probe
- `probe_visits_P008_<geno>.mat` — all computed data

**Colors:** Q2+Q4 correct = blue [0.2 0.5 0.8], Q1+Q3 incorrect = orange [0.85 0.33 0.10]. Legends outside plots ('NorthEastOutside').

---

### Cumulative Occupancy Analysis (NEW) (2026-04-14)

**New file:** `cumulative_occupancy_P008.m`

Adapted from user's CumulativeOccupancy_V3.m and CumulativeOccupancyAll_v4.m scripts. Computes the cumulative running average of time spent in Q2+Q4 (correct) and Q1+Q3 (incorrect) during probe trials.

**Method:**
- Bin each probe trial into 2-second bins (`BIN_FRAMES = round(2 × 30.1) = 60 frames`)
- Per bin: compute fraction of frames the fly spends in target quad pair
- Cumulative running average: `cumsum(occ_per_bin) ./ (1:n_bins)`
- Computed for both Q2+Q4 and Q1+Q3 independently

**Per-genotype figure (saved to `P008/summary/cumulative_occupancy/`):**
- 5 subplots (one per probe: PP, B1.P–B4.P)
- Grey individual fly traces in background
- Blue mean ± SEM ribbon for Q2+Q4 (correct)
- Red/orange mean ± SEM ribbon for Q1+Q3 (incorrect)
- Black dashed chance line at 0.5
- Legend on last subplot only, outside plot
- `cumulative_occ_P008_<geno>.png/.fig/.mat`

**Pipeline infrastructure:** Uses arena calibration masks for quadrant lookup, LED detector for probe frame boundaries, QPI dead fly log for exclusion — same as all other P008 analysis scripts.

---

### Generalized All P008-Specific Scripts to All Protocols (2026-04-15)

All scripts that were previously hardcoded to P008 have been generalized to loop over all applicable protocols. The original P008-specific versions are preserved; the new generalized scripts are separate files.

**New generalized files (replace P008-only scripts):**

| New file | Replaces | Protocols |
|----------|----------|-----------|
| `analyze_probe_visits.m` | `analyze_probe_visits_P008.m` | P003, P005, P006, P007, P008, P009 |
| `cumulative_occupancy.m` | `cumulative_occupancy_P008.m` | P003, P005, P006, P007, P008, P009 |
| `analyze_optomotor.m` | `analyze_optomotor_P008.m` | P006, P007, P008, P009 |
| `plot_optomotor_trajectories.m` | `plot_optomotor_trajectories_P008.m` | P006, P007, P008, P009 |
| `summary_speed.m` | `summary_speed_P008.m` | P003, P005, P006, P007, P008, P009 |
| `run_speed.m` | `run_speed_P008.m` | P001–P009 (skip P004) |
| `run_all_protocols.m` | *(new master runner)* | All applicable |

**What changed in each generalized script:**
- `PROTOCOL = 'P008'` replaced with a loop over all applicable protocols
- `build_P008_labels()` replaced with `build_protocol_labels(protocol)` — returns 46-cycle labels for P003/P005 (no OM1/OM2) or 48-cycle labels for P006–P009 (with OM1/OM2)
- Summary output directories are per-protocol: `<protocol>/summary/<analysis_type>/`
- Protocols whose directories don't exist are skipped gracefully
- All computation logic is identical to the P008 versions — no new methods introduced

**Protocol applicability:**
- Optomotor analysis and trajectories: only P006–P009 (protocols with OM1/OM2 phases)
- Probe visits and cumulative occupancy: only P003, P005–P009 (place learning protocols with probe trials)
- Speed: P001–P009 except P004 (per-experiment computation), P003+P005–P009 (genotype summaries)
- P001/P002 (intensity ramps): no probes, no optomotor — only speed applies
- P004 (optomotor only): skipped entirely — no LED quadrant patterns

**Master batch runner (`run_all_protocols.m`):** Sequentially runs all 6 generalized scripts in order: run_speed → summary_speed → analyze_optomotor → plot_optomotor_trajectories → analyze_probe_visits → cumulative_occupancy. Each step is wrapped in try/catch. Reports total elapsed time.

**Note:** The existing batch scripts (`batch_QPI_summary`, `batch_latency_summary`, `batch_distance_summary`, `batch_distance_to_safe_summary`, `batch_plot_speed`) already handle all protocols natively and are not affected by this change. Run them separately as before.

---

## 2026-05-08 Updates

### Centralized Quadrant Mapping — Metadata as Ground Truth

All files that need to determine which quadrants are lit vs safe now use `original_metadata.txt` as the primary source. The previous approach used `get_protocol_config` as the primary source with `validate_quad_patterns` as an optional cross-check, and several files had their own internal hardcoded pattern logic that never consulted metadata at all.

**New shared utility files:**

| File | Purpose |
|------|---------|
| `led_pattern_to_quads.m` | Single source of truth for LED string → quadrant mapping. `[lit, safe] = led_pattern_to_quads('1010')` returns `lit=[2,4], safe=[1,3]`. Encodes the hardware wiring where string positions do NOT map directly to quadrant numbers. |
| `get_quadrant_layout.m` | Single source of truth for quadrant spatial positions. Returns struct with `sign_x`, `sign_y`, `name`, `label` per quadrant. Matches the mask definition in `arena_led_pipeline_local.m` lines 200-209. Any code placing quadrant labels or computing spatial offsets MUST use this function. |

**Canonical quadrant layout** (from `arena_led_pipeline_local.m`, now exposed via `get_quadrant_layout()`):

```
Q2 (mask=2, Top-Left)   | Q1 (mask=1, Top-Right)
-------------------------+-------------------------
Q3 (mask=3, Bottom-Left) | Q4 (mask=4, Bottom-Right)
```

**Hardware LED wiring** (from `led_pattern_to_quads()`):

| LED string | Lit quadrants | Safe quadrants |
|------------|---------------|----------------|
| `'1010'` | Q2, Q4 (top-left, bottom-right) | Q1, Q3 (top-right, bottom-left) |
| `'0101'` | Q1, Q3 (top-right, bottom-left) | Q2, Q4 (top-left, bottom-right) |
| `'1111'` | All | None (probe) |

**Files updated to metadata-first pattern source:**

All files below now call `parse_metadata_led_patterns(exp_path)` directly. If metadata exists, it is used as ground truth. Only if no `original_metadata.txt` / `copy_metadata.txt` is found does the function fall back to `get_protocol_config`. The old `validate_quad_patterns` intermediate layer is no longer used.

| File | Old approach | New approach |
|------|-------------|-------------|
| `compute_latency_per_cycle_local.m` | `validate_quad_patterns(exp_path, cfg.quad_patterns)` | `parse_metadata_led_patterns` → `led_pattern_to_quads` |
| `compute_distance_to_safe_local.m` | `validate_quad_patterns(exp_path, cfg.quad_patterns)` | `parse_metadata_led_patterns` → `led_pattern_to_quads` |
| `plot_latency_trajectories.m` | `validate_quad_patterns(exp_path, cfg.quad_patterns)` | `parse_metadata_led_patterns` → `led_pattern_to_quads` |
| `plot_quadrant_preference_local.m` | Internal `get_protocol_labels()` subfunction | `parse_metadata_led_patterns` → `led_pattern_to_quads` |
| `diagnose_cycle.m` | Internal `get_protocol_labels_lat()` subfunction | `parse_metadata_led_patterns` → `led_pattern_to_quads` |
| `test_speed_per_fly.m` | Internal `get_protocol_labels_speed()` subfunction | `parse_metadata_led_patterns` → `led_pattern_to_quads` |
| `qc_qpi_frames.m` | Config + `validate_quad_patterns` + `find(qp=='1')` (WRONG) | `parse_metadata_led_patterns` → `led_pattern_to_quads` + `get_quadrant_layout` |
| `plot_quadrant_occupancy_all_local.m` | Hardcoded legend strings | Legend generated from `get_quadrant_layout()` |

**Eliminated duplication:** Previously, the LED-to-quadrant mapping was duplicated in 7+ files via hardcoded `strcmp(qp, '1010') → lit=[2,4]` blocks and internal `get_protocol_labels_*()` subfunctions. All of these now call `led_pattern_to_quads` for the mapping. The probe-specific override (`'1111'` → `correct_quads = [2,4]` for PP and B*.P cycles) is preserved in each compute function.

**Bug fixed:** `qc_qpi_frames.m` previously used `find(qp == '1')` to interpret LED strings, which treated string position as quadrant number. This gave the wrong quadrants (e.g., `'1010'` → lit=[1,3] instead of lit=[2,4]). The overlay coloring used `all_masks` and was correct, but the text labels were placed using a separate hardcoded offset array (`q_offsets`) that had Q1/Q2 swapped. Both issues are fixed: the pattern is now interpreted via `led_pattern_to_quads` and labels are positioned via `get_quadrant_layout`.

---

### QC QPI Frames Visualization (NEW)

**New file:** `qc_qpi_frames.m`

Visual QC tool for verifying quadrant pattern assignments per LED cycle. For each cycle, samples N random frames from the last half of the ON period and renders them as annotated arena snapshots.

**Per-frame rendering:**
- Dimmed arena background (40% brightness)
- Lit quadrants overlaid with red tint (no color on safe/dark quadrants)
- White arena circle outline and quadrant dividing lines
- Per-quadrant text labels (e.g., "Q1 (lit)", "Q2 (safe)") positioned via `get_quadrant_layout()`
- Fly positions as colored dots (12 distinct colors, no red/green to avoid confusion with overlay)
- Dead flies marked with X
- Frame number above each panel

**LUT text file:** Saved alongside PNGs at `qc_qpi_frames/qc_lut_<exp_name>.txt`. Lists every cycle with: LED pattern, lit/safe quadrants, ON/OFF frame range, sampled frame numbers, and per-fly x/y positions with alive/dead status and original trx index.

**Metadata source:** Reads `original_metadata.txt` directly via `parse_metadata_led_patterns`. Falls back to `get_protocol_config` with a printed warning if metadata is missing.

**Output:** One PNG per cycle saved to `<exp>/analysis/qc_qpi_frames/`. Super title shows experiment name, cycle number, label, and pattern (e.g., "Q1,Q3 lit | Q2,Q4 safe").

**Usage:**
```matlab
qc_qpi_frames('/path/to/experiment')
qc_qpi_frames('/path/to/experiment', 'NumFrames', 6, 'ShowPlots', true)
```

**Parameters:** `Protocol` (auto-detect), `NumFrames` (default 4), `ShowPlots` (default false).

---

### P015 and P016 Protocol Support

**Protocol definitions:**
- P015: Same 48-cycle structure as P008/P014. Inverted coupled place learning with lower LED intensity (training=6, probe=4).
- P016: Same 48-cycle structure as P015. All LED intensities at 4%.

**Files modified (~40 files):** Added `'P015'`, `'P016'` to protocol case lists in `get_protocol_config.m` and all compute/plot/batch functions. Both protocols use the same 48-cycle structure as P006-P014.

**Calibration:** Removed hardcoded `pxpermm_map` entries from `batch_plot_distance.m`, `batch_plot_speed.m`, and `run_speed.m`. Replaced with dynamic calibration via `get_mean_pxpermm(analysis_dir, protocol)`.

**New shared utility:** `get_mean_pxpermm.m` — scans all experiments of a protocol, reads `trx(1).pxpermm`, returns the mean. Falls back to `get_protocol_config(protocol).pixels_per_mm` if no trx values found.

---

## 2026-05-12 — P017, Standalone UFMF Reader, Quadrant Mapping Fixes

### JAABA Path Management for LED Detection (FIX)

**File modified:** `detect_LED_from_video.m`

**Problem:** LED detection requires JAABA's `get_readframe_fcn` (UFMF video reader), but JAABA on the MATLAB path shadows the built-in `savefig`, breaking figure saving in later pipeline steps.

**Fix:** `detect_LED_from_video.m` now temporarily adds JAABA (`/Users/rathores/Documents/MATLAB/JAABA`) to the path before reading the video and removes it immediately after intensity extraction completes. This keeps the UFMF reader available for LED detection without affecting `savefig` in subsequent analysis steps.

**Standalone `get_readframe_fcn.m` removed** — no longer needed with the temporary path approach.

---

### P017 Protocol Support (NEW)

**Protocol:** `Optomotor_Mode2SD_PlaceLearning_SBD_ProbeIntensity6`

**Description:** Combined optomotor (Mode 2 SD) + SBD place learning. Based on P013 structure with optomotor bookends.

**Key parameters:**
- Pattern: SBD (Bars + Stripes + Diagonal), 32x192px, brightness=6
- 4 orientations (0-3), each shifts pattern by ori*48 pixels
- LED patterns: `1101`, `1011`, `0111`, `1110` (single-quadrant punishment)
- Pairing: ori 0→1101 (Q4 safe), ori 1→1011 (Q3 safe), ori 2→0111 (Q2 safe), ori 3→1110 (Q1 safe)
- LED intensity: training=8, probe=6
- Trial/probe duration: 40s each

**Cycle structure (37 total):** OM1(1) + PP(2) + Ag(3) + B1.1-B1.10(4-13) + B1.P(14) + B2.1-B2.10(15-24) + B2.P(25) + B3.1-B3.10(26-35) + B3.P(36) + OM2(37)

**Key difference from P013:** Randomized trial orientations (no consecutive repeats). The config provides a default cycling sequence, but `parse_metadata_led_patterns` reads the actual randomized order from `original_metadata.txt` — this is the ground truth for each experiment.

**Files modified:**
- `get_protocol_config.m` (local + server): Added P017 alongside P013 in the same case block (identical 37-cycle structure)
- `get_protocol_config.m` (local + server): Fixed `training_cycles` detection — changed from `strcmp(qp, '1010') || strcmp(qp, '0101')` to `any(qp == '0')` to correctly classify single-quadrant patterns as training cycles

---

### LED-to-Quadrant Mapping Fix (BUG FIX)

**File:** `led_pattern_to_quads.m`

**Bug:** The `otherwise` branch (used for any LED pattern not explicitly listed) had incorrect individual position-to-quadrant mappings: pos2→Q4 and pos3→Q1. The correct empirically verified mapping (from P013) is pos2→Q3 and pos3→Q4.

**Why it was hidden:** The common patterns `1010` and `0101` are handled by explicit switch cases where the pair-level mapping ({pos1,pos3}→{Q2,Q4}) is sufficient. The bug only manifests for single-quadrant patterns like `1101`, `1011`, `0111`, `1110` (used by P013 and P017) that hit the `otherwise` branch.

**Example:** For `1101` (pos3=0), the old code returned safe=Q1 (wrong). The fix returns safe=Q4 (correct — verified from P013 empirical data).

**Corrected mapping:**
- pos 1 → Q2 (Top-Left) — unchanged
- pos 2 → Q3 (Bottom-Left) — was Q4
- pos 3 → Q4 (Bottom-Right) — was Q1
- pos 4 → Q1 (Top-Right) — was Q3

---

### Centralized Protocol Labels (REFACTOR)

**8 files modified:** Replaced duplicated `get_protocol_labels_*()` local functions (each 100-200 lines of switch/case) with thin wrappers calling the centralized `get_protocol_config()`.

**Files changed:**
- `plot_quadrant_preference_local.m` — `get_protocol_labels()`
- `compute_QPI_summary_local.m` — `get_protocol_labels_summary()`
- `compute_distance_per_cycle_local.m` — `get_protocol_labels_dist()`
- `compute_distance_to_safe_local.m` — `get_protocol_labels_dist()`
- `compute_latency_per_cycle_local.m` — `get_protocol_labels_lat()`
- `compute_speed_per_cycle_local.m` — `get_protocol_labels_speed()`
- `compute_onset_velocity_trace_local.m` — `get_protocol_labels_ovt()`
- `diagnose_cycle.m` — `get_protocol_labels_lat()`

Each was replaced with:
```matlab
function [labels, colors, sections, quad_patterns] = get_protocol_labels_*(protocol)
    cfg = get_protocol_config(protocol);
    labels = cfg.labels;
    colors = cfg.colors;
    sections = cfg.sections;
    quad_patterns = cfg.quad_patterns;
end
```

**Why:** Adding P013/P017 would have required updating all 8 switch/case blocks. Now only `get_protocol_config.m` needs to be updated for new protocols.

---

### Single-Quadrant QPI for P013/P017 (NEW)

**Problem:** The local pipeline used the diagonal-pair QPI formula `(Q1+Q3 − Q2−Q4) / total` for all protocols. P013 and P017 use single-quadrant punishment (one quadrant safe, three lit), requiring `(N_safe − N_other) / N_total`.

**Detection:** `is_single_quadrant = isfield(cfg, 'led_to_quad') && ~isempty(cfg.led_to_quad)` — only true for P013/P017 (the only protocols that set `cfg.led_to_quad = [2, 3, 4, 1]`). All other protocols are unaffected.

**Files modified:**

| File | Change |
|------|--------|
| `plot_quadrant_preference_local.m` | Branched frame-wise QPI: single-quadrant uses per-frame safe quad lookup via `cfg.led_to_quad(dark_pos)`. Added safe/hot zone overlay (safe=QPI>0, hot=QPI<0, per-cycle "Q# safe" label). Added chance line at −0.5. Updated y-axis label. |
| `compute_QPI_summary_local.m` | Same branched frame-wise QPI for first-half/second-half cycle means. Metadata patterns loaded via `parse_metadata_led_patterns`. |
| `compute_quadrant_preference_local.m` | Complete rewrite: protocol-aware with `get_protocol_from_opts()` helper. Per-fly per-stimulus QPI uses metadata patterns and `cfg.led_to_quad` mapping for single-quadrant, diagonal-pair for standard. |
| `batch_analyze_experiments_with_qc_local.m` | Added `opts.Protocol = protocol` and `opts.exp_path = exp_path` before calling `analyze_single_experiment_local`, so downstream QPI functions can access protocol config and metadata. |

**Safe quad determination per cycle:**
1. Read quad pattern (e.g., `'1101'`)
2. Find the `'0'` position → `dark_pos`
3. Map via `cfg.led_to_quad(dark_pos)` → safe quadrant number
4. For probe cycles (`'1111'`): use `cfg.probe_target_quad` (= 2 for P013/P017)

**Chance level:** −0.5 for single-quadrant (1 safe out of 4 quadrants = 25% expected occupancy → QPI = (0.25 − 0.75)/1 = −0.5). Displayed as dashed black line on plots.

---

### Batch Preprocessing — Background & Mask Images (FIX)

**File modified:** `batch_preprocessing_manual_local.m`

**Problem:** `batch_preprocessing_manual_local.m` (used for P013/P017) only saved `arena_calib_*.mat` and `LED_detector_*.mat`. It was missing the background PNG and quadrant mask PNG that `arena_led_pipeline_local.m` (used for P001–P016) produces.

**Fix:** Added `save_background_image()` and `save_quadrant_mask_image()` helper functions (matching `arena_led_pipeline_local.m` output format) and calls them after arena calibration save.

**New outputs per experiment:**
- `background_<exp_name>.png` — normalized uint8 background image
- `quadrant_masks_<exp_name>.png` — 2-panel figure (arena overlay + colored mask with Q1–Q4 legend)

---

### Metadata Parser — Randomized Orientation Log Support (FIX)

**File modified:** `parse_metadata_led_patterns.m` (local + server)

**Problem:** For randomized protocols (P017), the "Place Learning Block Schedule" section contains `LED=RANDOM` instead of actual 4-digit patterns. One line (`Preprobe: ori=RANDOM, LED=1111`) matched the regex, so the function returned `{'1111'}` instead of empty — the fallback to `get_protocol_config` then produced a static default sequence that didn't match the actual randomized trial order. This caused the frame-wise QPI to oscillate between +1 and −1 as the safe quadrant was misidentified on ~half the cycles.

**Fix:** The parser now checks for a "Randomized Orientation Log" section first (ground truth for P017). Only if that section doesn't exist does it fall back to the "Block Schedule" section (used by P013 and older fixed-order protocols).

**New second output — `training_patterns`:**
```matlab
[led_patterns, training_patterns] = parse_metadata_led_patterns(exp_path)
```
- For training cycles: same as `led_patterns` (the actual LED pattern)
- For probe cycles (LED=1111): the paired training LED pattern based on the probe's orientation, resolved from:
  1. `paired_LED=XXXX` field in probe lines (Randomized Orientation Log), or
  2. `ori=X` field + `Pairing:` line mapping (e.g., `ori 0→1101`)
- For OM cycles: `'1111'` (no training pairing)

This allows downstream code to determine which quadrant was the "learned safe" zone during probe trials, even though all LEDs are on.

Existing callers that use single-output syntax are unaffected (MATLAB silently discards extra outputs).

---

### QPI .mat Data Saving (NEW)

**File modified:** `plot_quadrant_preference_local.m`

Now saves `QPI_<exp_name>.mat` in the experiment's `analysis/` folder containing: frame-wise QPI trace (`quad_pref`), per-fly quadrant assignments (`fly_quad`), per-quadrant alive fly counts (`quad_counts_clean`), dead fly status (`fly_alive`), original trx indices, actual and training-equivalent LED patterns, safe quadrant per cycle, timestamps, LED cycle boundaries, and cycle labels.

**Safe quadrant labeling on plots:** Training cycles show a green "Q#" label; probe cycles show a blue "Q#" label indicating the learned safe quadrant (resolved from the probe's orientation via `training_patterns`). OM cycles show no label.

---

### Cross-Protocol Distance Overlay (NEW)

**New file:** `plot_distance_protocol_overlay.m`

Overlays distance travelled per cycle across multiple protocols on the same axes, grouped by genotype. Each protocol gets a distinct color (blue, red, green, orange, purple, teal) with SEM ribbon.

**Parameters:**
- `'CycleFilter'` — cell array to select cycle types: `{'PP', 'Ag', 'Training', 'Probe', 'OM'}`. When specified, excluded cycles are removed and the x-axis is re-indexed contiguously.
- `'Metric'` — column name from `distance_summary` table (default: `'mean_dist_mm'`)

**Legend display names:** Protocol numbers replaced with light intensity labels for P008-P016:
- P008 = 12%, P014 = 8%, P015 = 6%, P016 = 4%

Falls back to protocol name for unlisted protocols.

**Section dividers:** Uses block-number-aware grouping (`B1.x` vs `B2.x`) so training blocks are correctly separated even when probe cycles are filtered out.

**Usage:**
```matlab
plot_distance_protocol_overlay({'P008', 'P014', 'P015', 'P016'}, 'CycleFilter', {'PP', 'Ag', 'Training'});
```

---

### Probe Visit Analysis Extended to P014-P016 (UPDATE)

**File modified:** `analyze_probe_visits.m`

Removed the skip-if-exists check (lines 48-53) so the script always recomputes. Protocol list can be set to any subset (e.g., `{'P014', 'P015', 'P016'}`).

---

### P013/P017 QPI Summary Pipeline (NEW)

**New files:**
- `build_p013_p017_summary_local.m` — aggregates QPI across experiments for P013 or P017. Groups by genotype, calls `compute_QPI_summary_local` per experiment, computes mean ± SEM of first/second half |QPI| across experiments. Saves `<protocol>_summary.mat`.
- `plot_p013_p017_summary_local.m` — per-genotype QPI plots with second-half |QPI| as colored line + SEM ribbon, first-half as solid black line. Genotype overlay when multiple genotypes exist. Section dividers with rotated vertical labels (no background shading, no grid).
- `plot_p013_vs_p017_overlay.m` — overlays P013 (blue) and P017 (red) second-half |QPI| per genotype with SEM ribbons.

---

### Probe Trajectory Plots (NEW)

**New file:** `plot_probe_trajectories.m`

Per-experiment trajectory plots during probe trials (PP, B1.P–B4.P) for any protocol.

**Features:**
- Plots first 20 seconds of each probe trial (configurable via `'Duration'` parameter)
- Arena background (dimmed), circle boundary, dashed quadrant dividers
- Safe quadrants shaded green (Q2+Q4 for diagonal-pair protocols, per-cycle single quad for P013/P017)
- Per-fly trajectories with consistent colors across all panels within an experiment
- Markers: filled circle = start, filled square = first entry into safe zone, X = end of 20s window
- Dead flies automatically dimmed

**Parameters:**
- `'AnalysisDir'` — data root
- `'ShowPlots'` — keep figures visible (default: false)
- `'SavePlot'` — save PNG (default: true)
- `'Experiments'` — cell array to process subset
- `'FPS'` — frame rate (default: 30.1)
- `'Duration'` — seconds to plot per probe (default: 20)

**Output:** `probe_trajectories_<protocol>_<exp_name>.png` in each experiment's `plots/` folder.

Adapted from server pipeline's `plot_trajectories_p013.m`. Supports both diagonal-pair (P006-P016) and single-quadrant (P013/P017) safe zone logic.

**Usage:**
```matlab
plot_probe_trajectories('P014');
plot_probe_trajectories('P016', 'Duration', 30, 'ShowPlots', true);
```

---

### P018-P022 Protocol Support (NEW)

**File modified:** `get_protocol_config.m` (local + server)

Added protocol definitions for P018 through P022, sourced from recording scripts in `codes/`.

| Protocol | Type | Cycles | Notes |
|----------|------|--------|-------|
| P018 | Red-only intensity ramp | 42 | Same structure as P002 (7 intensities × 2 patterns × 3 reps). Standard optics. |
| P019 | Opto + SBD dark place learning | 37 | Same 37-cycle structure as P017 (OM1 + PP + Ag + 3 blocks + OM2). SBD pattern, 4 orientations, brightness=0 during training (dark). |
| P020 | Red stepped-block intensity | 24 | 3 blocks × 8 trials. Block 1: 1%/2%, Block 2: 3%/4%, Block 3: 5%/6%. Alternating 1010/0101. Standard optics. |
| P021 | Red stepped-block intensity | 24 | Same as P020 but with V11 attenuator + thin diffuser sandwich. |
| P022 | Red-only intensity ramp | 42 | Same as P018 but with V11 attenuator + thin diffuser sandwich. |

**P019 notes:** Uses `led_to_quad` and `probe_target_quad` (same single-quadrant mapping as P013/P017). Randomized trial orientations — use `parse_metadata_led_patterns` for ground truth.

---

### Preprocessing Consolidation (2026-05-18)

**Scripts consolidated:**
- `batch_preprocessing_manual_local.m` — **rewritten** as a thin batch wrapper that delegates to `arena_led_pipeline_local()` for each experiment. Previously reimplemented arena calibration inline (duplicate of `arena_led_pipeline_local`'s logic).
- `arena_led_pipeline_local.m` — **unchanged**, single-experiment workhorse (background → arena calibration → LED detection)
- `detect_LED_from_video.m` — **unchanged**, leaf-level LED detector

**Deprecated:**
- `manual_arena_led_pipeline_local.m` — emits deprecation warning, use `arena_led_pipeline_local()` instead. Fully redundant: fewer features (no SavedCalib, no per-step skip, no NumLEDs parameter).
- `batch_preprocessing_complete_local.m` — emits deprecation warning, use `batch_preprocessing_manual_local()` instead. Had bugs: passed invalid `UseFlyTrackerCalib` parameter, hardcoded NumLEDs=3, contained dead `process_indicator_data` code.

**Clean call graph:**
```
batch_preprocessing_manual_local(analysis_dir)
  └── arena_led_pipeline_local(exp_path, network_root)
      └── detect_LED_from_video(exp_path, network_root)
```

**Protocol-aware NumLEDs:** P001 = 3 (RGB LEDs), all other protocols = 1. Determined automatically from the protocol folder name.

**NetworkRoot default fixed:** All scripts now use `/Volumes/ReiserLab/Shubham/Projects/Feature learning/2026/board4/videos`. Previously three different paths were hardcoded across scripts (year/folder order swapped, missing `/videos`).

**Field naming standardized:** `arena_led_pipeline_local` writes `vert_coef`/`horiz_coef`. The only downstream consumer (`qc_qpi_frames.m`) already handles both naming conventions via `isfield` fallback.

---

### Trajectory Plotting Scripts — Reference Inventory

Six trajectory plotting scripts exist across the codebase, each with distinct logic. Documented here for future reference and potential consolidation.

**Pipeline scripts (in `freewalkinganalysislocal/`):**

| Script | Cycles | Time Window | Markers | Safe Zone | Grouping | Protocols |
|--------|--------|-------------|---------|-----------|----------|-----------|
| `plot_probe_trajectories.m` | Probes only (PP, B*.P) | First 20s (configurable) | ●=start, ×=end, ■=safe entry | Green shaded (diagonal or single-quad) | Per-experiment | Any (generic) |
| `plot_fly_trajectories_dark.m` | All training + probes | Full cycle | ○=start, ■=end | None | Per-experiment | P014 only (hardcoded) |
| `plot_latency_trajectories.m` | Training only | Onset → first safe entry (variable) | ●=onset, ■=safe entry, ×=never reached | Implicit (trajectory terminates at safe) | Per-experiment | P008/P010/P011/P014 |
| `plot_optomotor_trajectories.m` | OM1/OM2 (CW + CCW) | First 50s | ●=start, ■=end | N/A | Per-genotype (3 median flies) | 9 protocols |
| `plot_optomotor_trajectories_P008.m` | OM1/OM2 (CW + CCW) | First 50s | ●=start, ■=end | N/A | Per-genotype (3 median flies) | P008 only |

**Server pipeline script (in `FreewalkingAnalysisPipeline/`):**

| Script | Cycles | Time Window | Markers | Safe Zone | Grouping | Protocols |
|--------|--------|-------------|---------|-----------|----------|-----------|
| `plot_trajectories_p013.m` | All training + probes + Ag | Onset → first safe entry | ●=onset, ■=safe entry, ×=never reached | Green shaded (single-quad per cycle) | Per-experiment | P013 only |

**Unique logic not yet generalized:**
- **Latency-path rendering** (`plot_latency_trajectories.m`): Three-way trajectory logic — (a) fly already in safe at onset shows 1s of movement, (b) fly found safe shows onset-to-entry + 1s dimmed jitter, (c) fly never reached safe shows full dimmed trajectory + × marker. Useful for visualizing learning progression.
- **Optomotor fly selection** (`plot_optomotor_trajectories.m`): Picks 3 flies closest to genotype-wide median angular velocity (computed from `trx.theta`). Aggregates across experiments per genotype. L2A/L3A get an offset of 3 to pick different representatives.
- **Edited trx source** (`plot_trajectories_p013.m`): Uses `edited_registered_trx.mat` preferentially over `trx.mat` (stitched tracking data for P013 server pipeline).

**Legacy script (in `Documents/codes/`):**
- `Plottrajectoryandvelocity_V1.m` — original interactive script (code cells). Single-experiment, hardcoded paths. Per-fly and per-cycle trajectory + velocity plots. Predecessor to all pipeline trajectory scripts.

---

### Trajectory Safe Zone Fix — Probes Use Training Patterns (2026-05-18)

**Bug:** All three trajectory plotting scripts (`plot_perfly_trajectories.m`, `plot_probe_trajectories.m`, `plot_trajectories_p013.m`) and `plot_latency_trajectories.m` were using `led_patterns` (first output of `parse_metadata_led_patterns`) to determine safe-zone shading. For probe trials where `LED=1111` (all LEDs on), the pattern has no `'0'` position, so the code fell through to `cfg.probe_target_quad` — always shading Q2 regardless of which orientation was being probed.

**The problem:** In randomized protocols (P017, P019), each probe tests a specific orientation. The orientation determines the *target* safe quadrant (e.g., probe at ori=1 → paired LED `1011` → Q3 is the learned safe zone). Showing the wrong quadrant as safe misrepresents the fly's behavioral context.

**Fix:** All four trajectory scripts now use `training_patterns` (second output of `parse_metadata_led_patterns`) instead of `led_patterns` for safe-zone visualization. For training cycles, `training_patterns` is identical to `led_patterns`. For probe cycles, it contains the paired training LED pattern resolved from the probe's orientation — so `find(qp == '0')` correctly identifies the target safe quadrant.

**Files changed:**
- `plot_perfly_trajectories.m` — `[~, metadata_training] = parse_metadata_led_patterns(exp_path)`
- `plot_probe_trajectories.m` — same change
- `plot_latency_trajectories.m` — same change
- `plot_trajectories_p013.m` (server pipeline) — same change

The `probe_target_quad` fallback in the safe-quadrant logic is preserved for protocols without metadata.

---

### Per-Fly Trajectory Dashboard (NEW) (2026-05-18)

**New file:** `plot_perfly_trajectories.m`

Per-fly trajectory dashboard: one figure per fly showing all cycles in a tiled grid. Inspired by `Plottrajectoryandvelocity_V1.m` per-cycle trajectory logic.

**Features:**
- One figure per fly, tiled grid (auto-sized: 10 cols for 48 cycles, 8 for 37, 6 for 24)
- Each panel: dimmed background, arena circle, quadrant dividers, green-shaded safe zones
- Trajectory from `on_times` to `off_times` with markers: filled circle=start, X=end, filled square=first safe entry
- Cycle labels color-coded from `get_protocol_config` colors (red=training, gold=probe, grey=OM/PP/Ag)
- Dead flies dimmed to 30%, noted in figure title
- Safe zone shading uses `training_patterns` from metadata (orientation-resolved for probes)

**Output:** `<protocol>/<exp_name>/perflytrajectories/fly<NN>_<exp_name>.png`

**Usage:**
```matlab
plot_perfly_trajectories('P019');
plot_perfly_trajectories('P017', 'Experiments', {'L2A_Rig1_20260506_143055'}, 'FlyIndex', [1 5 10]);
```

---

### Interactive Trajectory Dashboard (NEW) (2026-05-18)

**New directory:** `trajectory_dashboard/`

Browser-based interactive dashboard for browsing per-fly trajectories across protocols and experiments. Full-resolution trajectory data — every frame preserved.

**How it was built:**
1. Python script (`extract_fullres.py`) reads `trx.mat`, `arena_calib_*.mat`, `LED_detector_*.mat`, and `original_metadata.txt` from each experiment
2. Extracts full-resolution x,y coordinates for every fly during every LED cycle (on_times to off_times)
3. Parses metadata for LED patterns, training patterns (orientation-resolved for probes), and cycle labels
4. Saves per-protocol JSON files (e.g., `P008.json`, `P019.json`)
5. `index.html` loads one protocol at a time via `fetch()`, renders tiled canvas grid

**Data format (per-protocol JSON):**
- Per experiment: `xc`, `yc`, `r` (arena), `nc` (num cycles), `lp` (LED patterns), `tp` (training patterns), `lb` (labels)
- Per fly per cycle: `[x_array, y_array]` — full frame-by-frame coordinates, rounded to 0.1px

**Dashboard features:**
- Protocol selector → Experiment selector → Fly navigation (arrow keys)
- **View filter:** "All Cycles" (default) or "Probes Only" — shows only PP and block probe trials (B1.P–B4.P or B1.P–B3.P depending on protocol) for focused probe assessment
- Tiled grid: one canvas per cycle with arena circle, quadrant dividers, safe-zone shading. Grid columns auto-adapt to visible cycle count (e.g., 5 columns for 5 probes).
- Click any tile for zoomed 600×600 detail view with LED pattern, target pattern, and safe quadrant info
- Labels color-coded: red=training, gold=probe, grey=OM/PP/Ag
- Safe zone shading from `training_patterns` (orientation-aware for probes)

**Protocols currently extracted:** P008, P010, P011, P013, P014, P015, P016, P017, P019

**To serve:**
```bash
cd ~/Documents/codes/freewalkinganalysislocal/trajectory_dashboard
python3 -m http.server 8080
# Open http://localhost:8080
```

**To add more protocols:**
```bash
python3 extract_fullres.py P013 P014 P015
```
Then add the protocol to the `<select>` in `index.html`.

**Note:** `extract_fullres.py` merges into the existing `manifest.json` rather than overwriting it.

---

### Per-Cycle Track Completeness QC (NEW) (2026-05-18)

**File modified:** `validate_experiment_simple_local.m`

**Problem:** The pipeline had no per-cycle check for tracking completeness within LED on/off windows. A fly with large NaN gaps in its x,y trajectory during a specific cycle would still contribute to distance, latency, QPI, and distance-to-safe computations. Distance was silently underestimated (`sum(..., 'omitnan')` skipped NaN steps without flagging), latency searches skipped NaN frames without warning, and QPI excluded NaN-position frames from quadrant counts without annotation. No `.mat` file recorded per-cycle validity.

**New function:** `compute_percycle_completeness()` (local function in `validate_experiment_simple_local.m`)

For each good fly and each LED cycle, computes:
```
valid_frac(f, c) = sum(~isnan(x) & ~isnan(y)) / num_frames
```
over the frame window `on_times(c):off_times(c)`.

**Output:** `track_completeness_<exp>.mat` saved in the experiment's `analysis/` folder, containing:
- `valid_frac` — `[num_good_flies × num_cycles]` fraction of valid frames per fly per cycle
- `nan_frame_count` — `[num_good_flies × num_cycles]` count of NaN frames per fly per cycle
- `total_frame_count` — `[num_good_flies × num_cycles]` total frames per fly per cycle
- `fly_ids_original` — original trx indices of good flies (for alignment with compute functions)
- `on_times`, `off_times` — LED cycle boundaries used
- `num_cycles` — number of LED cycles
- `min_valid_frac` — threshold (default 0.80 = 80%)

**Tracking gap schematic extended:** `plot_tracking_gaps()` now produces a two-panel figure:
- **Panel 1 (unchanged):** Whole-experiment horizontal raster (blue=tracked, orange=NaN gap, grey=no data)
- **Panel 2 (new):** Per-cycle completeness heatmap (`imagesc`, `parula` colormap, 0–1 scale). Red-bordered cells indicate fly-cycle pairs below the 80% threshold. X-axis = LED cycle number, Y-axis = good fly IDs.

Both panels saved as `tracking_gaps.png` + `tracking_gaps.fig`.

**Downstream integration (pending):** The 4 compute functions (`compute_distance_per_cycle_local`, `compute_latency_per_cycle_local`, `compute_distance_to_safe_local`, `compute_QPI_summary_local`) do NOT yet use the completeness data. The `.mat` file is generated and the heatmap visualized so the threshold can be evaluated empirically before wiring the gate into the compute pipeline.

**Default threshold:** 80% (`min_valid_frac = 0.80`). Subject to revision after inspecting the completeness heatmaps across protocols.

**Empirical scan (2026-05-18):** Full scan of 123 experiments / 1,432 good flies / 64,500 fly-cycle pairs found 466 pairs with any NaN (0.7%). Zero pairs below 80%. Only 7 below 90% (worst: P014/L2A_Rig1_20260429_160004 fly 7 cycle 37 at 85.7%). 25 below 95%. Most are single-frame blips (99.9% valid). Threshold decision deferred — the data is very clean overall.

**TODO:** Wire the completeness gate into the 4 compute functions once a threshold is chosen. Consider 90% or 95% based on the scan results.

---

### Summary Folder Pollution Fix (2026-05-18)

**File modified:** `batch_analyze_experiments_with_qc_local.m`

**Bug:** The genotype discovery functions (`discover_protocols_genotypes` and `collect_protocol_genotype_experiments`) scanned all subdirectories inside each protocol folder and only excluded `.`, `..`, and `Summary_Plots`. Non-experiment directories like `QPI_summary`, `distance_summary`, `dist_to_safe_summary`, `latency_summary`, `summary`, `perflytrajectories`, and `latency_trajectories` were passed through. Their names were split on `_` to extract fake genotype tokens (`QPI`, `distance`, `dist`, `latency`, `summary`), which then polluted the genotype list and caused the pipeline to attempt analysis on summary folders as if they were experiments.

**Fix:** Replaced the exclusion-list approach with a regex filter requiring valid experiment folder names to match `^\w+_Rig\d+_\d{8}_\d{6}$` (e.g., `L2A_Rig1_20260409_122638`). Applied in both `discover_protocols_genotypes` (line ~164) and `collect_protocol_genotype_experiments` (line ~188). This is the same pattern used by `extract_fullres.py` (`'_Rig' not in en`) and automatically excludes any future non-experiment directories without needing to maintain a hardcoded exclusion list.

**Old code:**
```matlab
exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..', 'Summary_Plots'}));
```

**New code:**
```matlab
exp_dirs = exp_dirs([exp_dirs.isdir]);
valid = ~cellfun(@isempty, regexp({exp_dirs.name}, '^\w+_Rig\d+_\d{8}_\d{6}$'));
exp_dirs = exp_dirs(valid);
```

---

### TODO: Linearize QPI Computation Pipeline

**Current problem:** QPI is computed from raw data (trx.mat, arena_calib, LED_detector) independently in three places:

1. `plot_quadrant_preference_local.m` — frame-wise QPI for plotting, now saves `QPI_<exp>.mat`
2. `compute_QPI_summary_local.m` — frame-wise QPI → per-cycle first/second half means
3. `compute_quadrant_preference_local.m` — per-fly per-stimulus QPI (called by `analyze_single_experiment_local`)

Each reloads the same files, re-maps flies to quadrants, re-detects dead flies, and re-computes QPI. This is redundant and error-prone (changes to one don't automatically propagate to others).

**Proposed fix:** Linearize into a single compute step that saves all intermediate results, with downstream consumers loading from the saved .mat:

1. **`compute_qpi_local.m`** (new, single source of truth): loads raw data, maps flies to quadrants, detects dead flies, computes frame-wise QPI and per-fly per-stimulus QPI. Saves everything to `QPI_<exp>.mat`.
2. **`plot_quadrant_preference_local.m`**: loads `QPI_<exp>.mat`, plots. No computation.
3. **`compute_QPI_summary_local.m`**: loads `QPI_<exp>.mat`, computes cycle means. No raw data access.
4. **`compute_quadrant_preference_local.m`**: loads `QPI_<exp>.mat` or is eliminated (merged into step 1).

This eliminates triple computation and ensures all downstream consumers use identical fly filtering, dead fly detection, and quadrant mapping.

---

## 2026-05-18 — DRY Refactor: All Plotters Now Use get_protocol_config

### Refactored 20 plotters to use `get_protocol_config` as single source of truth

**Root cause fix:** Every plotter previously had its own `switch upper(protocol)` block duplicating cycle layout knowledge (probe cycles, training blocks, block counts, etc.). When new protocols (P013/P017/P019) were added, every plotter needed manual updates — leading to recurring `undefined variable` bugs whenever a case was missed.

**Solution:** All 20 plotters now call `cfg = get_protocol_config(protocol)` and extract cycle layout from the returned struct. Adding a new protocol only requires updating `get_protocol_config.m`.

**Convenience fields added to `get_protocol_config.m`:**
- `cfg.preprobe_cycle` — cycle index labeled 'PP'
- `cfg.pretrain_cycle` — cycle index labeled 'Ag'
- `cfg.num_blocks` — number of training blocks (from sections)
- `cfg.training_blocks` — cell of cycle vectors per block (training cycles only)
- `cfg.block_probe_cycles` — probe cycle per block [B1.P, B2.P, ...]
- `cfg.probe_labels` — {'PP', 'B1.P', 'B2.P', ...}
- `cfg.all_probe_cycle_nums` — [PP, B1.P, B2.P, ...] cycle indices
- `cfg.block_labels` — {'B1', 'B2', ...}

**Place-learning plotters refactored (12 files):**
- `plot_QPI_allcycles_local.m`, `plot_QPI_blocks_local.m`, `plot_QPI_probes_local.m`
- `plot_distance_allcycles_local.m`, `plot_distance_blocks_local.m`, `plot_distance_probes_local.m`
- `plot_latency_allcycles_local.m`, `plot_latency_blocks_local.m`, `plot_latency_probes_local.m`
- `plot_dist_to_safe_allcycles_local.m`, `plot_dist_to_safe_blocks_local.m`, `plot_dist_to_safe_probes_local.m`

**Speed and per-experiment plotters refactored (6 files):**
- `plot_speed_training_local.m`, `plot_speed_probes_local.m`, `plot_speed_block_overlay.m`
- `plot_exp_training_allcycles_local.m`, `plot_exp_training_blocks_local.m`, `plot_exp_probes_local.m`

**Per-experiment helper refactored (1 file):**
- `plot_distance_per_experiment_local.m` — `get_distance_cycle_colors` helper now reads labels/colors from `get_protocol_config`

**Intensity plotters refactored (4 files) — gating only:**
- `plot_QPI_intensity_local.m`, `plot_distance_intensity_local.m`, `plot_latency_intensity_local.m`, `plot_onset_velocity_trace_local.m`
- Hardcoded place-learning skip lists replaced with `cfg.is_intensity` check
- P001/P002 plot-specific config (block colors, intensity arrays) retained since those are visualization-only

**Verification:** `grep -r "switch upper(protocol)" plot_*.m` confirms only the 4 intensity plotters retain a switch — and only for P001/P002-specific visualization config, not for protocol gating.

---

## 2026-05-18 — Centralized Dead Fly Detection, P013/P017/P019 Summary Plotter Support

### Centralized Dead Fly Detection Batch Script (NEW)

**New file:** `batch_dead_fly_detection.m`

**Problem:** Dead fly detection was computed redundantly by every compute function (`compute_QPI_summary_local`, `compute_distance_per_cycle_local`, `compute_latency_per_cycle_local`, `compute_speed_per_cycle_local`, `compute_onset_velocity_trace_local`, `compute_distance_to_safe_local`). Each independently loads trx, LED detector, and runs `detect_dead_flies_posture()`. Running all compute functions for one experiment means dead fly detection executes 5–6× per experiment.

**Fix:** `batch_dead_fly_detection.m` pre-generates `dead_fly_report.mat` for every experiment in one pass. All compute functions already check for this file first in their fallback chain (`FlyAlive` parameter → `dead_fly_report.mat` → QPI log → inline detection), so once the file exists, the inline detection is never reached.

**Usage:**
```matlab
batch_dead_fly_detection                  % all protocols
batch_dead_fly_detection('P017', 'P019')  % specific protocols
```

**Output per experiment:** `analysis/dead_fly_report.mat` containing `dead_report` struct with fields:
- `fly_alive` — [num_flies × num_cycles] logical
- `num_flies`, `num_dead`, `num_alive`
- `dead_from_cycle` — [num_flies × 1], cycle at which each fly was flagged (Inf = alive)
- `consecutive_cycles`, `move_thresh_px` — detection parameters used
- `fly_ids_original` — original trx indices of evaluated flies (for consistency verification)
- `timestamp` — when the report was generated

**Pipeline order:** Run `batch_dead_fly_detection` before any batch compute scripts (`batch_QPI_summary`, `batch_distance_summary`, `batch_latency_summary`, etc.). Existing experiments that already have `dead_fly_report.mat` are skipped unless `FORCE_RECOMPUTE` is set to `true`.

**No changes to compute functions.** The fallback chain in all 6 compute functions is unchanged — they already prefer `dead_fly_report.mat` when it exists.

### P013/P017/P019 Added to Summary Plotters (FIX)

**Problem:** 9 summary plotters had hardcoded `switch` statements enumerating place learning protocols. P013, P017, and P019 (3-block, 37-cycle SBD protocols) were missing, causing them to be silently skipped with "Not a place learning protocol."

**Files modified (9):**

| Plotter | Change |
|---------|--------|
| `plot_QPI_allcycles_local.m` | Added `'P019'` to existing `{'P013','P017'}` case |
| `plot_QPI_blocks_local.m` | Added `{'P013','P017','P019'}` case; dynamic axis labels |
| `plot_QPI_probes_local.m` | Added `{'P013','P017','P019'}` case with 4 probes |
| `plot_distance_allcycles_local.m` | Added `{'P013','P017','P019'}` case |
| `plot_distance_blocks_local.m` | Added `{'P013','P017','P019'}` case; dynamic axis labels |
| `plot_distance_probes_local.m` | Added `{'P013','P017','P019'}` case with 4 probes |
| `plot_latency_allcycles_local.m` | Added `{'P013','P017','P019'}` case; dynamic block_names |
| `plot_latency_blocks_local.m` | Added `{'P013','P017','P019'}` case; dynamic axis labels |
| `plot_latency_probes_local.m` | Added `{'P013','P017','P019'}` case with 4 probes |

**Cycle layout for P013/P017/P019:**
- 37 cycles: OM1(1) + PP(2) + Ag(3) + 3×(10 training + 1 probe) + OM2(37)
- `preprobe_cycle = 2`, `pretrain_cycle = 3`, `opto_cycles = [1, 37]`
- `probe_cycles = [14, 25, 36]` (3 probes, not 4)
- `training_blocks = {[4 13], [15 24], [26 35]}` (3 blocks, not 4)

**Axis label fix:** Block plotters previously had hardcoded x-tick labels (`{'B1','B2','B3','B4'}`) and `xlim([0.5 4.5])`. Now generated dynamically from `num_blocks` using `arrayfun`. Probe plotters already used `num_probes` dynamically — only the probe cycle numbers and labels needed updating.

### Probe Safe Quadrant Resolution for Single-Quad Protocols (FIX)

**Files modified:**
- `compute_QPI_summary_local.m`
- `compute_latency_per_cycle_local.m`
- `compute_distance_to_safe_local.m`

**Problem:** All three compute functions used the first output of `parse_metadata_led_patterns` (`led_patterns`), which returns `'1111'` for probe cycles. They then hardcoded the safe zone as `[2, 4]` (diagonal pair) or `probe_target_quad` (single-quad fallback). For P017/P019 where the safe quadrant rotates per trial orientation, this meant probes were always measured against a fixed default safe zone instead of the orientation-matched trained safe zone.

**Fix:** Use `training_patterns` (second output of `parse_metadata_led_patterns`) as the quad pattern source — same approach already used in `plot_probe_trajectories.m`. For probe cycles, `training_patterns` contains the paired training LED pattern (e.g. `'1101'` instead of `'1111'`), resolved from `paired_LED=` fields or the ori-to-LED mapping in the metadata. `led_pattern_to_quads` then directly resolves the correct safe quadrant per trial. The `'1111'` fallback (using `probe_target_quad` for single-quad or `[2, 4]` for diagonal) only fires when pairing couldn't be resolved from metadata.

**Universality:** The `training_patterns` approach works across all protocol types without branching:
- **2-orientation diagonal** (P008): ori 0 → `0101` → safe `[2, 4]`
- **4-orientation single-quad fixed** (P013): ori 2 → `0111` → safe `[2]`
- **4-orientation single-quad randomized** (P017/P019): each trial's orientation from metadata → paired LED → single safe quad

### Recomputation Required for P017 and P019

**Reason:** Latency and distance-to-safe summary files for P017 and P019 were computed with the old code (probe safe zone hardcoded as `[2, 4]`). With the `training_patterns` fix above, per-experiment and summary-level results must be recomputed.

**Procedure:**
```matlab
%% Delete stale summary files (batch scripts skip experiments already in summary)
ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';
delete(fullfile(ANALYSIS_DIR, 'P017', 'latency_summary_P017.mat'));
delete(fullfile(ANALYSIS_DIR, 'P019', 'latency_summary_P019.mat'));
delete(fullfile(ANALYSIS_DIR, 'P017', 'dist_to_safe_summary_P017.mat'));
delete(fullfile(ANALYSIS_DIR, 'P019', 'dist_to_safe_summary_P019.mat'));

%% Recompute
batch_dead_fly_detection('P017', 'P019')   % ensure dead fly reports exist
batch_latency_summary                       % recomputes P017/P019 latency
batch_distance_to_safe_summary              % recomputes P017/P019 distance-to-safe
```

**Note:** Per-experiment `.mat` files (e.g. `analysis/latency_*.mat`) are overwritten unconditionally by the compute functions, so only the summary-level files need to be deleted. The batch scripts skip experiments already present in the summary table — deleting the summary forces a full recompute for that protocol. Other protocols are unaffected.
