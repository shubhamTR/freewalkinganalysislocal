function plot_QPI_blocks_local(protocol, varargin)
% PLOT_QPI_BLOCKS_LOCAL  Block-mean training QPI for place learning protocols
%
%   plot_QPI_blocks_local('P017')
%   plot_QPI_blocks_local('P017', 'ShowPlots', true)
%
%   Generates ONE SEPARATE FIGURE PER GENOTYPE.
%   Plots mean |QPI| per training block (PP + B1-B4) with errorbar.
%
%   NAME-VALUE PARAMETERS
%     'AnalysisDir'  — root of protocol folders (default: ~/Documents/analysisdatalocal)
%     'SavePath'     — folder to save PNG (default: '' = auto)
%     'ShowPlots'    — keep figure visible (default: true)
%     'ControlGeno'  — control genotype name (default: 'L1')
%     'Metric'       — 'mean_QPI_firsthalf' or 'mean_QPI_secondhalf'

    %% Parse
    p = inputParser;
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    addParameter(p, 'ControlGeno', 'L1', @ischar);
    addParameter(p, 'Metric', 'mean_QPI_secondhalf', @ischar);
    parse(p, protocol, varargin{:});
    opts = p.Results;

    %% Load QPI summary
    ADIR = opts.AnalysisDir;
    summary_file = fullfile(ADIR, protocol, sprintf('QPI_summary_%s.mat', protocol));
    if ~exist(summary_file, 'file')
        error('QPI summary not found: %s\nRun batch_QPI_summary first.', summary_file);
    end
    tmp = load(summary_file, 'QPI_summary');
    T = tmp.QPI_summary;

    %% Default save path
    if isempty(opts.SavePath)
        opts.SavePath = fullfile(ADIR, protocol, 'QPI_summary');
    end
    CONTROL = opts.ControlGeno;
    METRIC  = opts.Metric;

    %% Determine cycle layout from get_protocol_config (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_place_learning
        fprintf('  %s: Not a place learning protocol — skipping block QPI plot.\n', protocol);
        return;
    end
    preprobe_cycle   = cfg.preprobe_cycle;
    num_blocks       = cfg.num_blocks;
    block_train_cycles = cfg.training_blocks;  % cell of cycle vectors per block
    is_single_quadrant = isfield(cfg, 'led_to_quad') && ~isempty(cfg.led_to_quad);

    %% Half label for title and filename
    if contains(METRIC, 'firsthalf')
        half_label = 'First Half';
        half_suffix = 'firsthalf';
    else
        half_label = 'Second Half';
        half_suffix = 'secondhalf';
    end

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
        exp_preprobe    = NaN(n_exps, 1);

        for ei = 1:n_exps
            exp_mask = strcmp(T.experiment, exps{ei});
            pp_mask = exp_mask & T.cycle == preprobe_cycle;
            if any(pp_mask)
                exp_preprobe(ei) = mean(T.(METRIC)(pp_mask), 'omitnan');
            end
            for blk = 1:num_blocks
                train_mask = exp_mask & ismember(T.cycle, block_train_cycles{blk});
                if any(train_mask)
                    exp_block_means(ei, blk) = mean(T.(METRIC)(train_mask), 'omitnan');
                end
            end
        end

        pp_m  = mean(exp_preprobe, 'omitnan');
        pp_se = std(exp_preprobe, 0, 'omitnan') / sqrt(sum(~isnan(exp_preprobe)));
        blk_m  = mean(exp_block_means, 1, 'omitnan');
        blk_n  = sum(~isnan(exp_block_means), 1);
        blk_se = std(exp_block_means, 0, 1, 'omitnan') ./ sqrt(blk_n);

        all_x  = [0, 1:num_blocks];
        all_m  = [pp_m, blk_m];
        all_se = [pp_se, blk_se];

        fig = figure('Position', [50 50 600 500], 'Visible', 'off');
        ax = axes; hold on;

        errorbar(all_x, all_m, all_se, 'o-', ...
            'Color', col, 'MarkerFaceColor', col, ...
            'MarkerSize', 8, 'LineWidth', 1.5, 'CapSize', 6);

        blk_tick_labels = arrayfun(@(b) sprintf('B%d', b), 1:num_blocks, 'UniformOutput', false);
        set(ax, 'XTick', 0:num_blocks, 'XTickLabel', [{'PP'}, blk_tick_labels]);
        set(ax, 'FontSize', 16);
        xlabel('Training Block', 'FontSize', 18);
        ylabel('Mean |QPI|', 'FontSize', 18);
        title(sprintf('%s  —  %d experiments  |  QPI %s  (%s)', ...
            geno, n_exps, half_label, protocol), 'FontSize', 20);
        if is_single_quadrant
            yl = ylim(ax);
            ylim([min(yl(1), -0.6) 1]);
        else
            ylim([0 1]);
        end
        xlim([-0.5 num_blocks+0.5]);
        grid on; box on;

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('QPI_blocks_%s_%s_%s.png', protocol, half_suffix, geno));
            exportgraphics(fig, out_file, 'Resolution', 200);
            saveas(fig, strrep(out_file, '.png', '.svg'));
            savefig(fig, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved block QPI: %s\n', out_file);
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
            exp_preprobe    = NaN(n_exps, 1);

            for ei = 1:n_exps
                exp_mask = strcmp(T.experiment, exps{ei});
                pp_mask = exp_mask & T.cycle == preprobe_cycle;
                if any(pp_mask)
                    exp_preprobe(ei) = mean(T.(METRIC)(pp_mask), 'omitnan');
                end
                for blk = 1:num_blocks
                    train_mask = exp_mask & ismember(T.cycle, block_train_cycles{blk});
                    if any(train_mask)
                        exp_block_means(ei, blk) = mean(T.(METRIC)(train_mask), 'omitnan');
                    end
                end
            end

            pp_m  = mean(exp_preprobe, 'omitnan');
            pp_se = std(exp_preprobe, 0, 'omitnan') / sqrt(sum(~isnan(exp_preprobe)));
            blk_m  = mean(exp_block_means, 1, 'omitnan');
            blk_n  = sum(~isnan(exp_block_means), 1);
            blk_se = std(exp_block_means, 0, 1, 'omitnan') ./ sqrt(blk_n);

            all_x  = [0, 1:num_blocks];
            all_m  = [pp_m, blk_m];
            all_se = [pp_se, blk_se];

            % SEM ribbon
            fill_x = [all_x, fliplr(all_x)];
            fill_y = [all_m + all_se, fliplr(all_m - all_se)];
            fill(ax_ov, fill_x, fill_y, col, 'FaceAlpha', 0.2, ...
                'EdgeColor', 'none', 'HandleVisibility', 'off');

            h = plot(ax_ov, all_x, all_m, 'o-', ...
                'Color', col, 'MarkerFaceColor', col, ...
                'MarkerSize', 8, 'LineWidth', 1.5);
            h_lines = [h_lines, h]; %#ok<AGROW>
            legend_entries{end+1} = sprintf('%s (n=%d)', geno, n_exps); %#ok<AGROW>
        end

        blk_tick_labels_ov = arrayfun(@(b) sprintf('B%d', b), 1:num_blocks, 'UniformOutput', false);
        set(ax_ov, 'XTick', 0:num_blocks, 'XTickLabel', [{'PP'}, blk_tick_labels_ov]);
        set(ax_ov, 'FontSize', 16);
        xlabel('Training Block', 'FontSize', 18);
        ylabel('Mean |QPI|', 'FontSize', 18);
        title(sprintf('All genotypes  |  QPI %s  (%s)', half_label, protocol), 'FontSize', 20);
        if is_single_quadrant
            yl = ylim(ax_ov);
            ylim([min(yl(1), -0.6) 1]);
        else
            ylim([0 1]);
        end
        xlim([-0.5 num_blocks+0.5]);
        grid on; box on;

        if ~isempty(h_lines)
            legend(h_lines, legend_entries, 'Location', 'bestoutside', 'FontSize', 14);
        end

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('QPI_blocks_%s_%s_overlay.png', protocol, half_suffix));
            exportgraphics(fig_ov, out_file, 'Resolution', 200);
            saveas(fig_ov, strrep(out_file, '.png', '.svg'));
            savefig(fig_ov, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved block QPI overlay: %s\n', out_file);
        end
        if opts.ShowPlots, set(fig_ov, 'Visible', 'on'); else, close(fig_ov); end
    end
end
