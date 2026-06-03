function plot_latency_probes_local(latency_summary, protocol, varargin)
% PLOT_LATENCY_PROBES_LOCAL  Probe-trial latency for place learning protocols
%
%   Generates ONE SEPARATE FIGURE PER GENOTYPE.
%   Plots mean (or median) latency for probe trials (PP + B1.P-B4.P) with errorbar.
%
%   Applies to: P003, P005, P006, P007, P008, P009

    %% Parse
    p = inputParser;
    addRequired(p, 'latency_summary');
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    addParameter(p, 'ControlGeno', 'L1', @ischar);
    addParameter(p, 'Metric', 'mean_latency_s', @ischar);
    addParameter(p, 'PlotName', '', @ischar);
    parse(p, latency_summary, protocol, varargin{:});
    opts = p.Results;

    T = latency_summary;
    CONTROL = opts.ControlGeno;
    METRIC  = opts.Metric;

    %% Determine probe cycle numbers from get_protocol_config (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_place_learning
        fprintf('  %s: Not a place learning protocol — skipping probe latency plot.\n', protocol);
        return;
    end
    probe_cycle_nums = cfg.all_probe_cycle_nums;
    probe_labels     = cfg.probe_labels;
    num_probes = length(probe_cycle_nums);

    switch METRIC
        case 'mean_latency_s'
            y_label = 'Mean Latency (s)';  plot_suffix = 'lat_probes';
        case 'median_latency_s'
            y_label = 'Median Latency (s)';  plot_suffix = 'lat_median_probes';
        otherwise
            y_label = strrep(METRIC, '_', ' ');  plot_suffix = 'lat_probes';
    end
    if ~isempty(opts.PlotName), plot_suffix = opts.PlotName; end

    all_genos = unique(T.genotype);
    is_control = strcmp(all_genos, CONTROL);
    geno_order = [all_genos(is_control); all_genos(~is_control)];
    % Genotype colors — consistent across all plotters (see get_genotype_color.m)

    for gi = 1:length(geno_order)
        geno = geno_order{gi};
        col = get_genotype_color(geno);

        geno_rows = strcmp(T.genotype, geno);
        exps = unique(T.experiment(geno_rows));
        n_exps = length(exps);
        if n_exps == 0, continue; end

        exp_probe_vals = NaN(n_exps, num_probes);
        for ei = 1:n_exps
            exp_mask = strcmp(T.experiment, exps{ei});
            for pi = 1:num_probes
                probe_mask = exp_mask & T.cycle == probe_cycle_nums(pi);
                if any(probe_mask)
                    exp_probe_vals(ei, pi) = mean(T.(METRIC)(probe_mask), 'omitnan');
                end
            end
        end

        prb_m  = mean(exp_probe_vals, 1, 'omitnan');
        prb_n  = sum(~isnan(exp_probe_vals), 1);
        prb_se = std(exp_probe_vals, 0, 1, 'omitnan') ./ sqrt(prb_n);

        fig = figure('Position', [50 50 600 500], 'Visible', 'off');
        ax = axes; hold on;

        valid = ~isnan(prb_m);
        if any(valid)
            errorbar(find(valid), prb_m(valid), prb_se(valid), '-^', ...
                'Color', col, 'MarkerFaceColor', col, ...
                'MarkerSize', 8, 'LineWidth', 1.5, 'CapSize', 6);
        end

        set(ax, 'XTick', 1:num_probes, 'XTickLabel', probe_labels);
        xlabel('Probe Trial', 'FontSize', 11);
        ylabel(y_label, 'FontSize', 11);
        title(sprintf('%s  —  %d experiments  (%s)', geno, n_exps, protocol), ...
            'FontSize', 13);
        xlim([0.5 num_probes + 0.5]);
        grid on; box on;

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('%s_%s_%s.png', plot_suffix, protocol, geno));
            saveas(fig, out_file);
            savefig(fig, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved probe latency: %s\n', out_file);
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

            exp_probe_vals = NaN(n_exps, num_probes);
            for ei = 1:n_exps
                exp_mask = strcmp(T.experiment, exps{ei});
                for pi = 1:num_probes
                    probe_mask = exp_mask & T.cycle == probe_cycle_nums(pi);
                    if any(probe_mask)
                        exp_probe_vals(ei, pi) = mean(T.(METRIC)(probe_mask), 'omitnan');
                    end
                end
            end

            prb_m  = mean(exp_probe_vals, 1, 'omitnan');
            prb_n  = sum(~isnan(exp_probe_vals), 1);
            prb_se = std(exp_probe_vals, 0, 1, 'omitnan') ./ sqrt(prb_n);

            valid = ~isnan(prb_m);
            if any(valid)
                x_v = find(valid);
                m_v = prb_m(valid);
                se_v = prb_se(valid);

                % SEM ribbon
                fill_x = [x_v, fliplr(x_v)];
                fill_y = [m_v + se_v, fliplr(m_v - se_v)];
                fill(ax_ov, fill_x, fill_y, col, 'FaceAlpha', 0.2, ...
                    'EdgeColor', 'none', 'HandleVisibility', 'off');

                h = plot(ax_ov, x_v, m_v, '-^', ...
                    'Color', col, 'MarkerFaceColor', col, ...
                    'MarkerSize', 8, 'LineWidth', 1.5);
                h_lines = [h_lines, h]; %#ok<AGROW>
                legend_entries{end+1} = sprintf('%s (n=%d)', geno, n_exps); %#ok<AGROW>
            end
        end

        set(ax_ov, 'XTick', 1:num_probes, 'XTickLabel', probe_labels);
        xlabel('Probe Trial', 'FontSize', 11);
        ylabel(y_label, 'FontSize', 11);
        title(sprintf('All genotypes  (%s)', protocol), 'FontSize', 13);
        xlim([0.5 num_probes + 0.5]);
        grid on; box on;

        if ~isempty(h_lines)
            legend(h_lines, legend_entries, 'Location', 'bestoutside', 'FontSize', 9);
        end

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('%s_%s_overlay.png', plot_suffix, protocol));
            saveas(fig_ov, out_file);
            savefig(fig_ov, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved probe latency overlay: %s\n', out_file);
        end
        if opts.ShowPlots, set(fig_ov, 'Visible', 'on'); else, close(fig_ov); end
    end
end
