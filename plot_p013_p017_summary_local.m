function plot_p013_p017_summary_local(summary, varargin)
% PLOT_P013_P017_SUMMARY_LOCAL  Per-genotype QPI summary plots for P013/P017
%
%   plot_p013_p017_summary_local(summary)
%   plot_p013_p017_summary_local(summary, 'SaveDir', '/path/to/save')
%
%   Adapted from server pipeline's plot_p013_summary.m.
%   Generates per-genotype and overlay QPI plots with section dividers.
%
%   INPUT:
%     summary — struct from build_p013_p017_summary_local()

    p = inputParser;
    addParameter(p, 'SaveDir', '', @ischar);
    addParameter(p, 'ShowPlots', false, @islogical);
    parse(p, varargin{:});
    opts = p.Results;

    protocol   = summary.protocol;
    genotypes  = summary.genotypes;
    num_cycles = summary.num_cycles;
    cycle_labels = summary.cycle_labels;

    cfg = get_protocol_config(protocol);

    % Default save directory
    if isempty(opts.SaveDir)
        save_dir = fullfile('/Users/rathores/Documents/analysisdatalocal', protocol, 'Summary_Plots');
    else
        save_dir = opts.SaveDir;
    end
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end

    x = 1:num_cycles;

    %% ===== Per-genotype QPI plots =====
    for gi = 1:length(genotypes)
        geno = genotypes{gi};
        gs = summary.(geno);
        line_color = get_genotype_color(geno);

        fig1 = figure('Name', sprintf('QPI - %s', geno), ...
                       'Position', [50 50 1400 500], ...
                       'Visible', ternary(opts.ShowPlots, 'on', 'off'));
        hold on;

        % Plot second-half mean |QPI| ± SEM (across experiments)
        mu = gs.per_cycle.mean_qpi_2nd;
        se = gs.per_cycle.sem_qpi_2nd;

        valid = ~isnan(mu);
        if any(valid)
            fill_x = [x(valid), fliplr(x(valid))];
            fill_y = [(mu(valid) + se(valid))', fliplr((mu(valid) - se(valid))')];
            fill(fill_x, fill_y, line_color, 'FaceAlpha', 0.2, 'EdgeColor', 'none');
            plot(x(valid), mu(valid), '-o', 'Color', line_color, 'LineWidth', 2, ...
                'MarkerSize', 5, 'MarkerFaceColor', line_color);
        end

        % First-half as solid black line
        mu1 = gs.per_cycle.mean_qpi_1st;
        valid1 = ~isnan(mu1);
        if any(valid1)
            plot(x(valid1), mu1(valid1), '-', 'Color', [0 0 0], 'LineWidth', 1.2);
        end

        % Reference line
        yline(0, '-', 'Color', [0.8 0.8 0.8], 'LineWidth', 0.5);

        % Format — no x-tick labels, no grid
        set(gca, 'XTick', x, 'XTickLabel', cycle_labels, 'XTickLabelRotation', 60, 'FontSize', 9);
        xlim([0.5, num_cycles + 0.5]);
        ylim([0, 1]);
        ylabel('|QPI| (mean ± SEM)', 'FontSize', 12);
        xlabel('Cycle', 'FontSize', 12);
        title(sprintf('%s — |QPI| per Cycle — %s  (N=%d experiments, %d flies)', ...
            protocol, geno, gs.num_experiments, gs.num_flies), 'FontSize', 14);
        legend({'SEM', 'Second half', 'First half'}, 'Location', 'bestoutside');
        box on;

        % Section dividers and labels
        draw_section_dividers(cfg, num_cycles);

        out_png = fullfile(save_dir, sprintf('%s_QPI_summary_%s.png', protocol, geno));
        saveas(fig1, out_png);
        savefig(fig1, strrep(out_png, '.png', '.fig'));
        fprintf('  Saved: %s_QPI_summary_%s.png\n', protocol, geno);

        if ~opts.ShowPlots, close(fig1); end
    end

    %% ===== Genotype overlay =====
    if length(genotypes) >= 2
        fprintf('\n  Generating genotype overlay plot...\n');

        fig_ov = figure('Name', 'QPI Overlay', ...
                         'Position', [50 50 1400 500], ...
                         'Visible', ternary(opts.ShowPlots, 'on', 'off'));
        hold on;

        legend_entries = {};
        for gi = 1:length(genotypes)
            geno = genotypes{gi};
            gs = summary.(geno);
            lc = get_genotype_color(geno);

            mu = gs.per_cycle.mean_qpi_2nd;
            se = gs.per_cycle.sem_qpi_2nd;
            valid = ~isnan(mu);

            if any(valid)
                fill_x = [x(valid), fliplr(x(valid))];
                fill_y = [(mu(valid) + se(valid))', fliplr((mu(valid) - se(valid))')];
                fill(fill_x, fill_y, lc, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                plot(x(valid), mu(valid), '-o', 'Color', lc, 'LineWidth', 2, ...
                    'MarkerSize', 5, 'MarkerFaceColor', lc);
            end
            legend_entries{end+1} = sprintf('%s (N=%d exps)', geno, gs.num_experiments); %#ok<AGROW>
        end

        yline(0, '-', 'Color', [0.8 0.8 0.8], 'LineWidth', 0.5, 'HandleVisibility', 'off');

        set(gca, 'XTick', x, 'XTickLabel', cycle_labels, 'XTickLabelRotation', 60, 'FontSize', 9);
        xlim([0.5, num_cycles + 0.5]);
        ylim([0, 1]);
        ylabel('|QPI| second half (mean ± SEM)', 'FontSize', 12);
        xlabel('Cycle', 'FontSize', 12);
        title(sprintf('%s — Second-Half |QPI| per Cycle — All Genotypes', protocol), 'FontSize', 14);
        legend(legend_entries, 'Location', 'bestoutside', 'FontSize', 11);
        box on;

        draw_section_dividers(cfg, num_cycles);

        out_png = fullfile(save_dir, sprintf('%s_QPI_summary_overlay.png', protocol));
        saveas(fig_ov, out_png);
        savefig(fig_ov, strrep(out_png, '.png', '.fig'));
        fprintf('  Saved: %s_QPI_summary_overlay.png\n', protocol);

        if ~opts.ShowPlots, close(fig_ov); end
    end

    fprintf('\n  All summary plots saved to: %s\n\n', save_dir);
end


%% ===== Helper functions =====

function draw_section_dividers(cfg, num_cycles)
% Draw vertical divider lines at section boundaries with rotated labels
    yl = ylim;
    n = min(num_cycles, length(cfg.labels));

    % Identify section boundaries and labels
    %   Sections: OM1, PP, Ag, Block1, Probe1, Block2, Probe2, Block3, Probe3, OM2
    sections = {};  % each: {start_cycle, end_cycle, label}

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
            % Start of a training block — find its end
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

    % Draw vertical lines at each section boundary and label at center
    line_color = [0.5 0.5 0.5];

    for si = 1:length(sections)
        s_start = sections{si}{1};
        s_end   = sections{si}{2};
        s_label = sections{si}{3};

        % Vertical line at left edge of section
        x_line = s_start - 0.5;
        plot([x_line x_line], yl, '-', 'Color', line_color, 'LineWidth', 1, ...
            'HandleVisibility', 'off');

        % Vertical line at right edge of section
        x_line_r = s_end + 0.5;
        plot([x_line_r x_line_r], yl, '-', 'Color', line_color, 'LineWidth', 1, ...
            'HandleVisibility', 'off');

        % Rotated label at center of section
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
