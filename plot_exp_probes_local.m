function plot_exp_probes_local(T_exp, protocol, varargin)
% PLOT_EXP_PROBES_LOCAL  Per-experiment probe trials plot
%
%   Plots mean ± SEM across flies for probe trials: PP, B1.P–B4.P.
%   Excludes optomotor and training cycles.
%   One figure per experiment.
%
%   REQUIRED
%     T_exp    — rows from a summary table for ONE experiment
%     protocol — 'P003', 'P005', 'P006', etc.
%
%   NAME-VALUE PARAMETERS
%     'MeanCol'  — column name for mean values
%     'SEMCol'   — column name for SEM values
%     'YLabel'   — y-axis label
%     'YMax'     — fixed y-axis max (default: auto)
%     'PlotName' — filename prefix for PNG
%     'SavePath' — folder to save PNG
%     'ShowPlots'— keep figure visible

    p = inputParser;
    addRequired(p, 'T_exp');
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'MeanCol', 'mean_dist_mm', @ischar);
    addParameter(p, 'SEMCol', 'sem_dist_mm', @ischar);
    addParameter(p, 'YLabel', 'Distance (mm)', @ischar);
    addParameter(p, 'YMax', [], @isnumeric);
    addParameter(p, 'PlotName', 'probes', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    parse(p, T_exp, protocol, varargin{:});
    opts = p.Results;

    %% Determine probe cycle numbers from get_protocol_config (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_place_learning, return; end
    probe_cycle_nums = cfg.all_probe_cycle_nums;

    num_probes = length(probe_cycle_nums);
    probe_labels = [{'PP'}, arrayfun(@(b) sprintf('B%d.P', b), 1:(num_probes-1), 'UniformOutput', false)];

    %% Extract probe data
    m  = NaN(1, num_probes);
    se = NaN(1, num_probes);
    for pi = 1:num_probes
        row = T_exp.cycle == probe_cycle_nums(pi);
        if any(row)
            m(pi)  = T_exp.(opts.MeanCol)(row);
            se(pi) = T_exp.(opts.SEMCol)(row);
        end
    end

    exp_name = T_exp.experiment{1};

    %% Plot
    fig = figure('Position', [50 50 500 450], 'Visible', 'off');
    ax = axes; hold on;

    col = [0.00 0.45 0.70];
    valid = ~isnan(m);
    if any(valid)
        errorbar(find(valid), m(valid), se(valid), '-^', ...
            'Color', col, 'MarkerFaceColor', col, ...
            'MarkerSize', 8, 'LineWidth', 1.5, 'CapSize', 6);
    end

    if ~isempty(opts.YMax)
        ylim([0 opts.YMax]);
    else
        max_val = max(m(valid) + se(valid));
        if ~isempty(max_val) && max_val > 0
            ylim([0, max_val * 1.15]);
        end
    end

    set(ax, 'XTick', 1:num_probes, 'XTickLabel', probe_labels);
    xlabel('Probe Trial', 'FontSize', 11);
    ylabel(opts.YLabel, 'FontSize', 11);
    title(sprintf('%s  |  Probes', strrep(exp_name, '_', '\_')), 'FontSize', 12);
    xlim([0.5 num_probes+0.5]);
    grid on; box on;

    if ~isempty(opts.SavePath)
        out_file = fullfile(opts.SavePath, sprintf('%s_%s.png', opts.PlotName, exp_name));
        saveas(fig, out_file);
        fprintf('    Saved: %s\n', out_file);
    end
    if opts.ShowPlots, set(fig, 'Visible', 'on'); else, close(fig); end
end
