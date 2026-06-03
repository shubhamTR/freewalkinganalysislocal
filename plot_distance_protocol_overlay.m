function plot_distance_protocol_overlay(protocols, varargin)
% PLOT_DISTANCE_PROTOCOL_OVERLAY  Overlay distance travelled across protocols
%
%   plot_distance_protocol_overlay({'P008', 'P014', 'P015', 'P016'})
%   plot_distance_protocol_overlay({'P008', 'P014'}, 'CycleFilter', {'PP', 'Ag', 'Training'})
%
%   Loads distance_summary_<protocol>.mat for each protocol, groups by
%   genotype, computes per-experiment mean distance → protocol mean ± SEM,
%   and overlays all protocols on the same axes per genotype.
%
%   All protocols must share the same cycle structure (48 cycles).
%
%   NAME-VALUE PARAMETERS
%     'AnalysisDir' — data root (default: '/Users/rathores/Documents/analysisdatalocal')
%     'SaveDir'     — output folder (default: <AnalysisDir>/Summary_Plots)
%     'ShowPlots'   — keep figures open (default: false)
%     'Metric'      — column name in distance_summary table (default: 'mean_dist_mm')
%     'CycleFilter' — cell array of cycle types to include (default: {} = all)
%                      Valid types: 'OM', 'PP', 'Ag', 'Training', 'Probe'

    p = inputParser;
    addRequired(p, 'protocols', @iscell);
    addParameter(p, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(p, 'SaveDir', '', @ischar);
    addParameter(p, 'ShowPlots', false, @islogical);
    addParameter(p, 'Metric', 'mean_dist_mm', @ischar);
    addParameter(p, 'CycleFilter', {}, @iscell);
    parse(p, protocols, varargin{:});
    opts = p.Results;

    analysis_dir = opts.AnalysisDir;
    METRIC = opts.Metric;

    if isempty(opts.SaveDir)
        save_dir = fullfile(analysis_dir, 'Summary_Plots');
    else
        save_dir = opts.SaveDir;
    end
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end

    %% Load all protocol summaries
    prot_data = struct();  % prot_data.<protocol>.table, .genotypes

    for pi = 1:length(protocols)
        prot = protocols{pi};
        summary_file = fullfile(analysis_dir, prot, sprintf('distance_summary_%s.mat', prot));

        if ~exist(summary_file, 'file')
            fprintf('  ✗ %s — distance_summary not found, skipping\n', prot);
            continue;
        end

        loaded = load(summary_file, 'distance_summary');
        T = loaded.distance_summary;

        prot_data.(prot).table = T;
        prot_data.(prot).genotypes = unique(T.genotype);
        fprintf('  ✓ %s — %d rows, genotypes: %s\n', prot, height(T), strjoin(unique(T.genotype)', ', '));
    end

    loaded_prots = fieldnames(prot_data);
    if isempty(loaded_prots)
        fprintf('No distance summaries found.\n');
        return;
    end

    %% Get cycle structure from first protocol
    cfg = get_protocol_config(loaded_prots{1});
    num_cycles = cfg.num_cycles;
    cycle_labels = cfg.labels;

    %% Apply cycle filter if specified
    if ~isempty(opts.CycleFilter)
        keep = false(1, num_cycles);
        for c = 1:num_cycles
            lbl = cycle_labels{c};
            for fi = 1:length(opts.CycleFilter)
                ftype = opts.CycleFilter{fi};
                if strcmpi(ftype, 'OM') && (strcmp(lbl, 'OM1') || strcmp(lbl, 'OM2'))
                    keep(c) = true;
                elseif strcmpi(ftype, 'PP') && strcmp(lbl, 'PP')
                    keep(c) = true;
                elseif strcmpi(ftype, 'Ag') && strcmp(lbl, 'Ag')
                    keep(c) = true;
                elseif strcmpi(ftype, 'Training') && contains(lbl, '.') && ~endsWith(lbl, '.P')
                    keep(c) = true;
                elseif strcmpi(ftype, 'Probe') && endsWith(lbl, '.P')
                    keep(c) = true;
                end
            end
        end
        cycle_indices = find(keep);  % original cycle numbers to include
        cycle_labels_filtered = cycle_labels(cycle_indices);
        filter_tag = strjoin(opts.CycleFilter, '_');
    else
        cycle_indices = 1:num_cycles;
        cycle_labels_filtered = cycle_labels;
        filter_tag = '';
    end
    num_plot_cycles = length(cycle_indices);

    %% Collect all genotypes across protocols
    all_genos = {};
    for pi = 1:length(loaded_prots)
        all_genos = union(all_genos, prot_data.(loaded_prots{pi}).genotypes);
    end

    %% Protocol display names (light intensity)
    prot_display = containers.Map();
    prot_display('P008') = '12%';
    prot_display('P014') = '8%';
    prot_display('P015') = '6%';
    prot_display('P016') = '4%';

    %% Protocol colors
    prot_colors = containers.Map();
    color_list = [
        0.2  0.4  0.8;   % blue
        0.8  0.2  0.2;   % red
        0.2  0.7  0.3;   % green
        0.7  0.4  0.1;   % orange
        0.5  0.2  0.7;   % purple
        0.1  0.6  0.6;   % teal
    ];
    for pi = 1:length(loaded_prots)
        ci = mod(pi - 1, size(color_list, 1)) + 1;
        prot_colors(loaded_prots{pi}) = color_list(ci, :);
    end

    %% Per-genotype overlay plot
    for gi = 1:length(all_genos)
        geno = all_genos{gi};

        fig = figure('Name', sprintf('Distance overlay - %s', geno), ...
                     'Position', [50 50 1500 500], ...
                     'Visible', ternary(opts.ShowPlots, 'on', 'off'));
        hold on;

        legend_entries = {};
        x = 1:num_plot_cycles;

        for pi = 1:length(loaded_prots)
            prot = loaded_prots{pi};
            T = prot_data.(prot).table;
            col = prot_colors(prot);

            % Filter to this genotype
            geno_rows = strcmp(T.genotype, geno);
            if ~any(geno_rows), continue; end

            Tg = T(geno_rows, :);
            exps = unique(Tg.experiment);
            n_exps = length(exps);

            % Compute per-experiment mean distance per cycle, then mean ± SEM across experiments
            dist_per_exp = NaN(n_exps, num_cycles);
            for ei = 1:n_exps
                exp_rows = strcmp(Tg.experiment, exps{ei});
                Te = Tg(exp_rows, :);
                for c = 1:num_cycles
                    cr = Te.cycle == c;
                    if any(cr)
                        dist_per_exp(ei, c) = Te.(METRIC)(cr);
                    end
                end
            end

            % Extract only filtered cycles
            dist_filtered = dist_per_exp(:, cycle_indices);

            mu = NaN(num_plot_cycles, 1);
            se = NaN(num_plot_cycles, 1);
            for c = 1:num_plot_cycles
                vals = dist_filtered(:, c);
                vals = vals(~isnan(vals));
                if ~isempty(vals)
                    mu(c) = mean(vals);
                    se(c) = std(vals) / sqrt(length(vals));
                end
            end

            valid = ~isnan(mu);
            if any(valid)
                fill_x = [x(valid), fliplr(x(valid))];
                fill_y = [(mu(valid) + se(valid))', fliplr((mu(valid) - se(valid))')];
                fill(fill_x, fill_y, col, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                plot(x(valid), mu(valid), '-o', 'Color', col, 'LineWidth', 2, ...
                    'MarkerSize', 4, 'MarkerFaceColor', col);
            end
            if prot_display.isKey(prot)
                legend_entries{end+1} = sprintf('%s (N=%d exps)', prot_display(prot), n_exps); %#ok<AGROW>
            else
                legend_entries{end+1} = sprintf('%s (N=%d exps)', prot, n_exps); %#ok<AGROW>
            end
        end

        % Format
        set(gca, 'XTick', x, 'XTickLabel', cycle_labels_filtered, 'XTickLabelRotation', 60, 'FontSize', 8);
        xlim([0.5, num_plot_cycles + 0.5]);
        ylabel('Distance (mm, mean ± SEM)', 'FontSize', 12);
        xlabel('Cycle', 'FontSize', 12);

        prot_str = strjoin(loaded_prots', ' vs ');
        if ~isempty(filter_tag)
            title(sprintf('%s — Distance per Cycle (%s) — %s', prot_str, strrep(filter_tag, '_', ', '), geno), ...
                'FontSize', 13, 'Interpreter', 'none');
        else
            title(sprintf('%s — Distance per Cycle — %s', prot_str, geno), 'FontSize', 13, 'Interpreter', 'none');
        end
        legend(legend_entries, 'Location', 'bestoutside', 'FontSize', 10);
        box on;

        draw_section_dividers_filtered(cycle_labels_filtered);

        % Save
        if ~isempty(filter_tag)
            fname = sprintf('distance_overlay_%s_%s_%s.png', strjoin(loaded_prots', '_'), filter_tag, geno);
        else
            fname = sprintf('distance_overlay_%s_%s.png', strjoin(loaded_prots', '_'), geno);
        end
        out_png = fullfile(save_dir, fname);
        saveas(fig, out_png);
        savefig(fig, strrep(out_png, '.png', '.fig'));
        fprintf('  Saved: %s\n', fname);

        if ~opts.ShowPlots, close(fig); end
    end

    fprintf('\n  Overlay plots saved to: %s\n\n', save_dir);
end


%% ===== Helper functions =====

function draw_section_dividers_filtered(labels)
% Draw section dividers for filtered (re-indexed) cycle labels
    yl = ylim;
    n = length(labels);

    sections = {};
    block_num = 0;
    i = 1;
    while i <= n
        lbl = labels{i};

        if strcmp(lbl, 'OM1') || strcmp(lbl, 'OM2')
            sections{end+1} = {i, i, lbl}; %#ok<AGROW>
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
            % Extract block number from label (e.g., 'B2' from 'B2.3')
            tok = regexp(lbl, '^(B\d+)\.', 'tokens');
            if ~isempty(tok)
                cur_block = tok{1}{1};
            else
                cur_block = '';
            end
            block_num = block_num + 1;
            blk_start = i;
            while i <= n
                li = labels{i};
                if contains(li, '.') && ~endsWith(li, '.P')
                    % Check if still same block number
                    tok2 = regexp(li, '^(B\d+)\.', 'tokens');
                    if ~isempty(tok2) && ~strcmp(tok2{1}{1}, cur_block)
                        break;  % different block number, stop
                    end
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
