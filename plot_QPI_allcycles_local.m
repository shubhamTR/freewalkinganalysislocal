function plot_QPI_allcycles_local(protocol, varargin)
% PLOT_QPI_ALLCYCLES_LOCAL  Per-cycle QPI for place learning protocols
%
%   plot_QPI_allcycles_local('P017')
%   plot_QPI_allcycles_local('P017', 'ShowPlots', true)
%
%   Generates ONE SEPARATE FIGURE PER GENOTYPE.
%   Uses errorbar() with training-block shading, probe dashed lines,
%   and pre-probe / pre-train annotations.
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
        fprintf('  %s: Not a place learning protocol — skipping all-cycles QPI plot.\n', protocol);
        return;
    end
    preprobe_cycle  = cfg.preprobe_cycle;
    pretrain_cycle  = cfg.pretrain_cycle;
    probe_cycles    = cfg.block_probe_cycles;
    opto_cycles     = cfg.om_cycles;
    % Convert training_blocks from cell of vectors to cell of [start end] pairs
    training_blocks = cell(cfg.num_blocks, 1);
    for blk = 1:cfg.num_blocks
        tc = cfg.training_blocks{blk};
        training_blocks{blk} = [tc(1), tc(end)];
    end

    %% Detect single-quadrant protocol (QPI can be negative)
    is_single_quadrant = isfield(cfg, 'led_to_quad') && ~isempty(cfg.led_to_quad);

    %% Half label for title and filename
    if contains(METRIC, 'firsthalf')
        half_label = 'First Half';
        half_suffix = 'firsthalf';
    else
        half_label = 'Second Half';
        half_suffix = 'secondhalf';
    end

    %% Get cycle info
    all_cycles = sort(unique(T.cycle));
    num_cycles = length(all_cycles);

    cycle_labels = cell(num_cycles, 1);
    for ci = 1:num_cycles
        c = all_cycles(ci);
        idx = find(T.cycle == c, 1, 'first');
        if ~isempty(idx)
            cycle_labels{ci} = T.label{idx};
        else
            cycle_labels{ci} = sprintf('C%d', c);
        end
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

        exp_vals = NaN(n_exps, num_cycles);
        for ei = 1:n_exps
            exp_mask = strcmp(T.experiment, exps{ei});
            for ci = 1:num_cycles
                c = all_cycles(ci);
                row_mask = exp_mask & T.cycle == c;
                if any(row_mask)
                    exp_vals(ei, ci) = T.(METRIC)(row_mask);
                end
            end
        end

        n_valid = sum(~isnan(exp_vals), 1);
        m  = mean(exp_vals, 1, 'omitnan');
        se = std(exp_vals, 0, 1, 'omitnan') ./ sqrt(max(n_valid, 1));

        fig = figure('Position', [100 100 1300 500], 'Visible', 'off');
        ax = axes; hold on;

        % Plot errorbar
        errorbar(1:num_cycles, m, se, 'o-', ...
            'Color', col, 'MarkerFaceColor', col, ...
            'MarkerSize', 5, 'LineWidth', 1.2, 'CapSize', 4);

        if is_single_quadrant
            yl = ylim(ax);
            ylim([min(yl(1), -0.6) 1]);
        else
            ylim([0 1]);
        end

        % Annotations
        add_qpi_annotations(ax, num_cycles, training_blocks, ...
            preprobe_cycle, pretrain_cycle, probe_cycles, opto_cycles);

        set(ax, 'XTick', 1:num_cycles, 'XTickLabel', cycle_labels);
        xtickangle(90);
        set(ax, 'FontSize', 16);
        xlabel('Cycle', 'FontSize', 18);
        ylabel('Mean |QPI|', 'FontSize', 18);
        title(sprintf('%s  —  %d experiments  |  QPI %s  (%s)', ...
            geno, n_exps, half_label, protocol), 'FontSize', 20);
        xlim([0.5 num_cycles + 0.5]);
        grid on; box on;

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('QPI_allcycles_%s_%s_%s.png', protocol, half_suffix, geno));
            exportgraphics(fig, out_file, 'Resolution', 200);
            saveas(fig, strrep(out_file, '.png', '.svg'));
            savefig(fig, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved QPI all-cycles: %s\n', out_file);
        end
        if opts.ShowPlots, set(fig, 'Visible', 'on'); else, close(fig); end
    end

    %% ===== OVERLAY FIGURE: all genotypes on one plot =====
    nGenos = length(geno_order);
    if nGenos > 0
        fig_ov = figure('Position', [100 100 1400 550], 'Visible', 'off');
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

            exp_vals = NaN(n_exps, num_cycles);
            for ei = 1:n_exps
                exp_mask = strcmp(T.experiment, exps{ei});
                for ci = 1:num_cycles
                    c = all_cycles(ci);
                    row_mask = exp_mask & T.cycle == c;
                    if any(row_mask)
                        exp_vals(ei, ci) = T.(METRIC)(row_mask);
                    end
                end
            end

            n_valid = sum(~isnan(exp_vals), 1);
            m  = mean(exp_vals, 1, 'omitnan');
            se = std(exp_vals, 0, 1, 'omitnan') ./ sqrt(max(n_valid, 1));

            % SEM ribbon
            valid = ~isnan(m);
            x_v = find(valid);
            m_v = m(valid);
            se_v = se(valid);
            fill_x = [x_v, fliplr(x_v)];
            fill_y = [m_v + se_v, fliplr(m_v - se_v)];
            fill(ax_ov, fill_x, fill_y, col, 'FaceAlpha', 0.2, ...
                'EdgeColor', 'none', 'HandleVisibility', 'off');

            h = plot(ax_ov, x_v, m_v, 'o-', ...
                'Color', col, 'MarkerFaceColor', col, ...
                'MarkerSize', 5, 'LineWidth', 1.2);
            h_lines = [h_lines, h]; %#ok<AGROW>
            legend_entries{end+1} = sprintf('%s (n=%d)', geno, n_exps); %#ok<AGROW>
        end

        if is_single_quadrant
            yl = ylim(ax_ov);
            ylim([min(yl(1), -0.6) 1]);
        else
            ylim([0 1]);
        end

        add_qpi_annotations(ax_ov, num_cycles, training_blocks, ...
            preprobe_cycle, pretrain_cycle, probe_cycles, opto_cycles);

        % Bring lines to front (over ribbons and patches)
        children = get(ax_ov, 'Children');
        is_line = arrayfun(@(c) isa(c, 'matlab.graphics.chart.primitive.Line'), children);
        set(ax_ov, 'Children', [children(is_line); children(~is_line)]);

        set(ax_ov, 'XTick', 1:num_cycles, 'XTickLabel', cycle_labels);
        xtickangle(90);
        set(ax_ov, 'FontSize', 16);
        xlabel('Cycle', 'FontSize', 18);
        ylabel('Mean |QPI|', 'FontSize', 18);
        title(sprintf('All genotypes  |  QPI %s  (%s)', half_label, protocol), 'FontSize', 20);
        xlim([0.5 num_cycles + 0.5]);
        grid on; box on;

        if ~isempty(h_lines)
            legend(h_lines, legend_entries, 'Location', 'bestoutside', 'FontSize', 14);
        end

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('QPI_allcycles_%s_%s_overlay.png', protocol, half_suffix));
            exportgraphics(fig_ov, out_file, 'Resolution', 200);
            saveas(fig_ov, strrep(out_file, '.png', '.svg'));
            savefig(fig_ov, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved QPI all-cycles overlay: %s\n', out_file);
        end
        if opts.ShowPlots, set(fig_ov, 'Visible', 'on'); else, close(fig_ov); end
    end
end


function add_qpi_annotations(ax, max_cycles, training_blocks, ...
    preprobe_cycle, pretrain_cycle, probe_cycles, opto_cycles)

    hold(ax, 'on');
    yl = ylim(ax);

    % Training block shading
    for b = 1:length(training_blocks)
        blk = training_blocks{b};
        if blk(1) <= max_cycles
            x1 = blk(1) - 0.5;
            x2 = min(blk(2), max_cycles) + 0.5;
            p = patch(ax, [x1 x2 x2 x1], [yl(1) yl(1) yl(2) yl(2)], ...
                [0.85 0.92 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.35);
            set(p, 'HandleVisibility', 'off');
        end
    end

    % Probe shading
    all_probes = [preprobe_cycle, probe_cycles];
    for pc = all_probes
        if pc <= max_cycles
            p = patch(ax, [pc-0.5 pc+0.5 pc+0.5 pc-0.5], [yl(1) yl(1) yl(2) yl(2)], ...
                [0.9 0.9 0.95], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
            set(p, 'HandleVisibility', 'off');
        end
    end

    % Optomotor shading
    for oc = opto_cycles
        if oc <= max_cycles
            p = patch(ax, [oc-0.5 oc+0.5 oc+0.5 oc-0.5], [yl(1) yl(1) yl(2) yl(2)], ...
                [1 0.92 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
            set(p, 'HandleVisibility', 'off');
        end
    end

    % Block boundaries
    for b = 1:length(training_blocks)
        blk = training_blocks{b};
        if blk(1) <= max_cycles
            xline(blk(1) - 0.5, ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 0.8, ...
                'HandleVisibility', 'off');
        end
    end

    % Bring data to front
    children = get(ax, 'Children');
    is_data = arrayfun(@(c) isa(c, 'matlab.graphics.chart.decoration.ErrorBar'), children);
    set(ax, 'Children', [children(is_data); children(~is_data)]);
    ylim(ax, yl);
end
