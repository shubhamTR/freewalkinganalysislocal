function summary = summarize_tracking_qc_local(analysis_dir, varargin)
% SUMMARIZE_TRACKING_QC - Summary table and figure for tracking quality
%
% Loops through all experiments in a protocol folder, collects tracking
% QC statistics, and produces:
%   1. A MATLAB figure table (saved as PNG) with per-experiment stats
%   2. A summary raster figure showing track fragmentation across experiments
%
% USAGE:
%   summary = summarize_tracking_qc('/path/to/AnalysisData/P001')
%   summary = summarize_tracking_qc(analysis_dir, 'Protocol', 'P001')
%   summary = summarize_tracking_qc(analysis_dir, 'FrameTolerance', 30)
%
% NAME-VALUE PARAMETERS:
%   'Protocol'       — protocol folder name (default: '' = use analysis_dir directly)
%   'FrameTolerance' — frames tolerance for completeness (default: 30)
%   'FPS'            — frame rate (default: 30)
%   'SaveDir'        — where to save figures (default: analysis_dir)

    p = inputParser;
    addParameter(p, 'Protocol', '', @ischar);
    addParameter(p, 'FrameTolerance', 30, @isnumeric);
    addParameter(p, 'FPS', 30, @isnumeric);
    addParameter(p, 'SaveDir', '', @ischar);
    parse(p, varargin{:});

    frame_tol = p.Results.FrameTolerance;
    fps       = p.Results.FPS;
    save_dir  = p.Results.SaveDir;

    if isempty(save_dir)
        save_dir = analysis_dir;
    end

    % --- Find experiments ---
    if ~isempty(p.Results.Protocol)
        search_dir = fullfile(analysis_dir, p.Results.Protocol);
    else
        search_dir = analysis_dir;
    end

    exp_dirs = dir(fullfile(search_dir, '*_Rig*'));
    exp_dirs = exp_dirs([exp_dirs.isdir]);

    if isempty(exp_dirs)
        fprintf('No experiments found in %s\n', search_dir);
        summary = [];
        return;
    end

    fprintf('\n========================================\n');
    fprintf('TRACKING QC SUMMARY\n');
    fprintf('========================================\n');
    fprintf('Directory: %s\n', search_dir);
    fprintf('Experiments: %d\n', length(exp_dirs));
    fprintf('Frame tolerance: %d\n', frame_tol);
    fprintf('========================================\n\n');

    % --- Collect stats per experiment ---
    num_exp = length(exp_dirs);

    exp_names       = cell(num_exp, 1);
    total_tracks    = zeros(num_exp, 1);
    complete_tracks = zeros(num_exp, 1);
    removed_tracks  = zeros(num_exp, 1);
    fragmented_pairs = zeros(num_exp, 1);  % likely identity swaps
    total_frames    = zeros(num_exp, 1);
    pct_kept        = zeros(num_exp, 1);

    % For the raster figure: store per-fly frame spans
    all_fly_data = {};  % cell array of structs per experiment

    for i = 1:num_exp
        exp_path = fullfile(exp_dirs(i).folder, exp_dirs(i).name);
        exp_names{i} = exp_dirs(i).name;

        trx_file = fullfile(exp_path, 'trx.mat');
        if ~exist(trx_file, 'file')
            total_tracks(i) = 0;
            continue;
        end

        load(trx_file, 'trx');
        num_flies = length(trx);
        total_tracks(i) = num_flies;

        max_end = max([trx.endframe]);
        total_frames(i) = max_end;
        min_acceptable = max_end - frame_tol;

        % Classify each fly
        good = 0;
        bad = 0;
        swap_pairs = 0;
        fly_data = struct('firstframe', {}, 'endframe', {}, 'is_complete', {}, 'fly_id', {});

        for k = 1:num_flies
            fd.firstframe = trx(k).firstframe;
            fd.endframe = trx(k).endframe;
            fd.fly_id = k;

            is_complete = (trx(k).firstframe == 1) && (trx(k).endframe >= min_acceptable);
            fd.is_complete = is_complete;

            if is_complete
                good = good + 1;
            else
                bad = bad + 1;
            end

            fly_data(end+1) = fd;
        end

        complete_tracks(i) = good;
        removed_tracks(i) = bad;
        pct_kept(i) = 100 * good / num_flies;

        % Detect identity swap pairs: a fly ending early + another starting
        % near that frame (within 500 frames ~ 17 sec)
        SWAP_GAP = 500;
        early_enders = find([fly_data.is_complete] == false & [fly_data.firstframe] == 1);
        late_starters = find([fly_data.is_complete] == false & [fly_data.firstframe] > 1);

        for ee = 1:length(early_enders)
            end_frame = fly_data(early_enders(ee)).endframe;
            for ls = 1:length(late_starters)
                start_frame = fly_data(late_starters(ls)).firstframe;
                if abs(start_frame - end_frame) <= SWAP_GAP
                    swap_pairs = swap_pairs + 1;
                end
            end
        end
        fragmented_pairs(i) = swap_pairs;

        all_fly_data{i} = fly_data;
    end

    % --- Build summary struct ---
    summary = struct();
    summary.exp_names = exp_names;
    summary.total_tracks = total_tracks;
    summary.complete_tracks = complete_tracks;
    summary.removed_tracks = removed_tracks;
    summary.fragmented_pairs = fragmented_pairs;
    summary.total_frames = total_frames;
    summary.pct_kept = pct_kept;

    % --- Figure 1: Summary table ---
    plot_summary_table(summary, save_dir);

    % --- Figure 2: Fragmentation raster ---
    plot_fragmentation_raster(all_fly_data, exp_names, total_frames, fps, save_dir);

    fprintf('\nFigures saved to: %s\n\n', save_dir);
end

function plot_summary_table(summary, save_dir)
% PLOT_SUMMARY_TABLE - Render QC stats as a MATLAB figure table

    num_exp = length(summary.exp_names);

    % Colorblind-friendly palette (Wong 2011)
    color_good = [0.00 0.45 0.70];    % blue
    color_bad  = [0.90 0.62 0.00];    % orange
    color_warn = [0.80 0.47 0.65];    % reddish purple

    % Shorten experiment names for display (Genotype_Rig_Date)
    short_names = cell(num_exp, 1);
    for i = 1:num_exp
        parts = strsplit(summary.exp_names{i}, '_');
        if length(parts) >= 4
            short_names{i} = sprintf('%s_%s_%s', parts{1}, parts{2}, parts{3});
        else
            short_names{i} = summary.exp_names{i};
        end
    end

    % Build cell array for table data
    col_headers = {'Experiment', 'Total', 'Kept', 'Removed', 'Swaps', '% Kept', 'Status'};
    num_cols = length(col_headers);

    table_data = cell(num_exp, num_cols);
    row_colors = zeros(num_exp, 3);

    for i = 1:num_exp
        table_data{i, 1} = short_names{i};
        table_data{i, 2} = sprintf('%d', summary.total_tracks(i));
        table_data{i, 3} = sprintf('%d', summary.complete_tracks(i));
        table_data{i, 4} = sprintf('%d', summary.removed_tracks(i));
        table_data{i, 5} = sprintf('%d', summary.fragmented_pairs(i));
        table_data{i, 6} = sprintf('%.0f%%', summary.pct_kept(i));

        if summary.pct_kept(i) == 100
            table_data{i, 7} = 'Clean';
            row_colors(i,:) = color_good;
        elseif summary.pct_kept(i) >= 50
            table_data{i, 7} = 'Usable';
            row_colors(i,:) = color_bad;
        else
            table_data{i, 7} = 'Poor';
            row_colors(i,:) = color_warn;
        end
    end

    % --- Render as figure ---
    fig_height = max(400, 80 + num_exp * 28);
    fig = figure('Name', 'Tracking QC Summary', ...
                 'Position', [100 100 900 fig_height], ...
                 'Visible', 'off', 'Color', 'w');

    ax = axes('Position', [0.02 0.02 0.96 0.90], 'Visible', 'off');
    hold on;

    % Column positions (normalized x)
    col_x = [0.01, 0.28, 0.38, 0.46, 0.56, 0.64, 0.74];
    col_widths = [0.26, 0.08, 0.08, 0.08, 0.08, 0.08, 0.12];

    row_height = 1 / (num_exp + 2);  % +2 for header and padding
    header_y = 1 - row_height;

    % Draw header
    for c = 1:num_cols
        text(col_x(c), header_y, col_headers{c}, ...
            'FontSize', 10, 'FontWeight', 'bold', ...
            'VerticalAlignment', 'middle', 'Units', 'normalized');
    end

    % Header underline
    line([0 1], [header_y - row_height*0.4, header_y - row_height*0.4], ...
        'Color', 'k', 'LineWidth', 1.5);

    % Draw rows
    for i = 1:num_exp
        y = header_y - row_height * (i + 0.3);

        % Row background for poor experiments
        if summary.pct_kept(i) < 50
            rectangle('Position', [0, y - row_height*0.4, 1, row_height*0.8], ...
                'FaceColor', [1 0.95 0.90], 'EdgeColor', 'none');
        end

        for c = 1:num_cols
            if c == 7
                % Status column — color coded
                text(col_x(c), y, table_data{i, c}, ...
                    'FontSize', 9, 'Color', row_colors(i,:), ...
                    'FontWeight', 'bold', ...
                    'VerticalAlignment', 'middle', 'Units', 'normalized');
            else
                text(col_x(c), y, table_data{i, c}, ...
                    'FontSize', 9, 'Color', [0.1 0.1 0.1], ...
                    'VerticalAlignment', 'middle', 'Units', 'normalized');
            end
        end
    end

    % Title
    title_y = 1 - row_height * 0.2;
    text(0.5, title_y, 'Tracking QC Summary', ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'top', 'Units', 'normalized');

    % Totals row
    total_y = header_y - row_height * (num_exp + 1.5);
    line([0 1], [total_y + row_height*0.4, total_y + row_height*0.4], ...
        'Color', 'k', 'LineWidth', 1);

    text(col_x(1), total_y, 'TOTAL', 'FontSize', 10, 'FontWeight', 'bold', ...
        'VerticalAlignment', 'middle', 'Units', 'normalized');
    text(col_x(2), total_y, sprintf('%d', sum(summary.total_tracks)), ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'VerticalAlignment', 'middle', 'Units', 'normalized');
    text(col_x(3), total_y, sprintf('%d', sum(summary.complete_tracks)), ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'VerticalAlignment', 'middle', 'Units', 'normalized');
    text(col_x(4), total_y, sprintf('%d', sum(summary.removed_tracks)), ...
        'FontSize', 10, 'FontWeight', 'bold', ...
        'VerticalAlignment', 'middle', 'Units', 'normalized');

    xlim([0 1]); ylim([0 1]);

    % Save
    out_file = fullfile(save_dir, 'tracking_qc_table.png');
    saveas(fig, out_file);
    close(fig);
    fprintf('  Table saved: %s\n', out_file);
end

function plot_fragmentation_raster(all_fly_data, exp_names, total_frames, fps, save_dir)
% PLOT_FRAGMENTATION_RASTER - Overview of track spans across all experiments
%
%   Each experiment gets a horizontal strip. Within that strip, each fly
%   track is shown as a bar from firstframe to endframe.
%     - Blue:           complete tracks (kept)
%     - Orange:         incomplete tracks (removed)
%   Identity swap pairs are connected with dashed lines.

    % Colorblind-friendly palette (Wong 2011)
    color_complete   = [0.00 0.45 0.70];   % blue
    color_incomplete = [0.90 0.62 0.00];   % orange

    num_exp = length(all_fly_data);
    max_frames = max(total_frames);

    % Count max flies per experiment for sizing
    max_flies_per_exp = 0;
    for i = 1:num_exp
        max_flies_per_exp = max(max_flies_per_exp, length(all_fly_data{i}));
    end

    % Each experiment gets a vertical band
    band_height = max(2, max_flies_per_exp * 0.3);
    fig_height = max(500, 60 + num_exp * (band_height * 18 + 20));

    fig = figure('Name', 'Track Fragmentation Summary', ...
                 'Position', [50 50 1500 fig_height], ...
                 'Visible', 'off');
    hold on;

    y_offset = 0;
    y_ticks = [];
    y_labels = {};

    for i = num_exp:-1:1  % bottom to top
        fly_data = all_fly_data{i};
        num_flies = length(fly_data);
        nframes = total_frames(i);

        if num_flies == 0
            y_offset = y_offset + 2;
            continue;
        end

        % Sort flies by firstframe for cleaner visual
        [~, sort_idx] = sort([fly_data.firstframe]);
        fly_data = fly_data(sort_idx);

        for f = 1:num_flies
            fd = fly_data(f);

            % Normalize to max_frames for consistent x-axis
            x_start = fd.firstframe;
            x_end   = fd.endframe;

            y_pos = y_offset + (f - 1) * 0.3;

            if fd.is_complete
                bar_color = color_complete;
            else
                bar_color = color_incomplete;
            end

            % Draw bar
            rectangle('Position', [x_start, y_pos, x_end - x_start, 0.25], ...
                'FaceColor', bar_color, 'EdgeColor', 'none');
        end

        % Experiment label position
        y_mid = y_offset + (num_flies - 1) * 0.15;
        y_ticks(end+1) = y_mid;

        % Shorten name
        parts = strsplit(exp_names{i}, '_');
        if length(parts) >= 4
            short = sprintf('%s %s %s', parts{1}, parts{2}, parts{3});
        else
            short = exp_names{i};
        end
        kept = sum([fly_data.is_complete]);
        y_labels{end+1} = sprintf('%s (%d/%d)', short, kept, num_flies);

        % Separator line
        sep_y = y_offset - 0.3;
        plot([0 max_frames], [sep_y sep_y], '-', 'Color', [0.8 0.8 0.8], 'LineWidth', 0.5);

        y_offset = y_offset + num_flies * 0.3 + 1.5;
    end

    % Axis formatting
    xlim([0 max_frames]);
    ylim([-1, y_offset]);

    set(gca, 'YTick', y_ticks, 'YTickLabel', y_labels, 'FontSize', 8);

    % X-axis in seconds
    x_ticks_frames = linspace(0, max_frames, 8);
    x_ticks_sec = x_ticks_frames / fps;
    set(gca, 'XTick', x_ticks_frames, ...
        'XTickLabel', arrayfun(@(s) sprintf('%.0fs', s), x_ticks_sec, 'UniformOutput', false));

    xlabel('Time', 'FontSize', 12);
    ylabel('Experiment', 'FontSize', 12);
    title('Track Fragmentation Summary — All Experiments', 'FontSize', 14);

    % Legend
    h1 = patch([NaN NaN NaN NaN], [NaN NaN NaN NaN], color_complete, 'EdgeColor', 'none');
    h2 = patch([NaN NaN NaN NaN], [NaN NaN NaN NaN], color_incomplete, 'EdgeColor', 'none');
    legend([h1 h2], {'Complete track', 'Incomplete / fragment'}, ...
        'Location', 'northeast', 'FontSize', 10);

    box on; grid on;
    set(gca, 'GridAlpha', 0.15);

    % Save
    out_file = fullfile(save_dir, 'track_fragmentation_summary.png');
    saveas(fig, out_file);
    close(fig);
    fprintf('  Raster saved: %s\n', out_file);
end
