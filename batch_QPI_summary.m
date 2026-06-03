%% batch_QPI_summary.m
% Compute per-cycle mean QPI (first/second half) for all experiments.
% Saves one .mat file per protocol in the protocol folder.
%
% Output .mat files:
%   QPI_summary_P001.mat, QPI_summary_P002.mat
%
% Each contains a table `QPI_summary` with columns:
%   experiment, genotype, cycle, label, n_flies,
%   mean_QPI_firsthalf, mean_QPI_secondhalf
%
% The file is updated recursively: existing experiments are kept,
% new experiments are appended. Re-running for the same experiment
% overwrites its rows.
%
% Author: Shubham Rathore

clc;

ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

% Optional: restrict to specific protocols (empty = all protocols)
if ~exist('TARGET_PROTOCOLS', 'var'), TARGET_PROTOCOLS = {}; end

% Set FORCE_RECOMPUTE = true to overwrite existing experiment rows
if ~exist('FORCE_RECOMPUTE', 'var'), FORCE_RECOMPUTE = false; end

%% Experiments to exclude
EXCLUDE_EXPERIMENTS = get_exclude_experiments();

%% Find all protocols
protocol_dirs = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocol_dirs = protocol_dirs([protocol_dirs.isdir]);
protocol_dirs = protocol_dirs(~cellfun('isempty', regexp({protocol_dirs.name}, '^P\d+$', 'once')));

% Filter to target protocols if specified
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

    %% Load existing summary if present (check column compatibility)
    expected_cols = {'experiment','genotype','cycle','label','n_flies','mean_QPI_firsthalf','mean_QPI_secondhalf'};
    summary_file = fullfile(prot_path, sprintf('QPI_summary_%s.mat', prot_name));
    if exist(summary_file, 'file')
        loaded = load(summary_file, 'QPI_summary');
        if all(ismember(expected_cols, loaded.QPI_summary.Properties.VariableNames))
            QPI_summary = loaded.QPI_summary;
            fprintf('  Loaded existing summary: %d rows\n', height(QPI_summary));
        else
            fprintf('  Existing summary has outdated columns — regenerating from scratch.\n');
            QPI_summary = table();
        end
    else
        QPI_summary = table();
    end

    nProcessed = 0;
    nSkipped   = 0;
    nFailed    = 0;
    failed_list = {};

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        exp_name = exp_dirs(e).name;

        % Exclude list
        if ismember(exp_name, EXCLUDE_EXPERIMENTS)
            fprintf('  [%d/%d] %s — EXCLUDED\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Check required files exist
        analysis_subdir = fullfile(exp_path, 'analysis');
        if isempty(dir(fullfile(analysis_subdir, 'arena_calib_*.mat'))) || ...
           isempty(dir(fullfile(analysis_subdir, 'LED_detector_*.mat')))
            fprintf('  [%d/%d] %s — missing calib/LED files, skipping\n', ...
                e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Skip if already in summary table (unless FORCE_RECOMPUTE)
        if ~FORCE_RECOMPUTE && ~isempty(QPI_summary) && ismember('experiment', QPI_summary.Properties.VariableNames) && ...
                any(strcmp(QPI_summary.experiment, exp_name))
            fprintf('  [%d/%d] %s — already in summary, skipping\n', ...
                e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end
        % Remove old rows if recomputing
        if FORCE_RECOMPUTE && ~isempty(QPI_summary) && ismember('experiment', QPI_summary.Properties.VariableNames)
            QPI_summary(strcmp(QPI_summary.experiment, exp_name), :) = [];
        end

        try
            %% Compute summary for this experiment
            s = compute_QPI_summary_local(exp_path, 'Protocol', prot_name);

            %% Build rows for this experiment
            num_cycles = height(s.cycle_table);
            exp_col   = repmat({s.experiment}, num_cycles, 1);
            geno_col  = repmat({s.genotype}, num_cycles, 1);

            new_rows = table(exp_col, geno_col, ...
                s.cycle_table.cycle, s.cycle_table.label, ...
                s.cycle_table.n_flies, ...
                s.cycle_table.mean_QPI_firsthalf, ...
                s.cycle_table.mean_QPI_secondhalf, ...
                'VariableNames', {'experiment', 'genotype', 'cycle', 'label', ...
                    'n_flies', 'mean_QPI_firsthalf', 'mean_QPI_secondhalf'});

            %% Remove existing rows for this experiment (if re-running)
            if ~isempty(QPI_summary) && ismember('experiment', QPI_summary.Properties.VariableNames)
                keep = ~strcmp(QPI_summary.experiment, exp_name);
                QPI_summary = QPI_summary(keep, :);
            end

            %% Append
            QPI_summary = [QPI_summary; new_rows]; %#ok<AGROW>
            nProcessed = nProcessed + 1;

        catch ME
            fprintf('  [%d/%d] %s — Error: %s\n', e, length(exp_dirs), exp_name, ME.message);
            failed_list{end+1} = sprintf('%s: %s', exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end

    %% Sort by genotype then experiment then cycle
    if ~isempty(QPI_summary)
        QPI_summary = sortrows(QPI_summary, {'genotype', 'experiment', 'cycle'});
    end

    %% Save
    save(summary_file, 'QPI_summary');
    fprintf('\n  Saved: %s (%d total rows)\n', summary_file, height(QPI_summary));

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

    % Quick overview by genotype
    if ~isempty(QPI_summary)
        genotypes = unique(QPI_summary.genotype);
        for g = 1:length(genotypes)
            geno_rows = strcmp(QPI_summary.genotype, genotypes{g});
            exps = unique(QPI_summary.experiment(geno_rows));
            fprintf('  %s: %d experiments\n', genotypes{g}, length(exps));
        end
    end
end

%% ====== PLOT INTENSITY-RESPONSE CURVES ======
fprintf('\n--- Generating intensity-response plots ---\n');
for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);
    summary_file = fullfile(prot_path, sprintf('QPI_summary_%s.mat', prot_name));

    if ~exist(summary_file, 'file')
        fprintf('  %s — no summary file, skipping plot\n', prot_name);
        continue;
    end

    % Create summary directory
    qpi_dir = fullfile(prot_path, 'QPI_summary');
    if ~exist(qpi_dir, 'dir'), mkdir(qpi_dir); end

    fprintf('  Plotting %s (second half) ...\n', prot_name);
    plot_QPI_intensity_local(prot_name, ...
        'SavePath', qpi_dir, 'ShowPlots', false, ...
        'Metric', 'mean_QPI_secondhalf');

    fprintf('  Plotting %s (first half) ...\n', prot_name);
    plot_QPI_intensity_local(prot_name, ...
        'SavePath', qpi_dir, 'ShowPlots', false, ...
        'Metric', 'mean_QPI_firsthalf');

    % Place learning: all-cycles plots (skips non-PL protocols internally)
    fprintf('  Plotting %s (all cycles, second half) ...\n', prot_name);
    plot_QPI_allcycles_local(prot_name, ...
        'SavePath', qpi_dir, 'ShowPlots', false, ...
        'Metric', 'mean_QPI_secondhalf');

    fprintf('  Plotting %s (all cycles, first half) ...\n', prot_name);
    plot_QPI_allcycles_local(prot_name, ...
        'SavePath', qpi_dir, 'ShowPlots', false, ...
        'Metric', 'mean_QPI_firsthalf');

    % Place learning: block means (skips non-PL protocols internally)
    fprintf('  Plotting %s (blocks, second half) ...\n', prot_name);
    plot_QPI_blocks_local(prot_name, ...
        'SavePath', qpi_dir, 'ShowPlots', false, ...
        'Metric', 'mean_QPI_secondhalf');

    fprintf('  Plotting %s (blocks, first half) ...\n', prot_name);
    plot_QPI_blocks_local(prot_name, ...
        'SavePath', qpi_dir, 'ShowPlots', false, ...
        'Metric', 'mean_QPI_firsthalf');

    % Place learning: probe trials (skips non-PL protocols internally)
    fprintf('  Plotting %s (probes, second half) ...\n', prot_name);
    plot_QPI_probes_local(prot_name, ...
        'SavePath', qpi_dir, 'ShowPlots', false, ...
        'Metric', 'mean_QPI_secondhalf');

    fprintf('  Plotting %s (probes, first half) ...\n', prot_name);
    plot_QPI_probes_local(prot_name, ...
        'SavePath', qpi_dir, 'ShowPlots', false, ...
        'Metric', 'mean_QPI_firsthalf');

end

fprintf('\n========================================\n');
fprintf('Done: %s\n\n', datestr(now));
