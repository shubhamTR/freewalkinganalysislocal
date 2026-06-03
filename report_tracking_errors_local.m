function report = report_tracking_errors_local(analysis_dir, varargin)
% REPORT_TRACKING_ERRORS - Table of fragmented tracks with frame numbers
%
% Identifies identity swap pairs (one track ends, another starts nearby)
% and renders as a MATLAB figure table with frame numbers.
%
% USAGE:
%   report = report_tracking_errors('/path/to/AnalysisData/P001')
%   report = report_tracking_errors(analysis_dir, 'FrameTolerance', 30)

    p = inputParser;
    addParameter(p, 'FrameTolerance', 30, @isnumeric);
    addParameter(p, 'SwapGap', 500, @isnumeric);  % max frame gap for swap pair
    addParameter(p, 'FPS', 30, @isnumeric);
    addParameter(p, 'SaveDir', '', @ischar);
    parse(p, varargin{:});

    frame_tol = p.Results.FrameTolerance;
    swap_gap  = p.Results.SwapGap;
    fps       = p.Results.FPS;
    save_dir  = p.Results.SaveDir;
    if isempty(save_dir), save_dir = analysis_dir; end

    % --- Find experiments ---
    exp_dirs = dir(fullfile(analysis_dir, '*_Rig*'));
    exp_dirs = exp_dirs([exp_dirs.isdir]);

    if isempty(exp_dirs)
        fprintf('No experiments found.\n');
        report = [];
        return;
    end

    fprintf('\n========================================\n');
    fprintf('TRACKING ERROR REPORT\n');
    fprintf('========================================\n\n');

    % --- Collect all errors across experiments ---
    % Table rows: Experiment | Fly ID | Frames | Duration | Type | Swap Partner
    rows = struct('experiment', {}, 'fly_id', {}, 'firstframe', {}, ...
                  'endframe', {}, 'duration_sec', {}, 'error_type', {}, ...
                  'swap_partner', {}, 'gap_frames', {});

    for i = 1:length(exp_dirs)
        exp_path = fullfile(exp_dirs(i).folder, exp_dirs(i).name);
        exp_name = exp_dirs(i).name;

        trx_file = fullfile(exp_path, 'trx.mat');
        if ~exist(trx_file, 'file'), continue; end

        load(trx_file, 'trx');
        num_flies = length(trx);
        max_end = max([trx.endframe]);
        min_acceptable = max_end - frame_tol;

        % Find incomplete flies
        incomplete = [];
        for k = 1:num_flies
            is_complete = (trx(k).firstframe == 1) && (trx(k).endframe >= min_acceptable);
            if ~is_complete
                incomplete = [incomplete, k];
            end
        end

        if isempty(incomplete), continue; end

        % Classify each incomplete fly and find swap partners
        for idx = 1:length(incomplete)
            k = incomplete(idx);

            % Determine error type
            late_start = trx(k).firstframe > 1;
            early_end  = trx(k).endframe < min_acceptable;

            if late_start && early_end
                err_type = 'Fragment (mid)';
            elseif late_start
                err_type = 'Late start';
            elseif early_end
                err_type = 'Early end';
            else
                err_type = 'Unknown';
            end

            dur_sec = (trx(k).endframe - trx(k).firstframe + 1) / fps;

            % Find swap partner: another incomplete fly whose start/end
            % is within swap_gap frames of this fly's end/start
            partner_id = NaN;
            gap = NaN;

            if early_end
                % Look for a late-starting fly that picks up after this one ends
                for j = 1:length(incomplete)
                    kj = incomplete(j);
                    if kj == k, continue; end
                    if trx(kj).firstframe > 1  % late starter
                        g = trx(kj).firstframe - trx(k).endframe;
                        if g > 0 && g <= swap_gap
                            if isnan(gap) || g < gap
                                partner_id = kj;
                                gap = g;
                            end
                        end
                    end
                end
            elseif late_start
                % Look for an early-ending fly that precedes this one
                for j = 1:length(incomplete)
                    kj = incomplete(j);
                    if kj == k, continue; end
                    if trx(kj).endframe < min_acceptable  % early ender
                        g = trx(k).firstframe - trx(kj).endframe;
                        if g > 0 && g <= swap_gap
                            if isnan(gap) || g < gap
                                partner_id = kj;
                                gap = g;
                            end
                        end
                    end
                end
            end

            row.experiment = exp_name;
            row.fly_id = k;
            row.firstframe = trx(k).firstframe;
            row.endframe = trx(k).endframe;
            row.duration_sec = dur_sec;
            row.error_type = err_type;
            row.swap_partner = partner_id;
            row.gap_frames = gap;

            rows(end+1) = row;
        end
    end

    report = rows;

    if isempty(rows)
        fprintf('No tracking errors found.\n');
        return;
    end

    fprintf('Found %d tracking errors across %d experiments\n\n', length(rows), length(exp_dirs));

    % --- Console output ---
    for i = 1:length(rows)
        r = rows(i);
        if isnan(r.swap_partner)
            partner_str = '-';
        else
            partner_str = sprintf('Fly %d (gap %d fr)', r.swap_partner, r.gap_frames);
        end
        fprintf('  %-45s Fly %2d  [%6d - %6d]  %6.1fs  %-16s  %s\n', ...
            r.experiment, r.fly_id, r.firstframe, r.endframe, ...
            r.duration_sec, r.error_type, partner_str);
    end

    % --- Render figure table ---
    plot_error_table(rows, fps, save_dir);
end

function plot_error_table(rows, fps, save_dir)
% PLOT_ERROR_TABLE - Render tracking errors as a MATLAB figure table

    % Colorblind-friendly palette (Wong 2011)
    color_early  = [0.90 0.62 0.00];   % orange
    color_late   = [0.00 0.45 0.70];   % blue
    color_frag   = [0.80 0.47 0.65];   % reddish purple

    num_rows = length(rows);

    col_headers = {'Experiment', 'Fly', 'Start Frame', 'End Frame', 'Duration', 'Error Type', 'Swap Partner', 'Gap'};
    num_cols = length(col_headers);

    % Column x-positions (normalized)
    col_x = [0.01, 0.22, 0.27, 0.34, 0.42, 0.50, 0.64, 0.80];

    row_height = min(0.035, 0.85 / (num_rows + 2));
    fig_height = max(500, 80 + num_rows * 22);

    fig = figure('Name', 'Tracking Error Report', ...
                 'Position', [50 50 1300 fig_height], ...
                 'Visible', 'off', 'Color', 'w');

    ax = axes('Position', [0.02 0.02 0.96 0.92], 'Visible', 'off');
    hold on;

    header_y = 1 - row_height;

    % --- Header ---
    for c = 1:num_cols
        text(col_x(c), header_y, col_headers{c}, ...
            'FontSize', 9, 'FontWeight', 'bold', ...
            'VerticalAlignment', 'middle', 'Units', 'normalized');
    end
    line([0 1], [header_y - row_height*0.5, header_y - row_height*0.5], ...
        'Color', 'k', 'LineWidth', 1.5);

    % --- Data rows ---
    prev_exp = '';
    for i = 1:num_rows
        r = rows(i);
        y = header_y - row_height * (i + 0.5);

        % Alternate experiment background
        if ~strcmp(r.experiment, prev_exp)
            if mod(sum(~strcmp({rows(1:i).experiment}, r.experiment) == 0), 2) == 0
                rectangle('Position', [0, y - row_height*0.45, 1, row_height*0.9], ...
                    'FaceColor', [0.97 0.97 0.97], 'EdgeColor', 'none');
            end
            prev_exp = r.experiment;
        end

        % Choose color based on error type
        if contains(r.error_type, 'Early')
            row_color = color_early;
        elseif contains(r.error_type, 'Late')
            row_color = color_late;
        else
            row_color = color_frag;
        end

        % Shorten experiment name
        parts = strsplit(r.experiment, '_');
        if length(parts) >= 4
            short_name = sprintf('%s_%s_%s', parts{1}, parts{2}, parts{3});
        else
            short_name = r.experiment;
        end

        % Partner string
        if isnan(r.swap_partner)
            partner_str = '-';
            gap_str = '-';
        else
            partner_str = sprintf('Fly %d', r.swap_partner);
            gap_str = sprintf('%d fr (%.2fs)', r.gap_frames, r.gap_frames / fps);
        end

        % Write cells
        cell_data = {short_name, ...
                     sprintf('%d', r.fly_id), ...
                     sprintf('%d', r.firstframe), ...
                     sprintf('%d', r.endframe), ...
                     sprintf('%.1f s', r.duration_sec), ...
                     r.error_type, ...
                     partner_str, ...
                     gap_str};

        for c = 1:num_cols
            if c == 6  % error type column — color coded
                text(col_x(c), y, cell_data{c}, ...
                    'FontSize', 8, 'Color', row_color, 'FontWeight', 'bold', ...
                    'VerticalAlignment', 'middle', 'Units', 'normalized');
            else
                text(col_x(c), y, cell_data{c}, ...
                    'FontSize', 8, 'Color', [0.1 0.1 0.1], ...
                    'VerticalAlignment', 'middle', 'Units', 'normalized');
            end
        end
    end

    % Title
    text(0.5, 1 - row_height * 0.1, ...
        sprintf('Tracking Error Report  (%d errors)', num_rows), ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'top', 'Units', 'normalized');

    % Legend at bottom
    leg_y = header_y - row_height * (num_rows + 2.5);
    legend_items = {{'Early end', color_early}, {'Late start', color_late}, {'Fragment', color_frag}};
    for li = 1:3
        lx = 0.25 + (li-1) * 0.2;
        rectangle('Position', [lx, leg_y - 0.005, 0.02, 0.015], ...
            'FaceColor', legend_items{li}{2}, 'EdgeColor', 'none');
        text(lx + 0.025, leg_y + 0.002, legend_items{li}{1}, ...
            'FontSize', 9, 'VerticalAlignment', 'middle', 'Units', 'normalized');
    end

    xlim([0 1]); ylim([0 1]);

    % Save
    out_file = fullfile(save_dir, 'tracking_error_report.png');
    saveas(fig, out_file);
    savefig(fig, strrep(out_file, '.png', '.fig'));
    close(fig);
    fprintf('\n  Table saved: %s\n', out_file);
end
