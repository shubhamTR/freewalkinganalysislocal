function qc_report = validate_experiment_simple_local(exp_path, stage, opts)
% VALIDATE_EXPERIMENT_SIMPLE - Keep flies with nearly complete tracking
%
% Keeps fly if:
%   - firstframe == 1 (must start at beginning)
%   - endframe within TOLERANCE of max endframe (allows small variation)

    qc_report = struct();
    qc_report.passed = true;
    qc_report.checks = [];
    qc_report.warnings = {};
    qc_report.errors = {};
    qc_report.flies_removed = [];
    
    % Extract parameters
    if isfield(opts, 'MinFlies')
        min_flies = opts.MinFlies;
    else
        min_flies = 1;
    end
    
    if isfield(opts, 'MaxFlies')
        max_flies = opts.MaxFlies;
    else
        max_flies = 20;
    end
    
    % TOLERANCE: Allow flies to end within this many frames of the max
    % e.g., if max is 40635, accept flies ending at 40605 or later (within 30 frames)
    FRAME_TOLERANCE = 30;  % Adjust this as needed (30 frames = 1 second at 30 fps)
    
    %% Load trx
    trx_file = fullfile(exp_path, 'trx.mat');
    if ~exist(trx_file, 'file')
        qc_report.passed = false;
        qc_report.errors{end+1} = 'Missing trx.mat';
        return;
    end
    
    try
        load(trx_file, 'trx');
    catch ME
        qc_report.passed = false;
        qc_report.errors{end+1} = sprintf('Error loading trx: %s', ME.message);
        return;
    end
    
    num_flies_original = length(trx);
    
    %% Filter based on firstframe and endframe with tolerance
    analysis_dir = fullfile(exp_path, 'analysis');
    if ~exist(analysis_dir, 'dir')
        mkdir(analysis_dir);
    end
    
    % Get maximum endframe across all flies
    max_endframe = max([trx.endframe]);
    
    % Minimum acceptable endframe (with tolerance)
    min_acceptable_endframe = max_endframe - FRAME_TOLERANCE;
    
    fprintf('      Video frames: 1-%d (tolerance: ±%d frames)\n', max_endframe, FRAME_TOLERANCE);
    
    % Check each fly
    good_flies = [];
    bad_flies = [];
    
    for k = 1:num_flies_original
        % Fly is COMPLETE if:
        % 1. Starts at frame 1
        % 2. Ends within tolerance of max endframe
        starts_at_beginning = (trx(k).firstframe == 1);
        ends_near_end = (trx(k).endframe >= min_acceptable_endframe);
        
        is_complete = starts_at_beginning && ends_near_end;
        
        if is_complete
            good_flies = [good_flies, k];
        else
            bad_flies = [bad_flies, k];
            
            % Explain why it failed
            if ~starts_at_beginning
                reason = sprintf('starts at frame %d (not 1)', trx(k).firstframe);
            else
                frames_short = max_endframe - trx(k).endframe;
                reason = sprintf('ends at %d (-%d frames, beyond tolerance)', ...
                    trx(k).endframe, frames_short);
            end
            
            qc_report.warnings{end+1} = sprintf('Fly %d removed: %s', k, reason);
        end
    end
    
    % Filter if needed
    if ~isempty(bad_flies)
        fprintf('      Removing %d/%d flies:\n', length(bad_flies), num_flies_original);
        
        for i = 1:length(bad_flies)
            k = bad_flies(i);
            fprintf('        Fly %d: frames %d-%d', k, trx(k).firstframe, trx(k).endframe);
            
            if trx(k).firstframe ~= 1
                fprintf(' (late start)');
            end
            if trx(k).endframe < min_acceptable_endframe
                fprintf(' (early end, -%d frames)', max_endframe - trx(k).endframe);
            end
            fprintf('\n');
        end
        
        trx = trx(good_flies);
        qc_report.flies_removed = bad_flies;
        
        % Save filtered trx
        filtered_trx_file = fullfile(analysis_dir, 'trx_filtered.mat');
        save(filtered_trx_file, 'trx');
        fprintf('      ✓ Filtered trx saved: %d flies kept\n', length(good_flies));
    else
        fprintf('      ✓ All %d flies complete (1-%d)\n', num_flies_original, max_endframe);
    end

    num_flies = length(trx);

    %% Per-cycle track completeness
    % For each good fly and each LED cycle, compute the fraction of frames
    % with valid (non-NaN) x,y positions within on_times(c):off_times(c).
    % Saved as track_completeness_<exp>.mat for downstream compute functions.
    [~, exp_name] = fileparts(exp_path);
    completeness = compute_percycle_completeness(trx, good_flies, exp_path, analysis_dir, exp_name);
    qc_report.track_completeness = completeness;

    %% Generate tracking gap schematic (with per-cycle completeness panel)
    % Uses the ORIGINAL trx (before filtering) so removed flies are visible
    trx_original = load(trx_file, 'trx');
    plot_tracking_gaps(trx_original.trx, good_flies, bad_flies, max_endframe, ...
        exp_path, analysis_dir, completeness);

    %% Duplicate fly detection
    % Check for flies within proximity threshold (potential misidentification)
    fps = 30;
    if isfield(opts, 'FPS'), fps = opts.FPS; end

    dist_thresh = 2;
    if isfield(opts, 'DistThreshPx'), dist_thresh = opts.DistThreshPx; end
    min_dup_frames = 30;
    if isfield(opts, 'MinDupFrames'), min_dup_frames = opts.MinDupFrames; end

    % Run on ORIGINAL (unfiltered) trx so we catch overlapping fragments
    dup_report = detect_duplicate_flies_local(trx_original.trx, 'DistThreshPx', dist_thresh, ...
        'MinFrames', min_dup_frames, 'FPS', fps, ...
        'SaveDir', analysis_dir, 'ExpName', exp_name);
    qc_report.duplicate_report = dup_report;

    if dup_report.has_duplicates
        qc_report.warnings{end+1} = sprintf('%d fly pair(s) within proximity threshold', ...
            dup_report.num_pairs_flagged);
    end

    %% Check if enough flies remain
    if num_flies < min_flies
        qc_report.passed = false;
        qc_report.errors{end+1} = sprintf('Too few flies: %d after filtering (min %d)', num_flies, min_flies);
        return;
    end
    
    if num_flies > max_flies
        qc_report.passed = false;
        qc_report.errors{end+1} = sprintf('Too many flies: %d (max %d)', num_flies, max_flies);
        return;
    end
    
    %% Rest of validation
    
    % Arena calibration
    arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    if isempty(arena_files)
        qc_report.passed = false;
        qc_report.errors{end+1} = 'Missing arena_calib_*.mat';
        return;
    end
    
    % LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    if isempty(led_files)
        qc_report.passed = false;
        qc_report.errors{end+1} = 'Missing LED_detector_*.mat';
        return;
    end
    
    % Calibration
    if ~isfield(trx, 'pxpermm') || isempty(trx(1).pxpermm)
        calib_file = fullfile(exp_path, 'movie-calibration.mat');
        if ~exist(calib_file, 'file')
            qc_report.warnings{end+1} = 'No calibration (will use default)';
        end
    end
end

function completeness = compute_percycle_completeness(trx, good_flies, exp_path, analysis_dir, exp_name)
% COMPUTE_PERCYCLE_COMPLETENESS  Fraction of valid x,y frames per fly per LED cycle
%
%   For each good fly and each LED on/off window, computes:
%     valid_frac(f, c) = sum(~isnan(x(on:off))) / (off - on + 1)
%
%   Saves track_completeness_<exp>.mat with:
%     valid_frac       — [num_good_flies x num_cycles] fraction of valid frames
%     fly_ids_original — original trx indices of good flies
%     on_times, off_times — LED cycle boundaries used
%     num_cycles       — number of LED cycles
%     min_valid_frac   — recommended threshold (0.80)

    MIN_VALID_FRAC = 0.80;  % Default threshold: 80% valid frames required

    completeness = struct();
    completeness.valid_frac = [];
    completeness.fly_ids_original = good_flies;
    completeness.min_valid_frac = MIN_VALID_FRAC;

    % Load LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    if isempty(led_files)
        fprintf('      No LED_detector — skipping per-cycle completeness\n');
        return;
    end

    led_data = load(fullfile(analysis_dir, led_files(end).name));
    if isfield(led_data, 'LED_detector')
        on_times  = double(led_data.LED_detector.on_times(:)');
        off_times = double(led_data.LED_detector.off_times(:)');
    elseif isfield(led_data, 'LED_detector_thresh')
        on_times  = double(led_data.LED_detector_thresh.on_times(:)');
        off_times = double(led_data.LED_detector_thresh.off_times(:)');
    else
        fprintf('      Unrecognized LED detector format — skipping per-cycle completeness\n');
        return;
    end

    num_cycles = min(length(on_times), length(off_times));
    num_good = length(trx);

    valid_frac = ones(num_good, num_cycles);  % default 1.0 (fully valid)
    nan_frame_count = zeros(num_good, num_cycles, 'double');
    total_frame_count = zeros(num_good, num_cycles, 'double');
    nan_frame_indices = cell(num_good, num_cycles);  % actual frame numbers with NaN

    for f = 1:num_good
        npts = length(trx(f).x);
        for c = 1:num_cycles
            fr_on  = on_times(c);
            fr_off = min(off_times(c), npts);
            if fr_on > npts || fr_on > fr_off
                valid_frac(f, c) = 0;
                total_frame_count(f, c) = off_times(c) - on_times(c) + 1;
                nan_frame_count(f, c) = total_frame_count(f, c);
                nan_frame_indices{f, c} = (fr_on:off_times(c))';
                continue;
            end

            x_seg = trx(f).x(fr_on:fr_off);
            y_seg = trx(f).y(fr_on:fr_off);
            n_total = length(x_seg);
            nan_mask = isnan(x_seg) | isnan(y_seg);
            n_nan = sum(nan_mask);

            total_frame_count(f, c) = n_total;
            nan_frame_count(f, c) = n_nan;
            valid_frac(f, c) = (n_total - n_nan) / max(n_total, 1);

            if n_nan > 0
                % Store absolute frame numbers (1-based) where NaN occurs
                nan_frame_indices{f, c} = fr_on - 1 + find(nan_mask);
            else
                nan_frame_indices{f, c} = [];
            end
        end
    end

    completeness.valid_frac = valid_frac;
    completeness.nan_frame_count = nan_frame_count;
    completeness.total_frame_count = total_frame_count;
    completeness.nan_frame_indices = nan_frame_indices;
    completeness.on_times = on_times(1:num_cycles);
    completeness.off_times = off_times(1:num_cycles);
    completeness.num_cycles = num_cycles;
    completeness.fly_ids_original = good_flies;
    completeness.min_valid_frac = MIN_VALID_FRAC;

    % Count flagged fly-cycle pairs
    n_flagged = sum(valid_frac(:) < MIN_VALID_FRAC);
    n_total_pairs = numel(valid_frac);
    min_val = min(valid_frac(:));

    fprintf('      Per-cycle completeness: %d/%d fly-cycle pairs below %.0f%% threshold', ...
        n_flagged, n_total_pairs, MIN_VALID_FRAC * 100);
    if n_flagged > 0
        fprintf(' (worst: %.1f%%)', min_val * 100);
    end
    fprintf('\n');

    % Save .mat
    mat_file = fullfile(analysis_dir, sprintf('track_completeness_%s.mat', exp_name));
    save(mat_file, '-struct', 'completeness');
    fprintf('      Track completeness saved: %s\n', mat_file);
end


function plot_tracking_gaps(trx, good_flies, bad_flies, max_endframe, exp_path, analysis_dir, completeness)
% PLOT_TRACKING_GAPS - Two-panel figure: whole-experiment raster + per-cycle heatmap
%
%   Panel 1: Horizontal raster showing tracked vs missing frames (full recording)
%     - Blue:   tracked frames (valid x/y)
%     - Orange: NaN gaps within the trajectory span
%     - Gray:   frames outside the fly's firstframe-endframe range
%     Removed flies (bad_flies) are marked in reddish purple.
%
%   Panel 2: Per-cycle completeness heatmap (good flies only)
%     - Color = fraction of valid frames per LED cycle
%     - Red cells = below threshold (80%)

    num_flies = length(trx);
    if num_flies == 0, return; end

    % Colorblind-friendly palette (Wong 2011)
    color_tracked = [0.00 0.45 0.70];   % blue
    color_gap     = [0.90 0.62 0.00];   % orange
    color_nodata  = [0.85 0.85 0.85];   % gray

    % Build a status matrix: 0 = no data, 1 = tracked, 2 = NaN gap
    MAX_COLS = 2000;
    if max_endframe > MAX_COLS
        bin_size = ceil(max_endframe / MAX_COLS);
        num_bins = ceil(max_endframe / bin_size);
    else
        bin_size = 1;
        num_bins = max_endframe;
    end

    status = zeros(num_flies, num_bins, 'uint8');
    nan_counts = zeros(num_flies, 1);

    for k = 1:num_flies
        f1 = trx(k).firstframe;
        fe = trx(k).endframe;
        npts = length(trx(k).x);

        for b = 1:num_bins
            frame_start = (b - 1) * bin_size + 1;
            frame_end   = min(b * bin_size, max_endframe);

            if frame_end < f1 || frame_start > fe
                status(k, b) = 0;
                continue;
            end

            idx_start = max(1, frame_start - f1 + 1);
            idx_end   = min(npts, frame_end - f1 + 1);

            if idx_start > npts || idx_end < 1
                status(k, b) = 0;
                continue;
            end

            x_slice = trx(k).x(idx_start:idx_end);
            nan_frac = sum(isnan(x_slice)) / length(x_slice);

            if nan_frac > 0.5
                status(k, b) = 2;
            else
                status(k, b) = 1;
            end
        end

        nan_counts(k) = sum(isnan(trx(k).x));
    end

    % Build RGB image for panel 1
    img = zeros(num_flies, num_bins, 3);
    for ch = 1:3
        layer = zeros(num_flies, num_bins);
        layer(status == 0) = color_nodata(ch);
        layer(status == 1) = color_tracked(ch);
        layer(status == 2) = color_gap(ch);
        img(:,:,ch) = layer;
    end

    % --- Determine layout ---
    [~, exp_name] = fileparts(exp_path);
    has_completeness = ~isempty(completeness) && ~isempty(completeness.valid_frac);

    if has_completeness
        num_good = size(completeness.valid_frac, 1);
        num_cycles = completeness.num_cycles;
        % Two-panel figure
        fig_height = max(500, 80 + num_flies * 24 + num_good * 24);
        fig = figure('Name', 'Tracking Gaps + Completeness', ...
                     'Position', [100 50 1400 fig_height], ...
                     'Visible', 'off');

        % --- Panel 1: whole-experiment raster ---
        ax1 = subplot(2, 1, 1);
    else
        fig = figure('Name', 'Tracking Gap Schematic', ...
                     'Position', [100 100 1200 max(300, 50 + num_flies * 28)], ...
                     'Visible', 'off');
        ax1 = gca;
    end

    imagesc(ax1, img);
    hold(ax1, 'on');

    for k = 1:num_flies - 1
        plot(ax1, [0.5, num_bins + 0.5], [k + 0.5, k + 0.5], 'k-', 'LineWidth', 0.3);
    end

    % Y-axis labels
    y_labels = cell(num_flies, 1);
    for k = 1:num_flies
        nan_pct = 100 * nan_counts(k) / max(1, trx(k).endframe - trx(k).firstframe + 1);
        if ismember(k, bad_flies)
            y_labels{k} = sprintf('Fly %d  x  [%d-%d] %.1f%% NaN', ...
                k, trx(k).firstframe, trx(k).endframe, nan_pct);
        else
            y_labels{k} = sprintf('Fly %d  [%d-%d] %.1f%% NaN', ...
                k, trx(k).firstframe, trx(k).endframe, nan_pct);
        end
    end

    set(ax1, 'YTick', 1:num_flies, 'YTickLabel', y_labels, 'TickLabelInterpreter', 'tex');

    for k = 1:num_flies
        if ismember(k, bad_flies)
            ax1.YAxis.TickLabels{k} = ['\color[rgb]{0.80,0.47,0.65}' y_labels{k}];
        end
    end

    num_ticks = min(10, num_bins);
    tick_positions = round(linspace(1, num_bins, num_ticks));
    tick_labels_fr = arrayfun(@(b) sprintf('%d', (b-1)*bin_size + 1), tick_positions, 'UniformOutput', false);
    set(ax1, 'XTick', tick_positions, 'XTickLabel', tick_labels_fr);

    xlabel(ax1, 'Frame', 'FontSize', 11);
    ylabel(ax1, 'Fly ID (original trx index)', 'FontSize', 11);
    title(ax1, sprintf('Tracking Gaps — %s  (%d flies, %d frames)', ...
        exp_name, num_flies, max_endframe), ...
        'FontSize', 12, 'Interpreter', 'none');

    % Legend for panel 1
    legend_x = num_bins * 0.82;
    legend_y = -0.8;
    patch_w = num_bins * 0.03;
    annotation_colors = {color_tracked, color_gap, color_nodata};
    annotation_labels = {'Tracked', 'NaN gap', 'No data'};
    for i = 1:3
        rectangle(ax1, 'Position', [legend_x + (i-1)*num_bins*0.06, legend_y, patch_w, 0.6], ...
            'FaceColor', annotation_colors{i}, 'EdgeColor', 'k');
        text(ax1, legend_x + (i-1)*num_bins*0.06 + patch_w + num_bins*0.005, legend_y + 0.3, ...
            annotation_labels{i}, 'FontSize', 9, 'VerticalAlignment', 'middle');
    end

    hold(ax1, 'off');

    % --- Panel 2: per-cycle completeness heatmap (good flies only) ---
    if has_completeness
        ax2 = subplot(2, 1, 2);

        vf = completeness.valid_frac;  % [num_good x num_cycles]
        thresh = completeness.min_valid_frac;

        imagesc(ax2, vf);
        colormap(ax2, parula);
        caxis(ax2, [0 1]);
        cb = colorbar(ax2);
        cb.Label.String = 'Valid frame fraction';
        cb.Label.FontSize = 10;
        hold(ax2, 'on');

        % Mark cells below threshold with red border
        [bad_f, bad_c] = find(vf < thresh);
        for bi = 1:length(bad_f)
            rectangle(ax2, 'Position', [bad_c(bi)-0.5, bad_f(bi)-0.5, 1, 1], ...
                'EdgeColor', [0.9 0.1 0.1], 'LineWidth', 1.5);
        end

        % Grid lines
        for k = 1:num_good - 1
            plot(ax2, [0.5, num_cycles + 0.5], [k + 0.5, k + 0.5], ...
                'Color', [0.5 0.5 0.5], 'LineWidth', 0.2);
        end

        % Y-axis: good fly IDs
        fly_labels = arrayfun(@(i) sprintf('Fly %d', good_flies(i)), 1:num_good, 'UniformOutput', false);
        set(ax2, 'YTick', 1:num_good, 'YTickLabel', fly_labels, 'FontSize', 8);

        % X-axis: cycle numbers (show every Nth to avoid clutter)
        if num_cycles > 30
            xtick_step = 5;
        else
            xtick_step = 1;
        end
        set(ax2, 'XTick', 1:xtick_step:num_cycles);

        xlabel(ax2, 'LED Cycle', 'FontSize', 11);
        ylabel(ax2, 'Good Fly ID', 'FontSize', 11);

        n_flagged = sum(vf(:) < thresh);
        title(ax2, sprintf('Per-Cycle Track Completeness — %d/%d pairs below %.0f%% threshold', ...
            n_flagged, numel(vf), thresh * 100), ...
            'FontSize', 12, 'Interpreter', 'none');

        hold(ax2, 'off');
    end

    % Save
    out_file = fullfile(analysis_dir, 'tracking_gaps.png');
    exportgraphics(fig, out_file, 'Resolution', 200);
    savefig(fig, fullfile(analysis_dir, 'tracking_gaps.fig'));
    close(fig);

    fprintf('      Tracking gap schematic saved: %s\n', out_file);
end

% To call:
% For specific experiment
% exp_path = '/Users/rathores/Documents/2026/AnalysisData/P001/L3A_Rig1_20260225_162932';
% opts.MinFlies = 1;
% opts.MaxFlies = 15;
% qc_report = validate_experiment_simple_local(exp_path, 'pre_analysis', opts);

% To loop through all experiments
% exp_dirs = dir('/Users/rathores/Documents/2026/AnalysisData/P001/*_Rig*');
% exp_dirs = exp_dirs([exp_dirs.isdir]);
% for i = 1:length(exp_dirs)
%     fprintf('\n--- %s ---\n', exp_dirs(i).name);
%     qc_report = validate_experiment_simple_local(fullfile(exp_dirs(i).folder, exp_dirs(i).name), 'pre_analysis', opts);
% end