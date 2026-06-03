function analyze_single_experiment_local(exp_path, opts)
% ANALYZE_SINGLE_EXPERIMENT_LOCAL - Full analysis with centralized dead fly detection
%
%   Runs dead fly detection once, saves dead_fly_report.mat, and passes
%   fly_alive to all downstream compute functions via the 'FlyAlive' parameter.

    analysis_dir = fullfile(exp_path, 'analysis');

    % Load filtered trx if available (from QC), otherwise use original
    filtered_trx_file = fullfile(analysis_dir, 'trx_filtered.mat');
    trx_file = fullfile(exp_path, 'trx.mat');

    if exist(filtered_trx_file, 'file')
        fprintf('      Using filtered trx (incomplete flies removed)\n');
        load(filtered_trx_file, 'trx');
    else
        load(trx_file, 'trx');
    end

    % Load preprocessing files
    arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    load(fullfile(analysis_dir, arena_files(end).name), 'arena_calib');
    all_masks = arena_calib.all_masks;

    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    load(fullfile(analysis_dir, led_files(end).name), 'LED_detector');

    LED_detector_thresh = struct();
    LED_detector_thresh.on_times = LED_detector.on_times;
    LED_detector_thresh.off_times = LED_detector.off_times;

    % Auto-extract calibration
    pixels_per_mm = extract_calibration_robust_local(exp_path, trx);
    opts.PixelsPerMM = pixels_per_mm;

    %% Centralized dead fly detection
    %  Run once, save, pass to all compute functions.
    dead_fly_file = fullfile(analysis_dir, 'dead_fly_report.mat');

    if exist(dead_fly_file, 'file')
        loaded = load(dead_fly_file, 'dead_report');
        dead_report = loaded.dead_report;
        fly_alive = dead_report.fly_alive;
        fprintf('      Loaded dead fly report: %d/%d dead\n', ...
            dead_report.num_dead, dead_report.num_flies);
    else
        fprintf('      Running dead fly detection...\n');
        [fly_alive, dead_report] = detect_dead_flies_posture(trx, LED_detector_thresh);
        save(dead_fly_file, 'dead_report');
        fprintf('      Dead fly report saved: %d/%d dead\n', ...
            dead_report.num_dead, dead_report.num_flies);
    end

    %% Run analyses (pass fly_alive via 'FlyAlive' parameter)
    distance_results = compute_distance_travelled_local(trx, LED_detector_thresh, opts);
    save(fullfile(analysis_dir, 'distance_results.mat'), 'distance_results');

    latency_results = compute_latency_to_dark_local(trx, all_masks, LED_detector_thresh, opts);
    save(fullfile(analysis_dir, 'latency_results.mat'), 'latency_results');

    quad_pref_results = compute_quadrant_preference_local(trx, all_masks, LED_detector_thresh, opts);
    save(fullfile(analysis_dir, 'quadrant_preference_results.mat'), 'quad_pref_results');
end
