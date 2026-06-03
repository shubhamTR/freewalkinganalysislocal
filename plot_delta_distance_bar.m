function plot_delta_distance_bar(protocols, varargin)
% PLOT_DELTA_DISTANCE_BAR  Bar chart of delta distance (B1 - B_last) per condition.
%
%   plot_delta_distance_bar({'P017','P019'})
%   plot_delta_distance_bar({'P017','P019'}, 'Genotype', 'L2A')
%
%   For a given genotype, computes B1 block mean minus last-block mean
%   distance (mm) per experiment. Produces a bar chart with individual
%   experiment dots, SEM error bars, and one-sample t-test p-values.
%   Between-condition pairwise t-tests are also reported.
%
%   Uses get_protocol_config for cycle layout (works with any protocol).
%
%   Required:
%     protocols      — cell array of protocol names, e.g. {'P017','P019'}
%
%   Name-Value pairs:
%     'AnalysisDir'  — path to analysis root (default: ~/Documents/analysisdatalocal)
%     'Genotype'     — genotype string (default: 'L2A')
%     'ShowPlots'    — logical (default: false)
%     'SavePath'     — override output directory
%
%   Saves PNG + SVG + FIG to condition_comparison/distance/

    ip = inputParser;
    addParameter(ip, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(ip, 'Genotype', 'L2A', @ischar);
    addParameter(ip, 'ShowPlots', false, @islogical);
    addParameter(ip, 'SavePath', '', @ischar);
    parse(ip, varargin{:});
    opts = ip.Results;

    ADIR = opts.AnalysisDir;
    geno = opts.Genotype;

    %% Display-name maps
    [prot_display, geno_display] = get_display_names();
    gname = @(g) map_or_default(geno_display, g);
    pname = @(p) map_or_default(prot_display, p);

    %% Build conditions from protocols input
    nConds = length(protocols);
    conds = struct();
    for ci = 1:nConds
        conds(ci).protocol = protocols{ci};
        conds(ci).label    = pname(protocols{ci});
    end

    %% Get protocol configs and determine block layout
    cfgs = cell(nConds, 1);
    for ci = 1:nConds
        cfgs{ci} = get_protocol_config(conds(ci).protocol);
    end
    % Use minimum number of blocks across conditions
    num_blocks = min(cellfun(@(c) c.num_blocks, cfgs));
    last_block = num_blocks;

    fprintf('Delta distance: B1 vs B%d across %d conditions\n', last_block, nConds);

    %% Load and compute deltas
    delta_all = cell(nConds, 1);
    exp_names_all = cell(nConds, 1);

    for ci = 1:nConds
        prot = conds(ci).protocol;
        cfg = cfgs{ci};
        f = fullfile(ADIR, prot, sprintf('distance_summary_%s.mat', prot));
        tmp = load(f, 'distance_summary');
        T = tmp.distance_summary;

        % Training cycles for B1 and B_last from config
        b1_cycles   = cfg.training_blocks{1};
        blast_cycles = cfg.training_blocks{last_block};

        % Per-experiment block means for this genotype
        geno_rows = strcmp(T.genotype, geno);
        exps = unique(T.experiment(geno_rows));
        n_exp = length(exps);

        b1_means    = NaN(n_exp, 1);
        blast_means = NaN(n_exp, 1);

        for ei = 1:n_exp
            exp_mask = strcmp(T.experiment, exps{ei});
            mask_b1 = exp_mask & ismember(T.cycle, b1_cycles);
            if any(mask_b1)
                b1_means(ei) = mean(T.mean_dist_mm(mask_b1), 'omitnan');
            end
            mask_blast = exp_mask & ismember(T.cycle, blast_cycles);
            if any(mask_blast)
                blast_means(ei) = mean(T.mean_dist_mm(mask_blast), 'omitnan');
            end
        end

        delta_all{ci} = b1_means - blast_means;
        exp_names_all{ci} = exps;
        fprintf('  %s (%s): %d experiments\n', prot, conds(ci).label, n_exp);
    end

    %% Output directory
    if isempty(opts.SavePath)
        save_dir = fullfile(ADIR, 'condition_comparison', 'distance');
    else
        save_dir = opts.SavePath;
    end
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end

    %% Condition colors — same hand-tuned palette as plot_condition_comparison

    %% Plot
    fig = figure('Position', [80 80 550 500], 'Visible', 'off');
    ax = axes; hold on;

    bar_width = 0.6;
    x_positions = 1:nConds;

    for ci = 1:nConds
        cc = get_condition_shade(geno, ci);
        vals = delta_all{ci};
        valid = ~isnan(vals);
        vals = vals(valid);
        n = length(vals);

        m = mean(vals);
        se = std(vals) / sqrt(n);

        % Bar
        bar(ax, x_positions(ci), m, bar_width, 'FaceColor', cc, ...
            'EdgeColor', cc * 0.7, 'LineWidth', 1, 'FaceAlpha', 0.8);

        % SEM error bar
        errorbar(ax, x_positions(ci), m, se, 'Color', [0.3 0.3 0.3], ...
            'LineWidth', 1.5, 'CapSize', 10, 'HandleVisibility', 'off');

        % Individual experiment dots
        jitter = (rand(n, 1) - 0.5) * 0.25;
        scatter(ax, x_positions(ci) + jitter, vals, 40, [0.5 0.5 0.5], ...
            'filled', 'MarkerFaceAlpha', 0.6, 'HandleVisibility', 'off');

        % One-sample t-test (is delta > 0?)
        if n >= 3
            [~, p_val] = ttest(vals, 0, 'Tail', 'right');
            y_top = max(max(vals), m + se) + 15;
            text(ax, x_positions(ci), y_top, sprintf('p=%.3f %s', p_val, sig_stars(p_val)), ...
                'HorizontalAlignment', 'center', 'FontSize', 14, 'Color', [0.2 0.2 0.2]);
        end
    end

    %% Between-condition pairwise t-tests
    if nConds >= 2
        pairs = nchoosek(1:nConds, 2);
        fprintf('\n--- Between-condition t-tests (B1-B%d delta) ---\n', last_block);
        for pi = 1:size(pairs,1)
            a = pairs(pi,1); b = pairs(pi,2);
            va = delta_all{a}(~isnan(delta_all{a}));
            vb = delta_all{b}(~isnan(delta_all{b}));
            if length(va) >= 3 && length(vb) >= 3
                [~, p_val] = ttest2(va, vb);
                fprintf('  %s vs %s: p=%.4f %s  (n=%d,%d)\n', ...
                    conds(a).label, conds(b).label, p_val, sig_stars(p_val), ...
                    length(va), length(vb));
            end
        end
    end

    %% Format
    set(ax, 'XTick', x_positions, 'XTickLabel', {conds.label});
    set(ax, 'FontSize', 16);
    ylabel(sprintf('Delta distance, B1 - B%d (mm)', last_block), 'FontSize', 18);
    title(sprintf('%s — Distance decrease (B1 to B%d)', gname(geno), last_block), 'FontSize', 20);
    xlim([0.3 nConds + 0.7]);
    yl = ylim(ax);
    ylim(ax, [min(yl(1), -20) yl(2) * 1.15]);
    yline(ax, 0, '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8, 'HandleVisibility', 'off');
    box on; grid on;
    set(ax, 'GridAlpha', 0.15);

    %% Save
    tag = strjoin({conds.protocol}, '_');
    fname = sprintf('delta_distance_bar_%s_%s', geno, tag);
    exportgraphics(fig, fullfile(save_dir, [fname '.png']), 'Resolution', 250);
    saveas(fig, fullfile(save_dir, [fname '.svg']));
    savefig(fig, fullfile(save_dir, [fname '.fig']));
    fprintf('Saved: %s.png\n', fname);

    if opts.ShowPlots
        set(fig, 'Visible', 'on');
    else
        close(fig);
    end
end


%% ========================================================================
%  get_condition_shade — Hand-tuned condition colors per genotype.
%    cond_idx: 1=darkest, 2=mid, 3=lightest (matches plot_condition_comparison)
%  ========================================================================
function c = get_condition_shade(geno, cond_idx)
    switch upper(geno)
        case 'L2A'   % red → wine / brick / terracotta
            palette = [0.45 0.09 0.18;
                       0.70 0.24 0.20;
                       0.82 0.51 0.35];
        case 'L1'    % blue → navy / blue / steel
            palette = [0.05 0.20 0.50;
                       0.15 0.45 0.75;
                       0.45 0.65 0.82];
        case 'L3A'   % green → forest / green / sage
            palette = [0.08 0.38 0.12;
                       0.25 0.60 0.25;
                       0.55 0.75 0.45];
        case 'L0'    % grey → charcoal / grey / silver
            palette = [0.20 0.20 0.20;
                       0.45 0.45 0.45;
                       0.70 0.70 0.70];
        case 'L3C'   % orange → chocolate / burnt orange / sand
            palette = [0.50 0.25 0.00;
                       0.70 0.40 0.00;
                       0.85 0.60 0.30];
        otherwise    % purple fallback
            palette = [0.30 0.12 0.42;
                       0.55 0.35 0.65;
                       0.75 0.60 0.82];
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


