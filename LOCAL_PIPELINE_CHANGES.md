# Local Pipeline Centralization Changes

**Date:** 2026-04-22

## Summary

Centralized two redundant patterns across all compute functions in `freewalkinganalysislocal/`:

1. **Protocol configuration** — replaced per-function `get_protocol_labels_*()` helpers with a single shared `get_protocol_config.m`
2. **Dead fly detection** — replaced per-function QPI log parsing / inline detection with a centralized `detect_dead_flies_posture.m` and a priority-based fallback chain

All changes are backward-compatible. Existing experiments with QPI log files or no `dead_fly_report.mat` will continue to work via the fallback chain.

---

## New Files Added

| File | Source | Purpose |
|------|--------|---------|
| `get_protocol_config.m` | Copied from `FreewalkingAnalysisPipeline/` | Single source of truth for all protocol definitions (P001-P010): cycle labels, quad patterns, sections, flags |
| `detect_dead_flies_posture.m` | Copied from `FreewalkingAnalysisPipeline/` | Standalone dead fly detection using sliding-window position analysis. Returns `[fly_alive, dead_report]` |

---

## Files Modified

### compute_distance_per_cycle_local.m

| Change | Before | After |
|--------|--------|-------|
| Protocol labels | `get_protocol_labels_dist(protocol)` (internal helper, 96 lines) | `cfg = get_protocol_config(protocol); cycle_labels = cfg.labels;` |
| FlyAlive parameter | Not accepted | `addParameter(p, 'FlyAlive', [], ...)` — optional, backward-compatible |
| Dead fly source priority | 1. QPI log → 2. internal `detect_dead_flies()` | 1. Passed-in `FlyAlive` → 2. `dead_fly_report.mat` → 3. QPI log → 4. `detect_dead_flies_posture()` |

### compute_latency_per_cycle_local.m

| Change | Before | After |
|--------|--------|-------|
| Protocol labels + quad patterns | `get_protocol_labels_lat(protocol)` (internal helper, 123 lines) | `cfg = get_protocol_config(protocol);` extracting `.labels`, `.sections`, `.quad_patterns` |
| FlyAlive parameter | Not accepted | `addParameter(p, 'FlyAlive', [], ...)` |
| Dead fly source priority | 1. QPI log → 2. internal `detect_dead_flies()` | 1. Passed-in `FlyAlive` → 2. `dead_fly_report.mat` → 3. QPI log → 4. `detect_dead_flies_posture()` |

### compute_QPI_summary_local.m

| Change | Before | After |
|--------|--------|-------|
| Protocol labels | `get_protocol_labels_summary(protocol)` (internal helper, 71 lines) | `cfg = get_protocol_config(protocol); cycle_labels = cfg.labels;` |
| FlyAlive parameter | Not accepted | `addParameter(p, 'FlyAlive', [], ...)` |
| Dead fly detection | Inline 22-line sliding-window loop | 1. Passed-in `FlyAlive` → 2. `dead_fly_report.mat` → 3. `detect_dead_flies_posture()` |

### compute_speed_per_cycle_local.m

| Change | Before | After |
|--------|--------|-------|
| Protocol labels | `get_protocol_labels_speed(protocol)` (internal helper, 97 lines) | `cfg = get_protocol_config(protocol); cycle_labels = cfg.labels;` |
| FlyAlive parameter | Not accepted | `addParameter(p, 'FlyAlive', [], ...)` |
| Dead fly source priority | 1. QPI log → 2. internal `detect_dead_flies()` | 1. Passed-in `FlyAlive` → 2. `dead_fly_report.mat` → 3. QPI log → 4. `detect_dead_flies_posture()` |

### compute_distance_to_safe_local.m

| Change | Before | After |
|--------|--------|-------|
| Protocol labels + quad patterns | `get_protocol_labels_lat(protocol)` (internal helper, duplicated from latency) | `cfg = get_protocol_config(protocol);` extracting `.labels`, `.sections`, `.quad_patterns` |
| FlyAlive parameter | Not accepted | `addParameter(p, 'FlyAlive', [], ...)` |
| Dead fly source priority | 1. QPI log → 2. internal `detect_dead_flies()` | 1. Passed-in `FlyAlive` → 2. `dead_fly_report.mat` → 3. QPI log → 4. `detect_dead_flies_posture()` |

### compute_onset_velocity_trace_local.m

| Change | Before | After |
|--------|--------|-------|
| Protocol labels | `get_protocol_labels_ovt(protocol)` (internal helper, 71 lines) | `cfg = get_protocol_config(protocol); cycle_labels = cfg.labels;` |
| FlyAlive parameter | Not accepted | `addParameter(p, 'FlyAlive', [], ...)` |
| Dead fly source priority | 1. QPI log → 2. internal `detect_dead_flies_ovt()` | 1. Passed-in `FlyAlive` → 2. `dead_fly_report.mat` → 3. QPI log → 4. `detect_dead_flies_posture()` |

### analyze_single_experiment_local.m

| Change | Before | After |
|--------|--------|-------|
| Dead fly handling | None — each compute function handled its own | Loads or creates `dead_fly_report.mat` once; downstream compute functions find it via the `dead_fly_report.mat` fallback |
| Arena/LED file selection | `arena_files(1)`, `led_files(1)` | `arena_files(end)`, `led_files(end)` (use latest, consistent with server) |

---

## Dead Fly Detection Priority Chain

Every compute function now follows the same priority order:

```
1. FlyAlive parameter (passed in by caller)
      ↓ if empty
2. dead_fly_report.mat (centralized, from preprocessing or analyze_single_experiment)
      ↓ if not found
3. QPI_log_*.txt (legacy, written by plot_quadrant_preference_local)
      ↓ if not found
4. detect_dead_flies_posture() (runtime fallback)
```

This means:
- **New experiments:** `analyze_single_experiment_local.m` creates `dead_fly_report.mat` on first run. All subsequent compute calls find it at priority 2.
- **Legacy experiments:** QPI log files still work at priority 3. No reprocessing needed.
- **Standalone compute calls:** If called outside the orchestrator without `FlyAlive`, the function self-resolves via the fallback chain.

---

## Internal Helpers Still Present (Not Removed)

The old `get_protocol_labels_*()` and `detect_dead_flies()` / `parse_qpi_log()` nested functions are still physically present at the bottom of each file. They are no longer called by the main function body but remain as dead code for reference. They can be safely removed in a future cleanup pass.

---

## What Was NOT Changed

| Component | Status |
|-----------|--------|
| Plotting functions (`plot_*_local.m`) | Unchanged — still use their own protocol label logic |
| Batch summary scripts (`batch_*_summary.m`) | Unchanged |
| Batch plot scripts (`batch_plot_*.m`) | Unchanged |
| Preprocessing scripts (`batch_preprocessing_*_local.m`) | Unchanged — `dead_fly_report.mat` creation is handled by `analyze_single_experiment_local.m` for now |
| `compute_distance_travelled_local.m` | Unchanged — basic version without per-cycle summaries |
| `compute_latency_to_dark_local.m` | Unchanged — basic version |
| `compute_quadrant_preference_local.m` | Unchanged — basic version |
