%% batch_latency_summary.m
% Compute per-cycle latency to correct quadrant for all experiments.
% Saves one .mat file per protocol in the protocol folder.
%
% Output .mat files:
%   latency_summary_P001.mat, latency_summary_P002.mat
%
% Each contains:
%   latency_summary — table with per-cycle mean/median latency
%       Columns: experiment, genotype, cycle, label, n_flies_alive,
%                n_responded, n_already_correct,
%                mean_latency_s, sem_latency_s, median_latency_s
%
%   latency_per_fly_all — struct array with raw per-fly latency matrices
%       Each entry has: .experiment, .genotype, .fly_ids_original,
%                       .latency_per_fly, .already_in_correct
%
% The file is updated recursively: existing experiments are kept,
% new experiments are appended. Re-running for the same experiment
% overwrites its rows.
%
% Reads dead fly status from QPI log files when available.
%
% Author: Shubham Rathore

clearvars -except TARGET_PROTOCOLS; clc;

ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';
if ~exist('TARGET_PROTOCOLS', 'var'), TARGET_PROTOCOLS = {}; end

%% Experiments to exclude
EXCLUDE_EXPERIMENTS = get_exclude_experiments();

%% Process each protocol
protocol_dirs = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocol_dirs = protocol_dirs([protocol_dirs.isdir]);
protocol_dirs = protocol_dirs(~cellfun('isempty', regexp({protocol_dirs.name}, '^P\d+$', 'once')));
if ~isempty(TARGET_PROTOCOLS)
    protocol_dirs = protocol_dirs(ismember({protocol_dirs.name}, TARGET_PROTOCOLS));
end

for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);

    exp_dirs = dir(prot_path);
    % SAFEGUARD: Only process experiment directories (contain '_Rig' in name)
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}) & contains({exp_dirs.name}, '_Rig'));

    fprintf('\n=== %s (%d experiments) ===\n', prot_name, length(exp_dirs));

    %% Load existing summary if present
    summary_file = fullfile(prot_path, sprintf('latency_summary_%s.mat', prot_name));
    if exist(summary_file, 'file')
        loaded = load(summary_file);
        latency_summary = loaded.latency_summary;
        if isfield(loaded, 'latency_per_fly_all')
            latency_per_fly_all = loaded.latency_per_fly_all;
        else
            latency_per_fly_all = struct('experiment', {}, 'genotype', {}, ...
                'fly_ids_original', {}, 'latency_per_fly', {}, ...
                'already_in_correct', {});
        end
        fprintf('  Loaded existing summary: %d rows\n', height(latency_summary));
    else
        latency_summary = table();
        latency_per_fly_all = struct('experiment', {}, 'genotype', {}, ...
            'fly_ids_original', {}, 'latency_per_fly', {}, ...
            'already_in_correct', {});
    end

    nProcessed = 0;
    nSkipped   = 0;
    nFailed    = 0;
    failed_list = {};

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        exp_name = exp_dirs(e).name;

        % Check exclusion list
        if ismember(exp_name, EXCLUDE_EXPERIMENTS)
            fprintf('  [%d/%d] %s — EXCLUDED\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Check required files
        analysis_subdir = fullfile(exp_path, 'analysis');
        if ~exist(fullfile(exp_path, 'trx.mat'), 'file') || ...
           isempty(dir(fullfile(analysis_subdir, 'LED_detector_*.mat'))) || ...
           isempty(dir(fullfile(analysis_subdir, 'arena_calib_*.mat')))
            fprintf('  [%d/%d] %s — missing trx/LED/arena files, skipping\n', ...
                e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Skip if already in summary table
        if ~isempty(latency_summary) && ismember('experiment', latency_summary.Properties.VariableNames) && ...
                any(strcmp(latency_summary.experiment, exp_name))
            fprintf('  [%d/%d] %s — already in summary, skipping\n', ...
                e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        try
            %% Compute latency for this experiment
            s = compute_latency_per_cycle_local(exp_path, 'Protocol', prot_name);

            if isempty(s)
                nSkipped = nSkipped + 1;
                continue;
            end

            %% Build summary rows
            num_cycles = height(s.cycle_table);
            exp_col   = repmat({s.experiment}, num_cycles, 1);
            geno_col  = repmat({s.genotype}, num_cycles, 1);

            new_rows = table(exp_col, geno_col, ...
                s.cycle_table.cycle, s.cycle_table.label, ...
                s.cycle_table.n_flies_alive, ...
                s.cycle_table.n_responded, ...
                s.cycle_table.n_already_correct, ...
                s.cycle_table.mean_latency_s, ...
                s.cycle_table.sem_latency_s, ...
                s.cycle_table.median_latency_s, ...
                'VariableNames', {'experiment', 'genotype', 'cycle', 'label', ...
                    'n_flies_alive', 'n_responded', 'n_already_correct', ...
                    'mean_latency_s', 'sem_latency_s', 'median_latency_s'});

            %% Remove existing rows for this experiment (if re-running)
            if ~isempty(latency_summary) && ismember('experiment', latency_summary.Properties.VariableNames)
                keep = ~strcmp(latency_summary.experiment, exp_name);
                latency_summary = latency_summary(keep, :);
            end
            latency_summary = [latency_summary; new_rows]; %#ok<AGROW>

            %% Store per-fly raw data (remove old entry first)
            old_idx = [];
            for ii = 1:length(latency_per_fly_all)
                if strcmp(latency_per_fly_all(ii).experiment, exp_name)
                    old_idx = ii;
                    break;
                end
            end
            if ~isempty(old_idx)
                latency_per_fly_all(old_idx) = [];
            end

            fly_entry.experiment         = s.experiment;
            fly_entry.genotype           = s.genotype;
            fly_entry.fly_ids_original   = s.fly_ids_original;
            fly_entry.latency_per_fly    = s.latency_per_fly;
            fly_entry.already_in_correct = s.already_in_correct;
            latency_per_fly_all = [latency_per_fly_all, fly_entry]; %#ok<AGROW>

            nProcessed = nProcessed + 1;

        catch ME
            fprintf('  [%d/%d] %s — Error: %s\n', e, length(exp_dirs), exp_name, ME.message);
            failed_list{end+1} = sprintf('%s: %s', exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end

    %% Sort by genotype then experiment then cycle
    if ~isempty(latency_summary)
        latency_summary = sortrows(latency_summary, {'genotype', 'experiment', 'cycle'});
    end

    %% Save
    save(summary_file, 'latency_summary', 'latency_per_fly_all');
    fprintf('\n  Saved: %s (%d total rows)\n', summary_file, height(latency_summary));

    %% Print summary
    fprintf('\n  --- %s Summary ---\n', prot_name);
    fprintf('  Processed: %d\n', nProcessed);
    fprintf('  Skipped:   %d\n', nSkipped);
    fprintf('  Failed:    %d\n', nFailed);
    if ~isempty(failed_list)
        fprintf('\n  Failed experiments:\n');
        for fi = 1:length(failed_list)
            fprintf('    %s\n', failed_list{fi});
        end
    end

    if ~isempty(latency_summary)
        genotypes = unique(latency_summary.genotype);
        for g = 1:length(genotypes)
            geno_rows = strcmp(latency_summary.genotype, genotypes{g});
            exps = unique(latency_summary.experiment(geno_rows));
            fprintf('  %s: %d experiments\n', genotypes{g}, length(exps));
        end
    end
end

%% ====== PLOT LATENCY vs INTENSITY CURVES ======
fprintf('\n--- Generating latency vs intensity plots ---\n');
for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);
    summary_file = fullfile(prot_path, sprintf('latency_summary_%s.mat', prot_name));

    if ~exist(summary_file, 'file')
        fprintf('  %s — no summary file, skipping plot\n', prot_name);
        continue;
    end

    % Create summary directory
    lat_dir = fullfile(prot_path, 'latency_summary');
    if ~exist(lat_dir, 'dir'), mkdir(lat_dir); end

    loaded = load(summary_file, 'latency_summary');

    fprintf('  Plotting mean latency vs intensity: %s ...\n', prot_name);
    plot_latency_intensity_local(loaded.latency_summary, prot_name, ...
        'SavePath', lat_dir, 'ShowPlots', false, ...
        'Metric', 'mean_latency_s', 'PlotName', 'latency_intensity');

    fprintf('  Plotting median latency vs intensity: %s ...\n', prot_name);
    plot_latency_intensity_local(loaded.latency_summary, prot_name, ...
        'SavePath', lat_dir, 'ShowPlots', false, ...
        'Metric', 'median_latency_s', 'PlotName', 'latency_median_intensity');
end

%% ====== PLOT PLACE-LEARNING LATENCY SUMMARIES ======
fprintf('\n--- Generating place-learning latency plots ---\n');
for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);
    summary_file = fullfile(prot_path, sprintf('latency_summary_%s.mat', prot_name));

    if ~exist(summary_file, 'file')
        fprintf('  %s — no summary file, skipping PL plots\n', prot_name);
        continue;
    end

    % Create summary directory
    lat_dir = fullfile(prot_path, 'latency_summary');
    if ~exist(lat_dir, 'dir'), mkdir(lat_dir); end

    loaded = load(summary_file, 'latency_summary');

    % All-cycles mean latency
    fprintf('  Plotting all-cycles mean latency: %s ...\n', prot_name);
    plot_latency_allcycles_local(loaded.latency_summary, prot_name, ...
        'SavePath', lat_dir, 'ShowPlots', false, 'Metric', 'mean_latency_s');

    % All-cycles median latency
    fprintf('  Plotting all-cycles median latency: %s ...\n', prot_name);
    plot_latency_allcycles_local(loaded.latency_summary, prot_name, ...
        'SavePath', lat_dir, 'ShowPlots', false, ...
        'Metric', 'median_latency_s', 'PlotName', 'lat_median_allcycles');

    % Block-mean latency
    fprintf('  Plotting block-mean latency: %s ...\n', prot_name);
    plot_latency_blocks_local(loaded.latency_summary, prot_name, ...
        'SavePath', lat_dir, 'ShowPlots', false, 'Metric', 'mean_latency_s');

    % Block-mean median latency
    fprintf('  Plotting block-mean median latency: %s ...\n', prot_name);
    plot_latency_blocks_local(loaded.latency_summary, prot_name, ...
        'SavePath', lat_dir, 'ShowPlots', false, ...
        'Metric', 'median_latency_s', 'PlotName', 'lat_median_blocks');

    % Probe mean latency
    fprintf('  Plotting probe mean latency: %s ...\n', prot_name);
    plot_latency_probes_local(loaded.latency_summary, prot_name, ...
        'SavePath', lat_dir, 'ShowPlots', false, 'Metric', 'mean_latency_s');

    % Probe median latency
    fprintf('  Plotting probe median latency: %s ...\n', prot_name);
    plot_latency_probes_local(loaded.latency_summary, prot_name, ...
        'SavePath', lat_dir, 'ShowPlots', false, ...
        'Metric', 'median_latency_s', 'PlotName', 'lat_median_probes');

end

fprintf('\n========================================\n');
fprintf('Done: %s\n\n', datestr(now));
