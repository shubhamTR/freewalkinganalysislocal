%% batch_onset_velocity.m
% Extract per-frame velocity aligned to LED onset for all experiments.
% Generates peri-stimulus velocity trace plots per protocol.
%
% Output:
%   onset_vel_trace_P001.mat / onset_vel_trace_P002.mat — struct arrays
%   onset_vel_trace_P001.png / onset_vel_trace_P002.png — trace plots
%
% Author: Shubham Rathore

clearvars -except TARGET_PROTOCOLS; clc;

ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

%% Experiments to exclude
EXCLUDE_EXPERIMENTS = get_exclude_experiments();

%% Compute average pixels_per_mm from trx.mat across all experiments
fprintf('--- Assessing pixels_per_mm from trx.mat files ---\n');
protocol_dirs = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocol_dirs = protocol_dirs([protocol_dirs.isdir]);
protocol_dirs = protocol_dirs(~cellfun('isempty', regexp({protocol_dirs.name}, '^P\d+$', 'once')));
if ~exist('TARGET_PROTOCOLS', 'var'), TARGET_PROTOCOLS = {}; end
if ~isempty(TARGET_PROTOCOLS)
    protocol_dirs = protocol_dirs(ismember({protocol_dirs.name}, TARGET_PROTOCOLS));
end

pxpermm_vals = [];
for pp = 1:length(protocol_dirs)
    prot_path = fullfile(ANALYSIS_DIR, protocol_dirs(pp).name);
    exp_dirs_tmp = dir(prot_path);
    exp_dirs_tmp = exp_dirs_tmp([exp_dirs_tmp.isdir] & ~ismember({exp_dirs_tmp.name}, {'.', '..'}));
    for ee = 1:length(exp_dirs_tmp)
        trx_file = fullfile(prot_path, exp_dirs_tmp(ee).name, 'trx.mat');
        if ~exist(trx_file, 'file'), continue; end
        try
            trx_tmp = load(trx_file, 'trx');
            if isfield(trx_tmp.trx, 'pxpermm') && ~isempty(trx_tmp.trx(1).pxpermm)
                pxpermm_vals(end+1) = trx_tmp.trx(1).pxpermm; %#ok<SAGROW>
            end
        catch
        end
    end
end

if isempty(pxpermm_vals)
    PIXELS_PER_MM = 11.54;
    fprintf('  WARNING: No pxpermm found — using fallback %.2f\n', PIXELS_PER_MM);
else
    PIXELS_PER_MM = mean(pxpermm_vals);
    fprintf('  Mean pxpermm: %.4f (n=%d experiments)\n', PIXELS_PER_MM, length(pxpermm_vals));
end
fprintf('  Using PIXELS_PER_MM = %.4f\n\n', PIXELS_PER_MM);

%% Process each protocol
for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);

    exp_dirs = dir(prot_path);
    % SAFEGUARD: Only process experiment directories (contain '_Rig' in name)
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}) & contains({exp_dirs.name}, '_Rig'));

    % Skip if onset velocity .mat already exists for this protocol
    onset_mat = fullfile(prot_path, sprintf('onset_vel_trace_%s.mat', prot_name));
    if exist(onset_mat, 'file')
        fprintf('\n=== %s — onset_vel_trace exists, skipping ===\n', prot_name);
        continue;
    end

    fprintf('\n=== %s (%d experiments) ===\n', prot_name, length(exp_dirs));

    all_results = [];
    nProcessed = 0;
    nSkipped   = 0;
    nFailed    = 0;
    failed_list = {};

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        exp_name = exp_dirs(e).name;

        % Exclusion
        if ismember(exp_name, EXCLUDE_EXPERIMENTS)
            fprintf('  [%d/%d] %s — EXCLUDED\n', e, length(exp_dirs), exp_name);
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

        try
            r = compute_onset_velocity_trace_local(exp_path, ...
                'Protocol', prot_name, 'PixelsPerMM', PIXELS_PER_MM);

            if isempty(r)
                nSkipped = nSkipped + 1;
                continue;
            end

            all_results = [all_results, r]; %#ok<AGROW>
            nProcessed = nProcessed + 1;

        catch ME
            fprintf('  [%d/%d] %s — Error: %s\n', e, length(exp_dirs), exp_name, ME.message);
            failed_list{end+1} = sprintf('%s: %s', exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end

    fprintf('\n  --- %s Summary ---\n', prot_name);
    fprintf('  Processed: %d  |  Skipped: %d  |  Failed: %d\n', ...
        nProcessed, nSkipped, nFailed);
    if ~isempty(failed_list)
        fprintf('\n  Failed experiments:\n');
        for fi = 1:length(failed_list)
            fprintf('    %s\n', failed_list{fi});
        end
    end

    if isempty(all_results)
        fprintf('  No results to plot — skipping %s\n', prot_name);
        continue;
    end

    %% Save results
    save_file = fullfile(prot_path, sprintf('onset_vel_trace_%s.mat', prot_name));
    onset_vel_results = all_results; %#ok<NASGU>
    save(save_file, 'onset_vel_results', '-v7.3');
    fprintf('  Saved: %s\n', save_file);

    %% Plot
    fprintf('  Plotting peri-stimulus velocity trace: %s ...\n', prot_name);
    plot_onset_velocity_trace_local(all_results, prot_name, ...
        'SavePath', prot_path, 'ShowPlots', false);
end

fprintf('\n========================================\n');
fprintf('Done: %s\n\n', datestr(now));
