function dup_report = detect_duplicate_flies_local(trx, varargin)
% DETECT_DUPLICATE_FLIES - Flag fly pairs with near-identical positions
%
% Finds frames where two flies are within a configurable pixel distance
% of each other, suggesting the tracker may have assigned two IDs to the
% same physical fly. Reports proximity events across the full video.
%
% USAGE:
%   dup_report = detect_duplicate_flies(trx)
%   dup_report = detect_duplicate_flies(trx, 'DistThreshPx', 5, 'FPS', 30)
%
% INPUTS:
%   trx — trajectory struct array from registered_trx.mat
%
% NAME-VALUE PARAMETERS:
%   'DistThreshPx'  — max distance in pixels to flag as duplicate (default: 5)
%   'MinFrames'     — minimum number of close frames to flag a pair (default: 30)
%   'FPS'           — frame rate (default: 30)
%   'SaveDir'       — directory to save the diagnostic figure (default: '' = no save)
%   'ExpName'       — experiment name for the figure title (default: 'Experiment')
%
% OUTPUT:
%   dup_report — struct with fields:
%     .num_pairs_flagged      — number of fly pairs flagged
%     .pair_details           — struct array with per-pair info
%     .total_close_frames     — total close frames across all pairs
%     .has_duplicates         — true if any pairs were flagged
%     .dist_thresh_px         — threshold used

    p = inputParser;
    addParameter(p, 'DistThreshPx', 5, @isnumeric);
    addParameter(p, 'MinFrames', 30, @isnumeric);
    addParameter(p, 'FPS', 30, @isnumeric);
    addParameter(p, 'SaveDir', '', @ischar);
    addParameter(p, 'ExpName', 'Experiment', @ischar);
    parse(p, varargin{:});

    dist_thresh = p.Results.DistThreshPx;
    min_frames  = p.Results.MinFrames;
    fps         = p.Results.FPS;
    save_dir    = p.Results.SaveDir;
    exp_name    = p.Results.ExpName;

    num_flies = length(trx);
    max_endframe = max([trx.endframe]);

    fprintf('      Duplicate detection: %d flies, threshold = %g px, min = %d frames\n', ...
        num_flies, dist_thresh, min_frames);

    % --- Compare all fly pairs ---
    pair_details = struct('fly_i', {}, 'fly_j', {}, ...
                          'close_frames', {}, 'num_close', {}, ...
                          'mean_dist', {}, 'min_dist', {});

    for i = 1:num_flies
        for j = (i+1):num_flies
            % Determine overlapping frame range
            overlap_start = max(trx(i).firstframe, trx(j).firstframe);
            overlap_end   = min(trx(i).endframe, trx(j).endframe);

            if overlap_start > overlap_end
                continue;  % no temporal overlap
            end

            % Index into each fly's coordinate arrays
            idx_i_start = overlap_start - trx(i).firstframe + 1;
            idx_i_end   = overlap_end   - trx(i).firstframe + 1;
            idx_j_start = overlap_start - trx(j).firstframe + 1;
            idx_j_end   = overlap_end   - trx(j).firstframe + 1;

            x_i = trx(i).x(idx_i_start:idx_i_end);
            y_i = trx(i).y(idx_i_start:idx_i_end);
            x_j = trx(j).x(idx_j_start:idx_j_end);
            y_j = trx(j).y(idx_j_start:idx_j_end);

            % Euclidean distance between the two flies at each frame
            dist = sqrt((x_i - x_j).^2 + (y_i - y_j).^2);

            % Find frames where distance is below threshold (excluding NaN)
            close_mask = dist <= dist_thresh & ~isnan(dist);
            close_indices = find(close_mask);

            if length(close_indices) < min_frames
                continue;  % too few frames to be meaningful
            end

            % Convert to absolute frame numbers
            close_frames_abs = close_indices + overlap_start - 1;

            % Store result
            entry = struct();
            entry.fly_i = i;
            entry.fly_j = j;
            entry.close_frames = close_frames_abs;
            entry.num_close = length(close_frames_abs);
            entry.mean_dist = mean(dist(close_mask), 'omitnan');
            entry.min_dist = min(dist(close_mask));

            pair_details(end+1) = entry;
        end
    end

    % --- Console output ---
    if isempty(pair_details)
        total_close = 0;
        fprintf('      No duplicate positions detected\n');
    else
        total_close = sum([pair_details.num_close]);
        fprintf('      FLAGGED: %d fly pair(s) within %g px (%d total frames)\n', ...
            length(pair_details), dist_thresh, total_close);

        for p_idx = 1:length(pair_details)
            pd = pair_details(p_idx);
            dur_sec = pd.num_close / fps;
            pct = 100 * pd.num_close / max_endframe;
            fprintf('        Fly %d & Fly %d: %d frames (%.1f sec, %.1f%% of video), mean dist = %.2f px, min = %.2f px\n', ...
                pd.fly_i, pd.fly_j, pd.num_close, dur_sec, pct, pd.mean_dist, pd.min_dist);
        end
    end

    % --- Build report ---
    dup_report = struct();
    dup_report.num_pairs_flagged = length(pair_details);
    dup_report.pair_details = pair_details;
    dup_report.total_close_frames = total_close;
    dup_report.has_duplicates = ~isempty(pair_details);
    dup_report.dist_thresh_px = dist_thresh;
    dup_report.min_frames = min_frames;

    % --- Diagnostic figure ---
    if ~isempty(pair_details)
        plot_duplicate_diagnostic(trx, pair_details, max_endframe, fps, ...
            dist_thresh, exp_name, save_dir);
    end
end

function plot_duplicate_diagnostic(trx, pair_details, max_endframe, fps, ...
    dist_thresh, exp_name, save_dir)
% PLOT_DUPLICATE_DIAGNOSTIC - Visualize proximity events across fly pairs

    % Colorblind-friendly palette (Wong 2011)
    pair_colors = [
        0.00 0.45 0.70;   % blue
        0.90 0.62 0.00;   % orange
        0.00 0.62 0.45;   % teal
        0.80 0.47 0.65;   % reddish purple
        0.94 0.89 0.26;   % yellow
        0.34 0.71 0.91;   % sky blue
        ];

    num_pairs = length(pair_details);

    fig = figure('Name', 'Duplicate Fly Detection', ...
                 'Position', [100 100 1400 max(400, 120 + num_pairs * 80)], ...
                 'Visible', 'off');

    % --- Top panel: proximity frame markers on a timeline ---
    subplot(2, 1, 1);
    hold on;

    for p_idx = 1:num_pairs
        pd = pair_details(p_idx);
        c_idx = mod(p_idx - 1, size(pair_colors, 1)) + 1;

        frame_times = pd.close_frames / fps;
        y_val = p_idx * ones(size(frame_times));

        plot(frame_times, y_val, '|', 'Color', pair_colors(c_idx, :), ...
            'MarkerSize', 10, 'LineWidth', 1.5);
    end

    % Y-axis labels
    pair_labels = cell(num_pairs, 1);
    for p_idx = 1:num_pairs
        pd = pair_details(p_idx);
        pair_labels{p_idx} = sprintf('Fly %d & %d  (%d fr, %.1f px)', ...
            pd.fly_i, pd.fly_j, pd.num_close, pd.mean_dist);
    end

    set(gca, 'YTick', 1:num_pairs, 'YTickLabel', pair_labels);
    ylim([0.5, num_pairs + 0.5]);
    xlim([0, max_endframe / fps]);
    xlabel('Time (s)', 'FontSize', 11);
    ylabel('Fly Pair', 'FontSize', 11);
    title(sprintf('Proximity Events (<=%g px) - %s', dist_thresh, exp_name), ...
        'FontSize', 13, 'Interpreter', 'none');
    grid on; box on;

    % --- Bottom panel: spatial view of proximity positions ---
    subplot(2, 1, 2);
    hold on;

    % Plot all fly trajectories in light gray first
    for k = 1:length(trx)
        plot(trx(k).x, trx(k).y, '-', 'Color', [0.85 0.85 0.85], 'LineWidth', 0.3);
    end

    % Overlay proximity positions for each pair
    legend_handles = [];
    legend_entries = {};

    for p_idx = 1:num_pairs
        pd = pair_details(p_idx);
        c_idx = mod(p_idx - 1, size(pair_colors, 1)) + 1;

        fly_i = pd.fly_i;
        % Map close frames to fly_i's index space
        idx_i = pd.close_frames - trx(fly_i).firstframe + 1;
        valid = idx_i >= 1 & idx_i <= length(trx(fly_i).x);
        idx_i = idx_i(valid);

        h = scatter(trx(fly_i).x(idx_i), trx(fly_i).y(idx_i), 15, ...
            pair_colors(c_idx, :), 'filled', 'MarkerFaceAlpha', 0.6);

        legend_handles(end+1) = h;
        legend_entries{end+1} = sprintf('Fly %d & %d', pd.fly_i, pd.fly_j);
    end

    axis equal;
    xlabel('X (px)', 'FontSize', 11);
    ylabel('Y (px)', 'FontSize', 11);
    title('Spatial Location of Proximity Events', 'FontSize', 13);
    grid on; box on;

    if ~isempty(legend_handles)
        legend(legend_handles, legend_entries, 'Location', 'bestoutside', 'FontSize', 9);
    end

    % Save
    if ~isempty(save_dir)
        if ~exist(save_dir, 'dir')
            mkdir(save_dir);
        end
        out_file = fullfile(save_dir, 'duplicate_fly_detection.png');
        saveas(fig, out_file);
        fprintf('      Duplicate detection figure saved: %s\n', out_file);
    end

    close(fig);
end

% To call standalone:
% load('/path/to/experiment/registered_trx.mat', 'trx');
% dup_report = detect_duplicate_flies(trx, 'DistThreshPx', 5, 'FPS', 30, ...
%     'SaveDir', '/path/to/experiment/analysis', ...
%     'ExpName', 'L3A_Rig1_20260225_162932');
