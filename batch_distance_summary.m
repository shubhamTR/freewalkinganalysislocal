%% batch_distance_summary.m
% Compute per-cycle distance travelled for all experiments.
% Saves one .mat file per protocol in the protocol folder.
%
% Output .mat files:
%   distance_summary_P001.mat, distance_summary_P002.mat
%
% Each contains:
%   distance_summary — table with per-cycle mean distance
%       Columns: experiment, genotype, cycle, label, n_flies_alive,
%                mean_dist_mm, sem_dist_mm
%
%   distance_per_fly — struct array with raw per-fly distance matrices
%       Each entry has: .experiment, .genotype, .fly_ids_original,
%                       .distance_per_fly
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

%% Experiments to exclude from distance/speed analysis
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
    summary_file = fullfile(prot_path, sprintf('distance_summary_%s.mat', prot_name));
    if exist(summary_file, 'file')
        loaded = load(summary_file);
        distance_summary = loaded.distance_summary;

        %% Migrate old column format — drop stale columns
        stale_cols = {'mean_vel_pre', 'sem_vel_pre', 'mean_vel_post', ...
            'sem_vel_post', 'mean_delta_vel', 'sem_delta_vel', ...
            'delta_vel_onset', 'sem_delta_vel_onset', ...
            'mean_speed_on', 'sem_speed_on', 'mean_speed_off', 'sem_speed_off'};
        for vc = 1:length(stale_cols)
            if ismember(stale_cols{vc}, distance_summary.Properties.VariableNames)
                distance_summary.(stale_cols{vc}) = [];
                fprintf('  Dropped stale column: %s\n', stale_cols{vc});
            end
        end

        if isfield(loaded, 'distance_per_fly_all')
            distance_per_fly_all = loaded.distance_per_fly_all;
        else
            distance_per_fly_all = struct('experiment', {}, 'genotype', {}, ...
                'fly_ids_original', {}, 'distance_per_fly', {});
        end
        fprintf('  Loaded existing summary: %d rows\n', height(distance_summary));
    else
        distance_summary = table();
        distance_per_fly_all = struct('experiment', {}, 'genotype', {}, ...
            'fly_ids_original', {}, 'distance_per_fly', {});
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
            fprintf('  [%d/%d] %s — EXCLUDED (see EXCLUDE_EXPERIMENTS)\n', ...
                e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Check required files
        analysis_subdir = fullfile(exp_path, 'analysis');
        if ~exist(fullfile(exp_path, 'trx.mat'), 'file') || ...
           isempty(dir(fullfile(analysis_subdir, 'LED_detector_*.mat')))
            fprintf('  [%d/%d] %s — missing trx/LED files, skipping\n', ...
                e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Skip if already in summary table
        if ~isempty(distance_summary) && ismember('experiment', distance_summary.Properties.VariableNames) && ...
                any(strcmp(distance_summary.experiment, exp_name))
            fprintf('  [%d/%d] %s — already in summary, skipping\n', ...
                e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        try
            %% Compute distance for this experiment
            s = compute_distance_per_cycle_local(exp_path, ...
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
                s.cycle_table.mean_dist_mm, ...
                s.cycle_table.sem_dist_mm, ...
                'VariableNames', {'experiment', 'genotype', 'cycle', 'label', ...
                    'n_flies_alive', 'mean_dist_mm', 'sem_dist_mm'});

            %% Remove existing rows for this experiment (if re-running)
            if ~isempty(distance_summary) && ismember('experiment', distance_summary.Properties.VariableNames)
                keep = ~strcmp(distance_summary.experiment, exp_name);
                distance_summary = distance_summary(keep, :);
            end
            % Ensure column order matches before concatenation
            if ~isempty(distance_summary)
                new_rows = new_rows(:, distance_summary.Properties.VariableNames);
            end
            distance_summary = [distance_summary; new_rows]; %#ok<AGROW>

            %% Store per-fly raw data (remove old entry first)
            old_idx = [];
            for ii = 1:length(distance_per_fly_all)
                if strcmp(distance_per_fly_all(ii).experiment, exp_name)
                    old_idx = ii;
                    break;
                end
            end
            if ~isempty(old_idx)
                distance_per_fly_all(old_idx) = [];
            end

            fly_entry.experiment        = s.experiment;
            fly_entry.genotype          = s.genotype;
            fly_entry.fly_ids_original  = s.fly_ids_original;
            fly_entry.distance_per_fly  = s.distance_per_fly;
            distance_per_fly_all = [distance_per_fly_all, fly_entry]; %#ok<AGROW>

            nProcessed = nProcessed + 1;

        catch ME
            fprintf('  [%d/%d] %s — Error: %s\n', e, length(exp_dirs), exp_name, ME.message);
            failed_list{end+1} = sprintf('%s: %s', exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end

    %% Sort by genotype then experiment then cycle
    if ~isempty(distance_summary)
        distance_summary = sortrows(distance_summary, {'genotype', 'experiment', 'cycle'});
    end

    %% Save
    pixels_per_mm_used = PIXELS_PER_MM;
    save(summary_file, 'distance_summary', 'distance_per_fly_all', 'pixels_per_mm_used');
    fprintf('\n  Saved: %s (%d total rows)\n', summary_file, height(distance_summary));

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

    if ~isempty(distance_summary)
        genotypes = unique(distance_summary.genotype);
        for g = 1:length(genotypes)
            geno_rows = strcmp(distance_summary.genotype, genotypes{g});
            exps = unique(distance_summary.experiment(geno_rows));
            fprintf('  %s: %d experiments\n', genotypes{g}, length(exps));
        end
    end
end

%% ====== PLOT DISTANCE vs INTENSITY CURVES ======
fprintf('\n--- Generating distance vs intensity plots ---\n');
for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);
    summary_file = fullfile(prot_path, sprintf('distance_summary_%s.mat', prot_name));

    if ~exist(summary_file, 'file')
        fprintf('  %s — no summary file, skipping plot\n', prot_name);
        continue;
    end

    % Create summary directory
    dist_dir = fullfile(prot_path, 'distance_summary');
    if ~exist(dist_dir, 'dir'), mkdir(dist_dir); end

    loaded = load(summary_file, 'distance_summary');

    fprintf('  Plotting distance vs intensity: %s ...\n', prot_name);
    plot_distance_intensity_local(loaded.distance_summary, prot_name, ...
        'SavePath', dist_dir, 'ShowPlots', false);
end

%% ====== PLOT PLACE-LEARNING DISTANCE SUMMARIES ======
fprintf('\n--- Generating place-learning distance plots ---\n');
for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);
    summary_file = fullfile(prot_path, sprintf('distance_summary_%s.mat', prot_name));

    if ~exist(summary_file, 'file')
        fprintf('  %s — no summary file, skipping PL plots\n', prot_name);
        continue;
    end

    % Create summary directory
    dist_dir = fullfile(prot_path, 'distance_summary');
    if ~exist(dist_dir, 'dir'), mkdir(dist_dir); end

    loaded = load(summary_file, 'distance_summary');

    % All-cycles distance
    fprintf('  Plotting all-cycles distance: %s ...\n', prot_name);
    plot_distance_allcycles_local(loaded.distance_summary, prot_name, ...
        'SavePath', dist_dir, 'ShowPlots', false, 'Metric', 'mean_dist_mm');

    % Block-mean distance
    fprintf('  Plotting block-mean distance: %s ...\n', prot_name);
    plot_distance_blocks_local(loaded.distance_summary, prot_name, ...
        'SavePath', dist_dir, 'ShowPlots', false, 'Metric', 'mean_dist_mm');

    % Probe distance
    fprintf('  Plotting probe distance: %s ...\n', prot_name);
    plot_distance_probes_local(loaded.distance_summary, prot_name, ...
        'SavePath', dist_dir, 'ShowPlots', false, 'Metric', 'mean_dist_mm');

end

fprintf('\n========================================\n');
fprintf('Done: %s\n\n', datestr(now));
