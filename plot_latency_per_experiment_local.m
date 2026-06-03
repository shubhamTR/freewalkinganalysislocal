function varargout = plot_latency_per_experiment_local(exp_path, varargin)
% PLOT_LATENCY_PER_EXPERIMENT_LOCAL  Per-cycle latency with scatter, heatmap, and fly counts
%
%   plot_latency_per_experiment_local(exp_path)
%   plot_latency_per_experiment_local(exp_path, 'Name', Value, ...)
%
%   Calls compute_latency_per_cycle_local to get per-cycle latency summaries
%   and per-fly latency matrix. Creates a figure with three subplots:
%     - Top:    Mean +/- SE with individual fly scatter overlay
%     - Middle: Per-fly latency heatmap [num_flies x num_cycles], NaN = white
%     - Bottom: Number of contributing flies per cycle (responded / already
%               correct / dead)
%
%   Saves PNG to experiment's analysis/ folder as latency_<exp_name>.png
%
%   INPUTS
%     exp_path -- path to experiment folder in analysisdatalocal
%
%   NAME-VALUE PARAMETERS
%     'ShowPlots'        -- keep figure open (default: false)
%     'SavePlot'         -- save PNG to analysis folder (default: true)
%     'Protocol'         -- 'P001', 'P002', etc. (default: auto-detect from path)
%     'PixelsPerMM'      -- pixels per mm (read from trx.mat; override with explicit value)
%     'ConsecutiveCycles'-- cycles window for dead detection (default: 3)
%     'MoveThreshPx'     -- pixel threshold for dead detection (default: 5)

    %% Parse inputs
    p = inputParser;
    addRequired(p, 'exp_path', @ischar);
    addParameter(p, 'ShowPlots', false, @islogical);
    addParameter(p, 'SavePlot', true, @islogical);
    addParameter(p, 'Protocol', '', @ischar);
    addParameter(p, 'PixelsPerMM', NaN, @isnumeric);
    addParameter(p, 'ConsecutiveCycles', 3, @isnumeric);
    addParameter(p, 'MoveThreshPx', 5, @isnumeric);
    parse(p, exp_path, varargin{:});

    opts = p.Results;
    [~, exp_name] = fileparts(exp_path);
    analysis_dir = fullfile(exp_path, 'analysis');

    %% Auto-detect protocol from path if not provided
    protocol = opts.Protocol;
    if isempty(protocol)
        [parent_dir, ~] = fileparts(exp_path);
        [~, parent_name] = fileparts(parent_dir);
        if startsWith(parent_name, 'P')
            protocol = parent_name;
        else
            protocol = 'unknown';
        end
    end

    %% Compute latency per cycle
    summary = compute_latency_per_cycle_local(exp_path, 'Protocol', protocol, ...
        'ConsecutiveCycles', opts.ConsecutiveCycles, ...
        'MoveThreshPx', opts.MoveThreshPx);

    if isempty(summary)
        warning('Empty latency summary — skipping %s', exp_name);
        return;
    end

    %% Extract data
    cycle_table     = summary.cycle_table;
    latency_matrix  = summary.latency_per_fly;       % [num_flies x num_cycles]
    num_cycles      = height(cycle_table);
    num_flies       = summary.num_flies_total;
    num_alive       = num_flies - summary.num_dead;

    cycle_nums      = cycle_table.cycle;
    mean_lats       = cycle_table.mean_latency_s;
    sem_lats        = cycle_table.sem_latency_s;
    cycle_lbls      = cycle_table.label;
    n_responded     = cycle_table.n_responded;
    n_already_corr  = cycle_table.n_already_correct;
    n_alive_vec     = cycle_table.n_flies_alive;

    %% Filter out optomotor cycles (OM1, OM2)
    om_mask = strcmp(cycle_lbls, 'OM1') | strcmp(cycle_lbls, 'OM2');
    if any(om_mask)
        keep = ~om_mask;
        cycle_table    = cycle_table(keep, :);
        latency_matrix = latency_matrix(:, keep);
        num_cycles     = height(cycle_table);
        cycle_nums     = (1:num_cycles)';
        mean_lats      = cycle_table.mean_latency_s;
        sem_lats       = cycle_table.sem_latency_s;
        cycle_lbls     = cycle_table.label;
        n_responded    = cycle_table.n_responded;
        n_already_corr = cycle_table.n_already_correct;
        n_alive_vec    = cycle_table.n_flies_alive;
    end

    %% Prepare per-cycle colors
    bar_colors = zeros(num_cycles, 3);
    for c = 1:num_cycles
        bar_colors(c, :) = get_cycle_color(cycle_lbls{c}, protocol);
    end

    %% Create figure — 3 subplots
    fig = figure('Position', [100 100 1500 900], 'Visible', 'off');

    %% SUBPLOT 1: Mean +/- SE with individual fly scatter
    ax1 = subplot(3, 1, 1);
    hold on;

    % Individual fly scatter (jittered)
    for c = 1:num_cycles
        fly_vals = latency_matrix(:, c);
        valid = find(~isnan(fly_vals));
        if ~isempty(valid)
            jitter = (rand(length(valid), 1) - 0.5) * 0.35;
            scatter(ax1, c + jitter, fly_vals(valid), 18, ...
                bar_colors(c, :), 'filled', 'MarkerFaceAlpha', 0.4);
        end
    end

    % Mean +/- SE as black markers with error bars
    valid_mean = ~isnan(mean_lats);
    errorbar(ax1, cycle_nums(valid_mean), mean_lats(valid_mean), ...
        sem_lats(valid_mean), 'k.', 'LineWidth', 1.5, 'CapSize', 4, 'MarkerSize', 12);

    % Formatting
    set(ax1, 'XTick', cycle_nums, 'XTickLabel', cycle_lbls, 'XTickLabelRotation', 45);
    xlabel('Cycle', 'FontSize', 10);
    ylabel('Latency (s)', 'FontSize', 11);
    title(sprintf('%s — Latency [%s] (%d/%d alive)', ...
        strrep(exp_name, '_', '\_'), protocol, num_alive, num_flies), ...
        'FontSize', 12, 'FontWeight', 'bold');
    xlim([0.5, num_cycles + 0.5]);
    max_val = max(latency_matrix(:));
    if isnan(max_val) || max_val == 0
        max_val = 1;
    end
    ylim([0, max_val * 1.15]);
    grid on; box on;
    hold off;

    %% SUBPLOT 2: Per-fly latency heatmap
    ax2 = subplot(3, 1, 2);

    % imagesc with NaN handling — replace NaN with a sentinel for white
    lat_display = latency_matrix;
    max_lat = max(lat_display(~isnan(lat_display)));
    if isempty(max_lat) || max_lat == 0
        max_lat = 1;
    end

    imagesc(ax2, lat_display);
    colormap(ax2, parula);
    caxis(ax2, [0, max_lat]);

    % Overlay white patches for NaN cells
    hold(ax2, 'on');
    [nan_r, nan_c] = find(isnan(latency_matrix));
    for k = 1:length(nan_r)
        patch(ax2, [nan_c(k)-0.5 nan_c(k)+0.5 nan_c(k)+0.5 nan_c(k)-0.5], ...
              [nan_r(k)-0.5 nan_r(k)-0.5 nan_r(k)+0.5 nan_r(k)+0.5], ...
              'w', 'EdgeColor', 'none');
    end
    hold(ax2, 'off');

    set(ax2, 'XTick', cycle_nums, 'XTickLabel', cycle_lbls, 'XTickLabelRotation', 45);
    ylabel('Fly ID', 'FontSize', 11);
    xlabel('Cycle', 'FontSize', 10);
    if num_flies <= 20
        set(ax2, 'YTick', 1:num_flies);
    else
        set(ax2, 'YTick', 1:5:num_flies);
    end
    cb = colorbar(ax2, 'Location', 'EastOutside');
    cb.Label.String = 'Latency (s)';
    cb.Label.FontSize = 10;

    %% SUBPLOT 3: Contributing flies per cycle (stacked)
    ax3 = subplot(3, 1, 3);
    hold on;

    % n_dead per cycle = num_flies - n_alive
    n_dead_vec = num_flies - n_alive_vec;
    % n_no_entry = alive but NaN and not already_correct
    n_no_entry = n_alive_vec - n_responded - n_already_corr;
    n_no_entry(n_no_entry < 0) = 0;  % guard against rounding

    % Stacked bar: responded (blue), already_correct (green), no_entry (orange), dead (grey)
    stack_data = [n_responded, n_already_corr, n_no_entry, n_dead_vec];
    hb = bar(ax3, cycle_nums, stack_data, 'stacked');

    hb(1).FaceColor = [0.2 0.5 0.8];   % responded — blue
    hb(2).FaceColor = [0.3 0.75 0.3];   % already correct — green
    hb(3).FaceColor = [0.95 0.6 0.15];  % no entry — orange
    hb(4).FaceColor = [0.7 0.7 0.7];    % dead — grey

    legend(ax3, {'Responded', 'Already correct', 'No entry', 'Dead'}, ...
        'Location', 'NorthEastOutside', 'FontSize', 8);

    set(ax3, 'XTick', cycle_nums, 'XTickLabel', cycle_lbls, 'XTickLabelRotation', 45);
    xlabel('Cycle', 'FontSize', 10);
    ylabel('# Flies', 'FontSize', 11);
    ylim([0, num_flies + 1]);
    xlim([0.5, num_cycles + 0.5]);
    grid on; box on;
    hold off;

    %% Save combined figure
    if opts.SavePlot
        if ~exist(analysis_dir, 'dir')
            mkdir(analysis_dir);
        end
        out_file = fullfile(analysis_dir, sprintf('latency_%s.png', exp_name));
        fig_file = fullfile(analysis_dir, sprintf('latency_%s.fig', exp_name));
        exportgraphics(fig, out_file, 'Resolution', 150);
        savefig(fig, fig_file);
        fprintf('Saved latency plot: %s\n', out_file);
    end

    if opts.ShowPlots
        set(fig, 'Visible', 'on');
    else
        close(fig);
    end

    %% Save individual standalone plots
    if opts.SavePlot
        title_str_base = sprintf('%s [%s] (%d/%d alive)', ...
            strrep(exp_name, '_', '\_'), protocol, num_alive, num_flies);

        % --- 1. Scatter + errorbar ---
        fig1 = figure('Position', [100 100 1500 400], 'Visible', 'off');
        ax = axes(fig1); hold(ax, 'on');
        for c = 1:num_cycles
            fly_vals = latency_matrix(:, c);
            valid = find(~isnan(fly_vals));
            if ~isempty(valid)
                jitter = (rand(length(valid), 1) - 0.5) * 0.35;
                scatter(ax, c + jitter, fly_vals(valid), 18, ...
                    bar_colors(c, :), 'filled', 'MarkerFaceAlpha', 0.4);
            end
        end
        valid_mean = ~isnan(mean_lats);
        errorbar(ax, cycle_nums(valid_mean), mean_lats(valid_mean), ...
            sem_lats(valid_mean), 'k.', 'LineWidth', 1.5, 'CapSize', 4, 'MarkerSize', 12);
        set(ax, 'XTick', cycle_nums, 'XTickLabel', cycle_lbls, 'XTickLabelRotation', 45);
        xlabel(ax, 'Cycle', 'FontSize', 10);
        ylabel(ax, 'Latency (s)', 'FontSize', 11);
        title(ax, sprintf('Latency — %s', title_str_base), 'FontSize', 12, 'FontWeight', 'bold');
        xlim(ax, [0.5, num_cycles + 0.5]);
        max_val = max(latency_matrix(:));
        if isnan(max_val) || max_val == 0; max_val = 1; end
        ylim(ax, [0, max_val * 1.15]);
        grid(ax, 'on'); box(ax, 'on'); hold(ax, 'off');
        exportgraphics(fig1, fullfile(analysis_dir, sprintf('latency_scatter_%s.png', exp_name)), 'Resolution', 150);
        savefig(fig1, fullfile(analysis_dir, sprintf('latency_scatter_%s.fig', exp_name)));
        close(fig1);

        % --- 2. Heatmap ---
        fig2 = figure('Position', [100 100 1500 400], 'Visible', 'off');
        ax = axes(fig2);
        lat_display = latency_matrix;
        max_lat = max(lat_display(~isnan(lat_display)));
        if isempty(max_lat) || max_lat == 0; max_lat = 1; end
        imagesc(ax, lat_display);
        colormap(ax, parula); caxis(ax, [0, max_lat]);
        hold(ax, 'on');
        [nan_r, nan_c] = find(isnan(latency_matrix));
        for k = 1:length(nan_r)
            patch(ax, [nan_c(k)-0.5 nan_c(k)+0.5 nan_c(k)+0.5 nan_c(k)-0.5], ...
                  [nan_r(k)-0.5 nan_r(k)-0.5 nan_r(k)+0.5 nan_r(k)+0.5], ...
                  'w', 'EdgeColor', 'none');
        end
        hold(ax, 'off');
        set(ax, 'XTick', cycle_nums, 'XTickLabel', cycle_lbls, 'XTickLabelRotation', 45);
        ylabel(ax, 'Fly ID', 'FontSize', 11);
        xlabel(ax, 'Cycle', 'FontSize', 10);
        title(ax, sprintf('Latency Heatmap — %s', title_str_base), 'FontSize', 12, 'FontWeight', 'bold');
        if num_flies <= 20; set(ax, 'YTick', 1:num_flies);
        else; set(ax, 'YTick', 1:5:num_flies); end
        cb = colorbar(ax, 'Location', 'EastOutside');
        cb.Label.String = 'Latency (s)'; cb.Label.FontSize = 10;
        exportgraphics(fig2, fullfile(analysis_dir, sprintf('latency_heatmap_%s.png', exp_name)), 'Resolution', 150);
        savefig(fig2, fullfile(analysis_dir, sprintf('latency_heatmap_%s.fig', exp_name)));
        close(fig2);

        % --- 3. Contributing flies ---
        fig3 = figure('Position', [100 100 1500 350], 'Visible', 'off');
        ax = axes(fig3); hold(ax, 'on');
        stack_data_ind = [n_responded, n_already_corr, n_no_entry, n_dead_vec];
        hb_ind = bar(ax, cycle_nums, stack_data_ind, 'stacked');
        hb_ind(1).FaceColor = [0.2 0.5 0.8];
        hb_ind(2).FaceColor = [0.3 0.75 0.3];
        hb_ind(3).FaceColor = [0.95 0.6 0.15];
        hb_ind(4).FaceColor = [0.7 0.7 0.7];
        legend(ax, {'Responded', 'Already correct', 'No entry', 'Dead'}, ...
            'Location', 'NorthEastOutside', 'FontSize', 8);
        set(ax, 'XTick', cycle_nums, 'XTickLabel', cycle_lbls, 'XTickLabelRotation', 45);
        xlabel(ax, 'Cycle', 'FontSize', 10);
        ylabel(ax, '# Flies', 'FontSize', 11);
        title(ax, sprintf('Contributing Flies — %s', title_str_base), 'FontSize', 12, 'FontWeight', 'bold');
        ylim(ax, [0, num_flies + 1]);
        xlim(ax, [0.5, num_cycles + 0.5]);
        grid(ax, 'on'); box(ax, 'on'); hold(ax, 'off');
        exportgraphics(fig3, fullfile(analysis_dir, sprintf('latency_contributing_%s.png', exp_name)), 'Resolution', 150);
        savefig(fig3, fullfile(analysis_dir, sprintf('latency_contributing_%s.fig', exp_name)));
        close(fig3);
    end

    %% Return summary if requested
    if nargout > 0
        varargout{1} = summary;
    end

end

%% ======== LOCAL HELPERS ========

function color = get_cycle_color(label, ~)
% GET_CYCLE_COLOR  Return RGB color for a given cycle label

    RED    = [1 0 0];
    GREEN  = [0 0.6 0];
    BLUE   = [0 0 1];
    GREY   = [0.5 0.5 0.5];
    ORANGE = [0.9 0.5 0];

    if strcmp(label, 'PP') || strcmp(label, 'OM1') || strcmp(label, 'OM2')
        color = GREY; return;
    end
    if strcmp(label, 'Ag')
        color = ORANGE; return;
    end
    if startsWith(label, 'B') && contains(label, '.')
        if endsWith(label, '.P')
            color = GREY;
        else
            color = RED;
        end
        return;
    end
    % P001/P002 convention
    if ~isempty(label)
        switch upper(label(1))
            case 'R', color = RED;
            case 'G', color = GREEN;
            case 'B', color = BLUE;
            otherwise, color = GREY;
        end
        return;
    end
    color = GREY;
end
