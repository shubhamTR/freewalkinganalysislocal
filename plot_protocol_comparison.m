function plot_protocol_comparison(protocols, varargin)
% PLOT_PROTOCOL_COMPARISON  Overlay any set of protocols for distance, latency & QPI.
%
%   plot_protocol_comparison({'P017','P019'})
%   plot_protocol_comparison({'P013','P017','P019'}, 'Genotypes', {'L1','L2A'})
%   plot_protocol_comparison({'P008','P010'}, 'ShowPlots', true, 'RunStats', false)
%
%   Compares any number of place-learning protocols. For each genotype and
%   metric (distance, latency, QPI first/second half), produces overlay
%   figures:
%     - All training cycles (x-axis = full cycle index per protocol)
%     - Distance PP-onwards (from preprobe cycle, OM excluded)
%     - Block means (B1, B2, ..., up to the minimum shared block count)
%     - Probes (PP, B1.P, B2.P, ..., up to the minimum shared probe count)
%
%   Also produces combined overlay figures with all genotypes.
%   Colors follow the hand-tuned get_condition_shade palette (not a ramp).
%   Markers cycle through o, s, ^, d per protocol index.
%
%   NAME-VALUE PARAMETERS
%     'AnalysisDir'  — root of protocol folders
%                      (default: '/Users/rathores/Documents/analysisdatalocal')
%     'Genotypes'    — cell array of genotypes to plot (default: {} = auto-detect)
%     'Metrics'      — cell array of {key,col,ylabel,tag} rows (default: {} = built-in)
%     'SavePath'     — output folder (default: <AnalysisDir>/protocol_comparison/<tag>)
%     'ShowPlots'    — display figures interactively (default: false)
%     'RunStats'     — run ANOVA + variance + paired t-test block comparisons
%                      (default: true)

    %% ----------------------------------------------------------------
    %  Parse inputs
    %  ----------------------------------------------------------------
    ip = inputParser;
    addRequired(ip,  'protocols',   @iscell);
    addParameter(ip, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(ip, 'Genotypes',   {},    @iscell);
    addParameter(ip, 'Metrics',     {},    @iscell);
    addParameter(ip, 'SavePath',    '',    @ischar);
    addParameter(ip, 'ShowPlots',   false, @islogical);
    addParameter(ip, 'RunStats',    true,  @islogical);
    parse(ip, protocols, varargin{:});
    opts  = ip.Results;

    ADIR  = opts.AnalysisDir;
    prots = protocols;
    nProt = length(prots);

    %% ----------------------------------------------------------------
    %  Display-name maps
    %  ----------------------------------------------------------------
    [prot_display, geno_display] = get_display_names();
    gname = @(g) map_or_default(geno_display, g);
    pname = @(p) map_or_default(prot_display, p);

    %% ----------------------------------------------------------------
    %  Save directory
    %  ----------------------------------------------------------------
    if isempty(opts.SavePath)
        save_dir = fullfile(ADIR, 'protocol_comparison', strjoin(prots, '_vs_'));
    else
        save_dir = opts.SavePath;
    end
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end

    %% ----------------------------------------------------------------
    %  Default metrics  {data_key, column_name, y_label, file_tag}
    %  ----------------------------------------------------------------
    if isempty(opts.Metrics)
        metrics = {
            'distance', 'mean_dist_mm',          'Distance (mm)',                'distance';
            'latency',  'mean_latency_s',         'Latency to dark quadrant (s)','latency';
            'qpi',      'mean_QPI_firsthalf',     'QPI (first half)',             'QPI_firsthalf';
            'qpi',      'mean_QPI_secondhalf',    'QPI (second half)',            'QPI_secondhalf';
        };
    else
        metrics = opts.Metrics;
    end

    %% ----------------------------------------------------------------
    %  Markers — one per protocol, cycling through list
    %  ----------------------------------------------------------------
    marker_list = {'o', 's', '^', 'd'};

    %% ----------------------------------------------------------------
    %  Load protocol configs + summary data
    %  Only load each unique metric key once per protocol.
    %  ----------------------------------------------------------------
    cfgs = cell(nProt, 1);
    data = struct();

    unique_keys = unique(metrics(:,1), 'stable');

    for pi = 1:nProt
        prot = prots{pi};
        cfgs{pi} = get_protocol_config(prot);

        for ki = 1:length(unique_keys)
            metric_key = unique_keys{ki};
            switch metric_key
                case 'distance'
                    mat_name = 'distance_summary';
                case 'latency'
                    mat_name = 'latency_summary';
                case 'dist_to_safe'
                    mat_name = 'dist_to_safe_summary';
                case 'qpi'
                    mat_name = 'QPI_summary';
                otherwise
                    mat_name = [metric_key '_summary'];
            end
            f = fullfile(ADIR, prot, sprintf('%s_%s.mat', mat_name, prot));
            if ~exist(f, 'file')
                error('Missing summary file: %s', f);
            end
            tmp = load(f, mat_name);
            data(pi).(metric_key) = tmp.(mat_name);
        end

        fprintf('Loaded %s\n', prot);
    end

    %% ----------------------------------------------------------------
    %  Auto-detect genotypes (from first metric key, across all protocols)
    %  ----------------------------------------------------------------
    first_key = unique_keys{1};
    if isempty(opts.Genotypes)
        all_genos = {};
        for pi = 1:nProt
            g = unique(data(pi).(first_key).genotype);
            all_genos = union(all_genos, g);
        end
        genos = sort(all_genos);
        fprintf('Auto-detected genotypes: %s\n', strjoin(genos, ', '));
    else
        genos = opts.Genotypes;
    end

    %% ----------------------------------------------------------------
    %  Build display title
    %  ----------------------------------------------------------------
    prot_dnames = cellfun(pname, prots, 'UniformOutput', false);
    prot_title  = strjoin(prot_dnames, ' vs ');

    %% ----------------------------------------------------------------
    %  Protocol configs and derived layout
    %  ----------------------------------------------------------------
    % min_blocks and min_probes across protocols
    min_blocks = min(cellfun(@(c) c.num_blocks, cfgs));
    min_probes = min(cellfun(@(c) length(c.all_probe_cycle_nums), cfgs));

    % Per-protocol cond_layout struct array (parallel to prots)
    cond_layout = struct();
    for pi = 1:nProt
        cfg    = cfgs{pi};
        om_set = cfg.om_cycles;
        all_c  = 1:cfg.num_cycles;
        cond_layout(pi).all_cycles         = all_c;
        cond_layout(pi).plot_cycles        = all_c(~ismember(all_c, om_set));
        cond_layout(pi).block_train_cycles = cfg.training_blocks(1:min_blocks);
        cond_layout(pi).probe_cycle_nums   = cfg.all_probe_cycle_nums(1:min_probes);
        cond_layout(pi).probe_labels       = cfg.probe_labels(1:min_probes);
    end

    block_labels = arrayfun(@(b) sprintf('B%d', b), 1:min_blocks, 'UniformOutput', false);
    probe_labels = cond_layout(1).probe_labels;

    fprintf('Common structure: %d blocks, %d probes\n', min_blocks, min_probes);

    %% ================================================================
    %  SECTION 1 — ALL CYCLES
    %  ================================================================
    for mi = 1:size(metrics, 1)
        metric_key = metrics{mi,1};
        metric_col = metrics{mi,2};
        y_label    = metrics{mi,3};
        file_tag   = metrics{mi,4};
        is_qpi     = strcmp(metric_key, 'qpi');

        % Create metric subdirectory
        metric_dir = fullfile(save_dir, file_tag);
        if ~exist(metric_dir, 'dir'), mkdir(metric_dir); end

        % --- Per-genotype figure ---
        for gi = 1:length(genos)
            geno = genos{gi};
            fig = figure('Position', [80 80 1600 520], 'Visible', 'off');
            ax  = axes; hold on;
            h_lines = []; leg_entries = {};

            for pi = 1:nProt
                cc     = get_condition_shade(geno, pi);
                mkr    = marker_list{mod(pi-1, length(marker_list)) + 1};
                T      = data(pi).(metric_key);
                plot_c = 1:cfgs{pi}.num_cycles;

                [m, se, n_exp] = compute_allcycles(T, geno, metric_col, plot_c);
                if all(isnan(m)), continue; end
                nf = count_flies(T, geno);

                valid = ~isnan(m);
                x_v = plot_c(valid); m_v = m(valid); se_v = se(valid);

                fill(ax, [x_v, fliplr(x_v)], [m_v+se_v, fliplr(m_v-se_v)], ...
                    cc, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                h = plot(ax, x_v, m_v, [mkr '-'], ...
                    'Color', cc, 'MarkerFaceColor', cc, ...
                    'MarkerSize', 5, 'LineWidth', 1.3);
                h_lines(end+1)    = h; %#ok<AGROW>
                leg_entries{end+1} = sprintf('%s (n=%d exp, %d flies)', pname(prots{pi}), n_exp, nf); %#ok<AGROW>
            end

            add_qpi_annotations(ax, cfgs{1});
            ylabel(y_label, 'FontSize', 18); xlabel('Cycle', 'FontSize', 18);
            title(sprintf('%s — All Cycles — %s', gname(geno), prot_title), ...
                'FontSize', 20, 'FontWeight', 'bold');
            xlim([0.5 cfgs{1}.num_cycles+0.5]);
            set(ax, 'XTick', 1:2:cfgs{1}.num_cycles);
            set(ax, 'FontSize', 16);
            if is_qpi, ylim_auto(ax); else, ylim_auto(ax); end
            box on;
            if ~isempty(h_lines)
                legend(h_lines, leg_entries, 'Location', 'bestoutside', 'FontSize', 14);
            end
            save_fig(fig, metric_dir, sprintf('allcycles_%s', geno), opts.ShowPlots);
        end

        % --- Combined overlay ---
        fig_ov = figure('Position', [80 80 1600 550], 'Visible', 'off');
        ax_ov  = axes; hold on;
        h_lines = []; leg_entries = {};

        for gi = 1:length(genos)
            geno = genos{gi};
            for pi = 1:nProt
                cc     = get_condition_shade(geno, pi);
                mkr    = marker_list{mod(pi-1, length(marker_list)) + 1};
                T      = data(pi).(metric_key);
                plot_c = 1:cfgs{pi}.num_cycles;

                [m, se, n_exp] = compute_allcycles(T, geno, metric_col, plot_c);
                if all(isnan(m)), continue; end
                nf = count_flies(T, geno);

                valid = ~isnan(m);
                x_v = plot_c(valid); m_v = m(valid); se_v = se(valid);

                fill(ax_ov, [x_v, fliplr(x_v)], [m_v+se_v, fliplr(m_v-se_v)], ...
                    cc, 'FaceAlpha', 0.08, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                h = plot(ax_ov, x_v, m_v, [mkr '-'], ...
                    'Color', cc, 'MarkerFaceColor', cc, ...
                    'MarkerSize', 5, 'LineWidth', 1.3);
                h_lines(end+1)    = h; %#ok<AGROW>
                leg_entries{end+1} = sprintf('%s %s (n=%d, %d flies)', gname(geno), pname(prots{pi}), n_exp, nf); %#ok<AGROW>
            end
        end

        add_qpi_annotations(ax_ov, cfgs{1});
        ylabel(y_label, 'FontSize', 18); xlabel('Cycle', 'FontSize', 18);
        title(sprintf('All Genotypes — All Cycles — %s', prot_title), ...
            'FontSize', 20, 'FontWeight', 'bold');
        xlim([0.5 cfgs{1}.num_cycles+0.5]);
        set(ax_ov, 'XTick', 1:2:cfgs{1}.num_cycles);
        set(ax_ov, 'FontSize', 16);
        if is_qpi, ylim_auto(ax_ov); else, ylim_auto(ax_ov); end
        box on;
        if ~isempty(h_lines)
            legend(h_lines, leg_entries, 'Location', 'bestoutside', 'FontSize', 14);
        end
        save_fig(fig_ov, metric_dir, 'allcycles_overlay', opts.ShowPlots);
    end

    %% ================================================================
    %  SECTION 2 — DISTANCE PP-ONWARDS
    %  ================================================================
    dist_idx = find(strcmp(metrics(:,1), 'distance'), 1);
    if ~isempty(dist_idx)
        metric_col_d = metrics{dist_idx, 2};
        y_label_d    = metrics{dist_idx, 3};
        file_tag_d   = metrics{dist_idx, 4};

        metric_dir_d = fullfile(save_dir, file_tag_d);
        if ~exist(metric_dir_d, 'dir'), mkdir(metric_dir_d); end

        % Reference PP range (from first protocol, excluding OM)
        ref_cfg  = cfgs{1};
        om_set   = ref_cfg.om_cycles;
        pp_cyc   = ref_cfg.preprobe_cycle;
        if isempty(pp_cyc), pp_cyc = 1; end
        pp_range = pp_cyc:ref_cfg.num_cycles;
        pp_range = pp_range(~ismember(pp_range, om_set));

        % --- Per-genotype ---
        for gi = 1:length(genos)
            geno = genos{gi};
            fig = figure('Position', [80 80 1600 520], 'Visible', 'off');
            ax  = axes; hold on;
            h_lines = []; leg_entries = {};

            for pi = 1:nProt
                cc     = get_condition_shade(geno, pi);
                mkr    = marker_list{mod(pi-1, length(marker_list)) + 1};
                T      = data(pi).distance;
                cfg_p  = cfgs{pi};
                om_p   = cfg_p.om_cycles;
                pp_p   = cfg_p.preprobe_cycle;
                if isempty(pp_p), pp_p = 1; end
                plot_c = pp_p:cfg_p.num_cycles;
                plot_c = plot_c(~ismember(plot_c, om_p));

                [m, se, n_exp] = compute_allcycles(T, geno, metric_col_d, plot_c);
                if all(isnan(m)), continue; end
                nf = count_flies(T, geno);

                valid = ~isnan(m);
                x_v = plot_c(valid); m_v = m(valid); se_v = se(valid);

                fill(ax, [x_v, fliplr(x_v)], [m_v+se_v, fliplr(m_v-se_v)], ...
                    cc, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                h = plot(ax, x_v, m_v, [mkr '-'], ...
                    'Color', cc, 'MarkerFaceColor', cc, ...
                    'MarkerSize', 5, 'LineWidth', 1.3);
                h_lines(end+1)    = h; %#ok<AGROW>
                leg_entries{end+1} = sprintf('%s (n=%d exp, %d flies)', pname(prots{pi}), n_exp, nf); %#ok<AGROW>
            end

            add_qpi_annotations(ax, ref_cfg);
            ylabel(y_label_d, 'FontSize', 18); xlabel('Cycle', 'FontSize', 18);
            title(sprintf('%s — PP Onwards — %s', gname(geno), prot_title), ...
                'FontSize', 20, 'FontWeight', 'bold');
            xlim([pp_range(1)-0.5  pp_range(end)+0.5]);
            set(ax, 'XTick', pp_range(1):2:pp_range(end));
            set(ax, 'FontSize', 16);
            ylim_auto(ax);
            box on;
            if ~isempty(h_lines)
                legend(h_lines, leg_entries, 'Location', 'bestoutside', 'FontSize', 14);
            end
            save_fig(fig, metric_dir_d, sprintf('pp_onwards_%s', geno), opts.ShowPlots);
        end

        % --- Combined overlay ---
        fig_ov = figure('Position', [80 80 1600 550], 'Visible', 'off');
        ax_ov  = axes; hold on;
        h_lines = []; leg_entries = {};

        for gi = 1:length(genos)
            geno = genos{gi};
            for pi = 1:nProt
                cc     = get_condition_shade(geno, pi);
                mkr    = marker_list{mod(pi-1, length(marker_list)) + 1};
                T      = data(pi).distance;
                cfg_p  = cfgs{pi};
                om_p   = cfg_p.om_cycles;
                pp_p   = cfg_p.preprobe_cycle;
                if isempty(pp_p), pp_p = 1; end
                plot_c = pp_p:cfg_p.num_cycles;
                plot_c = plot_c(~ismember(plot_c, om_p));

                [m, se, n_exp] = compute_allcycles(T, geno, metric_col_d, plot_c);
                if all(isnan(m)), continue; end
                nf = count_flies(T, geno);

                valid = ~isnan(m);
                x_v = plot_c(valid); m_v = m(valid); se_v = se(valid);

                fill(ax_ov, [x_v, fliplr(x_v)], [m_v+se_v, fliplr(m_v-se_v)], ...
                    cc, 'FaceAlpha', 0.08, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                h = plot(ax_ov, x_v, m_v, [mkr '-'], ...
                    'Color', cc, 'MarkerFaceColor', cc, ...
                    'MarkerSize', 5, 'LineWidth', 1.3);
                h_lines(end+1)    = h; %#ok<AGROW>
                leg_entries{end+1} = sprintf('%s %s (n=%d, %d flies)', gname(geno), pname(prots{pi}), n_exp, nf); %#ok<AGROW>
            end
        end

        add_qpi_annotations(ax_ov, ref_cfg);
        ylabel(y_label_d, 'FontSize', 18); xlabel('Cycle', 'FontSize', 18);
        title(sprintf('All Genotypes — PP Onwards — %s', prot_title), ...
            'FontSize', 20, 'FontWeight', 'bold');
        xlim([pp_range(1)-0.5  pp_range(end)+0.5]);
        set(ax_ov, 'XTick', pp_range(1):2:pp_range(end));
        set(ax_ov, 'FontSize', 16);
        ylim_auto(ax_ov);
        box on;
        if ~isempty(h_lines)
            legend(h_lines, leg_entries, 'Location', 'bestoutside', 'FontSize', 14);
        end
        save_fig(fig_ov, metric_dir_d, 'pp_onwards_overlay', opts.ShowPlots);
    end

    %% ================================================================
    %  SECTION 3 — BLOCKS
    %  ================================================================
    for mi = 1:size(metrics, 1)
        metric_key = metrics{mi,1};
        metric_col = metrics{mi,2};
        y_label    = metrics{mi,3};
        file_tag   = metrics{mi,4};

        metric_dir = fullfile(save_dir, file_tag);
        if ~exist(metric_dir, 'dir'), mkdir(metric_dir); end

        % --- Per-genotype ---
        for gi = 1:length(genos)
            geno = genos{gi};
            fig = figure('Position', [80 80 650 500], 'Visible', 'off');
            ax  = axes; hold on;
            h_lines = []; leg_entries = {};

            for pi = 1:nProt
                cc  = get_condition_shade(geno, pi);
                mkr = marker_list{mod(pi-1, length(marker_list)) + 1};
                T   = data(pi).(metric_key);
                [m, se, n_exp] = compute_blocks(T, geno, metric_col, cond_layout(pi).block_train_cycles);
                if all(isnan(m)), continue; end
                nf  = count_flies(T, geno);
                x_v = 1:min_blocks;

                fill(ax, [x_v, fliplr(x_v)], [m+se, fliplr(m-se)], ...
                    cc, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                h = plot(ax, x_v, m, [mkr '-'], ...
                    'Color', cc, 'MarkerFaceColor', cc, ...
                    'MarkerSize', 8, 'LineWidth', 1.5);
                h_lines(end+1)    = h; %#ok<AGROW>
                leg_entries{end+1} = sprintf('%s (n=%d exp, %d flies)', pname(prots{pi}), n_exp, nf); %#ok<AGROW>
            end

            set(ax, 'XTick', 1:min_blocks, 'XTickLabel', block_labels);
            set(ax, 'FontSize', 16);
            xlabel('Training Block', 'FontSize', 18); ylabel(y_label, 'FontSize', 18);
            title(sprintf('%s — Blocks — %s', gname(geno), prot_title), 'FontSize', 20);
            xlim([0.5 min_blocks+0.5]); grid on; box on;
            if ~isempty(h_lines)
                legend(h_lines, leg_entries, 'Location', 'best', 'FontSize', 14);
            end
            save_fig(fig, metric_dir, sprintf('blocks_%s', geno), opts.ShowPlots);
        end

        % --- Combined overlay ---
        fig_ov = figure('Position', [80 80 700 500], 'Visible', 'off');
        ax_ov  = axes; hold on;
        h_lines = []; leg_entries = {};

        for gi = 1:length(genos)
            geno = genos{gi};
            for pi = 1:nProt
                cc  = get_condition_shade(geno, pi);
                mkr = marker_list{mod(pi-1, length(marker_list)) + 1};
                T   = data(pi).(metric_key);
                [m, se, n_exp] = compute_blocks(T, geno, metric_col, cond_layout(pi).block_train_cycles);
                if all(isnan(m)), continue; end
                nf  = count_flies(T, geno);
                x_v = 1:min_blocks;

                fill(ax_ov, [x_v, fliplr(x_v)], [m+se, fliplr(m-se)], ...
                    cc, 'FaceAlpha', 0.08, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                h = plot(ax_ov, x_v, m, [mkr '-'], ...
                    'Color', cc, 'MarkerFaceColor', cc, ...
                    'MarkerSize', 8, 'LineWidth', 1.5);
                h_lines(end+1)    = h; %#ok<AGROW>
                leg_entries{end+1} = sprintf('%s %s (n=%d, %d flies)', gname(geno), pname(prots{pi}), n_exp, nf); %#ok<AGROW>
            end
        end

        set(ax_ov, 'XTick', 1:min_blocks, 'XTickLabel', block_labels);
        set(ax_ov, 'FontSize', 16);
        xlabel('Training Block', 'FontSize', 18); ylabel(y_label, 'FontSize', 18);
        title(sprintf('All Genotypes — Blocks — %s', prot_title), 'FontSize', 20);
        xlim([0.5 min_blocks+0.5]); grid on; box on;
        if ~isempty(h_lines)
            legend(h_lines, leg_entries, 'Location', 'bestoutside', 'FontSize', 14);
        end
        save_fig(fig_ov, metric_dir, 'blocks_overlay', opts.ShowPlots);
    end

    %% ================================================================
    %  SECTION 4 — PROBES
    %  ================================================================
    num_probes = min_probes;

    for mi = 1:size(metrics, 1)
        metric_key = metrics{mi,1};
        metric_col = metrics{mi,2};
        y_label    = metrics{mi,3};
        file_tag   = metrics{mi,4};

        metric_dir = fullfile(save_dir, file_tag);
        if ~exist(metric_dir, 'dir'), mkdir(metric_dir); end

        % --- Per-genotype ---
        for gi = 1:length(genos)
            geno = genos{gi};
            fig = figure('Position', [80 80 650 500], 'Visible', 'off');
            ax  = axes; hold on;
            h_lines = []; leg_entries = {};

            for pi = 1:nProt
                cc  = get_condition_shade(geno, pi);
                T   = data(pi).(metric_key);
                [m, se, n_exp] = compute_probes(T, geno, metric_col, cond_layout(pi).probe_cycle_nums);
                if all(isnan(m)), continue; end
                nf    = count_flies(T, geno);
                valid = ~isnan(m);
                x_v   = find(valid); m_v = m(valid); se_v = se(valid);

                fill(ax, [x_v, fliplr(x_v)], [m_v+se_v, fliplr(m_v-se_v)], ...
                    cc, 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                h = plot(ax, x_v, m_v, '^-', ...
                    'Color', cc, 'MarkerFaceColor', cc, ...
                    'MarkerSize', 8, 'LineWidth', 1.5);
                h_lines(end+1)    = h; %#ok<AGROW>
                leg_entries{end+1} = sprintf('%s (n=%d exp, %d flies)', pname(prots{pi}), n_exp, nf); %#ok<AGROW>
            end

            set(ax, 'XTick', 1:num_probes, 'XTickLabel', probe_labels);
            set(ax, 'FontSize', 16);
            xlabel('Probe Trial', 'FontSize', 18); ylabel(y_label, 'FontSize', 18);
            title(sprintf('%s — Probes — %s', gname(geno), prot_title), 'FontSize', 20);
            xlim([0.5 num_probes+0.5]); grid on; box on;
            if ~isempty(h_lines)
                legend(h_lines, leg_entries, 'Location', 'best', 'FontSize', 14);
            end
            save_fig(fig, metric_dir, sprintf('probes_%s', geno), opts.ShowPlots);
        end

        % --- Combined overlay ---
        fig_ov = figure('Position', [80 80 700 500], 'Visible', 'off');
        ax_ov  = axes; hold on;
        h_lines = []; leg_entries = {};

        for gi = 1:length(genos)
            geno = genos{gi};
            for pi = 1:nProt
                cc  = get_condition_shade(geno, pi);
                T   = data(pi).(metric_key);
                [m, se, n_exp] = compute_probes(T, geno, metric_col, cond_layout(pi).probe_cycle_nums);
                if all(isnan(m)), continue; end
                nf    = count_flies(T, geno);
                valid = ~isnan(m);
                x_v   = find(valid); m_v = m(valid); se_v = se(valid);

                fill(ax_ov, [x_v, fliplr(x_v)], [m_v+se_v, fliplr(m_v-se_v)], ...
                    cc, 'FaceAlpha', 0.08, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                h = plot(ax_ov, x_v, m_v, '^-', ...
                    'Color', cc, 'MarkerFaceColor', cc, ...
                    'MarkerSize', 8, 'LineWidth', 1.5);
                h_lines(end+1)    = h; %#ok<AGROW>
                leg_entries{end+1} = sprintf('%s %s (n=%d, %d flies)', gname(geno), pname(prots{pi}), n_exp, nf); %#ok<AGROW>
            end
        end

        set(ax_ov, 'XTick', 1:num_probes, 'XTickLabel', probe_labels);
        set(ax_ov, 'FontSize', 16);
        xlabel('Probe Trial', 'FontSize', 18); ylabel(y_label, 'FontSize', 18);
        title(sprintf('All Genotypes — Probes — %s', prot_title), 'FontSize', 20);
        xlim([0.5 num_probes+0.5]); grid on; box on;
        if ~isempty(h_lines)
            legend(h_lines, leg_entries, 'Location', 'bestoutside', 'FontSize', 14);
        end
        save_fig(fig_ov, metric_dir, 'probes_overlay', opts.ShowPlots);
    end

    %% ================================================================
    %  SECTION 5 — STATISTICS
    %  ================================================================
    if opts.RunStats

    stats_dir = fullfile(save_dir, 'statistics');
    if ~exist(stats_dir, 'dir'), mkdir(stats_dir); end

    all_anova_results = {};

    for stat_mi = 1:size(metrics, 1)
        stat_key   = metrics{stat_mi, 1};
        stat_col   = metrics{stat_mi, 2};
        stat_label = metrics{stat_mi, 3};

        fprintf('\n═══ ANOVA: %s across protocols ═══\n\n', stat_label);

        log_file = fullfile(stats_dir, sprintf('anova_%s_results.txt', stat_key));
        fid = fopen(log_file, 'w');
        fprintf(fid, 'ANOVA — %s Across Protocols\n', stat_label);
        prot_labels_str = strjoin(cellfun(pname, prots, 'UniformOutput', false), ', ');
        fprintf(fid, 'Conditions: %s\n', prot_labels_str);
        fprintf(fid, 'Date: %s\n', datestr(now));
        fprintf(fid, 'Unit of replication: experiment mean\n');
        fprintf(fid, '============================================================\n\n');

        %% 5a. ANOVA per genotype
        for gi = 1:length(genos)
            geno = genos{gi};
            fprintf('--- %s ---\n', geno);
            fprintf(fid, '--- %s ---\n', geno);

            % Overall training mean (pool all blocks → one mean per experiment per condition)
            cond_labels_all = {};
            values_all      = [];

            for pi = 1:nProt
                T = data(pi).(stat_key);
                [~, ~, ~, exp_means] = compute_blocks_raw(T, geno, stat_col, cond_layout(pi).block_train_cycles);
                overall = mean(exp_means, 2, 'omitnan');
                valid   = ~isnan(overall);
                vals    = overall(valid);
                values_all      = [values_all; vals(:)]; %#ok<AGROW>
                cond_labels_all = [cond_labels_all; repmat({pname(prots{pi})}, length(vals), 1)]; %#ok<AGROW>
            end

            if length(unique(cond_labels_all)) >= 2 && length(values_all) >= 3
                [p_overall, tbl_overall, stats_overall] = anova1(values_all, cond_labels_all, 'off');
                fprintf('  Overall training: F=%.2f, p=%.4f\n', tbl_overall{2,5}, p_overall);
                fprintf(fid, '  Overall training: F(%.0f,%.0f)=%.3f, p=%.4f\n', ...
                    tbl_overall{2,3}, tbl_overall{3,3}, tbl_overall{2,5}, p_overall);

                if p_overall < 0.05
                    mc = multcompare(stats_overall, 'Display', 'off');
                    fprintf(fid, '  Post-hoc (Tukey-Kramer):\n');
                    grp_names = stats_overall.gnames;
                    for ri = 1:size(mc, 1)
                        fprintf(fid, '    %s vs %s: diff=%.1f, p=%.4f %s\n', ...
                            grp_names{mc(ri,1)}, grp_names{mc(ri,2)}, ...
                            mc(ri,4), mc(ri,6), sig_stars(mc(ri,6)));
                        fprintf('    %s vs %s: p=%.4f %s\n', ...
                            grp_names{mc(ri,1)}, grp_names{mc(ri,2)}, ...
                            mc(ri,6), sig_stars(mc(ri,6)));
                    end
                end

                res.genotype   = geno;
                res.comparison = 'overall_training';
                res.F          = tbl_overall{2,5};
                res.df_between = tbl_overall{2,3};
                res.df_within  = tbl_overall{3,3};
                res.p          = p_overall;
                all_anova_results{end+1} = res; %#ok<AGROW>
            else
                fprintf('  Overall training: insufficient data for ANOVA\n');
                fprintf(fid, '  Overall training: insufficient data for ANOVA\n');
            end

            % Per-block ANOVA
            for blk = 1:min_blocks
                cond_labels_blk = {};
                values_blk      = [];

                for pi = 1:nProt
                    T = data(pi).(stat_key);
                    [~, ~, ~, exp_means] = compute_blocks_raw(T, geno, stat_col, cond_layout(pi).block_train_cycles);
                    vals  = exp_means(:, blk);
                    valid = ~isnan(vals);
                    vals  = vals(valid);
                    values_blk      = [values_blk; vals(:)]; %#ok<AGROW>
                    cond_labels_blk = [cond_labels_blk; repmat({pname(prots{pi})}, length(vals), 1)]; %#ok<AGROW>
                end

                if length(unique(cond_labels_blk)) >= 2 && length(values_blk) >= 3
                    [p_blk, tbl_blk, stats_blk] = anova1(values_blk, cond_labels_blk, 'off');
                    fprintf('  %s: F=%.2f, p=%.4f %s\n', block_labels{blk}, tbl_blk{2,5}, p_blk, sig_stars(p_blk));
                    fprintf(fid, '  %s: F(%.0f,%.0f)=%.3f, p=%.4f %s\n', ...
                        block_labels{blk}, tbl_blk{2,3}, tbl_blk{3,3}, tbl_blk{2,5}, p_blk, sig_stars(p_blk));

                    if p_blk < 0.05
                        mc = multcompare(stats_blk, 'Display', 'off');
                        grp_names = stats_blk.gnames;
                        for ri = 1:size(mc, 1)
                            fprintf(fid, '    %s vs %s: diff=%.1f, p=%.4f %s\n', ...
                                grp_names{mc(ri,1)}, grp_names{mc(ri,2)}, ...
                                mc(ri,4), mc(ri,6), sig_stars(mc(ri,6)));
                        end
                    end

                    res.genotype   = geno;
                    res.comparison = block_labels{blk};
                    res.F          = tbl_blk{2,5};
                    res.df_between = tbl_blk{2,3};
                    res.df_within  = tbl_blk{3,3};
                    res.p          = p_blk;
                    all_anova_results{end+1} = res; %#ok<AGROW>
                else
                    fprintf('  %s: insufficient data\n', block_labels{blk});
                    fprintf(fid, '  %s: insufficient data\n', block_labels{blk});
                end
            end

            fprintf(fid, '\n');
            fprintf('\n');
        end

        %% 5b. Variance tests
        fprintf(fid, '\n============================================================\n');
        fprintf(fid, 'VARIANCE TESTS — %s Across Protocols\n', stat_label);
        fprintf(fid, '============================================================\n\n');
        fprintf('\n═══ Variance Tests ═══\n\n');

        for gi = 1:length(genos)
            geno = genos{gi};
            fprintf('--- %s ---\n', geno);
            fprintf(fid, '--- %s ---\n', geno);

            vals_all  = [];
            names_all = {};
            for pi = 1:nProt
                T = data(pi).(stat_key);
                [~, ~, ~, exp_means] = compute_blocks_raw(T, geno, stat_col, cond_layout(pi).block_train_cycles);
                overall = mean(exp_means, 2, 'omitnan');
                valid   = ~isnan(overall);
                vals    = overall(valid);
                vals_all  = [vals_all; vals(:)]; %#ok<AGROW>
                names_all = [names_all; repmat({pname(prots{pi})}, length(vals), 1)]; %#ok<AGROW>

                fprintf('  %s: n=%d, mean=%.1f, std=%.1f, var=%.1f\n', ...
                    pname(prots{pi}), length(vals), mean(vals), std(vals), var(vals));
                fprintf(fid, '  %s: n=%d, mean=%.1f, std=%.1f, var=%.1f\n', ...
                    pname(prots{pi}), length(vals), mean(vals), std(vals), var(vals));
            end

            if length(unique(names_all)) >= 2
                % Bartlett
                try
                    p_bart = vartestn(vals_all, names_all, 'TestType', 'Bartlett', 'Display', 'off');
                    fprintf('  Bartlett:       p=%.4f %s\n', p_bart, sig_stars(p_bart));
                    fprintf(fid, '  Bartlett:       p=%.4f %s\n', p_bart, sig_stars(p_bart));
                catch ME
                    fprintf('  Bartlett failed: %s\n', ME.message);
                    fprintf(fid, '  Bartlett failed: %s\n', ME.message);
                end

                % Levene
                try
                    p_lev = vartestn(vals_all, names_all, 'TestType', 'LeveneAbsolute', 'Display', 'off');
                    fprintf('  Levene:         p=%.4f %s\n', p_lev, sig_stars(p_lev));
                    fprintf(fid, '  Levene:         p=%.4f %s\n', p_lev, sig_stars(p_lev));
                catch ME
                    fprintf('  Levene failed: %s\n', ME.message);
                    fprintf(fid, '  Levene failed: %s\n', ME.message);
                end

                % Brown-Forsythe
                try
                    p_bf = vartestn(vals_all, names_all, 'TestType', 'BrownForsythe', 'Display', 'off');
                    fprintf('  Brown-Forsythe: p=%.4f %s\n', p_bf, sig_stars(p_bf));
                    fprintf(fid, '  Brown-Forsythe: p=%.4f %s\n', p_bf, sig_stars(p_bf));
                catch ME
                    fprintf('  Brown-Forsythe failed: %s\n', ME.message);
                    fprintf(fid, '  Brown-Forsythe failed: %s\n', ME.message);
                end
            else
                fprintf('  Insufficient conditions for variance test\n');
                fprintf(fid, '  Insufficient conditions for variance test\n');
            end

            % Per-block Levene
            fprintf(fid, '\n  Per-block Levene tests:\n');
            fprintf('  Per-block:\n');
            for blk = 1:min_blocks
                vals_blk  = [];
                names_blk = {};
                for pi = 1:nProt
                    T = data(pi).(stat_key);
                    [~, ~, ~, exp_means] = compute_blocks_raw(T, geno, stat_col, cond_layout(pi).block_train_cycles);
                    v     = exp_means(:, blk);
                    valid = ~isnan(v);
                    v     = v(valid);
                    vals_blk  = [vals_blk; v(:)]; %#ok<AGROW>
                    names_blk = [names_blk; repmat({pname(prots{pi})}, length(v), 1)]; %#ok<AGROW>
                end

                if length(unique(names_blk)) >= 2
                    try
                        p_lev   = vartestn(vals_blk, names_blk, 'TestType', 'LeveneAbsolute', 'Display', 'off');
                        var_str = '';
                        for pi = 1:nProt
                            idx = strcmp(names_blk, pname(prots{pi}));
                            if any(idx)
                                var_str = [var_str, sprintf('%s=%.0f ', pname(prots{pi}), var(vals_blk(idx)))]; %#ok<AGROW>
                            end
                        end
                        fprintf('    %s: Levene p=%.4f %s  (%s)\n', block_labels{blk}, p_lev, sig_stars(p_lev), var_str);
                        fprintf(fid, '    %s: Levene p=%.4f %s  (%s)\n', block_labels{blk}, p_lev, sig_stars(p_lev), var_str);
                    catch ME
                        fprintf('    %s: failed: %s\n', block_labels{blk}, ME.message);
                        fprintf(fid, '    %s: failed: %s\n', block_labels{blk}, ME.message);
                    end
                end
            end

            fprintf(fid, '\n');
            fprintf('\n');
        end

        %% 5c. Within-group paired t-tests
        fprintf(fid, '\n============================================================\n');
        fprintf(fid, 'WITHIN-GROUP — Pairwise Block Comparisons (paired t-tests)\n');
        fprintf(fid, '============================================================\n\n');
        fprintf('\n═══ Within-Group Pairwise Block Comparisons ═══\n\n');

        block_pairs = nchoosek(1:min_blocks, 2);

        for gi = 1:length(genos)
            geno = genos{gi};
            fprintf('--- %s ---\n', geno);
            fprintf(fid, '--- %s ---\n', geno);

            for pi = 1:nProt
                T = data(pi).(stat_key);
                [~, ~, n_exp, exp_means] = compute_blocks_raw(T, geno, stat_col, cond_layout(pi).block_train_cycles);

                valid_rows      = all(~isnan(exp_means), 2);
                exp_means_valid = exp_means(valid_rows, :);
                n_valid         = size(exp_means_valid, 1);

                if n_valid < 2
                    fprintf('  %s: n=%d — insufficient data\n', pname(prots{pi}), n_valid);
                    fprintf(fid, '  %s: n=%d — insufficient data\n', pname(prots{pi}), n_valid);
                    continue;
                end

                fprintf('  %s (n=%d):\n', pname(prots{pi}), n_valid);
                fprintf(fid, '  %s (n=%d):\n', pname(prots{pi}), n_valid);

                for blk = 1:min_blocks
                    fprintf('    %s mean = %.1f\n', block_labels{blk}, mean(exp_means_valid(:, blk)));
                    fprintf(fid, '    %s mean = %.1f\n', block_labels{blk}, mean(exp_means_valid(:, blk)));
                end

                n_pairs = size(block_pairs, 1);
                for bpi = 1:n_pairs
                    b1 = block_pairs(bpi, 1);
                    b2 = block_pairs(bpi, 2);
                    [~, p_t, ~, t_stats] = ttest(exp_means_valid(:, b1), exp_means_valid(:, b2));
                    diff_mean = mean(exp_means_valid(:, b1) - exp_means_valid(:, b2));
                    p_bonf    = min(p_t * n_pairs, 1);

                    fprintf('    %s vs %s: diff=%+.1f, t(%.0f)=%.3f, p=%.4f %s (Bonf p=%.4f %s)\n', ...
                        block_labels{b1}, block_labels{b2}, diff_mean, ...
                        t_stats.df, t_stats.tstat, p_t, sig_stars(p_t), ...
                        p_bonf, sig_stars(p_bonf));
                    fprintf(fid, '    %s vs %s: diff=%+.1f, t(%.0f)=%.3f, p=%.4f %s (Bonf p=%.4f %s)\n', ...
                        block_labels{b1}, block_labels{b2}, diff_mean, ...
                        t_stats.df, t_stats.tstat, p_t, sig_stars(p_t), ...
                        p_bonf, sig_stars(p_bonf));
                end
            end

            fprintf(fid, '\n');
            fprintf('\n');
        end

        fclose(fid);
        fprintf('  Results saved to: %s\n', log_file);
        save(fullfile(stats_dir, sprintf('anova_%s_results.mat', stat_key)), 'all_anova_results');

    end  % end stat_mi metric loop

    end  % end if opts.RunStats

    fprintf('\nProtocol comparison complete. Saved to: %s\n', save_dir);
end


%% ========================================================================
%  compute_allcycles — mean ± SEM across experiments for specified cycles
%% ========================================================================
function [m, se, n_exp] = compute_allcycles(T, geno, metric_col, plot_cycles)
    num_cycles = length(plot_cycles);
    geno_rows  = strcmp(T.genotype, geno);
    exps       = unique(T.experiment(geno_rows));
    n_exp      = length(exps);
    exp_vals   = NaN(n_exp, num_cycles);
    for ei = 1:n_exp
        exp_mask = strcmp(T.experiment, exps{ei});
        for ci = 1:num_cycles
            row_mask = exp_mask & T.cycle == plot_cycles(ci);
            if any(row_mask)
                exp_vals(ei, ci) = mean(T.(metric_col)(row_mask), 'omitnan');
            end
        end
    end
    n_valid = sum(~isnan(exp_vals), 1);
    m  = mean(exp_vals, 1, 'omitnan');
    se = std(exp_vals, 0, 1, 'omitnan') ./ sqrt(max(n_valid, 1));
end


%% ========================================================================
%  compute_blocks — block-mean ± SEM across experiments
%% ========================================================================
function [m, se, n_exp] = compute_blocks(T, geno, metric_col, block_train_cycles)
    num_blocks = length(block_train_cycles);
    geno_rows  = strcmp(T.genotype, geno);
    exps       = unique(T.experiment(geno_rows));
    n_exp      = length(exps);
    exp_vals   = NaN(n_exp, num_blocks);
    for ei = 1:n_exp
        exp_mask = strcmp(T.experiment, exps{ei});
        for blk = 1:num_blocks
            train_mask = exp_mask & ismember(T.cycle, block_train_cycles{blk});
            if any(train_mask)
                exp_vals(ei, blk) = mean(T.(metric_col)(train_mask), 'omitnan');
            end
        end
    end
    n_valid = sum(~isnan(exp_vals), 1);
    m  = mean(exp_vals, 1, 'omitnan');
    se = std(exp_vals, 0, 1, 'omitnan') ./ sqrt(max(n_valid, 1));
end


%% ========================================================================
%  compute_probes — probe-cycle mean ± SEM across experiments
%% ========================================================================
function [m, se, n_exp] = compute_probes(T, geno, metric_col, probe_cycle_nums)
    num_probes = length(probe_cycle_nums);
    geno_rows  = strcmp(T.genotype, geno);
    exps       = unique(T.experiment(geno_rows));
    n_exp      = length(exps);
    exp_vals   = NaN(n_exp, num_probes);
    for ei = 1:n_exp
        exp_mask = strcmp(T.experiment, exps{ei});
        for pi = 1:num_probes
            probe_mask = exp_mask & T.cycle == probe_cycle_nums(pi);
            if any(probe_mask)
                exp_vals(ei, pi) = mean(T.(metric_col)(probe_mask), 'omitnan');
            end
        end
    end
    n_valid = sum(~isnan(exp_vals), 1);
    m  = mean(exp_vals, 1, 'omitnan');
    se = std(exp_vals, 0, 1, 'omitnan') ./ sqrt(max(n_valid, 1));
end


%% ========================================================================
%  compute_blocks_raw — block-mean matrix (nExp × nBlocks) for stats
%% ========================================================================
function [m, se, n_exp, exp_vals] = compute_blocks_raw(T, geno, metric_col, block_train_cycles)
    num_blocks = length(block_train_cycles);
    geno_rows  = strcmp(T.genotype, geno);
    exps       = unique(T.experiment(geno_rows));
    n_exp      = length(exps);
    exp_vals   = NaN(n_exp, num_blocks);
    for ei = 1:n_exp
        exp_mask = strcmp(T.experiment, exps{ei});
        for blk = 1:num_blocks
            train_mask = exp_mask & ismember(T.cycle, block_train_cycles{blk});
            if any(train_mask)
                exp_vals(ei, blk) = mean(T.(metric_col)(train_mask), 'omitnan');
            end
        end
    end
    n_valid = sum(~isnan(exp_vals), 1);
    m  = mean(exp_vals, 1, 'omitnan');
    se = std(exp_vals, 0, 1, 'omitnan') ./ sqrt(max(n_valid, 1));
end


%% ========================================================================
%  save_fig — export PNG (250 dpi) + SVG + FIG
%% ========================================================================
function save_fig(fig, save_dir, name, show)
    png_file = fullfile(save_dir, [name '.png']);
    svg_file = fullfile(save_dir, [name '.svg']);
    fig_file = fullfile(save_dir, [name '.fig']);
    exportgraphics(fig, png_file, 'Resolution', 250);
    saveas(fig, svg_file);
    savefig(fig, fig_file);
    fprintf('  Saved: %s\n', png_file);
    if show
        set(fig, 'Visible', 'on');
    else
        close(fig);
    end
end


%% ========================================================================
%  ylim_auto — scale y from 0 with 12% headroom
%% ========================================================================
function ylim_auto(ax)
    yl = ylim(ax);
    if yl(1) >= 0
        ylim(ax, [0, yl(2) * 1.12]);
    else
        ylim(ax, [yl(1) * 1.12, yl(2) * 1.12]);
    end
end


%% ========================================================================
%  add_qpi_annotations — block shading, probe lines, Ag marker
%% ========================================================================
function add_qpi_annotations(ax, cfg)
    hold(ax, 'on');
    yl = ylim(ax);
    nc = cfg.num_cycles; %#ok<NASGU>

    % Block shading — light blue, alternating
    for b = 1:length(cfg.sections)
        x1 = cfg.sections(b).start_cycle - 0.5;
        x2 = cfg.sections(b).end_cycle   + 0.5;
        if mod(b, 2) == 1
            p = patch(ax, [x1 x2 x2 x1], [yl(1) yl(1) yl(2) yl(2)], ...
                [0.85 0.92 1.0], 'EdgeColor', 'none', 'FaceAlpha', 0.25);
            set(p, 'HandleVisibility', 'off');
        end
        if b > 1
            xline(ax, x1, ':', 'Color', [0.5 0.5 0.5], ...
                'LineWidth', 0.8, 'HandleVisibility', 'off');
        end
        mid_x = (x1 + x2) / 2;
        text(ax, mid_x, yl(2) * 0.97, sprintf('B%d', b), ...
            'HorizontalAlignment', 'center', 'FontSize', 14, ...
            'Color', [0.3 0.3 0.3], 'FontWeight', 'bold');
    end

    % Probe vertical dashed lines + magenta labels below x-axis
    probe_c    = cfg.probe_cycles;
    probe_lbls = cfg.labels;
    for k = 1:length(probe_c)
        pc = probe_c(k);
        xline(ax, pc, ':', 'Color', [0.5 0.5 0.5], ...
            'LineWidth', 0.8, 'HandleVisibility', 'off');
        lbl = probe_lbls{pc};
        if ~strcmp(lbl, 'PP') && endsWith(lbl, '.P')
            lbl = 'P';
        end
        text(ax, pc, -0.04 * diff(yl), lbl, ...
            'HorizontalAlignment', 'center', 'FontSize', 12, ...
            'Color', [0.75 0.0 0.55], 'FontWeight', 'bold', ...
            'Clipping', 'off');
    end

    % Agitation marker — dashed green
    ag = cfg.pretrain_cycle;
    if ~isempty(ag)
        xline(ax, ag, ':', 'Color', [0.0 0.55 0.0], ...
            'LineWidth', 0.8, 'HandleVisibility', 'off');
        text(ax, ag, yl(2) * 1.02, 'Ag', ...
            'HorizontalAlignment', 'center', 'FontSize', 14, ...
            'Color', [0.0 0.55 0.0], 'FontWeight', 'bold', ...
            'Clipping', 'off');
    end

    % Preprobe marker
    pp = cfg.preprobe_cycle;
    if ~isempty(pp)
        xline(ax, pp, ':', 'Color', [0.5 0.5 0.5], ...
            'LineWidth', 0.8, 'HandleVisibility', 'off');
        text(ax, pp, -0.04 * diff(yl), 'PP', ...
            'HorizontalAlignment', 'center', 'FontSize', 12, ...
            'Color', [0.75 0.0 0.55], 'FontWeight', 'bold', ...
            'Clipping', 'off');
    end

    ylim(ax, yl);
end


%% ========================================================================
%  count_flies — total fly count for a genotype in a summary table
%% ========================================================================
function n_flies = count_flies(T, geno)
    geno_rows = strcmp(T.genotype, geno);
    if ~any(geno_rows), n_flies = 0; return; end

    if ismember('n_flies', T.Properties.VariableNames)
        fly_col = 'n_flies';
    elseif ismember('n_flies_alive', T.Properties.VariableNames)
        fly_col = 'n_flies_alive';
    else
        n_flies = 0; return;
    end

    exps    = unique(T.experiment(geno_rows));
    n_flies = 0;
    for ei = 1:length(exps)
        exp_mask = geno_rows & strcmp(T.experiment, exps{ei});
        vals     = T.(fly_col)(exp_mask);
        n_flies  = n_flies + round(median(vals, 'omitnan'));
    end
end


%% ========================================================================
%  get_condition_shade — hand-tuned palette per genotype × protocol index
%    cond_idx 1 = darkest shade, 2 = mid, 3 = lightest
%% ========================================================================
function c = get_condition_shade(geno, cond_idx)
    switch upper(geno)
        case 'L2A'
            palette = [0.45 0.09 0.18;
                       0.70 0.24 0.20;
                       0.82 0.51 0.35];
        case 'L1'
            palette = [0.05 0.20 0.50;
                       0.15 0.45 0.75;
                       0.45 0.65 0.82];
        case 'L3A'
            palette = [0.08 0.38 0.12;
                       0.25 0.60 0.25;
                       0.55 0.75 0.45];
        case 'L0'
            palette = [0.20 0.20 0.20;
                       0.45 0.45 0.45;
                       0.70 0.70 0.70];
        case 'L3C'
            palette = [0.50 0.25 0.00;
                       0.70 0.40 0.00;
                       0.85 0.60 0.30];
        otherwise
            palette = [0.30 0.12 0.42;
                       0.55 0.35 0.65;
                       0.75 0.60 0.82];
    end
    c = palette(min(cond_idx, size(palette,1)), :);
end


%% ========================================================================
%  sig_stars — significance stars string
%% ========================================================================
function s = sig_stars(p)
    if p < 0.001
        s = '***';
    elseif p < 0.01
        s = '**';
    elseif p < 0.05
        s = '*';
    else
        s = 'n.s.';
    end
end


