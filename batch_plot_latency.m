%% batch_plot_latency.m
% Generate per-experiment latency plots for all experiments, plus a
% per-protocol summary plot (mean +/- SE across experiments with scatter).
%
% Calls plot_latency_per_experiment_local for each experiment, which
% computes latency internally and saves latency_<exp_name>.png to analysis/.
% After each protocol, generates a summary plot saved to the protocol's
% summary/ folder.
%
% Requires arena_calib and LED_detector in each experiment's analysis/ folder.

clear; clc;

ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

% px/mm calibration is handled per-experiment by plot_latency_per_experiment_local
% (reads from trx.mat via extract_calibration_robust_local)

% Set to true to regenerate all plots (e.g., after changing plot style)
FORCE_REPLOT = false;

%% Find all protocols
protocol_dirs = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocol_dirs = protocol_dirs([protocol_dirs.isdir]);
protocol_dirs = protocol_dirs(~cellfun('isempty', regexp({protocol_dirs.name}, '^P\d+$', 'once')));

nPlotted = 0;
nSkipped = 0;
nFailed  = 0;
failed_list = {};

for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);

    % Skip P004 (optomotor only — no quadrant-based latency)
    if strcmp(prot_name, 'P004')
        fprintf('\n=== %s — optomotor only, skipping ===\n', prot_name);
        continue;
    end

    exp_dirs = dir(prot_path);
    % SAFEGUARD: Only process experiment directories (contain '_Rig' in name)
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}) & contains({exp_dirs.name}, '_Rig'));
    % Filter out summary directories
    exp_dirs = exp_dirs(~contains({exp_dirs.name}, 'summary'));

    fprintf('\n=== %s (%d experiments) ===\n', prot_name, length(exp_dirs));

    % Collect summaries for the protocol-level summary plot
    prot_summaries = {};

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        exp_name = exp_dirs(e).name;

        % Skip if plot already exists (unless FORCE_REPLOT)
        analysis_subdir = fullfile(exp_path, 'analysis');
        if ~FORCE_REPLOT && ~isempty(dir(fullfile(analysis_subdir, sprintf('latency_%s.png', exp_name))))
            fprintf('  [%d/%d] %s — latency plot exists, skipping\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Check for required files
        if isempty(dir(fullfile(analysis_subdir, 'arena_calib_*.mat')))
            fprintf('  [%d/%d] %s — no arena_calib, skipping\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        try
            fprintf('  [%d/%d] %s ... ', e, length(exp_dirs), exp_name);
            s = plot_latency_per_experiment_local(exp_path, ...
                'Protocol', prot_name, 'ShowPlots', false, 'SavePlot', true);
            if ~isempty(s)
                prot_summaries{end+1} = s; %#ok<AGROW>
            end
            nPlotted = nPlotted + 1;
            fprintf('done\n');
        catch ME
            fprintf('Error: %s\n', ME.message);
            failed_list{end+1} = sprintf('[%s] %s: %s', prot_name, exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end

    %% Generate per-protocol summary plot
    if length(prot_summaries) >= 1
        try
            plot_latency_summary(prot_summaries, prot_name, prot_path);
        catch ME
            fprintf('  Summary plot error for %s: %s\n', prot_name, ME.message);
        end
    end
end

%% Summary
fprintf('\n========================================\n');
fprintf('LATENCY BATCH PLOT SUMMARY\n');
fprintf('========================================\n');
fprintf('Plotted: %d\n', nPlotted);
fprintf('Skipped: %d\n', nSkipped);
fprintf('Failed:  %d\n', nFailed);
if ~isempty(failed_list)
    fprintf('\nFailed experiments:\n');
    for fi = 1:length(failed_list)
        fprintf('  %s\n', failed_list{fi});
    end
end
fprintf('========================================\n');
fprintf('Done: %s\n\n', datestr(now));


%% ======== LOCAL FUNCTIONS ========

function plot_latency_summary(summaries, prot_name, prot_path)
% PLOT_LATENCY_SUMMARY  Per-genotype summary: mean +/- SE across experiments
%   with individual fly scatter and experiment means.

    %% Get reference cycle labels (OM filtered)
    ref_table = summaries{1}.cycle_table;
    om_mask = strcmp(ref_table.label, 'OM1') | strcmp(ref_table.label, 'OM2');
    ref_table = ref_table(~om_mask, :);
    ref_labels = ref_table.label;
    nCycles = length(ref_labels);

    %% Group experiments by genotype
    genotypes = {};
    geno_idx  = {};
    for ei = 1:length(summaries)
        geno = summaries{ei}.genotype;
        gi = find(strcmp(genotypes, geno), 1);
        if isempty(gi)
            genotypes{end+1} = geno; %#ok<AGROW>
            geno_idx{end+1}  = ei;   %#ok<AGROW>
        else
            geno_idx{gi} = [geno_idx{gi}, ei]; %#ok<AGROW>
        end
    end

    summary_dir = fullfile(prot_path, 'summary');
    if ~exist(summary_dir, 'dir')
        mkdir(summary_dir);
    end

    %% Get cycle colors
    cycle_colors = zeros(nCycles, 3);
    for ci = 1:nCycles
        cycle_colors(ci, :) = get_summary_cycle_color(ref_labels{ci});
    end

    %% Generate one plot per genotype
    for gi = 1:length(genotypes)
        geno = genotypes{gi};
        exp_indices = geno_idx{gi};
        nExp = length(exp_indices);

        % Collect per-experiment mean latencies and fly data
        exp_means = NaN(nExp, nCycles);
        all_fly_data = cell(1, nCycles);

        for k = 1:nExp
            ei = exp_indices(k);
            ct = summaries{ei}.cycle_table;
            lat_mat = summaries{ei}.latency_per_fly;

            om_m = strcmp(ct.label, 'OM1') | strcmp(ct.label, 'OM2');
            ct = ct(~om_m, :);
            lat_mat = lat_mat(:, ~om_m);

            for ci = 1:nCycles
                idx = find(strcmp(ct.label, ref_labels{ci}), 1);
                if ~isempty(idx)
                    exp_means(k, ci) = ct.mean_latency_s(idx);
                    fly_vals = lat_mat(:, idx);
                    fly_vals = fly_vals(~isnan(fly_vals));
                    all_fly_data{ci} = [all_fly_data{ci}; fly_vals];
                end
            end
        end

        grand_mean = nanmean(exp_means, 1);
        grand_se   = nanstd(exp_means, 0, 1) ./ sqrt(sum(~isnan(exp_means), 1));

        %% Create figure
        fig = figure('Position', [100 100 1500 500], 'Visible', 'off');
        ax = axes(fig);
        hold(ax, 'on');

        % Individual fly scatter
        for ci = 1:nCycles
            vals = all_fly_data{ci};
            if ~isempty(vals)
                jitter = (rand(length(vals), 1) - 0.5) * 0.35;
                scatter(ax, ci + jitter, vals, 12, ...
                    cycle_colors(ci, :), 'filled', 'MarkerFaceAlpha', 0.25);
            end
        end

        % Experiment means as open circles
        for k = 1:nExp
            for ci = 1:nCycles
                if ~isnan(exp_means(k, ci))
                    jitter_e = (rand - 0.5) * 0.25;
                    scatter(ax, ci + jitter_e, exp_means(k, ci), 40, ...
                        cycle_colors(ci, :), 'LineWidth', 1.2);
                end
            end
        end

        % Grand mean +/- SE
        cycle_x = 1:nCycles;
        valid = ~isnan(grand_mean);
        errorbar(ax, cycle_x(valid), grand_mean(valid), grand_se(valid), ...
            'k.', 'LineWidth', 1.8, 'CapSize', 5, 'MarkerSize', 14);

        % Formatting
        set(ax, 'XTick', cycle_x, 'XTickLabel', ref_labels, 'XTickLabelRotation', 45);
        xlabel(ax, 'Cycle', 'FontSize', 11);
        ylabel(ax, 'Latency (s)', 'FontSize', 12);
        title(ax, sprintf('%s — %s — Latency Summary (n=%d experiments)', ...
            prot_name, geno, nExp), 'FontSize', 13, 'FontWeight', 'bold');
        xlim(ax, [0.5, nCycles + 0.5]);

        all_vals = cell2mat(all_fly_data(:));
        if ~isempty(all_vals)
            max_val = max(all_vals);
        else
            max_val = max(grand_mean + grand_se);
        end
        if isnan(max_val) || max_val == 0; max_val = 1; end
        ylim(ax, [0, max_val * 1.1]);
        grid(ax, 'on'); box(ax, 'on');
        hold(ax, 'off');

        %% Save
        out_png = fullfile(summary_dir, sprintf('summary_latency_%s_%s.png', prot_name, geno));
        out_fig = fullfile(summary_dir, sprintf('summary_latency_%s_%s.fig', prot_name, geno));
        exportgraphics(fig, out_png, 'Resolution', 150);
        savefig(fig, out_fig);
        close(fig);
        fprintf('  Saved summary latency plot: %s\n', out_png);
    end
end


function color = get_summary_cycle_color(label)
% GET_SUMMARY_CYCLE_COLOR  Return RGB color for a given cycle label
    GREY   = [0.5 0.5 0.5];
    ORANGE = [0.9 0.5 0];
    RED    = [1 0 0];

    if strcmp(label, 'PP')
        color = GREY;
    elseif strcmp(label, 'Ag')
        color = ORANGE;
    elseif contains(label, '.P')
        color = GREY;
    elseif startsWith(label, 'B')
        color = RED;
    else
        color = GREY;
    end
end
