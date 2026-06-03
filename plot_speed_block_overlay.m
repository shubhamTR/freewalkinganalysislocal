function plot_speed_block_overlay(summary, varargin)
% PLOT_SPEED_BLOCK_OVERLAY  Block-averaged speed traces overlaid to show learning
%
%   plot_speed_block_overlay(summary)
%   plot_speed_block_overlay(summary, 'Name', Value, ...)
%
%   Takes the summary struct from compute_speed_per_cycle_local and generates:
%     (1) Training blocks overlay — mean ± SEM trace for each block (B1–B4),
%         averaged across the 10 training trials within each block, overlaid
%         on a single axis. Shows whether the speed response changes with
%         training.
%     (2) Probe overlay — PP and B1.P–B4.P traces overlaid, showing whether
%         learned speed changes persist when all quadrants are lit.
%
%   Works for all place-learning protocols: 4-block (P003–P016) and 3-block
%   (P013, P017, P019). Returns without plotting for P001/P002.
%
%   NAME-VALUE PARAMETERS
%     'ShowPlots'  — keep figure open (default: false)
%     'SavePlot'   — save .png + .fig (default: true)
%     'OutputDir'  — save directory (default: analysis/speed_plots/)

    if isempty(summary), return; end

    %% Parse inputs
    ip = inputParser;
    addRequired(ip, 'summary', @isstruct);
    addParameter(ip, 'ShowPlots', false, @islogical);
    addParameter(ip, 'SavePlot', true, @islogical);
    addParameter(ip, 'OutputDir', '', @ischar);
    parse(ip, summary, varargin{:});
    opts = ip.Results;

    protocol  = upper(summary.protocol);
    exp_name  = summary.experiment;
    FPS       = summary.fps;

    %% Only place-learning protocols have block structure (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_place_learning
        fprintf('  Block overlay: %s not a place-learning protocol, skipping\n', protocol);
        return;
    end

    %% Output directory
    if isempty(opts.OutputDir)
        exp_path = summary.exp_path;
        if ~isfield(summary, 'exp_path')
            % Reconstruct from convention
            out_dir = '';
        else
            out_dir = fullfile(summary.exp_path, 'analysis', 'speed_plots');
        end
    else
        out_dir = opts.OutputDir;
    end

    % Fallback: use analysis dir based on experiment path pattern
    if isempty(out_dir)
        fprintf('  Block overlay: no output directory, skipping save\n');
        out_dir = tempdir;
    end

    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    vis = 'off';
    if opts.ShowPlots, vis = 'on'; end

    %% Group cycles by type using labels
    % Build lookup: label -> index into summary.cycles
    num_cycles = length(summary.cycles);
    cycle_map = containers.Map();
    for ci = 1:num_cycles
        if ~isempty(summary.cycles(ci).label)
            cycle_map(summary.cycles(ci).label) = ci;
        end
    end

    %% Identify block training cycles and probes
    % Detect num_blocks from cycle labels (look for highest B<N>.1 label)
    num_blocks = 0;
    for ci = 1:length(summary.cycles)
        lbl = summary.cycles(ci).label;
        tok = regexp(lbl, '^B(\d+)\.1$', 'tokens');
        if ~isempty(tok)
            num_blocks = max(num_blocks, str2double(tok{1}{1}));
        end
    end
    if num_blocks == 0
        fprintf('  No block structure detected — skipping block overlay for %s\n', summary.experiment);
        return;
    end
    trials_per_block = 10;

    block_indices = cell(num_blocks, 1);  % indices into summary.cycles
    probe_indices = [];                    % [PP, B1.P, B2.P, B3.P, B4.P]
    probe_labels  = {};

    % PP
    if cycle_map.isKey('PP')
        probe_indices(end+1) = cycle_map('PP');
        probe_labels{end+1}  = 'PP';
    end

    % Ag (not a probe, but useful reference)
    ag_idx = [];
    if cycle_map.isKey('Ag')
        ag_idx = cycle_map('Ag');
    end

    for blk = 1:num_blocks
        blk_trials = [];
        for trial = 1:trials_per_block
            key = sprintf('B%d.%d', blk, trial);
            if cycle_map.isKey(key)
                blk_trials(end+1) = cycle_map(key); %#ok<AGROW>
            end
        end
        block_indices{blk} = blk_trials;

        % Block probe
        probe_key = sprintf('B%d.P', blk);
        if cycle_map.isKey(probe_key)
            probe_indices(end+1) = cycle_map(probe_key); %#ok<AGROW>
            probe_labels{end+1}  = probe_key; %#ok<AGROW>
        end
    end

    %% Compute block-averaged speed traces
    % For each block, find common time axis length, interpolate, then average

    block_colors = [
        0.7  0.85 1.0;   % Block 1 — light blue
        0.3  0.6  0.9;   % Block 2 — medium blue
        0.1  0.35 0.7;   % Block 3 — dark blue
        0.0  0.15 0.45;  % Block 4 — very dark blue
    ];

    % Determine a common time axis from all training cycles
    % (they should be nearly identical, but let's be safe)
    all_t_min = inf;
    all_t_max = -inf;
    for blk = 1:num_blocks
        for ti = 1:length(block_indices{blk})
            ci = block_indices{blk}(ti);
            t = summary.cycles(ci).t_axis;
            if t(1) < all_t_min, all_t_min = t(1); end
            if t(end) > all_t_max, all_t_max = t(end); end
        end
    end

    % Common time axis at native resolution
    dt = 1 / FPS;
    t_common = all_t_min:dt:all_t_max;
    n_t = length(t_common);

    block_mean = NaN(num_blocks, n_t);
    block_sem  = NaN(num_blocks, n_t);
    block_n    = zeros(num_blocks, 1);

    for blk = 1:num_blocks
        n_trials = length(block_indices{blk});
        if n_trials == 0, continue; end

        % Stack all individual FLY means from all trials in this block
        % Each trial gives one mean trace; we average across trials
        trial_means = NaN(n_trials, n_t);

        for ti = 1:n_trials
            ci = block_indices{blk}(ti);
            cd = summary.cycles(ci);
            if isempty(cd.mean_speed), continue; end

            % Interpolate this trial's mean to common time axis
            trial_means(ti, :) = interp1(cd.t_axis, cd.mean_speed, t_common, ...
                'linear', NaN);
        end

        block_mean(blk, :) = mean(trial_means, 1, 'omitnan');
        block_sem(blk, :)  = std(trial_means, 0, 1, 'omitnan') / sqrt(n_trials);
        block_n(blk) = n_trials;
    end

    %% ===== FIGURE 1: Training block overlay =====
    fig1 = figure('Position', [100 100 1400 600], 'Visible', vis);
    ax1 = axes(fig1);
    hold(ax1, 'on');

    legend_h = [];
    legend_s = {};

    for blk = 1:num_blocks
        if block_n(blk) == 0, continue; end

        m = block_mean(blk, :);
        s = block_sem(blk, :);
        col = block_colors(blk, :);

        % SEM ribbon
        upper_b = m + s;
        lower_b = m - s;
        valid = ~isnan(m) & ~isnan(s);
        t_v = t_common(valid);
        if ~isempty(t_v)
            fill_x = [t_v, fliplr(t_v)];
            fill_y = [upper_b(valid), fliplr(lower_b(valid))];
            fill(ax1, fill_x, fill_y, col, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
        end

        % Mean line
        h = plot(ax1, t_common, m, 'Color', col, 'LineWidth', 2.5);
        legend_h(end+1) = h; %#ok<AGROW>
        legend_s{end+1} = sprintf('Block %d (n=%d trials)', blk, block_n(blk)); %#ok<AGROW>
    end

    % LED onset / offset markers
    xline(ax1, 0, 'r--', 'LineWidth', 1.5);
    % Estimate typical stim duration from first training cycle
    if ~isempty(block_indices{1})
        ci1 = block_indices{1}(1);
        t_off = (summary.cycles(ci1).fr_off - summary.cycles(ci1).fr_on) / FPS;
        xline(ax1, t_off, 'b--', 'LineWidth', 1.5);
    end

    xlabel(ax1, 'Time relative to LED onset (s)', 'FontSize', 12);
    ylabel(ax1, 'Speed (mm/s)', 'FontSize', 12);
    title(ax1, sprintf('%s — Block-averaged speed (training trials)', ...
        strrep(exp_name, '_', '\_')), 'FontSize', 13, 'FontWeight', 'bold');
    xlim(ax1, [t_common(1), t_common(end)]);
    ylim(ax1, [0, inf]);
    legend(ax1, legend_h, legend_s, 'Location', 'NorthEastOutside', 'FontSize', 10);
    grid(ax1, 'on'); box(ax1, 'on');
    hold(ax1, 'off');

    if opts.SavePlot
        out_png = fullfile(out_dir, sprintf('speed_blocks_%s.png', exp_name));
        out_fig = fullfile(out_dir, sprintf('speed_blocks_%s.fig', exp_name));
        exportgraphics(fig1, out_png, 'Resolution', 150);
        savefig(fig1, out_fig);
    end
    if ~opts.ShowPlots, close(fig1); end

    %% ===== FIGURE 2: Probe overlay =====
    if length(probe_indices) >= 2
        probe_colors = [
            0.6  0.6  0.6;   % PP — grey
            0.8  0.5  0.5;   % B1.P — light red
            0.7  0.2  0.2;   % B2.P — medium red
            0.5  0.1  0.1;   % B3.P — dark red
            0.3  0.0  0.0;   % B4.P — very dark red
        ];

        fig2 = figure('Position', [100 100 1400 600], 'Visible', vis);
        ax2 = axes(fig2);
        hold(ax2, 'on');

        legend_h2 = [];
        legend_s2 = {};

        for pi = 1:length(probe_indices)
            ci = probe_indices(pi);
            cd = summary.cycles(ci);
            if isempty(cd.mean_speed), continue; end

            m = cd.mean_speed;
            s = cd.sem_speed;
            t = cd.t_axis;
            col = probe_colors(min(pi, size(probe_colors,1)), :);

            % SEM ribbon
            upper_b = m + s;
            lower_b = m - s;
            valid = ~isnan(m) & ~isnan(s);
            t_v = t(valid);
            if ~isempty(t_v)
                fill_x = [t_v, fliplr(t_v)];
                fill_y = [upper_b(valid), fliplr(lower_b(valid))];
                fill(ax2, fill_x, fill_y, col, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
            end

            h = plot(ax2, t, m, 'Color', col, 'LineWidth', 2.5);
            legend_h2(end+1) = h; %#ok<AGROW>
            legend_s2{end+1} = sprintf('%s (n=%d flies)', probe_labels{pi}, cd.n_alive); %#ok<AGROW>
        end

        xline(ax2, 0, 'r--', 'LineWidth', 1.5);
        if ~isempty(probe_indices)
            ci_p = probe_indices(1);
            t_off = (summary.cycles(ci_p).fr_off - summary.cycles(ci_p).fr_on) / FPS;
            xline(ax2, t_off, 'b--', 'LineWidth', 1.5);
        end

        xlabel(ax2, 'Time relative to LED onset (s)', 'FontSize', 12);
        ylabel(ax2, 'Speed (mm/s)', 'FontSize', 12);
        title(ax2, sprintf('%s — Probe speed traces (PP vs block probes)', ...
            strrep(exp_name, '_', '\_')), 'FontSize', 13, 'FontWeight', 'bold');
        xlim(ax2, [t(1), t(end)]);
        ylim(ax2, [0, inf]);
        legend(ax2, legend_h2, legend_s2, 'Location', 'NorthEastOutside', 'FontSize', 10);
        grid(ax2, 'on'); box(ax2, 'on');
        hold(ax2, 'off');

        if opts.SavePlot
            out_png2 = fullfile(out_dir, sprintf('speed_probes_%s.png', exp_name));
            out_fig2 = fullfile(out_dir, sprintf('speed_probes_%s.fig', exp_name));
            exportgraphics(fig2, out_png2, 'Resolution', 150);
            savefig(fig2, out_fig2);
        end
        if ~opts.ShowPlots, close(fig2); end
    end

    fprintf('  Block overlay + probe plots saved to: %s\n', out_dir);
end
