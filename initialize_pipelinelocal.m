%% initialize_pipeline.m
% =========================================================================
%  FREEWALKING ANALYSIS PIPELINE (LOCAL) — Full initialization script
% =========================================================================
%
%  Runs the complete pipeline from start to finish:
%    Step 1:  Copy experiments from network to local
%    Step 2:  Validate fly counts
%    Step 3:  Preprocess (arena calibration + LED detection)
%    Step 4:  Per-experiment analysis with QC (distance, latency, QPI)
%    Step 5:  Per-experiment metrics (QPI summary, distance, latency,
%             distance-to-safe, speed)
%    Step 6:  Per-experiment plots (QPI, distance, latency, speed)
%    Step 7:  Per-genotype summaries (speed, optomotor, probe visits,
%             cumulative occupancy)
%    Step 8:  Spatial analysis (transit density)
%    Step 9:  Onset velocity traces
%    Step 10: Cross-protocol comparisons
%
%  USAGE:
%    1. Set the parameters in Section 0 below
%    2. Run: >> initialize_pipeline
%
%  NOTES:
%    - Step 3 requires user interaction (clicking 5 arena points) for the
%      first experiment. Remaining experiments reuse the calibration.
%    - Each step is independent. Set SKIP flags below to skip steps.
%    - Set RECOMPUTE_ALL = true to force reprocessing.
%    - The pipeline is incremental: already-processed experiments are skipped.
%    - Uses trx.mat (FlyTracker native output) as input data.
%
%  DATA SOURCE: trx.mat (FlyTracker)
%  PROTOCOL CONFIG: get_protocol_config.m (shared, centralized)
%  DEAD FLY DETECTION: detect_dead_flies_posture.m (centralized)
% =========================================================================

%% 0. CONFIGURATION
% =========================================================================

% --- Paths ---
NETWORK = '/Volumes/ReiserLab/Shubham/Projects/Feature learning/2026/board4/videos';    % Network source
LOCAL   = '/Users/rathores/Documents/analysisdatalocal'; % Local destination

% --- Pipeline parameters ---
FRAME_RATE    = 30;     % Video frame rate (fps)
MIN_FLIES     = 1;      % Minimum acceptable fly count
MAX_FLIES     = 15;     % Maximum acceptable fly count
RECOMPUTE_ALL = false;  % true = reprocess everything; false = skip already-done

% --- Skip flags (set to true to skip individual steps) ---
SKIP_COPY          = false;   % Step 1: Network copy
SKIP_VALIDATE      = false;   % Step 2: Fly count validation
SKIP_PREPROCESS    = false;   % Step 3: Arena calibration + LED detection
SKIP_QC_ANALYSIS   = false;   % Step 4: Per-experiment analysis with QC
SKIP_METRICS       = false;   % Step 5: Batch metric computation
SKIP_EXP_PLOTS     = false;   % Step 6: Per-experiment plots
SKIP_GENO_SUMMARIES = false;  % Step 7: Per-genotype summaries
SKIP_SPATIAL       = false;   % Step 8: Transit density
SKIP_ONSET_VEL     = false;   % Step 9: Onset velocity
SKIP_PROTOCOL_COMP = false;   % Step 10: Cross-protocol comparisons

% =========================================================================
% Remove conflicting toolbox paths if needed
try rmpath('/Users/rathores/Documents/MATLAB/JAABA/spaceTime/toolbox/external/other'); catch; end

fprintf('\n');
fprintf('================================================================\n');
fprintf('  FREEWALKING ANALYSIS PIPELINE (LOCAL)\n');
fprintf('  %s\n', datestr(now));
fprintf('================================================================\n');
fprintf('  Network:    %s\n', NETWORK);
fprintf('  Local:      %s\n', LOCAL);
fprintf('  Data src:   trx.mat (FlyTracker)\n');
fprintf('  FPS:        %d\n', FRAME_RATE);
fprintf('  Flies:      %d-%d\n', MIN_FLIES, MAX_FLIES);
fprintf('  Recompute:  %s\n', mat2str(RECOMPUTE_ALL));
fprintf('================================================================\n\n');

step_log = {};
step_time = [];
t_pipeline = tic;

%% 1. COPY FROM NETWORK
% =========================================================================
% Incrementally copies new experiments from the network drive.
% Parses folder names and reorganizes into Protocol/Genotype_Rig_Date_Time/.
% Copies: trx.mat, movie-bg.mat, movie-calibration.mat, movie-params.mat.

if ~SKIP_COPY
    fprintf('=== STEP 1: Copy from network ===\n');
    tic;
    try
        [nCopied, nFailed, nSkipped] = copy_and_organize_flydisco_local(NETWORK, LOCAL);
        fprintf('  Copied: %d | Skipped: %d | Failed: %d\n', nCopied, nSkipped, nFailed);
        step_log{end+1} = sprintf('Step 1  Copy: %d new, %d skipped', nCopied, nSkipped);
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        step_log{end+1} = 'Step 1  Copy: FAILED';
    end
    step_time(end+1) = toc;
else
    fprintf('=== STEP 1: Copy — SKIPPED ===\n');
    step_log{end+1} = 'Step 1  Copy: SKIPPED'; step_time(end+1) = 0;
end
fprintf('\n');

%% 2. VALIDATE FLY COUNTS
% =========================================================================
% Informational check of fly counts across all experiments.

if ~SKIP_VALIDATE
    fprintf('=== STEP 2: Validate fly counts ===\n');
    tic;
    try
        validate_reorganized_experiments_local(LOCAL, ...
            'MinFlies', MIN_FLIES, 'MaxFlies', MAX_FLIES);
        step_log{end+1} = 'Step 2  Validate: OK';
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        step_log{end+1} = 'Step 2  Validate: FAILED';
    end
    step_time(end+1) = toc;
else
    fprintf('=== STEP 2: Validate — SKIPPED ===\n');
    step_log{end+1} = 'Step 2  Validate: SKIPPED'; step_time(end+1) = 0;
end
fprintf('\n');

%% 3. PREPROCESS (Arena calibration + LED detection)
% =========================================================================
% Manual 5-point click on first experiment, reused for remaining.
% Saves arena_calib_*.mat and LED_detector_*.mat per experiment.

if ~SKIP_PREPROCESS
    fprintf('=== STEP 3: Preprocessing ===\n');
    fprintf('  NOTE: You will click 5 points on the first experiment.\n');
    fprintf('  Press Enter when ready...\n');
    pause;
    tic;
    try
        batch_preprocessing_manual_local(LOCAL, 'RecomputeAll', RECOMPUTE_ALL);
        step_log{end+1} = 'Step 3  Preprocess: OK';
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        step_log{end+1} = 'Step 3  Preprocess: FAILED';
    end
    step_time(end+1) = toc;
else
    fprintf('=== STEP 3: Preprocess — SKIPPED ===\n');
    step_log{end+1} = 'Step 3  Preprocess: SKIPPED'; step_time(end+1) = 0;
end
fprintf('\n');

%% 4. PER-EXPERIMENT ANALYSIS WITH QC
% =========================================================================
% For each experiment: QC (track completeness, duplicates, dead flies)
% then compute distance, latency, QPI. Saves dead_fly_report.mat.

if ~SKIP_QC_ANALYSIS
    fprintf('=== STEP 4: Per-experiment analysis with QC ===\n');
    tic;
    try
        batch_analyze_experiments_with_qc_local(LOCAL, ...
            'RecomputeAll', RECOMPUTE_ALL, ...
            'MinFlies', MIN_FLIES, ...
            'MaxFlies', MAX_FLIES, ...
            'FPS', FRAME_RATE);
        step_log{end+1} = 'Step 4  QC + Analysis: OK';
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        step_log{end+1} = 'Step 4  QC + Analysis: FAILED';
    end
    step_time(end+1) = toc;
else
    fprintf('=== STEP 4: QC + Analysis — SKIPPED ===\n');
    step_log{end+1} = 'Step 4  QC + Analysis: SKIPPED'; step_time(end+1) = 0;
end
fprintf('\n');

%% 5. BATCH METRIC COMPUTATION
% =========================================================================
% Computes per-cycle summaries for all metrics across all protocols:
%   - QPI summary, distance, latency, distance-to-safe, speed

if ~SKIP_METRICS
    fprintf('=== STEP 5: Batch metric computation ===\n');
    tic;

    metric_scripts = {'batch_QPI_summary', 'batch_distance_summary', ...
        'batch_latency_summary', 'batch_distance_to_safe_summary', 'run_speed'};

    n_ok = 0;
    for mi = 1:length(metric_scripts)
        fprintf('  [%d/%d] %s\n', mi, length(metric_scripts), metric_scripts{mi});
        try
            close all force;
            run_isolated(metric_scripts{mi});
            n_ok = n_ok + 1;
        catch ME
            fprintf('    FAILED: %s\n', ME.message);
        end
    end

    step_log{end+1} = sprintf('Step 5  Metrics: %d/%d OK', n_ok, length(metric_scripts));
    step_time(end+1) = toc;
else
    fprintf('=== STEP 5: Metrics — SKIPPED ===\n');
    step_log{end+1} = 'Step 5  Metrics: SKIPPED'; step_time(end+1) = 0;
end
fprintf('\n');

%% 6. PER-EXPERIMENT PLOTS
% =========================================================================
% Generates detailed plots for each experiment:
%   QPI bar plots, distance 3-panel, latency 3-panel, speed traces

if ~SKIP_EXP_PLOTS
    fprintf('=== STEP 6: Per-experiment plots ===\n');
    tic;

    plot_scripts = {'batch_plot_QPI', 'batch_plot_distance', ...
        'batch_plot_latency', 'batch_plot_speed'};

    n_ok = 0;
    for pi = 1:length(plot_scripts)
        fprintf('  [%d/%d] %s\n', pi, length(plot_scripts), plot_scripts{pi});
        try
            close all force;
            run_isolated(plot_scripts{pi});
            n_ok = n_ok + 1;
        catch ME
            fprintf('    FAILED: %s\n', ME.message);
        end
    end

    step_log{end+1} = sprintf('Step 6  Exp plots: %d/%d OK', n_ok, length(plot_scripts));
    step_time(end+1) = toc;
else
    fprintf('=== STEP 6: Exp plots — SKIPPED ===\n');
    step_log{end+1} = 'Step 6  Exp plots: SKIPPED'; step_time(end+1) = 0;
end
fprintf('\n');

%% 7. PER-GENOTYPE SUMMARIES
% =========================================================================
% Speed overlays, optomotor analysis, probe visits, cumulative occupancy.
% Applies to place learning protocols (P003, P005-P010).

if ~SKIP_GENO_SUMMARIES
    fprintf('=== STEP 7: Per-genotype summaries ===\n');
    tic;

    geno_scripts = {'summary_speed', ...
        'analyze_optomotor', 'plot_optomotor_trajectories', ...
        'analyze_probe_visits', 'cumulative_occupancy'};

    n_ok = 0;
    for gi = 1:length(geno_scripts)
        fprintf('  [%d/%d] %s\n', gi, length(geno_scripts), geno_scripts{gi});
        try
            close all force;
            run_isolated(geno_scripts{gi});
            n_ok = n_ok + 1;
        catch ME
            fprintf('    FAILED: %s\n', ME.message);
        end
    end

    step_log{end+1} = sprintf('Step 7  Geno summaries: %d/%d OK', n_ok, length(geno_scripts));
    step_time(end+1) = toc;
else
    fprintf('=== STEP 7: Geno summaries — SKIPPED ===\n');
    step_log{end+1} = 'Step 7  Geno summaries: SKIPPED'; step_time(end+1) = 0;
end
fprintf('\n');

%% 8. SPATIAL ANALYSIS
% =========================================================================
% Transit density heatmaps across arena regions.

if ~SKIP_SPATIAL
    fprintf('=== STEP 8: Spatial analysis (transit density) ===\n');
    tic;
    try
        close all force;
        run_isolated('run_transit_density');
        step_log{end+1} = 'Step 8  Transit density: OK';
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        step_log{end+1} = 'Step 8  Transit density: FAILED';
    end
    step_time(end+1) = toc;
else
    fprintf('=== STEP 8: Spatial — SKIPPED ===\n');
    step_log{end+1} = 'Step 8  Transit density: SKIPPED'; step_time(end+1) = 0;
end
fprintf('\n');

%% 9. ONSET VELOCITY TRACES
% =========================================================================
% Peri-stimulus velocity traces aligned to LED onset.

if ~SKIP_ONSET_VEL
    fprintf('=== STEP 9: Onset velocity traces ===\n');
    tic;
    try
        close all force;
        run_isolated('batch_onset_velocity');
        step_log{end+1} = 'Step 9  Onset velocity: OK';
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        step_log{end+1} = 'Step 9  Onset velocity: FAILED';
    end
    step_time(end+1) = toc;
else
    fprintf('=== STEP 9: Onset velocity — SKIPPED ===\n');
    step_log{end+1} = 'Step 9  Onset velocity: SKIPPED'; step_time(end+1) = 0;
end
fprintf('\n');

%% 10. CROSS-PROTOCOL COMPARISONS
% =========================================================================
% Overlay plots comparing metrics across protocols (e.g., P008 vs P010).

if ~SKIP_PROTOCOL_COMP
    fprintf('=== STEP 10: Cross-protocol comparisons ===\n');
    tic;
    try
        close all force;
        run_isolated('plot_protocol_comparison');
        step_log{end+1} = 'Step 10 Protocol comparison: OK';
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
        step_log{end+1} = 'Step 10 Protocol comparison: FAILED';
    end
    step_time(end+1) = toc;
else
    fprintf('=== STEP 10: Protocol comparison — SKIPPED ===\n');
    step_log{end+1} = 'Step 10 Protocol comparison: SKIPPED'; step_time(end+1) = 0;
end
fprintf('\n');

%% FINAL REPORT
% =========================================================================
elapsed = toc(t_pipeline);
close all force;

fprintf('================================================================\n');
fprintf('  PIPELINE COMPLETE — %s\n', datestr(now));
fprintf('================================================================\n');
for i = 1:length(step_log)
    fprintf('  %-48s  (%5.1f s)\n', step_log{i}, step_time(i));
end
fprintf('  %-48s  (%5.1f s)\n', 'TOTAL', elapsed);
fprintf('================================================================\n');
fprintf('  Data:   %s\n', LOCAL);
fprintf('  Logs:   %s/Logs/\n', LOCAL);
fprintf('================================================================\n\n');


%% ========================================================================
function run_isolated(script_name)
% RUN_ISOLATED  Execute a script inside its own function workspace
%   Prevents child script's clear/clc from wiping parent variables.
    try rmpath('/Users/rathores/Documents/MATLAB/JAABA/spaceTime/toolbox/external/other'); catch; end
    eval(script_name);
end
