%% batch_recompute_QPI.m
% Recompute quadrant_preference_results.mat for specified protocols.
% Use after fixing compute_quadrant_preference_local.m to regenerate
% QPI data without rerunning the full pipeline.
%
% Usage:
%   TARGET_PROTOCOLS = {'P017','P019'}; batch_recompute_QPI

clc;

ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

if ~exist('TARGET_PROTOCOLS', 'var') || isempty(TARGET_PROTOCOLS)
    error('Set TARGET_PROTOCOLS before running, e.g.: TARGET_PROTOCOLS = {''P017'',''P019''}; batch_recompute_QPI');
end

nRecomputed = 0;
nFailed = 0;
failed_list = {};

for p = 1:length(TARGET_PROTOCOLS)
    prot = TARGET_PROTOCOLS{p};
    prot_path = fullfile(ANALYSIS_DIR, prot);
    if ~exist(prot_path, 'dir')
        fprintf('Protocol %s not found, skipping\n', prot);
        continue;
    end

    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}) & contains({exp_dirs.name}, '_Rig'));

    fprintf('\n=== %s (%d experiments) ===\n', prot, length(exp_dirs));

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        exp_name = exp_dirs(e).name;
        analysis_dir = fullfile(exp_path, 'analysis');

        try
            % Load prerequisites
            filtered_trx_file = fullfile(analysis_dir, 'trx_filtered.mat');
            trx_file = fullfile(exp_path, 'trx.mat');
            if exist(filtered_trx_file, 'file')
                load(filtered_trx_file, 'trx');
            else
                load(trx_file, 'trx');
            end

            arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
            load(fullfile(analysis_dir, arena_files(end).name), 'arena_calib');
            all_masks = arena_calib.all_masks;

            led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
            load(fullfile(analysis_dir, led_files(end).name), 'LED_detector');

            LED_detector_thresh = struct();
            LED_detector_thresh.on_times = LED_detector.on_times;
            LED_detector_thresh.off_times = LED_detector.off_times;

            opts = struct('Protocol', prot, 'exp_path', exp_path);

            % Recompute QPI
            quad_pref_results = compute_quadrant_preference_local(trx, all_masks, LED_detector_thresh, opts);
            save(fullfile(analysis_dir, 'quadrant_preference_results.mat'), 'quad_pref_results');

            fprintf('  [%d/%d] %s — recomputed\n', e, length(exp_dirs), exp_name);
            nRecomputed = nRecomputed + 1;

        catch ME
            fprintf('  [%d/%d] %s — Error: %s\n', e, length(exp_dirs), exp_name, ME.message);
            failed_list{end+1} = sprintf('[%s] %s: %s', prot, exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end
end

%% Summary
fprintf('\n========================================\n');
fprintf('QPI RECOMPUTE SUMMARY\n');
fprintf('========================================\n');
fprintf('Recomputed: %d\n', nRecomputed);
fprintf('Failed:     %d\n', nFailed);
if ~isempty(failed_list)
    fprintf('\nFailed experiments:\n');
    for fi = 1:length(failed_list)
        fprintf('  %s\n', failed_list{fi});
    end
end
fprintf('========================================\n');
fprintf('Done: %s\n\n', datestr(now));
