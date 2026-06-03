function plot_dist_to_safe_allcycles_local(dist_to_safe_summary, protocol, varargin)
% PLOT_DIST_TO_SAFE_ALLCYCLES_LOCAL  Per-cycle distance-to-safe for place learning protocols
%
%   Generates ONE SEPARATE FIGURE PER GENOTYPE.
%   Uses errorbar() with training-block shading, pre-train annotation.
%   PP and probes are excluded (see probes plotter).
%
%   Applies to: P003, P005, P006, P007, P008, P009
%
%   NAME-VALUE PARAMETERS
%     'SavePath'       — folder to save PNG (default: '' = no save)
%     'ShowPlots'      — keep figure visible (default: true)
%     'ControlGeno'    — control genotype name (default: 'L1')
%     'Metric'         — 'mean_dist_to_safe_mm' (default)
%     'PlotName'       — custom filename prefix (default: auto from Metric)
%     'YMax'           — fixed y-axis maximum (default: auto)

    %% Parse
    p = inputParser;
    addRequired(p, 'dist_to_safe_summary');
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    addParameter(p, 'ControlGeno', 'L1', @ischar);
    addParameter(p, 'Metric', 'mean_dist_to_safe_mm', @ischar);
    addParameter(p, 'PlotName', '', @ischar);
    addParameter(p, 'YMax', [], @isnumeric);
    parse(p, dist_to_safe_summary, protocol, varargin{:});
    opts = p.Results;

    T = dist_to_safe_summary;
    CONTROL = opts.ControlGeno;
    METRIC  = opts.Metric;

    %% Determine cycle layout from get_protocol_config (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_place_learning
        fprintf('  %s: Not a place learning protocol — skipping all-cycles dist-to-safe plot.\n', protocol);
        return;
    end
    preprobe_cycle  = cfg.preprobe_cycle;
    pretrain_cycle  = cfg.pretrain_cycle;
    opto_cycles     = cfg.om_cycles;
    probe_cycles    = cfg.block_probe_cycles;
    training_blocks = cell(cfg.num_blocks, 1);
    for blk = 1:cfg.num_blocks
        tc = cfg.training_blocks{blk};
        training_blocks{blk} = [tc(1), tc(end)];
    end

    %% Build cycle list: Ag + training only (exclude opto, probes, PP)
    exclude_cycles = [opto_cycles, probe_cycles, preprobe_cycle];
    all_data_cycles = sort(unique(T.cycle));
    plot_cycles = setdiff(all_data_cycles, exclude_cycles);
    num_cycles = length(plot_cycles);

    % Remap pretrain/block positions to new x-axis indices
    pretrain_x  = find(plot_cycles == pretrain_cycle);
    block_x = cell(size(training_blocks));
    for b = 1:length(training_blocks)
        blk_range = training_blocks{b}(1):training_blocks{b}(2);
        block_x{b} = [find(ismember(plot_cycles, blk_range), 1, 'first'), ...
                      find(ismember(plot_cycles, blk_range), 1, 'last')];
    end

    %% Identify genotypes
    all_genos = unique(T.genotype);
    is_control = strcmp(all_genos, CONTROL);
    test_genos = all_genos(~is_control);
    geno_order = [all_genos(is_control); test_genos];

    % Genotype colors — consistent across all plotters (see get_genotype_color.m)

    %% Y-axis label and plot naming
    switch METRIC
        case 'mean_dist_to_safe_mm'
            y_label = 'Distance to Safe — First Entry (mm)';
            plot_suffix = 'dist_to_safe_allcycles';
        case 'median_dist_to_safe_mm'
            y_label = 'Median Distance to Safe — First Entry (mm)';
            plot_suffix = 'dist_to_safe_median_allcycles';
        case 'mean_dist_to_safe_last_mm'
            y_label = 'Distance to Safe — Last Entry (mm)';
            plot_suffix = 'dist_to_safe_last_allcycles';
        case 'median_dist_to_safe_last_mm'
            y_label = 'Median Distance to Safe — Last Entry (mm)';
            plot_suffix = 'dist_to_safe_last_median_allcycles';
        otherwise
            y_label = strrep(METRIC, '_', ' ');
            plot_suffix = 'dist_to_safe_allcycles';
    end

    if ~isempty(opts.PlotName)
        plot_suffix = opts.PlotName;
    end

    y_max = opts.YMax;  % empty = auto-scale

    cycles_x = 1:num_cycles;
    nGenos = length(geno_order);

    %% Generate one figure per genotype
    for gi = 1:nGenos
        geno = geno_order{gi};
        col = get_genotype_color(geno);

        geno_rows = strcmp(T.genotype, geno);
        exps = unique(T.experiment(geno_rows));
        n_exps = length(exps);
        if n_exps == 0, continue; end

        % Compute per-experiment means (training cycles only)
        exp_vals = NaN(n_exps, num_cycles);
        for ei = 1:n_exps
            exp_mask = strcmp(T.experiment, exps{ei});
            for ci = 1:num_cycles
                c = plot_cycles(ci);
                row_mask = exp_mask & T.cycle == c;
                if any(row_mask)
                    exp_vals(ei, ci) = mean(T.(METRIC)(row_mask), 'omitnan');
                end
            end
        end

        n_valid = sum(~isnan(exp_vals), 1);
        m  = mean(exp_vals, 1, 'omitnan');
        se = std(exp_vals, 0, 1, 'omitnan') ./ sqrt(max(n_valid, 1));

        % --- Create figure ---
        fig = figure('Position', [100 100 1300 500], 'Visible', 'off');
        ax = axes; hold on;

        % Plot errorbar
        errorbar(cycles_x, m, se, 'o-', ...
            'Color', col, 'MarkerFaceColor', col, ...
            'MarkerSize', 5, 'LineWidth', 1.2, 'CapSize', 4);

        % Set ylim before annotations
        if ~isempty(y_max)
            ylim([0, y_max]);
        else
            ylim([0, max(m + se) * 1.15]);
        end

        % Protocol annotations (training blocks + Ag marker only)
        add_protocol_annotations(ax, num_cycles, block_x, pretrain_x);

        ylabel(y_label, 'FontSize', 11);
        title(sprintf('%s  —  %d experiments', geno, n_exps), 'FontSize', 13);

        set(ax, 'XTick', 1:2:num_cycles);
        xlim([0.5, num_cycles + 0.5]);
        box on;

        xlabel('Cycle', 'FontSize', 12);

        % Save
        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('%s_%s_%s.png', plot_suffix, protocol, geno));
            saveas(fig, out_file);
            savefig(fig, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved dist-to-safe all-cycles: %s\n', out_file);
        end

        if opts.ShowPlots
            set(fig, 'Visible', 'on');
        else
            close(fig);
        end
    end

    %% ===== OVERLAY FIGURE: all genotypes on one plot =====
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
                    c = plot_cycles(ci);
                    row_mask = exp_mask & T.cycle == c;
                    if any(row_mask)
                        exp_vals(ei, ci) = mean(T.(METRIC)(row_mask), 'omitnan');
                    end
                end
            end

            n_valid = sum(~isnan(exp_vals), 1);
            m  = mean(exp_vals, 1, 'omitnan');
            se = std(exp_vals, 0, 1, 'omitnan') ./ sqrt(max(n_valid, 1));

            % SEM ribbon
            valid = ~isnan(m);
            x_v = cycles_x(valid);
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

        % Set ylim before annotations
        yl_data = ylim(ax_ov);
        if ~isempty(y_max)
            ylim(ax_ov, [0, y_max]);
        else
            ylim(ax_ov, [0, yl_data(2) * 1.15]);
        end

        add_protocol_annotations(ax_ov, num_cycles, block_x, pretrain_x);

        ylabel(y_label, 'FontSize', 11);
        title(sprintf('All genotypes  (%s)', protocol), 'FontSize', 13);
        set(ax_ov, 'XTick', 1:2:num_cycles);
        xlim([0.5, num_cycles + 0.5]);
        box on;
        xlabel('Cycle', 'FontSize', 12);

        if ~isempty(h_lines)
            legend(h_lines, legend_entries, 'Location', 'bestoutside', 'FontSize', 9);
        end

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('%s_%s_overlay.png', plot_suffix, protocol));
            saveas(fig_ov, out_file);
            savefig(fig_ov, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved dist-to-safe all-cycles overlay: %s\n', out_file);
        end
        if opts.ShowPlots, set(fig_ov, 'Visible', 'on'); else, close(fig_ov); end
    end

end


%% ===== LOCAL FUNCTION =====

function add_protocol_annotations(ax, max_x, block_x, pretrain_x)

    hold(ax, 'on');
    yl = ylim(ax);
    num_blks = length(block_x);
    block_names = arrayfun(@(b) sprintf('B%d', b), 1:num_blks, 'UniformOutput', false);

    % Training block shading (alternate light blue for odd blocks)
    for b = 1:length(block_x)
        bx = block_x{b};
        if ~isempty(bx) && bx(1) <= max_x
            x1 = bx(1) - 0.5;
            x2 = min(bx(2), max_x) + 0.5;

            % Shade odd blocks only
            if mod(b, 2) == 1
                pa = patch(ax, [x1 x2 x2 x1], [yl(1) yl(1) yl(2) yl(2)], ...
                    [0.85 0.92 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.25);
                set(pa, 'HandleVisibility', 'off');
            end

            % Block boundary line (between blocks)
            if b > 1
                xline(ax, x1, ':', 'Color', [0.5 0.5 0.5], ...
                    'LineWidth', 0.8, 'HandleVisibility', 'off');
            end

            % Block label at top
            mid_x = (bx(1) + min(bx(2), max_x)) / 2;
            if b <= length(block_names)
                text(mid_x, yl(2) * 0.97, block_names{b}, ...
                    'HorizontalAlignment', 'center', 'FontSize', 9, ...
                    'Color', [0.3 0.3 0.3]);
            end
        end
    end

    % Pre-train (Ag)
    if ~isempty(pretrain_x) && pretrain_x <= max_x
        xl = xline(ax, pretrain_x, ':', 'Color', [0.0 0.4 0.0], 'LineWidth', 1.2, ...
            'Label', 'Ag', 'LabelOrientation', 'horizontal', ...
            'LabelVerticalAlignment', 'top', 'FontSize', 8, ...
            'LabelHorizontalAlignment', 'center');
        set(xl, 'HandleVisibility', 'off');
    end

    % Bring data to front
    children = get(ax, 'Children');
    is_data = arrayfun(@(c) isa(c, 'matlab.graphics.chart.decoration.ErrorBar'), children);
    set(ax, 'Children', [children(is_data); children(~is_data)]);
    ylim(ax, yl);
end
