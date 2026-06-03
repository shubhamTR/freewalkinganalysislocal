function plot_speed_probes_local(distance_summary, protocol, varargin)
% PLOT_SPEED_PROBES_LOCAL  Walking speed during probe cycles (LED on vs off)
%
%   Generates ONE SEPARATE FIGURE PER GENOTYPE.
%   Plots mean speed (mm/s) during LED-on and LED-off for probe trials
%   (PP + B1.P–B4.P), showing speed changes at light onset/offset.
%
%   Applies to: P003, P005, P006, P007, P008, P009
%
%   NAME-VALUE PARAMETERS
%     'SavePath'    — folder to save PNG (default: '' = no save)
%     'ShowPlots'   — keep figure visible (default: true)
%     'ControlGeno' — control genotype name (default: 'L1')
%     'YMax'        — fixed y-axis maximum (default: auto)

    %% Parse
    p = inputParser;
    addRequired(p, 'distance_summary');
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    addParameter(p, 'ControlGeno', 'L1', @ischar);
    addParameter(p, 'YMax', [], @isnumeric);
    parse(p, distance_summary, protocol, varargin{:});
    opts = p.Results;

    T = distance_summary;
    CONTROL = opts.ControlGeno;

    %% Determine probe cycle numbers from get_protocol_config (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_place_learning
        fprintf('  %s: Not a place learning protocol — skipping speed probes plot.\n', protocol);
        return;
    end
    probe_cycle_nums = cfg.all_probe_cycle_nums;

    num_probes = length(probe_cycle_nums);
    probe_labels = [{'PP'}, arrayfun(@(b) sprintf('B%d.P', b), 1:(num_probes-1), 'UniformOutput', false)];

    %% Identify genotypes
    all_genos = unique(T.genotype);
    is_control = strcmp(all_genos, CONTROL);
    geno_order = [all_genos(is_control); all_genos(~is_control)];
    % Genotype colors — consistent across all plotters (see get_genotype_color.m)

    %% One figure per genotype
    for gi = 1:length(geno_order)
        geno = geno_order{gi};
        col = get_genotype_color(geno);
        col_off = min(col + 0.35, 1);

        geno_rows = strcmp(T.genotype, geno);
        exps = unique(T.experiment(geno_rows));
        n_exps = length(exps);
        if n_exps == 0, continue; end

        exp_on  = NaN(n_exps, num_probes);
        exp_off = NaN(n_exps, num_probes);

        for ei = 1:n_exps
            exp_mask = strcmp(T.experiment, exps{ei});
            for pi = 1:num_probes
                row_mask = exp_mask & T.cycle == probe_cycle_nums(pi);
                if any(row_mask)
                    exp_on(ei, pi)  = mean(T.mean_speed_on(row_mask), 'omitnan');
                    exp_off(ei, pi) = mean(T.mean_speed_off(row_mask), 'omitnan');
                end
            end
        end

        n_valid_on  = sum(~isnan(exp_on), 1);
        n_valid_off = sum(~isnan(exp_off), 1);
        m_on  = mean(exp_on, 1, 'omitnan');
        se_on = std(exp_on, 0, 1, 'omitnan') ./ sqrt(max(n_valid_on, 1));
        m_off  = mean(exp_off, 1, 'omitnan');
        se_off = std(exp_off, 0, 1, 'omitnan') ./ sqrt(max(n_valid_off, 1));

        x = 1:num_probes;

        fig = figure('Position', [50 50 600 500], 'Visible', 'off');
        ax = axes; hold on;

        valid_on  = ~isnan(m_on);
        valid_off = ~isnan(m_off);

        h_on  = gobjects(0);
        h_off = gobjects(0);

        if any(valid_on)
            h_on = errorbar(x(valid_on), m_on(valid_on), se_on(valid_on), '-^', ...
                'Color', col, 'MarkerFaceColor', col, ...
                'MarkerSize', 8, 'LineWidth', 1.5, 'CapSize', 6);
        end
        if any(valid_off)
            h_off = errorbar(x(valid_off), m_off(valid_off), se_off(valid_off), '--s', ...
                'Color', col_off, 'MarkerFaceColor', col_off, ...
                'MarkerSize', 8, 'LineWidth', 1.5, 'CapSize', 6);
        end

        % Y-axis
        if ~isempty(opts.YMax)
            ylim([0 opts.YMax]);
        else
            all_vals = [m_on + se_on, m_off + se_off];
            max_val = max(all_vals(~isnan(all_vals)));
            if ~isempty(max_val) && max_val > 0
                ylim([0, max_val * 1.15]);
            end
        end

        % Legend
        leg_h = []; leg_s = {};
        if ~isempty(h_on) && isvalid(h_on)
            leg_h = [leg_h; h_on]; leg_s{end+1} = 'LED on';
        end
        if ~isempty(h_off) && isvalid(h_off)
            leg_h = [leg_h; h_off]; leg_s{end+1} = 'LED off';
        end
        if ~isempty(leg_h)
            legend(leg_h, leg_s, 'Location', 'northeastoutside', 'FontSize', 9);
        end

        set(ax, 'XTick', 1:num_probes, 'XTickLabel', probe_labels);
        xlabel('Probe Trial', 'FontSize', 11);
        ylabel('Speed (mm/s)', 'FontSize', 11);
        title(sprintf('%s  —  %d experiments  |  Probe speed  (%s)', ...
            geno, n_exps, protocol), 'FontSize', 13);
        xlim([0.5 num_probes + 0.5]);
        grid on; box on;

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('speed_probes_%s_%s.png', protocol, geno));
            saveas(fig, out_file);
            fprintf('  Saved speed probes: %s\n', out_file);
        end
        if opts.ShowPlots, set(fig, 'Visible', 'on'); else, close(fig); end
    end
end
