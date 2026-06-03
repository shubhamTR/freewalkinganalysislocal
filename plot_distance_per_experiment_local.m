function varargout = plot_distance_per_experiment_local(exp_path, varargin)
% PLOT_DISTANCE_PER_EXPERIMENT_LOCAL  Per-cycle distance with scatter, heatmap, and fly counts
%
%   plot_distance_per_experiment_local(exp_path)
%   plot_distance_per_experiment_local(exp_path, 'Name', Value, ...)
%
%   Calls compute_distance_per_cycle_local, creates a figure with three subplots:
%     - Top:    Mean +/- SE with individual fly scatter overlay
%     - Middle: Per-fly distance heatmap [num_flies x num_cycles], NaN = white
%     - Bottom: Number of contributing flies per cycle (measured / dead)
%
%   Saves PNG to the experiment's analysis folder.
%
%   INPUTS
%     exp_path -- path to experiment folder
%
%   NAME-VALUE PARAMETERS
%     'ShowPlots'        -- keep figure open (default: false)
%     'SavePlot'         -- save PNG to analysis folder (default: true)
%     'Protocol'         -- 'P001', 'P002', 'P003', 'P005', 'P006' etc. (default: auto-detect from path)
%     'PixelsPerMM'      -- conversion factor (read from trx.mat; override with explicit value)
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

    %% Call compute_distance_per_cycle_local
    try
        summary = compute_distance_per_cycle_local(exp_path, ...
            'Protocol', protocol, ...
            'PixelsPerMM', opts.PixelsPerMM);
    catch ME
        warning('Error calling compute_distance_per_cycle_local: %s', ME.message);
        return;
    end

    if isempty(summary) || ~isfield(summary, 'cycle_table')
        warning('Empty or invalid summary for %s', exp_name);
        return;
    end

    %% Extract data
    cycle_table     = summary.cycle_table;
    dist_matrix     = summary.distance_per_fly;   % [num_flies x num_cycles]
    num_flies       = summary.num_flies_total;
    num_dead        = summary.num_dead;
    num_alive       = num_flies - num_dead;
    pixels_per_mm   = summary.pixels_per_mm;

    num_cycles      = height(cycle_table);
    cycle_nums      = cycle_table.cycle;
    mean_dists      = cycle_table.mean_dist_mm;
    sem_dists       = cycle_table.sem_dist_mm;
    cycle_lbls      = cycle_table.label;
    n_alive_vec     = cycle_table.n_flies_alive;

    %% Prepare per-cycle colors (before OM filter so indices match)
    [~, cycle_colors_cell] = get_distance_cycle_colors(protocol, num_cycles);
    % Pad if needed
    while length(cycle_colors_cell) < num_cycles
        cycle_colors_cell{end+1} = [0.5 0.5 0.5]; %#ok<AGROW>
    end

    %% Filter out optomotor cycles (OM1, OM2)
    om_mask = strcmp(cycle_lbls, 'OM1') | strcmp(cycle_lbls, 'OM2');
    if any(om_mask)
        keep = ~om_mask;
        cycle_table       = cycle_table(keep, :);
        dist_matrix       = dist_matrix(:, keep);
        cycle_colors_cell = cycle_colors_cell(keep);
        num_cycles        = height(cycle_table);
        cycle_nums        = (1:num_cycles)';
        mean_dists        = cycle_table.mean_dist_mm;
        sem_dists         = cycle_table.sem_dist_mm;
        cycle_lbls        = cycle_table.label;
        n_alive_vec       = cycle_table.n_flies_alive;
    end

    bar_colors = zeros(num_cycles, 3);
    for c = 1:num_cycles
        bar_colors(c, :) = cycle_colors_cell{c};
    end

    %% Create figure — 3 subplots
    fig = figure('Position', [100 100 1500 900], 'Visible', 'off');

    %% SUBPLOT 1: Mean +/- SE with individual fly scatter
    ax1 = subplot(3, 1, 1);
    hold on;

    % Individual fly scatter (jittered)
    for c = 1:num_cycles
        fly_vals = dist_matrix(:, c);
        valid = find(~isnan(fly_vals));
        if ~isempty(valid)
            jitter = (rand(length(valid), 1) - 0.5) * 0.35;
            scatter(ax1, c + jitter, fly_vals(valid), 18, ...
                bar_colors(c, :), 'filled', 'MarkerFaceAlpha', 0.4);
        end
    end

    % Mean +/- SE as black markers with error bars
    valid_mean = ~isnan(mean_dists);
    errorbar(ax1, cycle_nums(valid_mean), mean_dists(valid_mean), ...
        sem_dists(valid_mean), 'k.', 'LineWidth', 1.5, 'CapSize', 4, 'MarkerSize', 12);

    % Formatting
    set(ax1, 'XTick', cycle_nums, 'XTickLabel', cycle_lbls, 'XTickLabelRotation', 45);
    xlabel('Cycle', 'FontSize', 10);
    ylabel('Distance (mm)', 'FontSize', 11);
    title(sprintf('%s — Distance [%s] (%d/%d alive, %.2f px/mm)', ...
        strrep(exp_name, '_', '\_'), protocol, num_alive, num_flies, pixels_per_mm), ...
        'FontSize', 12, 'FontWeight', 'bold');
    xlim([0.5, num_cycles + 0.5]);
    max_val = max(dist_matrix(:));
    if isnan(max_val) || max_val == 0
        max_val = 1;
    end
    ylim([0, max_val * 1.15]);
    grid on; box on;
    hold off;

    %% SUBPLOT 2: Per-fly distance heatmap
    ax2 = subplot(3, 1, 2);

    imagesc(ax2, dist_matrix);
    colormap(ax2, parula);
    max_dist = max(dist_matrix(~isnan(dist_matrix)));
    if isempty(max_dist) || max_dist == 0
        max_dist = 1;
    end
    caxis(ax2, [0, max_dist]);

    % Overlay white patches for NaN cells
    hold(ax2, 'on');
    [nan_r, nan_c] = find(isnan(dist_matrix));
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
    cb.Label.String = 'Distance (mm)';
    cb.Label.FontSize = 10;

    %% SUBPLOT 3: Contributing flies per cycle
    ax3 = subplot(3, 1, 3);
    hold on;

    n_dead_vec = num_flies - n_alive_vec;
    % n_measured = alive flies with non-NaN distance
    n_measured = zeros(num_cycles, 1);
    for c = 1:num_cycles
        n_measured(c) = sum(~isnan(dist_matrix(:, c)));
    end
    n_nan_alive = n_alive_vec - n_measured;
    n_nan_alive(n_nan_alive < 0) = 0;

    stack_data = [n_measured, n_nan_alive, n_dead_vec];
    hb = bar(ax3, cycle_nums, stack_data, 'stacked');

    hb(1).FaceColor = [0.2 0.5 0.8];   % measured — blue
    hb(2).FaceColor = [0.95 0.6 0.15];  % alive but NaN — orange
    hb(3).FaceColor = [0.7 0.7 0.7];    % dead — grey

    legend(ax3, {'Measured', 'Alive (no data)', 'Dead'}, ...
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
        out_file = fullfile(analysis_dir, sprintf('distance_%s.png', exp_name));
        exportgraphics(fig, out_file, 'Resolution', 150);
        savefig(fig, fullfile(analysis_dir, sprintf('distance_%s.fig', exp_name)));
        fprintf('Saved distance plot: %s\n', out_file);
    end

    if opts.ShowPlots
        set(fig, 'Visible', 'on');
    else
        close(fig);
    end

    %% Save individual standalone plots
    if opts.SavePlot
        title_str_base = sprintf('%s [%s] (%d/%d alive, %.2f px/mm)', ...
            strrep(exp_name, '_', '\_'), protocol, num_alive, num_flies, pixels_per_mm);

        % --- 1. Scatter + errorbar ---
        fig1 = figure('Position', [100 100 1500 400], 'Visible', 'off');
        ax = axes(fig1); hold(ax, 'on');
        for c = 1:num_cycles
            fly_vals = dist_matrix(:, c);
            valid = find(~isnan(fly_vals));
            if ~isempty(valid)
                jitter = (rand(length(valid), 1) - 0.5) * 0.35;
                scatter(ax, c + jitter, fly_vals(valid), 18, ...
                    bar_colors(c, :), 'filled', 'MarkerFaceAlpha', 0.4);
            end
        end
        valid_mean = ~isnan(mean_dists);
        errorbar(ax, cycle_nums(valid_mean), mean_dists(valid_mean), ...
            sem_dists(valid_mean), 'k.', 'LineWidth', 1.5, 'CapSize', 4, 'MarkerSize', 12);
        set(ax, 'XTick', cycle_nums, 'XTickLabel', cycle_lbls, 'XTickLabelRotation', 45);
        xlabel(ax, 'Cycle', 'FontSize', 10);
        ylabel(ax, 'Distance (mm)', 'FontSize', 11);
        title(ax, sprintf('Distance — %s', title_str_base), 'FontSize', 12, 'FontWeight', 'bold');
        xlim(ax, [0.5, num_cycles + 0.5]);
        max_val = max(dist_matrix(:));
        if isnan(max_val) || max_val == 0; max_val = 1; end
        ylim(ax, [0, max_val * 1.15]);
        grid(ax, 'on'); box(ax, 'on'); hold(ax, 'off');
        exportgraphics(fig1, fullfile(analysis_dir, sprintf('distance_scatter_%s.png', exp_name)), 'Resolution', 150);
        savefig(fig1, fullfile(analysis_dir, sprintf('distance_scatter_%s.fig', exp_name)));
        close(fig1);

        % --- 2. Heatmap ---
        fig2 = figure('Position', [100 100 1500 400], 'Visible', 'off');
        ax = axes(fig2);
        max_dist = max(dist_matrix(~isnan(dist_matrix)));
        if isempty(max_dist) || max_dist == 0; max_dist = 1; end
        imagesc(ax, dist_matrix);
        colormap(ax, parula); caxis(ax, [0, max_dist]);
        hold(ax, 'on');
        [nan_r, nan_c] = find(isnan(dist_matrix));
        for k = 1:length(nan_r)
            patch(ax, [nan_c(k)-0.5 nan_c(k)+0.5 nan_c(k)+0.5 nan_c(k)-0.5], ...
                  [nan_r(k)-0.5 nan_r(k)-0.5 nan_r(k)+0.5 nan_r(k)+0.5], ...
                  'w', 'EdgeColor', 'none');
        end
        hold(ax, 'off');
        set(ax, 'XTick', cycle_nums, 'XTickLabel', cycle_lbls, 'XTickLabelRotation', 45);
        ylabel(ax, 'Fly ID', 'FontSize', 11);
        xlabel(ax, 'Cycle', 'FontSize', 10);
        title(ax, sprintf('Distance Heatmap — %s', title_str_base), 'FontSize', 12, 'FontWeight', 'bold');
        if num_flies <= 20; set(ax, 'YTick', 1:num_flies);
        else; set(ax, 'YTick', 1:5:num_flies); end
        cb = colorbar(ax, 'Location', 'EastOutside');
        cb.Label.String = 'Distance (mm)'; cb.Label.FontSize = 10;
        exportgraphics(fig2, fullfile(analysis_dir, sprintf('distance_heatmap_%s.png', exp_name)), 'Resolution', 150);
        savefig(fig2, fullfile(analysis_dir, sprintf('distance_heatmap_%s.fig', exp_name)));
        close(fig2);

        % --- 3. Contributing flies ---
        fig3 = figure('Position', [100 100 1500 350], 'Visible', 'off');
        ax = axes(fig3); hold(ax, 'on');
        stack_data_ind = [n_measured, n_nan_alive, n_dead_vec];
        hb_ind = bar(ax, cycle_nums, stack_data_ind, 'stacked');
        hb_ind(1).FaceColor = [0.2 0.5 0.8];
        hb_ind(2).FaceColor = [0.95 0.6 0.15];
        hb_ind(3).FaceColor = [0.7 0.7 0.7];
        legend(ax, {'Measured', 'Alive (no data)', 'Dead'}, ...
            'Location', 'NorthEastOutside', 'FontSize', 8);
        set(ax, 'XTick', cycle_nums, 'XTickLabel', cycle_lbls, 'XTickLabelRotation', 45);
        xlabel(ax, 'Cycle', 'FontSize', 10);
        ylabel(ax, '# Flies', 'FontSize', 11);
        title(ax, sprintf('Contributing Flies — %s', title_str_base), 'FontSize', 12, 'FontWeight', 'bold');
        ylim(ax, [0, num_flies + 1]);
        xlim(ax, [0.5, num_cycles + 0.5]);
        grid(ax, 'on'); box(ax, 'on'); hold(ax, 'off');
        exportgraphics(fig3, fullfile(analysis_dir, sprintf('distance_contributing_%s.png', exp_name)), 'Resolution', 150);
        savefig(fig3, fullfile(analysis_dir, sprintf('distance_contributing_%s.fig', exp_name)));
        close(fig3);
    end

    %% Return summary if requested
    if nargout > 0
        varargout{1} = summary;
    end

end

%% ======== LOCAL HELPERS ========

function [labels, colors] = get_distance_cycle_colors(protocol, num_cycles)
% GET_DISTANCE_CYCLE_COLORS  Return cycle labels and colors based on protocol
%   Uses get_protocol_config as single source of truth.

    GREY = [0.5 0.5 0.5];

    cfg = get_protocol_config(protocol);
    if cfg.num_cycles > 0
        labels = cfg.labels;
        colors = cfg.colors;
    else
        % Unknown protocol fallback
        labels = arrayfun(@(c) sprintf('C%d', c), 1:num_cycles, 'UniformOutput', false);
        colors = repmat({GREY}, 1, num_cycles);
    end
end
