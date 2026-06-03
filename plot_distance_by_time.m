function plot_distance_by_time(varargin)
% PLOT_DISTANCE_BY_TIME  Per-experiment distance traces colored by time of day.
%
%   plot_distance_by_time()
%   plot_distance_by_time('ShowPlots', true)
%
%   For L2A experiments in P008 (Coupled), P010 (Uncoupled), P011 (Dark):
%   plots individual experiment block-mean distance traces, one subplot per
%   condition, with line color mapped to experiment start time of day.
%
%   Colormap: cool-to-warm (morning=blue, afternoon=red) using the
%   experiment timestamp extracted from the folder name.

    ip = inputParser;
    addParameter(ip, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(ip, 'Genotype', 'L2A', @ischar);
    addParameter(ip, 'ShowPlots', false, @islogical);
    addParameter(ip, 'SavePath', '', @ischar);
    parse(ip, varargin{:});
    opts = ip.Results;

    ADIR = opts.AnalysisDir;
    GENO = opts.Genotype;

    if isempty(opts.SavePath)
        save_dir = fullfile(ADIR, 'condition_comparison', 'time_of_day');
    else
        save_dir = opts.SavePath;
    end
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end

    %% Conditions
    conds = struct();
    conds(1).protocol = 'P008';  conds(1).label = 'Coupled';
    conds(2).protocol = 'P010';  conds(2).label = 'Uncoupled';
    conds(3).protocol = 'P011';  conds(3).label = 'Dark';
    nConds = length(conds);

    %% Block structure (P006-P011)
    num_blocks = 4;
    offset = 3;
    block_train_cycles = cell(num_blocks, 1);
    for blk = 1:num_blocks
        blk_start = offset + (blk - 1) * 11 + 1;
        block_train_cycles{blk} = blk_start : (blk_start + 9);
    end

    %% Also build all-cycles list (exclude opto, probes, PP)
    opto_cycles    = [1, 48];
    preprobe_cycle = 2;
    probe_cycles   = [14, 25, 36, 47];
    exclude_cycles = [opto_cycles, probe_cycles, preprobe_cycle];

    %% Global time range for consistent colormap
    all_hours = [];
    for ci = 1:nConds
        prot = conds(ci).protocol;
        T = load_distance_table(ADIR, prot);
        exps = unique(T.experiment(strcmp(T.genotype, GENO)));
        for ei = 1:length(exps)
            h = extract_hour(exps{ei});
            if ~isnan(h), all_hours(end+1) = h; end %#ok<AGROW>
        end
    end
    h_min = min(all_hours);
    h_max = max(all_hours);
    fprintf('Time range: %.1f – %.1f hours\n', h_min, h_max);

    %% Colormap: parula-like from blue (morning) to red (afternoon)
    cmap = build_time_colormap(256);

    %% ================================================================
    %  FIGURE 1: Block means — one subplot per condition
    %  ================================================================
    fig1 = figure('Position', [50 50 1500 450], 'Visible', 'off');

    for ci = 1:nConds
        ax = subplot(1, 3, ci);
        hold(ax, 'on');

        prot = conds(ci).protocol;
        T = load_distance_table(ADIR, prot);
        exps = unique(T.experiment(strcmp(T.genotype, GENO)));
        n_exp = length(exps);

        for ei = 1:n_exp
            exp_name = exps{ei};
            h = extract_hour(exp_name);
            col = map_hour_to_color(h, h_min, h_max, cmap);

            exp_mask = strcmp(T.experiment, exp_name);
            blk_means = NaN(1, num_blocks);
            for blk = 1:num_blocks
                train_mask = exp_mask & ismember(T.cycle, block_train_cycles{blk});
                if any(train_mask)
                    blk_means(blk) = mean(T.mean_dist_mm(train_mask), 'omitnan');
                end
            end

            h_line = plot(ax, 1:num_blocks, blk_means, 'o-', ...
                'Color', col, 'MarkerFaceColor', col, ...
                'MarkerSize', 6, 'LineWidth', 1.5);

            % Label the earliest Coupled experiment (11:14 AM outlier)
            if strcmp(prot, 'P008') && contains(exp_name, '20260408_111416')
                % Mark B1 point with annotation
                text(ax, 1.15, blk_means(1), sprintf('%.0f:%02.0f AM', floor(h), mod(round(h*60),60)), ...
                    'FontSize', 8, 'Color', [0.0 0.43 0.34], 'FontWeight', 'bold');
            end
        end

        set(ax, 'XTick', 1:4, 'XTickLabel', {'B1','B2','B3','B4'});
        xlabel('Training Block', 'FontSize', 10);
        ylabel('Distance (mm)', 'FontSize', 10);
        title(sprintf('%s (n=%d)', conds(ci).label, n_exp), 'FontSize', 12, 'FontWeight', 'bold');
        xlim([0.5 4.5]); grid on; box on;

        % Match y-axis across subplots later
    end

    % Sync y-axes
    sync_ylim(fig1);

    % Add colorbar
    cb_ax = axes(fig1, 'Position', [0.93 0.15 0.015 0.7]);
    colormap(cb_ax, cmap);
    caxis(cb_ax, [h_min h_max]);
    cb = colorbar(cb_ax, 'Location', 'eastoutside');
    cb.Label.String = 'Time of day (h)';
    cb.Label.FontSize = 10;
    axis(cb_ax, 'off');

    sgtitle(fig1, sprintf('%s — Distance by Time of Day', GENO), ...
        'FontSize', 14, 'FontWeight', 'bold');

    exportgraphics(fig1, fullfile(save_dir, sprintf('blocks_by_time_%s.png', GENO)), 'Resolution', 250);
    saveas(fig1, fullfile(save_dir, sprintf('blocks_by_time_%s.svg', GENO)));
    savefig(fig1, fullfile(save_dir, sprintf('blocks_by_time_%s.fig', GENO)));
    fprintf('Saved: blocks_by_time_%s.png\n', GENO);
    if opts.ShowPlots, set(fig1, 'Visible', 'on'); else, close(fig1); end

    %% ================================================================
    %  FIGURE 2: All training cycles — one subplot per condition
    %  ================================================================
    fig2 = figure('Position', [50 50 1500 450], 'Visible', 'off');

    for ci = 1:nConds
        ax = subplot(1, 3, ci);
        hold(ax, 'on');

        prot = conds(ci).protocol;
        T = load_distance_table(ADIR, prot);

        ref_cycles = sort(unique(T.cycle));
        plot_cycles = setdiff(ref_cycles, exclude_cycles);
        num_cycles = length(plot_cycles);

        exps = unique(T.experiment(strcmp(T.genotype, GENO)));
        n_exp = length(exps);

        for ei = 1:n_exp
            exp_name = exps{ei};
            h = extract_hour(exp_name);
            col = map_hour_to_color(h, h_min, h_max, cmap);

            exp_mask = strcmp(T.experiment, exp_name);
            cycle_vals = NaN(1, num_cycles);
            for cii = 1:num_cycles
                row_mask = exp_mask & T.cycle == plot_cycles(cii);
                if any(row_mask)
                    cycle_vals(cii) = mean(T.mean_dist_mm(row_mask), 'omitnan');
                end
            end

            plot(ax, 1:num_cycles, cycle_vals, '-', ...
                'Color', [col 0.7], 'LineWidth', 1.2);
        end

        set(ax, 'XTick', 1:4:num_cycles);
        xlabel('Cycle', 'FontSize', 10);
        ylabel('Distance (mm)', 'FontSize', 10);
        title(sprintf('%s (n=%d)', conds(ci).label, n_exp), 'FontSize', 12, 'FontWeight', 'bold');
        xlim([0.5 num_cycles+0.5]); grid on; box on;
    end

    sync_ylim(fig2);

    cb_ax2 = axes(fig2, 'Position', [0.93 0.15 0.015 0.7]);
    colormap(cb_ax2, cmap);
    caxis(cb_ax2, [h_min h_max]);
    cb2 = colorbar(cb_ax2, 'Location', 'eastoutside');
    cb2.Label.String = 'Time of day (h)';
    cb2.Label.FontSize = 10;
    axis(cb_ax2, 'off');

    sgtitle(fig2, sprintf('%s — All Cycles by Time of Day', GENO), ...
        'FontSize', 14, 'FontWeight', 'bold');

    exportgraphics(fig2, fullfile(save_dir, sprintf('allcycles_by_time_%s.png', GENO)), 'Resolution', 250);
    saveas(fig2, fullfile(save_dir, sprintf('allcycles_by_time_%s.svg', GENO)));
    savefig(fig2, fullfile(save_dir, sprintf('allcycles_by_time_%s.fig', GENO)));
    fprintf('Saved: allcycles_by_time_%s.png\n', GENO);
    if opts.ShowPlots, set(fig2, 'Visible', 'on'); else, close(fig2); end

    fprintf('Done. Saved to: %s\n', save_dir);
end


%% ========================================================================
function T = load_distance_table(adir, prot)
    f = fullfile(adir, prot, sprintf('distance_summary_%s.mat', prot));
    loaded = load(f, 'distance_summary');
    T = loaded.distance_summary;
end


%% ========================================================================
function h = extract_hour(exp_name)
    % Extract time from folder name: ..._YYYYMMDD_HHMMSS
    tok = regexp(exp_name, '_(\d{6})$', 'tokens');
    if ~isempty(tok)
        ts = tok{1}{1};
        h = str2double(ts(1:2)) + str2double(ts(3:4))/60 + str2double(ts(5:6))/3600;
    else
        h = NaN;
    end
end


%% ========================================================================
function col = map_hour_to_color(h, h_min, h_max, cmap)
    n = size(cmap, 1);
    frac = (h - h_min) / max(h_max - h_min, 0.1);
    frac = min(max(frac, 0), 1);
    idx = max(1, round(frac * (n - 1)) + 1);
    col = cmap(idx, :);
end


%% ========================================================================
function cmap = build_time_colormap(n)
    % Blue (morning) → Yellow (midday) → Red (afternoon)
    r = [linspace(0.1, 1.0, round(n/2)), linspace(1.0, 0.8, n - round(n/2))];
    g = [linspace(0.2, 0.9, round(n/2)), linspace(0.9, 0.1, n - round(n/2))];
    b = [linspace(0.7, 0.2, round(n/2)), linspace(0.2, 0.1, n - round(n/2))];
    cmap = [r(:), g(:), b(:)];
end


%% ========================================================================
function sync_ylim(fig)
    axs = findobj(fig, 'Type', 'axes');
    % Exclude colorbar axes
    axs = axs(arrayfun(@(a) ~isempty(get(a, 'Children')), axs));
    yl_all = [Inf, -Inf];
    for i = 1:length(axs)
        yl = ylim(axs(i));
        yl_all(1) = min(yl_all(1), yl(1));
        yl_all(2) = max(yl_all(2), yl(2));
    end
    yl_all(1) = 0;
    yl_all(2) = yl_all(2) * 1.05;
    for i = 1:length(axs)
        ylim(axs(i), yl_all);
    end
end
