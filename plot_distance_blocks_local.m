function plot_distance_blocks_local(distance_summary, protocol, varargin)
% PLOT_DISTANCE_BLOCKS_LOCAL  Block-mean training distance for place learning protocols
%
%   Generates ONE SEPARATE FIGURE PER GENOTYPE.
%   Plots mean distance per training block (B1-B4) with errorbar.
%
%   Applies to: P003, P005, P006, P007, P008, P009, P010, P011, P014

    %% Parse
    p = inputParser;
    addRequired(p, 'distance_summary');
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    addParameter(p, 'ControlGeno', 'L1', @ischar);
    addParameter(p, 'Metric', 'mean_dist_mm', @ischar);
    addParameter(p, 'PlotName', '', @ischar);
    parse(p, distance_summary, protocol, varargin{:});
    opts = p.Results;

    T = distance_summary;
    CONTROL = opts.ControlGeno;
    METRIC  = opts.Metric;

    %% Determine cycle layout from get_protocol_config (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_place_learning
        fprintf('  %s: Not a place learning protocol — skipping block distance plot.\n', protocol);
        return;
    end
    num_blocks       = cfg.num_blocks;
    block_train_cycles = cfg.training_blocks;  % cell of cycle vectors per block

    %% Y-axis label and plot naming
    switch METRIC
        case 'mean_dist_mm'
            y_label = 'Mean Distance (mm)';  plot_suffix = 'dist_blocks';
        otherwise
            y_label = strrep(METRIC, '_', ' ');  plot_suffix = 'dist_blocks';
    end
    if ~isempty(opts.PlotName), plot_suffix = opts.PlotName; end

    %% Identify genotypes
    all_genos = unique(T.genotype);
    is_control = strcmp(all_genos, CONTROL);
    geno_order = [all_genos(is_control); all_genos(~is_control)];

    % Genotype colors — consistent across all plotters (see get_genotype_color.m)

    %% One figure per genotype
    for gi = 1:length(geno_order)
        geno = geno_order{gi};
        col = get_genotype_color(geno);

        geno_rows = strcmp(T.genotype, geno);
        exps = unique(T.experiment(geno_rows));
        n_exps = length(exps);
        if n_exps == 0, continue; end

        exp_block_means = NaN(n_exps, num_blocks);

        for ei = 1:n_exps
            exp_mask = strcmp(T.experiment, exps{ei});
            for blk = 1:num_blocks
                train_mask = exp_mask & ismember(T.cycle, block_train_cycles{blk});
                if any(train_mask)
                    exp_block_means(ei, blk) = mean(T.(METRIC)(train_mask), 'omitnan');
                end
            end
        end

        blk_m  = mean(exp_block_means, 1, 'omitnan');
        blk_n  = sum(~isnan(exp_block_means), 1);
        blk_se = std(exp_block_means, 0, 1, 'omitnan') ./ sqrt(blk_n);

        all_x  = 1:num_blocks;
        all_m  = blk_m;
        all_se = blk_se;

        fig = figure('Position', [50 50 600 500], 'Visible', 'off');
        ax = axes; hold on;

        errorbar(all_x, all_m, all_se, 'o-', ...
            'Color', col, 'MarkerFaceColor', col, ...
            'MarkerSize', 8, 'LineWidth', 1.5, 'CapSize', 6);

        blk_tick_labels = arrayfun(@(b) sprintf('B%d', b), 1:num_blocks, 'UniformOutput', false);
        set(ax, 'XTick', 1:num_blocks, 'XTickLabel', blk_tick_labels);
        xlabel('Training Block', 'FontSize', 11);
        ylabel(y_label, 'FontSize', 11);
        title(sprintf('%s  —  %d experiments  (%s)', geno, n_exps, protocol), ...
            'FontSize', 13);
        xlim([0.5 num_blocks+0.5]);
        grid on; box on;

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('%s_%s_%s.png', plot_suffix, protocol, geno));
            saveas(fig, out_file);
            savefig(fig, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved block distance: %s\n', out_file);
        end
        if opts.ShowPlots, set(fig, 'Visible', 'on'); else, close(fig); end
    end

    %% ===== OVERLAY FIGURE: all genotypes on one plot =====
    nGenos = length(geno_order);
    if nGenos > 0
        fig_ov = figure('Position', [50 50 650 500], 'Visible', 'off');
        ax_ov = axes; hold on;
        legend_entries = {};
        h_lines = [];

        for gi = 1:nGenos
            geno = geno_order{gi};
            col = get_genotype_color(geno);

            geno_rows = strcmp(T.genotype, geno);
            exps = unique(T.experiment(geno_rows));
            n_exps = length(exps);
            if n_exps == 0, continue; end

            exp_block_means = NaN(n_exps, num_blocks);
            for ei = 1:n_exps
                exp_mask = strcmp(T.experiment, exps{ei});
                for blk = 1:num_blocks
                    train_mask = exp_mask & ismember(T.cycle, block_train_cycles{blk});
                    if any(train_mask)
                        exp_block_means(ei, blk) = mean(T.(METRIC)(train_mask), 'omitnan');
                    end
                end
            end

            blk_m  = mean(exp_block_means, 1, 'omitnan');
            blk_n  = sum(~isnan(exp_block_means), 1);
            blk_se = std(exp_block_means, 0, 1, 'omitnan') ./ sqrt(blk_n);

            % SEM ribbon
            x_v = 1:num_blocks;
            fill_x = [x_v, fliplr(x_v)];
            fill_y = [blk_m + blk_se, fliplr(blk_m - blk_se)];
            fill(ax_ov, fill_x, fill_y, col, 'FaceAlpha', 0.2, ...
                'EdgeColor', 'none', 'HandleVisibility', 'off');

            h = plot(ax_ov, x_v, blk_m, 'o-', ...
                'Color', col, 'MarkerFaceColor', col, ...
                'MarkerSize', 8, 'LineWidth', 1.5);
            h_lines = [h_lines, h]; %#ok<AGROW>
            legend_entries{end+1} = sprintf('%s (n=%d)', geno, n_exps); %#ok<AGROW>
        end

        blk_tick_labels_ov = arrayfun(@(b) sprintf('B%d', b), 1:num_blocks, 'UniformOutput', false);
        set(ax_ov, 'XTick', 1:num_blocks, 'XTickLabel', blk_tick_labels_ov);
        xlabel('Training Block', 'FontSize', 11);
        ylabel(y_label, 'FontSize', 11);
        title(sprintf('All genotypes  (%s)', protocol), 'FontSize', 13);
        xlim([0.5 num_blocks+0.5]);
        grid on; box on;

        if ~isempty(h_lines)
            legend(h_lines, legend_entries, 'Location', 'bestoutside', 'FontSize', 9);
        end

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('%s_%s_overlay.png', plot_suffix, protocol));
            saveas(fig_ov, out_file);
            savefig(fig_ov, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved block distance overlay: %s\n', out_file);
        end
        if opts.ShowPlots, set(fig_ov, 'Visible', 'on'); else, close(fig_ov); end
    end
end
