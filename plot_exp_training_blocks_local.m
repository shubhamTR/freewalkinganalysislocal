function plot_exp_training_blocks_local(T_exp, protocol, varargin)
% PLOT_EXP_TRAINING_BLOCKS_LOCAL  Per-experiment block-average training plot
%
%   Plots mean ± SEM across flies, averaged over 10 training cycles per block.
%   X-axis: B1, B2, B3, B4. Excludes optomotor, pre-probe, probes.
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
    addParameter(p, 'PlotName', 'train_blocks', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    parse(p, T_exp, protocol, varargin{:});
    opts = p.Results;

    %% Determine training cycle numbers from get_protocol_config (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_place_learning, return; end
    training_blocks = cfg.training_blocks;  % cell of cycle vectors per block

    num_blocks = length(training_blocks);
    block_names = arrayfun(@(b) sprintf('B%d', b), 1:num_blocks, 'UniformOutput', false);

    %% Compute block averages from per-cycle values
    blk_m  = NaN(1, num_blocks);
    blk_se = NaN(1, num_blocks);

    for b = 1:num_blocks
        cycle_mask = ismember(T_exp.cycle, training_blocks{b});
        vals = T_exp.(opts.MeanCol)(cycle_mask);
        vals = vals(~isnan(vals));
        if ~isempty(vals)
            blk_m(b)  = mean(vals);
            blk_se(b) = std(vals) / sqrt(length(vals));
        end
    end

    exp_name = T_exp.experiment{1};

    %% Plot
    fig = figure('Position', [50 50 500 450], 'Visible', 'off');
    ax = axes; hold on;

    col = [0.00 0.45 0.70];
    errorbar(1:num_blocks, blk_m, blk_se, 'o-', ...
        'Color', col, 'MarkerFaceColor', col, ...
        'MarkerSize', 8, 'LineWidth', 1.5, 'CapSize', 6);

    if ~isempty(opts.YMax)
        ylim([0 opts.YMax]);
    else
        max_val = max(blk_m + blk_se);
        if ~isnan(max_val) && max_val > 0
            ylim([0, max_val * 1.15]);
        end
    end

    set(ax, 'XTick', 1:num_blocks, 'XTickLabel', block_names);
    xlabel('Training Block', 'FontSize', 11);
    ylabel(opts.YLabel, 'FontSize', 11);
    title(sprintf('%s  |  Block averages', strrep(exp_name, '_', '\_')), 'FontSize', 12);
    xlim([0.5, num_blocks+0.5]);
    grid on; box on;

    if ~isempty(opts.SavePath)
        out_file = fullfile(opts.SavePath, sprintf('%s_%s.png', opts.PlotName, exp_name));
        saveas(fig, out_file);
        savefig(fig, strrep(out_file, '.png', '.fig'));
        fprintf('    Saved: %s\n', out_file);
    end
    if opts.ShowPlots, set(fig, 'Visible', 'on'); else, close(fig); end
end
