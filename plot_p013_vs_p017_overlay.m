function plot_p013_vs_p017_overlay(summary_p013, summary_p017, varargin)
% PLOT_P013_VS_P017_OVERLAY  Overlay second-half |QPI| for P013 and P017
%
%   plot_p013_vs_p017_overlay(summary_p013, summary_p017)
%   plot_p013_vs_p017_overlay(summary_p013, summary_p017, 'ShowPlots', true)
%
%   Both protocols share 37-cycle structure. Overlays matching genotypes
%   on the same axes, with P013 and P017 as separate traces.

    p = inputParser;
    addParameter(p, 'SaveDir', '', @ischar);
    addParameter(p, 'ShowPlots', false, @islogical);
    parse(p, varargin{:});
    opts = p.Results;

    cfg = get_protocol_config('P013');  % same structure for both
    num_cycles = cfg.num_cycles;
    cycle_labels = cfg.labels;
    x = 1:num_cycles;

    if isempty(opts.SaveDir)
        save_dir = '/Users/rathores/Documents/analysisdatalocal/Summary_Plots';
    else
        save_dir = opts.SaveDir;
    end
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end

    % Find genotypes present in both
    genos_013 = summary_p013.genotypes;
    genos_017 = summary_p017.genotypes;
    common_genos = intersect(genos_013, genos_017);
    all_genos = union(genos_013, genos_017);

    %% Per-genotype overlay (P013 vs P017 on same axes)
    for gi = 1:length(all_genos)
        geno = all_genos{gi};

        fig = figure('Name', sprintf('P013 vs P017 - %s', geno), ...
                     'Position', [50 50 1400 500], ...
                     'Visible', ternary(opts.ShowPlots, 'on', 'off'));
        hold on;

        legend_entries = {};

        % P013
        if ismember(geno, genos_013)
            gs = summary_p013.(geno);
            mu = gs.per_cycle.mean_qpi_2nd;
            se = gs.per_cycle.sem_qpi_2nd;
            valid = ~isnan(mu);
            col = [0.2 0.4 0.8];  % blue for P013

            if any(valid)
                fill_x = [x(valid), fliplr(x(valid))];
                fill_y = [(mu(valid) + se(valid))', fliplr((mu(valid) - se(valid))')];
                fill(fill_x, fill_y, col, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                plot(x(valid), mu(valid), '-o', 'Color', col, 'LineWidth', 2, ...
                    'MarkerSize', 5, 'MarkerFaceColor', col);
            end
            legend_entries{end+1} = sprintf('P013 %s (N=%d exps, %d flies)', ...
                geno, gs.num_experiments, gs.num_flies); %#ok<AGROW>
        end

        % P017
        if ismember(geno, genos_017)
            gs = summary_p017.(geno);
            mu = gs.per_cycle.mean_qpi_2nd;
            se = gs.per_cycle.sem_qpi_2nd;
            valid = ~isnan(mu);
            col = [0.8 0.2 0.2];  % red for P017

            if any(valid)
                fill_x = [x(valid), fliplr(x(valid))];
                fill_y = [(mu(valid) + se(valid))', fliplr((mu(valid) - se(valid))')];
                fill(fill_x, fill_y, col, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                plot(x(valid), mu(valid), '-o', 'Color', col, 'LineWidth', 2, ...
                    'MarkerSize', 5, 'MarkerFaceColor', col);
            end
            legend_entries{end+1} = sprintf('P017 %s (N=%d exps, %d flies)', ...
                geno, gs.num_experiments, gs.num_flies); %#ok<AGROW>
        end

        % Reference line
        yline(0, '-', 'Color', [0.8 0.8 0.8], 'LineWidth', 0.5, 'HandleVisibility', 'off');

        % Format
        set(gca, 'XTick', x, 'XTickLabel', cycle_labels, 'XTickLabelRotation', 60, 'FontSize', 9);
        xlim([0.5, num_cycles + 0.5]);
        ylim([0, 1]);
        ylabel('|QPI| second half (mean ± SEM)', 'FontSize', 12);
        xlabel('Cycle', 'FontSize', 12);
        title(sprintf('P013 vs P017 — Second-Half |QPI| — %s', geno), 'FontSize', 14);
        legend(legend_entries, 'Location', 'bestoutside', 'FontSize', 11);
        box on;

        draw_section_dividers(cfg, num_cycles);

        out_png = fullfile(save_dir, sprintf('P013_vs_P017_QPI_%s.png', geno));
        saveas(fig, out_png);
        savefig(fig, strrep(out_png, '.png', '.fig'));
        fprintf('  Saved: P013_vs_P017_QPI_%s.png\n', geno);

        if ~opts.ShowPlots, close(fig); end
    end

    fprintf('\n  Overlay plots saved to: %s\n\n', save_dir);
end


%% ===== Helper functions =====

function draw_section_dividers(cfg, num_cycles)
    yl = ylim;
    n = min(num_cycles, length(cfg.labels));

    sections = {};
    block_num = 0;
    i = 1;
    while i <= n
        lbl = cfg.labels{i};

        if strcmp(lbl, 'OM1')
            sections{end+1} = {i, i, 'OM1'}; %#ok<AGROW>
            i = i + 1;
        elseif strcmp(lbl, 'OM2')
            sections{end+1} = {i, i, 'OM2'}; %#ok<AGROW>
            i = i + 1;
        elseif strcmp(lbl, 'PP')
            sections{end+1} = {i, i, 'PP'}; %#ok<AGROW>
            i = i + 1;
        elseif strcmp(lbl, 'Ag')
            sections{end+1} = {i, i, 'Ag'}; %#ok<AGROW>
            i = i + 1;
        elseif endsWith(lbl, '.P')
            sections{end+1} = {i, i, 'Probe'}; %#ok<AGROW>
            i = i + 1;
        elseif contains(lbl, '.') && ~endsWith(lbl, '.P')
            block_num = block_num + 1;
            blk_start = i;
            while i <= n
                li = cfg.labels{i};
                if contains(li, '.') && ~endsWith(li, '.P')
                    i = i + 1;
                else
                    break;
                end
            end
            blk_end = i - 1;
            sections{end+1} = {blk_start, blk_end, sprintf('Block %d', block_num)}; %#ok<AGROW>
        else
            i = i + 1;
        end
    end

    line_color = [0.5 0.5 0.5];
    for si = 1:length(sections)
        s_start = sections{si}{1};
        s_end   = sections{si}{2};
        s_label = sections{si}{3};

        plot([s_start-0.5, s_start-0.5], yl, '-', 'Color', line_color, 'LineWidth', 1, 'HandleVisibility', 'off');
        plot([s_end+0.5, s_end+0.5], yl, '-', 'Color', line_color, 'LineWidth', 1, 'HandleVisibility', 'off');

        x_mid = (s_start + s_end) / 2;
        y_mid = yl(1) + 0.5 * (yl(2) - yl(1));
        text(x_mid, y_mid, s_label, ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
            'Rotation', 90, 'FontSize', 8, 'FontWeight', 'bold', ...
            'Color', [0.4 0.4 0.4], 'HandleVisibility', 'off');
    end
end

function result = ternary(c, t, f)
    if c, result = t; else, result = f; end
end
