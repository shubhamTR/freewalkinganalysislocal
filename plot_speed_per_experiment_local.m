function varargout = plot_speed_per_experiment_local(exp_path, varargin)
% PLOT_SPEED_PER_EXPERIMENT_LOCAL  Per-cycle speed plots with mean +/- SEM
%
%   plot_speed_per_experiment_local(exp_path)
%   s = plot_speed_per_experiment_local(exp_path, 'Name', Value, ...)
%
%   Calls compute_speed_per_cycle_local to get per-fly speed traces, then
%   generates:
%     - One plot per cycle: grey individual traces + mean +/- SEM ribbon
%     - One combined all-cycles figure (subplot grid)
%   Saves .png + .fig per cycle, and combined .fig, to analysis/speed_plots/.
%
%   INPUTS
%     exp_path -- path to experiment folder in analysisdatalocal
%
%   NAME-VALUE PARAMETERS
%     'ShowPlots'         -- keep figures open (default: false)
%     'SavePlot'          -- save plots (default: true)
%     'Protocol'          -- 'P001', 'P002', etc. (default: auto-detect)
%     'PixelsPerMM'       -- px/mm conversion (read from trx.mat; override with explicit value)
%     'FPS'               -- frames per second (default: 30.1)
%     'PreOnsetSec'       -- seconds before LED onset (default: 10)
%     'SmoothWinSec'      -- smoothing window (default: 0.5)
%     'ConsecutiveCycles' -- dead fly detection window (default: 3)
%     'MoveThreshPx'      -- dead fly pixel threshold (default: 5)

    %% Parse inputs
    ip = inputParser;
    addRequired(ip, 'exp_path', @ischar);
    addParameter(ip, 'ShowPlots', false, @islogical);
    addParameter(ip, 'SavePlot', true, @islogical);
    addParameter(ip, 'Protocol', '', @ischar);
    addParameter(ip, 'PixelsPerMM', NaN, @isnumeric);
    addParameter(ip, 'FPS', 30.1, @isnumeric);
    addParameter(ip, 'PreOnsetSec', 10, @isnumeric);
    addParameter(ip, 'SmoothWinSec', 0.5, @isnumeric);
    addParameter(ip, 'ConsecutiveCycles', 3, @isnumeric);
    addParameter(ip, 'MoveThreshPx', 5, @isnumeric);
    parse(ip, exp_path, varargin{:});

    opts = ip.Results;
    [~, exp_name] = fileparts(exp_path);
    analysis_dir  = fullfile(exp_path, 'analysis');

    %% Compute speed (also saves .mat internally)
    summary = compute_speed_per_cycle_local(exp_path, ...
        'Protocol',          opts.Protocol, ...
        'PixelsPerMM',       opts.PixelsPerMM, ...
        'FPS',               opts.FPS, ...
        'PreOnsetSec',       opts.PreOnsetSec, ...
        'SmoothWinSec',      opts.SmoothWinSec, ...
        'ConsecutiveCycles', opts.ConsecutiveCycles, ...
        'MoveThreshPx',      opts.MoveThreshPx);

    if isempty(summary)
        if nargout > 0, varargout{1} = []; end
        return;
    end

    FPS = summary.fps;
    num_plot_cycles = length(summary.cycles);

    out_dir = fullfile(analysis_dir, 'speed_plots');
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    vis = 'off';
    if opts.ShowPlots, vis = 'on'; end

    %% Individual cycle plots
    for ci = 1:num_plot_cycles
        cd = summary.cycles(ci);
        if isempty(cd.t_axis), continue; end

        c   = cd.cycle_num;
        lbl = cd.label;
        t_axis = cd.t_axis;
        speed_matrix = cd.speed_matrix;
        mean_spd = cd.mean_speed;
        sem_spd  = cd.sem_speed;
        n_alive  = cd.n_alive;
        fr_off   = cd.fr_off;
        fr_on    = cd.fr_on;

        fig = figure('Position', [100 100 1200 500], 'Visible', vis);
        ax = axes(fig);
        hold(ax, 'on');

        % Grey individual traces
        for fi = 1:n_alive
            plot(ax, t_axis, speed_matrix(fi, :), ...
                'Color', [0.75 0.75 0.75 0.4], 'LineWidth', 0.5);
        end

        % SEM ribbon
        upper_b = mean_spd + sem_spd;
        lower_b = mean_spd - sem_spd;
        valid = ~isnan(mean_spd) & ~isnan(sem_spd);
        t_v = t_axis(valid);
        upper_v = upper_b(valid);
        lower_v = lower_b(valid);
        if ~isempty(t_v)
            fill_x = [t_v, fliplr(t_v)];
            fill_y = [upper_v, fliplr(lower_v)];
            fill(ax, fill_x, fill_y, [0.2 0.4 0.8], ...
                'FaceAlpha', 0.3, 'EdgeColor', 'none');
        end

        % Mean line
        plot(ax, t_axis, mean_spd, 'Color', [0.1 0.2 0.7], 'LineWidth', 2);

        % LED onset / offset
        xline(ax, 0, 'r--', 'LineWidth', 1.5);
        t_off = (fr_off - fr_on) / FPS;
        xline(ax, t_off, 'b--', 'LineWidth', 1.5);

        % Formatting
        xlabel(ax, 'Time relative to LED onset (s)', 'FontSize', 11);
        ylabel(ax, 'Speed (mm/s)', 'FontSize', 11);
        title(ax, sprintf('%s — Cycle %d (%s) — n=%d flies', ...
            strrep(exp_name, '_', '\_'), c, lbl, n_alive), ...
            'FontSize', 12, 'FontWeight', 'bold');
        xlim(ax, [t_axis(1), t_axis(end)]);
        ylim(ax, [0, inf]);
        grid(ax, 'on'); box(ax, 'on');
        hold(ax, 'off');

        % Save
        if opts.SavePlot
            out_png = fullfile(out_dir, sprintf('speed_%s_cycle%02d_%s.png', exp_name, c, lbl));
            out_fig = fullfile(out_dir, sprintf('speed_%s_cycle%02d_%s.fig', exp_name, c, lbl));
            exportgraphics(fig, out_png, 'Resolution', 150);
            savefig(fig, out_fig);
        end

        if ~opts.ShowPlots
            close(fig);
        end
    end

    %% Combined all-cycles figure
    % Determine grid layout
    n_cols = 8;
    n_rows = ceil(num_plot_cycles / n_cols);
    fig_all = figure('Position', [50 50 2400 n_rows * 280], 'Visible', vis);

    for ci = 1:num_plot_cycles
        cd = summary.cycles(ci);
        if isempty(cd.t_axis), continue; end

        c   = cd.cycle_num;
        lbl = cd.label;
        t_axis = cd.t_axis;
        speed_matrix = cd.speed_matrix;
        mean_spd = cd.mean_speed;
        sem_spd  = cd.sem_speed;
        n_alive  = cd.n_alive;
        fr_off   = cd.fr_off;
        fr_on    = cd.fr_on;

        ax = subplot(n_rows, n_cols, ci, 'Parent', fig_all);
        hold(ax, 'on');

        % Grey individual traces
        for fi = 1:n_alive
            plot(ax, t_axis, speed_matrix(fi, :), ...
                'Color', [0.75 0.75 0.75 0.4], 'LineWidth', 0.3);
        end

        % SEM ribbon
        upper_b = mean_spd + sem_spd;
        lower_b = mean_spd - sem_spd;
        valid = ~isnan(mean_spd) & ~isnan(sem_spd);
        t_v = t_axis(valid);
        upper_v = upper_b(valid);
        lower_v = lower_b(valid);
        if ~isempty(t_v)
            fill_x = [t_v, fliplr(t_v)];
            fill_y = [upper_v, fliplr(lower_v)];
            fill(ax, fill_x, fill_y, [0.2 0.4 0.8], ...
                'FaceAlpha', 0.3, 'EdgeColor', 'none');
        end

        % Mean line
        plot(ax, t_axis, mean_spd, 'Color', [0.1 0.2 0.7], 'LineWidth', 1.2);

        % LED onset / offset
        xline(ax, 0, 'r--', 'LineWidth', 0.8);
        t_off = (fr_off - fr_on) / FPS;
        xline(ax, t_off, 'b--', 'LineWidth', 0.8);

        % Compact formatting
        title(ax, sprintf('C%d %s (n=%d)', c, lbl, n_alive), 'FontSize', 7);
        xlim(ax, [t_axis(1), t_axis(end)]);
        ylim(ax, [0, inf]);
        set(ax, 'FontSize', 6);

        if mod(ci-1, n_cols) == 0
            ylabel(ax, 'mm/s', 'FontSize', 6);
        end
        if ci > (n_rows - 1) * n_cols
            xlabel(ax, 's', 'FontSize', 6);
        end

        hold(ax, 'off');
    end

    sgtitle(fig_all, sprintf('%s — Speed per fly (all cycles)', ...
        strrep(exp_name, '_', '\_')), 'FontSize', 14, 'FontWeight', 'bold');

    % Save combined figure
    if opts.SavePlot
        combined_fig = fullfile(out_dir, sprintf('speed_%s_allcycles.fig', exp_name));
        savefig(fig_all, combined_fig);
        combined_png = fullfile(out_dir, sprintf('speed_%s_allcycles.png', exp_name));
        exportgraphics(fig_all, combined_png, 'Resolution', 100);
    end

    if ~opts.ShowPlots
        close(fig_all);
    end

    fprintf('  Speed plots saved to: %s\n', out_dir);

    %% Return summary if requested
    if nargout > 0
        varargout{1} = summary;
    end
end
