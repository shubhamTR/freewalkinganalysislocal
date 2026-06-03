%% summary_speed.m
% Per-genotype speed summaries for all place-learning protocols.
%
% Processes all place-learning protocols and generates:
%   (1) Per-cycle speed traces per genotype — mean ± SEM across experiments
%       (one subplot per cycle, overlaid genotype traces)
%   (2) Block-averaged training overlay per genotype — Blocks overlaid (3 or 4)
%   (3) Probe overlay per genotype — PP and block probes overlaid
%
% Averaging hierarchy:
%   fly → experiment mean trace → genotype mean ± SEM (experiment = unit of replication)
%
% Saves .mat summary + .png/.fig to <PROTOCOL>/summary/speed/

clearvars -except TARGET_PROTOCOLS; clc;


ANALYSIS_DIR  = '/Users/rathores/Documents/analysisdatalocal';
FPS           = 30.1;

protocols = {'P003', 'P005', 'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P013', 'P014', 'P015', 'P016', 'P017', 'P019'};

if ~exist('TARGET_PROTOCOLS', 'var'), TARGET_PROTOCOLS = {}; end
if ~isempty(TARGET_PROTOCOLS)
    protocols = protocols(ismember(protocols, TARGET_PROTOCOLS));
end

for p_idx = 1:length(protocols)
    PROTOCOL    = protocols{p_idx};
    prot_path   = fullfile(ANALYSIS_DIR, PROTOCOL);

    % Skip if protocol directory doesn't exist
    if ~exist(prot_path, 'dir')
        fprintf('Protocol %s directory not found, skipping.\n\n', PROTOCOL);
        continue;
    end

    summary_dir = fullfile(prot_path, 'summary', 'speed');
    if ~exist(summary_dir, 'dir'), mkdir(summary_dir); end

    fprintf('========================================\n');
    fprintf('Processing: %s\n', PROTOCOL);
    fprintf('========================================\n\n');

    %% Load all speed .mat files
    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));

    % SAFEGUARD: Only process directories containing '_Rig' (experiment folders).
    % This prevents accidental processing of summary/output directories.
    exp_dirs = exp_dirs(~contains({exp_dirs.name}, 'summary') & ...
                         contains({exp_dirs.name}, '_Rig'));

    all_summaries = {};
    for e = 1:length(exp_dirs)
        exp_name = exp_dirs(e).name;
        mat_file = fullfile(prot_path, exp_name, 'analysis', sprintf('speed_%s.mat', exp_name));
        if ~exist(mat_file, 'file')
            fprintf('  %s — no speed .mat, skipping (run run_speed first)\n', exp_name);
            continue;
        end
        s = load(mat_file);
        all_summaries{end+1} = s; %#ok<AGROW>
        fprintf('  Loaded: %s (genotype=%s, %d cycles)\n', exp_name, s.genotype, length(s.cycles));
    end

    nLoaded = length(all_summaries);
    fprintf('\nLoaded %d experiments\n', nLoaded);
    if nLoaded == 0
        fprintf('No speed data found for %s. Run run_speed first.\n\n', PROTOCOL);
        continue;
    end

    %% Group by genotype
    genotypes = {};
    geno_idx  = {};
    for ei = 1:nLoaded
        geno = all_summaries{ei}.genotype;
        gi = find(strcmp(genotypes, geno), 1);
        if isempty(gi)
            genotypes{end+1} = geno; %#ok<AGROW>
            geno_idx{end+1}  = ei;   %#ok<AGROW>
        else
            geno_idx{gi} = [geno_idx{gi}, ei]; %#ok<AGROW>
        end
    end

    fprintf('\nGenotypes:\n');
    for gi = 1:length(genotypes)
        fprintf('  %s: %d experiments\n', genotypes{gi}, length(geno_idx{gi}));
    end

    %% Get reference cycle labels from first experiment
    ref = all_summaries{1};
    ref_labels = {};
    for ci = 1:length(ref.cycles)
        ref_labels{ci} = ref.cycles(ci).label; %#ok<AGROW>
    end
    nCycles = length(ref_labels);

    %% Build common time axis from reference experiment
    % All experiments in same protocol should have near-identical time axes
    t_min = inf; t_max = -inf;
    for ci = 1:nCycles
        t = ref.cycles(ci).t_axis;
        if ~isempty(t)
            if t(1) < t_min, t_min = t(1); end
            if t(end) > t_max, t_max = t(end); end
        end
    end
    dt = 1 / FPS;
    t_common = t_min:dt:t_max;
    n_t = length(t_common);

    %% Identify block structure from cycle labels
    % Detect num_blocks from the reference experiment's cycle labels
    trials_per_block = 10;
    num_blocks = 0;
    for ci = 1:nCycles
        tok = regexp(ref_labels{ci}, '^B(\d+)\.1$', 'tokens');
        if ~isempty(tok)
            num_blocks = max(num_blocks, str2double(tok{1}{1}));
        end
    end
    if num_blocks == 0
        fprintf('  No block structure detected for %s — skipping summary.\n', PROTOCOL);
        continue;
    end

    block_trial_labels = cell(num_blocks, 1);
    probe_labels = {'PP'};

    for blk = 1:num_blocks
        blk_labels = {};
        for trial = 1:trials_per_block
            blk_labels{trial} = sprintf('B%d.%d', blk, trial); %#ok<AGROW>
        end
        block_trial_labels{blk} = blk_labels;
        probe_labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
    end

    %% ======= Per-genotype computations and plots =======

    % Genotype colors — consistent across all plotters (see get_genotype_color.m)

    for gi = 1:length(genotypes)
        geno = genotypes{gi};
        exp_indices = geno_idx{gi};
        nExp = length(exp_indices);

        fprintf('\n--- %s (%d experiments) ---\n', geno, nExp);

        [~, blk_colors, prb_colors] = get_genotype_color(geno);

        %% ============================================================
        %  (1) Per-cycle mean traces: average experiment means → genotype
        %  ============================================================
        % For each cycle, interpolate each experiment's mean trace to t_common,
        % then compute genotype mean ± SEM across experiments.

        geno_cycle_mean = NaN(nCycles, n_t);
        geno_cycle_sem  = NaN(nCycles, n_t);
        geno_cycle_n    = zeros(nCycles, 1);

        for ci = 1:nCycles
            lbl = ref_labels{ci};

            % Collect experiment-level mean traces for this cycle
            exp_traces = NaN(nExp, n_t);
            for k = 1:nExp
                ei = exp_indices(k);
                s = all_summaries{ei};

                % Find matching cycle by label
                match_ci = [];
                for sci = 1:length(s.cycles)
                    if strcmp(s.cycles(sci).label, lbl)
                        match_ci = sci;
                        break;
                    end
                end
                if isempty(match_ci), continue; end
                if isempty(s.cycles(match_ci).mean_speed), continue; end

                exp_traces(k, :) = interp1(s.cycles(match_ci).t_axis, ...
                    s.cycles(match_ci).mean_speed, t_common, 'linear', NaN);
            end

            valid_exps = sum(~all(isnan(exp_traces), 2));
            geno_cycle_mean(ci, :) = mean(exp_traces, 1, 'omitnan');
            geno_cycle_sem(ci, :)  = std(exp_traces, 0, 1, 'omitnan') / sqrt(max(valid_exps, 1));
            geno_cycle_n(ci) = valid_exps;
        end

        %% Per-cycle subplots figure (all cycles in one figure)
        n_cols = 8;
        n_rows = ceil(nCycles / n_cols);
        fig_cycles = figure('Position', [50 50 2400 n_rows * 280], 'Visible', 'off');

        for ci = 1:nCycles
            ax = subplot(n_rows, n_cols, ci, 'Parent', fig_cycles);
            hold(ax, 'on');

            m = geno_cycle_mean(ci, :);
            s = geno_cycle_sem(ci, :);

            % SEM ribbon
            upper_b = m + s;
            lower_b = m - s;
            valid = ~isnan(m) & ~isnan(s);
            t_v = t_common(valid);
            if ~isempty(t_v)
                fill_x = [t_v, fliplr(t_v)];
                fill_y = [upper_b(valid), fliplr(lower_b(valid))];
                fill(ax, fill_x, fill_y, [0.2 0.4 0.8], ...
                    'FaceAlpha', 0.3, 'EdgeColor', 'none');
            end
            plot(ax, t_common, m, 'Color', [0.1 0.2 0.7], 'LineWidth', 1.2);

            % LED markers
            xline(ax, 0, 'r--', 'LineWidth', 0.8);
            % Estimate offset from reference
            for sci = 1:length(ref.cycles)
                if strcmp(ref.cycles(sci).label, ref_labels{ci})
                    t_off = (ref.cycles(sci).fr_off - ref.cycles(sci).fr_on) / FPS;
                    xline(ax, t_off, 'b--', 'LineWidth', 0.8);
                    break;
                end
            end

            title(ax, sprintf('%s (n=%d)', ref_labels{ci}, geno_cycle_n(ci)), 'FontSize', 7);
            xlim(ax, [t_common(1), t_common(end)]);
            ylim(ax, [0, inf]);
            set(ax, 'FontSize', 6);

            if mod(ci-1, n_cols) == 0
                ylabel(ax, 'mm/s', 'FontSize', 6);
            end
            if ci > (n_rows - 1) * n_cols
                xlabel(ax, 's', 'FontSize', 6);
            end
            hold(ax, 'off');
        end

        sgtitle(fig_cycles, sprintf('%s %s — Per-cycle speed (mean ± SEM, n=%d exp)', ...
            PROTOCOL, geno, nExp), 'FontSize', 14, 'FontWeight', 'bold');

        out_png = fullfile(summary_dir, sprintf('summary_speed_cycles_%s.png', geno));
        out_fig = fullfile(summary_dir, sprintf('summary_speed_cycles_%s.fig', geno));
        exportgraphics(fig_cycles, out_png, 'Resolution', 120);
        savefig(fig_cycles, out_fig);
        close(fig_cycles);
        fprintf('  Saved per-cycle figure: %s\n', out_png);

        %% ============================================================
        %  (2) Block-averaged training overlay per genotype
        %  ============================================================
        % For each block: average the 10 trial mean traces within each experiment,
        % then average across experiments → genotype block mean ± SEM.

        block_geno_mean = NaN(num_blocks, n_t);
        block_geno_sem  = NaN(num_blocks, n_t);
        block_geno_n    = zeros(num_blocks, 1);

        for blk = 1:num_blocks
            trial_labels = block_trial_labels{blk};

            % For each experiment, average its 10 trial means into one block trace
            exp_block_traces = NaN(nExp, n_t);

            for k = 1:nExp
                ei = exp_indices(k);
                s_exp = all_summaries{ei};

                trial_traces = NaN(trials_per_block, n_t);
                for ti = 1:trials_per_block
                    lbl = trial_labels{ti};
                    for sci = 1:length(s_exp.cycles)
                        if strcmp(s_exp.cycles(sci).label, lbl)
                            if ~isempty(s_exp.cycles(sci).mean_speed)
                                trial_traces(ti, :) = interp1(s_exp.cycles(sci).t_axis, ...
                                    s_exp.cycles(sci).mean_speed, t_common, 'linear', NaN);
                            end
                            break;
                        end
                    end
                end

                % Average across trials within this experiment
                exp_block_traces(k, :) = mean(trial_traces, 1, 'omitnan');
            end

            valid_exps = sum(~all(isnan(exp_block_traces), 2));
            block_geno_mean(blk, :) = mean(exp_block_traces, 1, 'omitnan');
            block_geno_sem(blk, :)  = std(exp_block_traces, 0, 1, 'omitnan') / sqrt(max(valid_exps, 1));
            block_geno_n(blk) = valid_exps;
        end

        fig_blk = figure('Position', [100 100 1400 600], 'Visible', 'off');
        ax_blk = axes(fig_blk);
        hold(ax_blk, 'on');

        legend_h = [];
        legend_s = {};

        for blk = 1:num_blocks
            if block_geno_n(blk) == 0, continue; end

            m = block_geno_mean(blk, :);
            se = block_geno_sem(blk, :);
            col = blk_colors(blk, :);

            % SEM ribbon
            upper_b = m + se;
            lower_b = m - se;
            valid = ~isnan(m) & ~isnan(se);
            t_v = t_common(valid);
            if ~isempty(t_v)
                fill_x = [t_v, fliplr(t_v)];
                fill_y = [upper_b(valid), fliplr(lower_b(valid))];
                fill(ax_blk, fill_x, fill_y, col, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
            end

            h = plot(ax_blk, t_common, m, 'Color', col, 'LineWidth', 2.5);
            legend_h(end+1) = h; %#ok<AGROW>
            legend_s{end+1} = sprintf('Block %d (n=%d exp)', blk, block_geno_n(blk)); %#ok<AGROW>
        end

        xline(ax_blk, 0, 'r--', 'LineWidth', 1.5);
        % Estimate stim offset from first training trial
        for sci = 1:length(ref.cycles)
            if startsWith(ref.cycles(sci).label, 'B1.1')
                t_off = (ref.cycles(sci).fr_off - ref.cycles(sci).fr_on) / FPS;
                xline(ax_blk, t_off, 'b--', 'LineWidth', 1.5);
                break;
            end
        end

        xlabel(ax_blk, 'Time relative to LED onset (s)', 'FontSize', 12);
        ylabel(ax_blk, 'Speed (mm/s)', 'FontSize', 12);
        title(ax_blk, sprintf('%s %s — Block-averaged speed (n=%d experiments)', ...
            PROTOCOL, geno, nExp), 'FontSize', 13, 'FontWeight', 'bold');
        xlim(ax_blk, [t_common(1), t_common(end)]);
        ylim(ax_blk, [0, inf]);
        legend(ax_blk, legend_h, legend_s, 'Location', 'NorthEastOutside', 'FontSize', 10);
        grid(ax_blk, 'on'); box(ax_blk, 'on');
        hold(ax_blk, 'off');

        out_png = fullfile(summary_dir, sprintf('summary_speed_blocks_%s.png', geno));
        out_fig = fullfile(summary_dir, sprintf('summary_speed_blocks_%s.fig', geno));
        exportgraphics(fig_blk, out_png, 'Resolution', 150);
        savefig(fig_blk, out_fig);
        close(fig_blk);
        fprintf('  Saved block overlay: %s\n', out_png);

        %% ============================================================
        %  (3) Probe overlay per genotype
        %  ============================================================
        % Each probe is a single cycle — average across experiments.

        n_probes = length(probe_labels);
        probe_geno_mean = NaN(n_probes, n_t);
        probe_geno_sem  = NaN(n_probes, n_t);
        probe_geno_n    = zeros(n_probes, 1);

        for pi = 1:n_probes
            lbl = probe_labels{pi};

            exp_traces = NaN(nExp, n_t);
            for k = 1:nExp
                ei = exp_indices(k);
                s_exp = all_summaries{ei};
                for sci = 1:length(s_exp.cycles)
                    if strcmp(s_exp.cycles(sci).label, lbl)
                        if ~isempty(s_exp.cycles(sci).mean_speed)
                            exp_traces(k, :) = interp1(s_exp.cycles(sci).t_axis, ...
                                s_exp.cycles(sci).mean_speed, t_common, 'linear', NaN);
                        end
                        break;
                    end
                end
            end

            valid_exps = sum(~all(isnan(exp_traces), 2));
            probe_geno_mean(pi, :) = mean(exp_traces, 1, 'omitnan');
            probe_geno_sem(pi, :)  = std(exp_traces, 0, 1, 'omitnan') / sqrt(max(valid_exps, 1));
            probe_geno_n(pi) = valid_exps;
        end

        fig_prb = figure('Position', [100 100 1400 600], 'Visible', 'off');
        ax_prb = axes(fig_prb);
        hold(ax_prb, 'on');

        legend_h3 = [];
        legend_s3 = {};

        for pi = 1:n_probes
            if probe_geno_n(pi) == 0, continue; end

            m = probe_geno_mean(pi, :);
            se = probe_geno_sem(pi, :);
            col = prb_colors(min(pi, size(prb_colors,1)), :);

            upper_b = m + se;
            lower_b = m - se;
            valid = ~isnan(m) & ~isnan(se);
            t_v = t_common(valid);
            if ~isempty(t_v)
                fill_x = [t_v, fliplr(t_v)];
                fill_y = [upper_b(valid), fliplr(lower_b(valid))];
                fill(ax_prb, fill_x, fill_y, col, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
            end

            h = plot(ax_prb, t_common, m, 'Color', col, 'LineWidth', 2.5);
            legend_h3(end+1) = h; %#ok<AGROW>
            legend_s3{end+1} = sprintf('%s (n=%d exp)', probe_labels{pi}, probe_geno_n(pi)); %#ok<AGROW>
        end

        xline(ax_prb, 0, 'r--', 'LineWidth', 1.5);
        for sci = 1:length(ref.cycles)
            if strcmp(ref.cycles(sci).label, 'PP')
                t_off = (ref.cycles(sci).fr_off - ref.cycles(sci).fr_on) / FPS;
                xline(ax_prb, t_off, 'b--', 'LineWidth', 1.5);
                break;
            end
        end

        xlabel(ax_prb, 'Time relative to LED onset (s)', 'FontSize', 12);
        ylabel(ax_prb, 'Speed (mm/s)', 'FontSize', 12);
        title(ax_prb, sprintf('%s %s — Probe speed traces (n=%d experiments)', ...
            PROTOCOL, geno, nExp), 'FontSize', 13, 'FontWeight', 'bold');
        xlim(ax_prb, [t_common(1), t_common(end)]);
        ylim(ax_prb, [0, inf]);
        legend(ax_prb, legend_h3, legend_s3, 'Location', 'NorthEastOutside', 'FontSize', 10);
        grid(ax_prb, 'on'); box(ax_prb, 'on');
        hold(ax_prb, 'off');

        out_png = fullfile(summary_dir, sprintf('summary_speed_probes_%s.png', geno));
        out_fig = fullfile(summary_dir, sprintf('summary_speed_probes_%s.fig', geno));
        exportgraphics(fig_prb, out_png, 'Resolution', 150);
        savefig(fig_prb, out_fig);
        close(fig_prb);
        fprintf('  Saved probe overlay: %s\n', out_png);

        %% Save per-genotype .mat
        geno_data = struct();
        geno_data.genotype     = geno;
        geno_data.protocol     = PROTOCOL;
        geno_data.n_experiments = nExp;
        geno_data.experiment_names = {};
        for k = 1:nExp
            geno_data.experiment_names{k} = all_summaries{exp_indices(k)}.experiment;
        end
        geno_data.t_common     = t_common;
        geno_data.cycle_labels = ref_labels;
        geno_data.cycle_mean   = geno_cycle_mean;
        geno_data.cycle_sem    = geno_cycle_sem;
        geno_data.cycle_n      = geno_cycle_n;
        geno_data.block_mean   = block_geno_mean;
        geno_data.block_sem    = block_geno_sem;
        geno_data.block_n      = block_geno_n;
        geno_data.probe_labels = probe_labels;
        geno_data.probe_mean   = probe_geno_mean;
        geno_data.probe_sem    = probe_geno_sem;
        geno_data.probe_n      = probe_geno_n;

        mat_out = fullfile(summary_dir, sprintf('summary_speed_%s.mat', geno));
        save(mat_out, '-struct', 'geno_data');
        fprintf('  Saved .mat: %s\n', mat_out);
    end

    fprintf('\n========================================\n');
    fprintf('Outputs saved to:\n  %s\n', summary_dir);
    fprintf('Done: %s\n', datestr(now));
    fprintf('========================================\n\n');
end

fprintf('All protocols processed.\n');
