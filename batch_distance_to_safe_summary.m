%% batch_distance_to_safe_summary.m
% Compute per-cycle distance-to-safe-quadrant for all experiments.
% Saves one .mat file per protocol in the protocol folder.
%
% This metric accumulates frame-to-frame displacement (mm) from LED onset
% until the fly first enters a dark (correct) quadrant it wasn't already in.
% Distinct from total distance travelled (batch_distance_summary.m).
%
% Output .mat files:
%   dist_to_safe_summary_P001.mat, dist_to_safe_summary_P002.mat, ...
%
% Each contains:
%   dist_to_safe_summary — table with per-cycle mean/median distance-to-safe
%       Columns: experiment, genotype, cycle, label, n_flies_alive,
%                n_responded, n_already_correct,
%                mean_dist_to_safe_mm, sem_dist_to_safe_mm,
%                median_dist_to_safe_mm
%
%   dist_to_safe_per_fly_all — struct array with raw per-fly matrices
%       Each entry has: .experiment, .genotype, .fly_ids_original,
%                       .dist_to_safe_per_fly, .already_in_correct
%
% The file is updated recursively: existing experiments are kept,
% new experiments are appended. Re-running for the same experiment
% overwrites its rows.
%
% Uses per-protocol pixels_per_mm from trx.mat (same as batch_distance_summary).
% Reads dead fly status from QPI log files when available.
%
% Author: Shubham Rathore

clearvars -except TARGET_PROTOCOLS; clc;

ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';
if ~exist('TARGET_PROTOCOLS', 'var'), TARGET_PROTOCOLS = {}; end

%% Experiments to exclude
EXCLUDE_EXPERIMENTS = get_exclude_experiments();

%% Compute average pixels_per_mm from trx.mat PER PROTOCOL
fprintf('--- Assessing pixels_per_mm from trx.mat files (per protocol) ---\n');
protocol_dirs = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocol_dirs = protocol_dirs([protocol_dirs.isdir]);
protocol_dirs = protocol_dirs(~cellfun('isempty', regexp({protocol_dirs.name}, '^P\d+$', 'once')));
if ~isempty(TARGET_PROTOCOLS)
    protocol_dirs = protocol_dirs(ismember({protocol_dirs.name}, TARGET_PROTOCOLS));
end

PXPERMM_MAP = containers.Map();   % protocol name → mean pxpermm

for pp = 1:length(protocol_dirs)
    prot_name_tmp = protocol_dirs(pp).name;
    PXPERMM_MAP(prot_name_tmp) = get_mean_pxpermm(ANALYSIS_DIR, prot_name_tmp);
end

%% Process each protocol
for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);
    PIXELS_PER_MM = PXPERMM_MAP(prot_name);
    fprintf('  Using PIXELS_PER_MM = %.4f for %s\n', PIXELS_PER_MM, prot_name);

    exp_dirs = dir(prot_path);
    % SAFEGUARD: Only process experiment directories (contain '_Rig' in name)
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}) & contains({exp_dirs.name}, '_Rig'));

    fprintf('\n=== %s (%d experiments) ===\n', prot_name, length(exp_dirs));

    %% Load existing summary if present
    summary_file = fullfile(prot_path, sprintf('dist_to_safe_summary_%s.mat', prot_name));
    if exist(summary_file, 'file')
        loaded = load(summary_file);
        dist_to_safe_summary = loaded.dist_to_safe_summary;
        if isfield(loaded, 'dist_to_safe_per_fly_all')
            dist_to_safe_per_fly_all = loaded.dist_to_safe_per_fly_all;
        else
            dist_to_safe_per_fly_all = struct('experiment', {}, 'genotype', {}, ...
                'fly_ids_original', {}, 'dist_to_safe_per_fly', {}, ...
                'already_in_correct', {});
        end
        fprintf('  Loaded existing summary: %d rows\n', height(dist_to_safe_summary));
    else
        dist_to_safe_summary = table();
        dist_to_safe_per_fly_all = struct('experiment', {}, 'genotype', {}, ...
            'fly_ids_original', {}, 'dist_to_safe_per_fly', {}, ...
            'dist_to_safe_last_per_fly', {}, 'safe_zone_occupancy', {}, ...
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

        % Check required files (needs arena_calib too, unlike total distance)
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
        if ~isempty(dist_to_safe_summary) && ismember('experiment', dist_to_safe_summary.Properties.VariableNames) && ...
                any(strcmp(dist_to_safe_summary.experiment, exp_name))
            fprintf('  [%d/%d] %s — already in summary, skipping\n', ...
                e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        try
            %% Compute distance-to-safe for this experiment
            s = compute_distance_to_safe_local(exp_path, ...
                'Protocol', prot_name, 'PixelsPerMM', PIXELS_PER_MM);

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
                s.cycle_table.mean_dist_to_safe_mm, ...
                s.cycle_table.sem_dist_to_safe_mm, ...
                s.cycle_table.median_dist_to_safe_mm, ...
                s.cycle_table.n_responded_last, ...
                s.cycle_table.mean_dist_to_safe_last_mm, ...
                s.cycle_table.sem_dist_to_safe_last_mm, ...
                s.cycle_table.median_dist_to_safe_last_mm, ...
                s.cycle_table.mean_safe_occupancy, ...
                s.cycle_table.sem_safe_occupancy, ...
                'VariableNames', {'experiment', 'genotype', 'cycle', 'label', ...
                    'n_flies_alive', 'n_responded', 'n_already_correct', ...
                    'mean_dist_to_safe_mm', 'sem_dist_to_safe_mm', ...
                    'median_dist_to_safe_mm', 'n_responded_last', ...
                    'mean_dist_to_safe_last_mm', 'sem_dist_to_safe_last_mm', ...
                    'median_dist_to_safe_last_mm', 'mean_safe_occupancy', ...
                    'sem_safe_occupancy'});

            %% Remove existing rows for this experiment (if re-running)
            if ~isempty(dist_to_safe_summary) && ismember('experiment', dist_to_safe_summary.Properties.VariableNames)
                keep = ~strcmp(dist_to_safe_summary.experiment, exp_name);
                dist_to_safe_summary = dist_to_safe_summary(keep, :);
            end
            % Ensure column order matches before concatenation
            if ~isempty(dist_to_safe_summary)
                new_rows = new_rows(:, dist_to_safe_summary.Properties.VariableNames);
            end
            dist_to_safe_summary = [dist_to_safe_summary; new_rows]; %#ok<AGROW>

            %% Store per-fly raw data (remove old entry first)
            old_idx = [];
            for ii = 1:length(dist_to_safe_per_fly_all)
                if strcmp(dist_to_safe_per_fly_all(ii).experiment, exp_name)
                    old_idx = ii;
                    break;
                end
            end
            if ~isempty(old_idx)
                dist_to_safe_per_fly_all(old_idx) = [];
            end

            fly_entry.experiment          = s.experiment;
            fly_entry.genotype            = s.genotype;
            fly_entry.fly_ids_original    = s.fly_ids_original;
            fly_entry.dist_to_safe_per_fly      = s.dist_to_safe_per_fly;
            fly_entry.dist_to_safe_last_per_fly = s.dist_to_safe_last_per_fly;
            fly_entry.safe_zone_occupancy       = s.safe_zone_occupancy;
            fly_entry.already_in_correct        = s.already_in_correct;
            dist_to_safe_per_fly_all = [dist_to_safe_per_fly_all, fly_entry]; %#ok<AGROW>

            nProcessed = nProcessed + 1;

        catch ME
            fprintf('  [%d/%d] %s — Error: %s\n', e, length(exp_dirs), exp_name, ME.message);
            failed_list{end+1} = sprintf('%s: %s', exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end

    %% Sort by genotype then experiment then cycle
    if ~isempty(dist_to_safe_summary)
        dist_to_safe_summary = sortrows(dist_to_safe_summary, {'genotype', 'experiment', 'cycle'});
    end

    %% Save
    pixels_per_mm_used = PIXELS_PER_MM;
    save(summary_file, 'dist_to_safe_summary', 'dist_to_safe_per_fly_all', 'pixels_per_mm_used');
    fprintf('\n  Saved: %s (%d total rows)\n', summary_file, height(dist_to_safe_summary));

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

    if ~isempty(dist_to_safe_summary)
        genotypes = unique(dist_to_safe_summary.genotype);
        for g = 1:length(genotypes)
            geno_rows = strcmp(dist_to_safe_summary.genotype, genotypes{g});
            exps = unique(dist_to_safe_summary.experiment(geno_rows));
            fprintf('  %s: %d experiments\n', genotypes{g}, length(exps));
        end
    end
end

%% ====== PLOT PLACE-LEARNING DISTANCE-TO-SAFE SUMMARIES ======
fprintf('\n--- Generating place-learning distance-to-safe plots ---\n');
for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);
    summary_file = fullfile(prot_path, sprintf('dist_to_safe_summary_%s.mat', prot_name));

    if ~exist(summary_file, 'file')
        fprintf('  %s — no summary file, skipping PL plots\n', prot_name);
        continue;
    end

    % Create summary directory
    dts_dir = fullfile(prot_path, 'dist_to_safe_summary');
    if ~exist(dts_dir, 'dir'), mkdir(dts_dir); end

    loaded = load(summary_file, 'dist_to_safe_summary');

    % All-cycles mean
    fprintf('  Plotting all-cycles mean dist-to-safe: %s ...\n', prot_name);
    plot_dist_to_safe_allcycles_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, 'Metric', 'mean_dist_to_safe_mm');

    % All-cycles median
    fprintf('  Plotting all-cycles median dist-to-safe: %s ...\n', prot_name);
    plot_dist_to_safe_allcycles_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, ...
        'Metric', 'median_dist_to_safe_mm', 'PlotName', 'dist_to_safe_median_allcycles');

    % Block-mean
    fprintf('  Plotting block-mean dist-to-safe: %s ...\n', prot_name);
    plot_dist_to_safe_blocks_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, 'Metric', 'mean_dist_to_safe_mm');

    % Block-mean median
    fprintf('  Plotting block-mean median dist-to-safe: %s ...\n', prot_name);
    plot_dist_to_safe_blocks_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, ...
        'Metric', 'median_dist_to_safe_mm', 'PlotName', 'dist_to_safe_median_blocks');

    % Probe mean
    fprintf('  Plotting probe mean dist-to-safe: %s ...\n', prot_name);
    plot_dist_to_safe_probes_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, 'Metric', 'mean_dist_to_safe_mm');

    % Probe median
    fprintf('  Plotting probe median dist-to-safe: %s ...\n', prot_name);
    plot_dist_to_safe_probes_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, ...
        'Metric', 'median_dist_to_safe_mm', 'PlotName', 'dist_to_safe_median_probes');

    % ---- LAST ENTRY plots ----
    % All-cycles mean (last entry)
    fprintf('  Plotting all-cycles mean dist-to-safe LAST: %s ...\n', prot_name);
    plot_dist_to_safe_allcycles_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, 'Metric', 'mean_dist_to_safe_last_mm');

    % All-cycles median (last entry)
    fprintf('  Plotting all-cycles median dist-to-safe LAST: %s ...\n', prot_name);
    plot_dist_to_safe_allcycles_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, ...
        'Metric', 'median_dist_to_safe_last_mm', 'PlotName', 'dist_to_safe_last_median_allcycles');

    % Block-mean (last entry)
    fprintf('  Plotting block-mean dist-to-safe LAST: %s ...\n', prot_name);
    plot_dist_to_safe_blocks_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, 'Metric', 'mean_dist_to_safe_last_mm');

    % Block-mean median (last entry)
    fprintf('  Plotting block-mean median dist-to-safe LAST: %s ...\n', prot_name);
    plot_dist_to_safe_blocks_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, ...
        'Metric', 'median_dist_to_safe_last_mm', 'PlotName', 'dist_to_safe_last_median_blocks');

    % Probe mean (last entry)
    fprintf('  Plotting probe mean dist-to-safe LAST: %s ...\n', prot_name);
    plot_dist_to_safe_probes_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, 'Metric', 'mean_dist_to_safe_last_mm');

    % Probe median (last entry)
    fprintf('  Plotting probe median dist-to-safe LAST: %s ...\n', prot_name);
    plot_dist_to_safe_probes_local(loaded.dist_to_safe_summary, prot_name, ...
        'SavePath', dts_dir, 'ShowPlots', false, ...
        'Metric', 'median_dist_to_safe_last_mm', 'PlotName', 'dist_to_safe_last_median_probes');

end

fprintf('\n========================================\n');
fprintf('Done: %s\n\n', datestr(now));
