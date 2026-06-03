function plot_exp_training_allcycles_local(T_exp, protocol, varargin)
% PLOT_EXP_TRAINING_ALLCYCLES_LOCAL  Per-experiment training cycles plot
%
%   Plots mean ± SEM across flies for Ag + all 40 training cycles (10 per block).
%   Excludes optomotor, pre-probe, and probe cycles.
%   One figure per experiment.
%
%   REQUIRED
%     T_exp    — rows from a summary table for ONE experiment
%     protocol — 'P003', 'P005', 'P006', etc.
%
%   NAME-VALUE PARAMETERS
%     'MeanCol'  — column name for mean values (e.g. 'mean_dist_mm')
%     'SEMCol'   — column name for SEM values (e.g. 'sem_dist_mm')
%     'YLabel'   — y-axis label
%     'YMax'     — fixed y-axis max (default: auto)
%     'PlotName' — filename prefix for PNG
%     'SavePath' — folder to save PNG (default: '' = no save)
%     'ShowPlots'— keep figure visible (default: true)

    p = inputParser;
    addRequired(p, 'T_exp');
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'MeanCol', 'mean_dist_mm', @ischar);
    addParameter(p, 'SEMCol', 'sem_dist_mm', @ischar);
    addParameter(p, 'YLabel', 'Distance (mm)', @ischar);
    addParameter(p, 'YMax', [], @isnumeric);
    addParameter(p, 'PlotName', 'train_allcycles', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    addParameter(p, 'ArenaDiameterMM', 0, @isnumeric);
    parse(p, T_exp, protocol, varargin{:});
    opts = p.Results;

    %% Determine Ag + training cycle numbers from get_protocol_config (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_place_learning, return; end
    pretrain_cycle  = cfg.pretrain_cycle;
    training_blocks = cfg.training_blocks;  % cell of cycle vectors per block

    training_cycles = pretrain_cycle;
    for b = 1:length(training_blocks)
        training_cycles = [training_cycles, training_blocks{b}]; %#ok<AGROW>
    end
    num_train = length(training_cycles);  % 41 total (1 Ag + 40 training)

    %% Extract data for training cycles
    m  = NaN(1, num_train);
    se = NaN(1, num_train);
    for ci = 1:num_train
        row = T_exp.cycle == training_cycles(ci);
        if any(row)
            m(ci)  = T_exp.(opts.MeanCol)(row);
            se(ci) = T_exp.(opts.SEMCol)(row);
        end
    end

    %% Get experiment name
    exp_name = T_exp.experiment{1};

    %% Plot
    fig = figure('Position', [100 100 1200 450], 'Visible', 'off');
    ax = axes; hold on;

    % Block shading (alternate light blue) — offset by 1 for Ag at x=1
    num_blocks = length(training_blocks);
    block_starts = cellfun(@(b) b(1), training_blocks);
    block_ends = cellfun(@(b) b(end), training_blocks);
    % Convert from cycle numbers to x-axis indices
    block_starts = arrayfun(@(s) find(training_cycles == s, 1), block_starts);
    block_ends   = arrayfun(@(e) find(training_cycles == e, 1), block_ends);
    block_names  = arrayfun(@(b) sprintf('B%d', b), 1:num_blocks, 'UniformOutput', false);

    x = 1:num_train;
    col = [0.00 0.45 0.70];

    errorbar(x, m, se, 'o-', 'Color', col, 'MarkerFaceColor', col, ...
        'MarkerSize', 5, 'LineWidth', 1.2, 'CapSize', 3);

    % Y limits
    if ~isempty(opts.YMax)
        ylim([0 opts.YMax]);
    else
        max_val = max(m + se);
        if ~isnan(max_val) && max_val > 0
            ylim([0, max_val * 1.15]);
        end
    end
    yl = ylim(ax);

    % Ag (pre-train) marker at x = 1
    xl_ag = xline(ax, 1, ':', 'Color', [0.0 0.4 0.0], 'LineWidth', 1.2, ...
        'Label', 'Ag', 'LabelOrientation', 'horizontal', ...
        'LabelVerticalAlignment', 'top', 'FontSize', 8, ...
        'LabelHorizontalAlignment', 'center');
    set(xl_ag, 'HandleVisibility', 'off');

    for b = 1:num_blocks
        if mod(b,2) == 1
            patch(ax, [block_starts(b)-0.5 block_ends(b)+0.5 block_ends(b)+0.5 block_starts(b)-0.5], ...
                [yl(1) yl(1) yl(2) yl(2)], ...
                [0.85 0.92 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.25, 'HandleVisibility', 'off');
        end
        % Block boundary
        if b > 1
            xline(ax, block_starts(b)-0.5, ':', 'Color', [0.5 0.5 0.5], ...
                'LineWidth', 0.8, 'HandleVisibility', 'off');
        end
        % Block label
        text((block_starts(b) + block_ends(b))/2, yl(2)*0.97, block_names{b}, ...
            'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', [0.3 0.3 0.3]);
    end

    % Arena diameter line
    if opts.ArenaDiameterMM > 0
        yline(ax, opts.ArenaDiameterMM, '-', 'Color', [0.6 0.6 0.6], 'LineWidth', 1, 'HandleVisibility', 'off');
        text(num_train+0.3, opts.ArenaDiameterMM, ...
            sprintf('Arena diam (%d mm)', opts.ArenaDiameterMM), ...
            'FontSize', 8, 'Color', [0.5 0.5 0.5], 'VerticalAlignment', 'bottom');
    end

    % Bring data to front
    children = get(ax, 'Children');
    is_data = arrayfun(@(c) isa(c, 'matlab.graphics.chart.decoration.ErrorBar'), children);
    set(ax, 'Children', [children(is_data); children(~is_data)]);
    ylim(ax, yl);

    xlabel('Training cycle', 'FontSize', 11);
    ylabel(opts.YLabel, 'FontSize', 11);
    title(sprintf('%s  |  Ag + Training cycles', strrep(exp_name, '_', '\_')), 'FontSize', 12);
    set(ax, 'XTick', 1:2:num_train);
    xlim([0.5, num_train+0.5]);
    box on;

    if ~isempty(opts.SavePath)
        out_file = fullfile(opts.SavePath, sprintf('%s_%s.png', opts.PlotName, exp_name));
        saveas(fig, out_file);
        savefig(fig, strrep(out_file, '.png', '.fig'));
        fprintf('    Saved: %s\n', out_file);
    end
    if opts.ShowPlots, set(fig, 'Visible', 'on'); else, close(fig); end
end
