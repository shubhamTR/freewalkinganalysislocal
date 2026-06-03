function plot_QPI_vs_distance(varargin)
% PLOT_QPI_VS_DISTANCE  Scatter of block QPI vs block distance per experiment.
%
%   plot_QPI_vs_distance()
%   plot_QPI_vs_distance('AnalysisDir', '/path/to/data')
%
%   For each genotype, produces:
%     1) A single scatter figure with all conditions overlaid.
%        Each dot = one experiment × one block (B1–B4).
%        Color = condition shade, marker = condition (o/^/s).
%        Block number is annotated next to each point.
%     2) Per-condition panels (1×3 subplot) with regression line + r, p.
%     3) A combined overlay of all genotypes.
%
%   Also saves correlation statistics to a text file.

    ip = inputParser;
    addParameter(ip, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(ip, 'ShowPlots', false, @islogical);
    parse(ip, varargin{:});
    opts = ip.Results;

    ADIR = opts.AnalysisDir;

    %% Condition definitions
    conds = struct();
    conds(1).protocol = 'P008';  conds(1).label = 'Coupled';    conds(1).marker = 'o';  conds(1).shade = 1.0;
    conds(2).protocol = 'P010';  conds(2).label = 'Uncoupled';  conds(2).marker = '^';  conds(2).shade = 0.55;
    conds(3).protocol = 'P011';  conds(3).label = 'Dark';       conds(3).marker = 's';  conds(3).shade = 0.25;
    nConds = length(conds);

    %% Block layout (P006-P011: 48 cycles)
    offset = 3;
    num_blocks = 4;
    block_train_cycles = cell(num_blocks, 1);
    for blk = 1:num_blocks
        blk_start = offset + (blk - 1) * 11 + 1;
        block_train_cycles{blk} = blk_start : (blk_start + 9);
    end

    %% Load data
    dist_data = struct();
    qpi_data  = struct();
    for ci = 1:nConds
        prot = conds(ci).protocol;
        f_dist = fullfile(ADIR, prot, sprintf('distance_summary_%s.mat', prot));
        f_qpi  = fullfile(ADIR, prot, sprintf('QPI_summary_%s.mat', prot));
        if ~exist(f_dist, 'file'), error('Missing: %s', f_dist); end
        if ~exist(f_qpi, 'file'),  error('Missing: %s', f_qpi);  end
        tmp = load(f_dist, 'distance_summary');
        dist_data(ci).T = tmp.distance_summary;
        tmp = load(f_qpi, 'QPI_summary');
        qpi_data(ci).T = tmp.QPI_summary;
        fprintf('Loaded %s (%s)\n', prot, conds(ci).label);
    end

    %% Auto-detect genotypes
    all_genos = {};
    for ci = 1:nConds
        all_genos = union(all_genos, unique(dist_data(ci).T.genotype));
    end
    genos = sort(all_genos);
    fprintf('Genotypes: %s\n', strjoin(genos, ', '));

    %% Output directory
    save_dir = fullfile(ADIR, 'condition_comparison', 'QPI_vs_distance');
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end

    %% Open stats log
    log_file = fullfile(save_dir, 'correlation_stats.txt');
    fid = fopen(log_file, 'w');
    fprintf(fid, 'Correlation: Block QPI (2nd half) vs Block Distance (mm)\n');
    fprintf(fid, 'Date: %s\n', datestr(now));
    fprintf(fid, 'Each point = one experiment x one block (B1-B4)\n');
    fprintf(fid, '============================================================\n\n');

    block_names = {'B1', 'B2', 'B3', 'B4'};
    block_markers = {'v', 'd', 'p', 'h'};  % for block identity in per-condition panels

    %% ================================================================
    %  Per-genotype: overlay scatter (all conditions)
    %  ================================================================
    for gi = 1:length(genos)
        geno = genos{gi};
        base_col = get_genotype_color(geno);

        fprintf(fid, '--- %s ---\n', geno);

        fig = figure('Position', [80 80 750 600], 'Visible', 'off');
        ax = axes; hold on;
        h_leg = []; leg_txt = {};

        for ci = 1:nConds
            cc = get_condition_shade(geno, ci);

            % Get per-experiment block means
            [dist_exp, qpi_exp, exp_names] = get_block_means(dist_data(ci).T, qpi_data(ci).T, ...
                geno, block_train_cycles);
            % dist_exp, qpi_exp: nExp × 4

            n_exp = size(dist_exp, 1);
            if n_exp == 0, continue; end

            % Flatten for scatter
            d_flat = dist_exp(:);
            q_flat = qpi_exp(:);
            blk_flat = repmat(1:4, n_exp, 1); blk_flat = blk_flat(:);

            valid = ~isnan(d_flat) & ~isnan(q_flat);
            d_v = d_flat(valid);
            q_v = q_flat(valid);
            b_v = blk_flat(valid);

            if isempty(d_v), continue; end

            % Scatter
            h = scatter(ax, d_v, q_v, 50, cc, conds(ci).marker, ...
                'filled', 'MarkerFaceAlpha', 0.7, 'MarkerEdgeColor', cc * 0.7);
            h_leg(end+1) = h; %#ok<AGROW>

            % Annotate block numbers
            for k = 1:length(d_v)
                text(ax, d_v(k) + 3, q_v(k), block_names{b_v(k)}, ...
                    'FontSize', 6, 'Color', cc * 0.6);
            end

            % Correlation
            if length(d_v) >= 4
                [r, p] = corr(d_v, q_v, 'Type', 'Pearson');
                leg_txt{end+1} = sprintf('%s (n=%d exp, r=%.2f, p=%.3f)', ...
                    conds(ci).label, n_exp, r, p); %#ok<AGROW>
                fprintf(fid, '  %s: n_exp=%d, n_pts=%d, r=%.3f, p=%.4f %s\n', ...
                    conds(ci).label, n_exp, length(d_v), r, p, sig_stars(p));

                % Regression line
                coeffs = polyfit(d_v, q_v, 1);
                x_range = linspace(min(d_v), max(d_v), 50);
                plot(ax, x_range, polyval(coeffs, x_range), '-', ...
                    'Color', [cc 0.5], 'LineWidth', 1.5, 'HandleVisibility', 'off');
            else
                leg_txt{end+1} = sprintf('%s (n=%d exp)', conds(ci).label, n_exp); %#ok<AGROW>
                fprintf(fid, '  %s: n_exp=%d — insufficient for correlation\n', ...
                    conds(ci).label, n_exp);
            end
        end

        xlabel('Block Distance (mm)', 'FontSize', 12);
        ylabel('Block QPI (2nd half)', 'FontSize', 12);
        title(sprintf('%s — QPI vs Distance by Block', geno), 'FontSize', 13);
        if ~isempty(h_leg)
            legend(h_leg, leg_txt, 'Location', 'best', 'FontSize', 8);
        end
        grid on; box on;
        save_fig(fig, save_dir, sprintf('qpi_vs_dist_%s', geno), opts.ShowPlots);
        fprintf(fid, '\n');

        %% Per-condition panels (1×3)
        fig2 = figure('Position', [40 100 1500 450], 'Visible', 'off');
        for ci = 1:nConds
            cc = get_condition_shade(geno, ci);
            ax2 = subplot(1, 3, ci); hold on;

            [dist_exp, qpi_exp, exp_names] = get_block_means(dist_data(ci).T, qpi_data(ci).T, ...
                geno, block_train_cycles);
            n_exp = size(dist_exp, 1);
            if n_exp == 0
                title(sprintf('%s — %s (no data)', geno, conds(ci).label), 'FontSize', 11);
                continue;
            end

            % Plot each block with a different marker shape
            blk_colors = [0.55 0.75 1.00; 0.30 0.55 0.85; 0.15 0.38 0.70; 0.00 0.20 0.50];
            % Use genotype ramp instead
            [~, blk_ramp] = get_genotype_color(geno);

            for blk = 1:4
                d_blk = dist_exp(:, blk);
                q_blk = qpi_exp(:, blk);
                valid = ~isnan(d_blk) & ~isnan(q_blk);
                if ~any(valid), continue; end
                scatter(ax2, d_blk(valid), q_blk(valid), 60, blk_ramp(blk,:), 'o', ...
                    'filled', 'MarkerFaceAlpha', 0.8, 'MarkerEdgeColor', blk_ramp(blk,:) * 0.7, ...
                    'DisplayName', block_names{blk});
            end

            % Overall regression
            d_flat = dist_exp(:); q_flat = qpi_exp(:);
            valid = ~isnan(d_flat) & ~isnan(q_flat);
            d_v = d_flat(valid); q_v = q_flat(valid);
            if length(d_v) >= 4
                [r, p] = corr(d_v, q_v, 'Type', 'Pearson');
                coeffs = polyfit(d_v, q_v, 1);
                x_range = linspace(min(d_v), max(d_v), 50);
                plot(ax2, x_range, polyval(coeffs, x_range), 'k-', 'LineWidth', 1.5, ...
                    'HandleVisibility', 'off');
                title(sprintf('%s — %s (n=%d)\nr=%.2f, p=%.3f', geno, conds(ci).label, n_exp, r, p), ...
                    'FontSize', 10);
            else
                title(sprintf('%s — %s (n=%d)', geno, conds(ci).label, n_exp), 'FontSize', 10);
            end

            xlabel('Block Distance (mm)', 'FontSize', 10);
            ylabel('Block QPI (2nd half)', 'FontSize', 10);
            legend('Location', 'best', 'FontSize', 8);
            grid on; box on;
        end
        sgtitle(sprintf('%s — QPI vs Distance per Condition', geno), 'FontSize', 13, 'FontWeight', 'bold');
        save_fig(fig2, save_dir, sprintf('qpi_vs_dist_panels_%s', geno), opts.ShowPlots);

        %% Per-cycle within each block (2×2 grid, one subplot per block)
        fig_cyc = figure('Position', [40 40 1200 900], 'Visible', 'off');
        fprintf(fid, '  Per-cycle correlations:\n');

        for blk = 1:4
            ax_cyc = subplot(2, 2, blk); hold on;
            h_leg_c = []; leg_txt_c = {};
            cycles_in_blk = block_train_cycles{blk};

            for ci = 1:nConds
                cc = get_condition_shade(geno, ci);

                [d_cycles, q_cycles, ~] = get_per_cycle_values( ...
                    dist_data(ci).T, qpi_data(ci).T, geno, cycles_in_blk);
                % d_cycles, q_cycles: nExp × nCyclesInBlock

                d_flat = d_cycles(:);
                q_flat = q_cycles(:);
                valid = ~isnan(d_flat) & ~isnan(q_flat);
                d_v = d_flat(valid);
                q_v = q_flat(valid);
                n_exp = size(d_cycles, 1);

                if isempty(d_v), continue; end

                h = scatter(ax_cyc, d_v, q_v, 30, cc, conds(ci).marker, ...
                    'filled', 'MarkerFaceAlpha', 0.5, 'MarkerEdgeColor', cc * 0.7);
                h_leg_c(end+1) = h; %#ok<AGROW>

                if length(d_v) >= 6
                    [r, p] = corr(d_v, q_v, 'Type', 'Pearson');
                    leg_txt_c{end+1} = sprintf('%s (n=%d, r=%.2f, p=%.3f)', ...
                        conds(ci).label, n_exp, r, p); %#ok<AGROW>
                    coeffs = polyfit(d_v, q_v, 1);
                    x_range = linspace(min(d_v), max(d_v), 50);
                    plot(ax_cyc, x_range, polyval(coeffs, x_range), '-', ...
                        'Color', [cc 0.5], 'LineWidth', 1.5, 'HandleVisibility', 'off');
                    fprintf(fid, '    %s %s: n_pts=%d, r=%.3f, p=%.4f %s\n', ...
                        block_names{blk}, conds(ci).label, length(d_v), r, p, sig_stars(p));
                else
                    leg_txt_c{end+1} = sprintf('%s (n=%d)', conds(ci).label, n_exp); %#ok<AGROW>
                end
            end

            xlabel('Cycle Distance (mm)', 'FontSize', 9);
            ylabel('Cycle QPI (2nd half)', 'FontSize', 9);
            title(sprintf('%s — %s', geno, block_names{blk}), 'FontSize', 11);
            if ~isempty(h_leg_c)
                legend(h_leg_c, leg_txt_c, 'Location', 'best', 'FontSize', 7);
            end
            grid on; box on;
        end
        sgtitle(sprintf('%s — QPI vs Distance (per cycle)', geno), 'FontSize', 13, 'FontWeight', 'bold');
        save_fig(fig_cyc, save_dir, sprintf('qpi_vs_dist_percycle_%s', geno), opts.ShowPlots);
        fprintf(fid, '\n');

        %% Experiment-mean trajectory: one line per experiment connecting B1→B4
        fig_traj = figure('Position', [40 40 1400 500], 'Visible', 'off');
        for ci = 1:nConds
            ax_t = subplot(1, 3, ci); hold on;

            [dist_exp_t, qpi_exp_t, exp_names_t] = get_block_means(dist_data(ci).T, qpi_data(ci).T, ...
                geno, block_train_cycles);
            n_exp = size(dist_exp_t, 1);
            [~, blk_ramp] = get_genotype_color(geno);

            for ei = 1:n_exp
                d_line = dist_exp_t(ei, :);
                q_line = qpi_exp_t(ei, :);
                valid = ~isnan(d_line) & ~isnan(q_line);
                if sum(valid) < 2, continue; end
                % Line connecting blocks
                plot(ax_t, d_line(valid), q_line(valid), '-', ...
                    'Color', [0.5 0.5 0.5 0.3], 'LineWidth', 0.8, 'HandleVisibility', 'off');
                % Block dots
                for blk = 1:4
                    if valid(blk)
                        scatter(ax_t, d_line(blk), q_line(blk), 50, blk_ramp(blk,:), 'o', ...
                            'filled', 'MarkerFaceAlpha', 0.8, 'MarkerEdgeColor', blk_ramp(blk,:)*0.7, ...
                            'HandleVisibility', 'off');
                    end
                end
                % Arrow from B1 to B4
                if valid(1) && valid(4)
                    dx = d_line(4) - d_line(1);
                    dq = q_line(4) - q_line(1);
                    quiver(ax_t, d_line(1), q_line(1), dx*0.9, dq*0.9, 0, ...
                        'Color', [0.3 0.3 0.3 0.4], 'MaxHeadSize', 0.5, ...
                        'LineWidth', 0.6, 'HandleVisibility', 'off');
                end
            end

            % Dummy handles for legend
            for blk = 1:4
                scatter(ax_t, NaN, NaN, 50, blk_ramp(blk,:), 'o', 'filled', ...
                    'DisplayName', block_names{blk});
            end

            xlabel('Block Distance (mm)', 'FontSize', 10);
            ylabel('Block QPI (2nd half)', 'FontSize', 10);
            title(sprintf('%s — %s (n=%d)', geno, conds(ci).label, n_exp), 'FontSize', 10);
            legend('Location', 'best', 'FontSize', 8); grid on; box on;
        end
        sgtitle(sprintf('%s — Learning Trajectory (B1→B4)', geno), 'FontSize', 13, 'FontWeight', 'bold');
        save_fig(fig_traj, save_dir, sprintf('qpi_vs_dist_trajectory_%s', geno), opts.ShowPlots);
    end

    %% ================================================================
    %  Per-condition: all genotypes overlaid
    %  ================================================================
    fig3 = figure('Position', [40 60 1500 450], 'Visible', 'off');
    for ci = 1:nConds
        ax3 = subplot(1, 3, ci); hold on;
        h_leg3 = []; leg_txt3 = {};

        for gi = 1:length(genos)
            geno = genos{gi};
            base_col = get_genotype_color(geno);
            cc = get_condition_shade(geno, ci);

            [dist_exp, qpi_exp, ~] = get_block_means(dist_data(ci).T, qpi_data(ci).T, ...
                geno, block_train_cycles);
            n_exp = size(dist_exp, 1);
            if n_exp == 0, continue; end

            d_flat = dist_exp(:); q_flat = qpi_exp(:);
            valid = ~isnan(d_flat) & ~isnan(q_flat);
            d_v = d_flat(valid); q_v = q_flat(valid);
            if isempty(d_v), continue; end

            h = scatter(ax3, d_v, q_v, 50, cc, 'o', 'filled', ...
                'MarkerFaceAlpha', 0.7, 'MarkerEdgeColor', cc * 0.7);
            h_leg3(end+1) = h; %#ok<AGROW>

            if length(d_v) >= 4
                [r, p] = corr(d_v, q_v, 'Type', 'Pearson');
                leg_txt3{end+1} = sprintf('%s (n=%d, r=%.2f)', geno, n_exp, r); %#ok<AGROW>
                coeffs = polyfit(d_v, q_v, 1);
                x_range = linspace(min(d_v), max(d_v), 50);
                plot(ax3, x_range, polyval(coeffs, x_range), '-', ...
                    'Color', [cc 0.5], 'LineWidth', 1.5, 'HandleVisibility', 'off');
            else
                leg_txt3{end+1} = sprintf('%s (n=%d)', geno, n_exp); %#ok<AGROW>
            end
        end

        xlabel('Block Distance (mm)', 'FontSize', 10);
        ylabel('Block QPI (2nd half)', 'FontSize', 10);
        title(sprintf('%s — All Genotypes', conds(ci).label), 'FontSize', 11);
        if ~isempty(h_leg3)
            legend(h_leg3, leg_txt3, 'Location', 'best', 'FontSize', 8);
        end
        grid on; box on;
    end
    sgtitle('QPI vs Distance — Per Condition', 'FontSize', 13, 'FontWeight', 'bold');
    save_fig(fig3, save_dir, 'qpi_vs_dist_by_condition', opts.ShowPlots);

    fclose(fid);
    fprintf('\nCorrelation stats saved: %s\n', log_file);
    fprintf('Plots saved to: %s\n', save_dir);
end


%% ========================================================================
function [dist_exp, qpi_exp, exp_names] = get_block_means(T_dist, T_qpi, geno, block_train_cycles)
% Returns per-experiment block means for distance and QPI.
%   dist_exp: nExp × nBlocks (mean distance mm)
%   qpi_exp:  nExp × nBlocks (mean QPI 2nd half)
    num_blocks = length(block_train_cycles);

    % Get experiment list from distance table (primary)
    geno_rows_d = strcmp(T_dist.genotype, geno);
    exps_d = unique(T_dist.experiment(geno_rows_d));

    geno_rows_q = strcmp(T_qpi.genotype, geno);
    exps_q = unique(T_qpi.experiment(geno_rows_q));

    % Intersect — only experiments present in both tables
    exp_names = intersect(exps_d, exps_q);
    n_exp = length(exp_names);

    dist_exp = NaN(n_exp, num_blocks);
    qpi_exp  = NaN(n_exp, num_blocks);

    for ei = 1:n_exp
        % Distance block means
        exp_mask_d = strcmp(T_dist.experiment, exp_names{ei});
        for blk = 1:num_blocks
            train_mask = exp_mask_d & ismember(T_dist.cycle, block_train_cycles{blk});
            if any(train_mask)
                dist_exp(ei, blk) = mean(T_dist.mean_dist_mm(train_mask), 'omitnan');
            end
        end

        % QPI block means (second half)
        exp_mask_q = strcmp(T_qpi.experiment, exp_names{ei});
        for blk = 1:num_blocks
            train_mask = exp_mask_q & ismember(T_qpi.cycle, block_train_cycles{blk});
            if any(train_mask)
                qpi_exp(ei, blk) = mean(T_qpi.mean_QPI_secondhalf(train_mask), 'omitnan');
            end
        end
    end
end


%% ========================================================================
function [dist_cycles, qpi_cycles, exp_names] = get_per_cycle_values(T_dist, T_qpi, geno, cycle_nums)
% Returns per-experiment, per-cycle values (NOT block means).
%   dist_cycles: nExp × nCycles
%   qpi_cycles:  nExp × nCycles
    nC = length(cycle_nums);

    geno_rows_d = strcmp(T_dist.genotype, geno);
    exps_d = unique(T_dist.experiment(geno_rows_d));
    geno_rows_q = strcmp(T_qpi.genotype, geno);
    exps_q = unique(T_qpi.experiment(geno_rows_q));
    exp_names = intersect(exps_d, exps_q);
    n_exp = length(exp_names);

    dist_cycles = NaN(n_exp, nC);
    qpi_cycles  = NaN(n_exp, nC);

    for ei = 1:n_exp
        mask_d = strcmp(T_dist.experiment, exp_names{ei});
        mask_q = strcmp(T_qpi.experiment, exp_names{ei});
        for ci = 1:nC
            row_d = mask_d & T_dist.cycle == cycle_nums(ci);
            if any(row_d)
                dist_cycles(ei, ci) = T_dist.mean_dist_mm(row_d);
            end
            row_q = mask_q & T_qpi.cycle == cycle_nums(ci);
            if any(row_q)
                qpi_cycles(ei, ci) = T_qpi.mean_QPI_secondhalf(row_q);
            end
        end
    end
end


%% ========================================================================
function save_fig(fig, save_dir, name, show)
    exportgraphics(fig, fullfile(save_dir, [name '.png']), 'Resolution', 250);
    saveas(fig, fullfile(save_dir, [name '.svg']));
    savefig(fig, fullfile(save_dir, [name '.fig']));
    fprintf('  Saved: %s\n', [name '.png']);
    if show, set(fig, 'Visible', 'on'); else, close(fig); end
end


%% ========================================================================
function c = get_condition_shade(geno, cond_idx)
    switch upper(geno)
        case 'L2A'
            palette = [0.45 0.09 0.18; 0.70 0.24 0.20; 0.82 0.51 0.35];
        case 'L1'
            palette = [0.05 0.20 0.50; 0.15 0.45 0.75; 0.45 0.65 0.82];
        case 'L3A'
            palette = [0.08 0.38 0.12; 0.25 0.60 0.25; 0.55 0.75 0.45];
        case 'L0'
            palette = [0.20 0.20 0.20; 0.45 0.45 0.45; 0.70 0.70 0.70];
        case 'L3C'
            palette = [0.50 0.25 0.00; 0.70 0.40 0.00; 0.85 0.60 0.30];
        otherwise
            palette = [0.30 0.12 0.42; 0.55 0.35 0.65; 0.75 0.60 0.82];
    end
    c = palette(min(cond_idx, size(palette,1)), :);
end


%% ========================================================================
function s = sig_stars(p)
    if p < 0.001,     s = '***';
    elseif p < 0.01,  s = '**';
    elseif p < 0.05,  s = '*';
    else,              s = 'n.s.';
    end
end
