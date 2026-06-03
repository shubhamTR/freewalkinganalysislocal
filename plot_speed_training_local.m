function plot_speed_training_local(distance_summary, protocol, varargin)
% PLOT_SPEED_TRAINING_LOCAL  Walking speed during training cycles (LED on vs off)
%
%   Generates ONE SEPARATE FIGURE PER GENOTYPE.
%   Plots mean speed (mm/s) during LED-on and LED-off periods for each
%   training cycle, showing how walking speed changes at light onset/offset.
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

    %% Determine training cycle numbers from get_protocol_config (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_place_learning
        fprintf('  %s: Not a place learning protocol — skipping speed training plot.\n', protocol);
        return;
    end
    training_blocks = cfg.training_blocks;  % cell of cycle vectors per block

    % Flatten training cycles in order
    training_cycles = [];
    for b = 1:length(training_blocks)
        training_cycles = [training_cycles, training_blocks{b}]; %#ok<AGROW>
    end
    num_train = length(training_cycles);

    %% Identify genotypes
    all_genos = unique(T.genotype);
    is_control = strcmp(all_genos, CONTROL);
    geno_order = [all_genos(is_control); all_genos(~is_control)];

    % Genotype colors — consistent across all plotters (see get_genotype_color.m)

    %% One figure per genotype
    for gi = 1:length(geno_order)
        geno = geno_order{gi};
        col = get_genotype_color(geno);
        col_off = min(col + 0.35, 1);  % lighter shade for LED-off

        geno_rows = strcmp(T.genotype, geno);
        exps = unique(T.experiment(geno_rows));
        n_exps = length(exps);
        if n_exps == 0, continue; end

        % Compute per-experiment means for training cycles
        exp_on  = NaN(n_exps, num_train);
        exp_off = NaN(n_exps, num_train);

        for ei = 1:n_exps
            exp_mask = strcmp(T.experiment, exps{ei});
            for ci = 1:num_train
                c = training_cycles(ci);
                row_mask = exp_mask & T.cycle == c;
                if any(row_mask)
                    exp_on(ei, ci)  = mean(T.mean_speed_on(row_mask), 'omitnan');
                    exp_off(ei, ci) = mean(T.mean_speed_off(row_mask), 'omitnan');
                end
            end
        end

        n_valid_on  = sum(~isnan(exp_on), 1);
        n_valid_off = sum(~isnan(exp_off), 1);
        m_on  = mean(exp_on, 1, 'omitnan');
        se_on = std(exp_on, 0, 1, 'omitnan') ./ sqrt(max(n_valid_on, 1));
        m_off  = mean(exp_off, 1, 'omitnan');
        se_off = std(exp_off, 0, 1, 'omitnan') ./ sqrt(max(n_valid_off, 1));

        x = 1:num_train;

        fig = figure('Position', [100 100 1300 500], 'Visible', 'off');
        ax = axes; hold on;

        % Training block shading
        block_lens   = cellfun(@numel, training_blocks);
        block_ends   = cumsum(block_lens);
        block_starts = [1, block_ends(1:end-1) + 1];
        for b = 1:length(training_blocks)
            if b <= length(block_starts)
                x1 = block_starts(b) - 0.5;
                x2 = block_ends(b) + 0.5;
                % Alternate blocks: light blue / white
                if mod(b, 2) == 1
                    patch(ax, [x1 x2 x2 x1], [0 0 1e6 1e6], ...
                        [0.85 0.92 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.25, ...
                        'HandleVisibility', 'off');
                end
            end
        end

        % Plot LED on and LED off
        h_on = errorbar(x, m_on, se_on, 'o-', ...
            'Color', col, 'MarkerFaceColor', col, ...
            'MarkerSize', 5, 'LineWidth', 1.2, 'CapSize', 3);
        h_off = errorbar(x, m_off, se_off, 's--', ...
            'Color', col_off, 'MarkerFaceColor', col_off, ...
            'MarkerSize', 5, 'LineWidth', 1.2, 'CapSize', 3);

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

        % Fix block shading to actual ylim
        yl = ylim(ax);
        children = get(ax, 'Children');
        for ch = 1:length(children)
            if isa(children(ch), 'matlab.graphics.primitive.Patch')
                ydata = get(children(ch), 'YData');
                if max(ydata) > yl(2) * 2
                    set(children(ch), 'YData', [yl(1) yl(1) yl(2) yl(2)]);
                end
            end
        end

        % Block boundary lines
        for b = 2:length(training_blocks)
            xline(ax, block_starts(b) - 0.5, ':', 'Color', [0.5 0.5 0.5], ...
                'LineWidth', 0.8, 'HandleVisibility', 'off');
        end

        % Block labels
        block_names = arrayfun(@(b) sprintf('B%d', b), 1:length(training_blocks), 'UniformOutput', false);
        for b = 1:min(length(training_blocks), length(block_names))
            mid = (block_starts(b) + block_ends(b)) / 2;
            text(mid, yl(2) * 0.97, block_names{b}, ...
                'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', [0.3 0.3 0.3]);
        end

        legend([h_on, h_off], {'LED on', 'LED off'}, ...
            'Location', 'northeastoutside', 'FontSize', 9);

        xlabel('Training cycle', 'FontSize', 11);
        ylabel('Speed (mm/s)', 'FontSize', 11);
        title(sprintf('%s  —  %d experiments  |  Training speed  (%s)', ...
            geno, n_exps, protocol), 'FontSize', 13);
        xlim([0.5, num_train + 0.5]);
        set(ax, 'XTick', 1:2:num_train);
        box on;

        % Bring data to front
        children = get(ax, 'Children');
        is_data = arrayfun(@(c) isa(c, 'matlab.graphics.chart.decoration.ErrorBar'), children);
        set(ax, 'Children', [children(is_data); children(~is_data)]);

        if ~isempty(opts.SavePath)
            out_file = fullfile(opts.SavePath, sprintf('speed_training_%s_%s.png', protocol, geno));
            saveas(fig, out_file);
            savefig(fig, strrep(out_file, '.png', '.fig'));
            fprintf('  Saved speed training: %s\n', out_file);
        end
        if opts.ShowPlots, set(fig, 'Visible', 'on'); else, close(fig); end
    end
end
