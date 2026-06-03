%% batch_plot_speed.m
% Generate per-experiment speed plots for all experiments across all protocols.
%
% Calls plot_speed_per_experiment_local for each experiment, which computes
% speed internally (via compute_speed_per_cycle_local) and saves:
%   - speed_<exp>.mat                  — per-cycle speed data
%   - speed_<exp>_cycle<NN>_<lbl>.png  — individual cycle plots
%   - speed_<exp>_cycle<NN>_<lbl>.fig  — individual cycle .fig files
%   - speed_<exp>_allcycles.fig        — combined all-cycles figure
%   - speed_<exp>_allcycles.png        — combined all-cycles PNG
%
% Requires LED_detector in each experiment's analysis/ folder.

clear; clc;

ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

% Per-protocol px/mm calibration (computed from trx.mat per protocol)
pxpermm_map = containers.Map();

% Set to true to regenerate all plots (e.g., after changing plot style)
FORCE_REPLOT = false;

% Speed-specific parameters
FPS           = 30.1;
PRE_ONSET_SEC = 10;
SMOOTH_WIN_SEC = 0.5;

%% Experiments to exclude
EXCLUDE_EXPERIMENTS = get_exclude_experiments();

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

    % Skip P004 (optomotor only — no place-learning cycles)
    if strcmp(prot_name, 'P004')
        fprintf('\n=== %s — optomotor only, skipping ===\n', prot_name);
        continue;
    end

    % Get px/mm for this protocol (average from trx.mat, cached)
    if ~pxpermm_map.isKey(prot_name)
        pxpermm_map(prot_name) = get_mean_pxpermm(ANALYSIS_DIR, prot_name);
    end
    PIXELS_PER_MM = pxpermm_map(prot_name);

    exp_dirs = dir(prot_path);
    % SAFEGUARD: Only process experiment directories (contain '_Rig' in name)
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}) & contains({exp_dirs.name}, '_Rig'));
    % Filter out summary directories
    exp_dirs = exp_dirs(~contains({exp_dirs.name}, 'summary'));

    fprintf('\n=== %s (%d experiments, px/mm=%.2f) ===\n', prot_name, length(exp_dirs), PIXELS_PER_MM);

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        exp_name = exp_dirs(e).name;
        analysis_subdir = fullfile(exp_path, 'analysis');

        % Exclude list
        if ismember(exp_name, EXCLUDE_EXPERIMENTS)
            fprintf('  [%d/%d] %s — EXCLUDED\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Skip if speed .mat already exists (unless FORCE_REPLOT)
        if ~FORCE_REPLOT && exist(fullfile(analysis_subdir, sprintf('speed_%s.mat', exp_name)), 'file')
            fprintf('  [%d/%d] %s — speed data exists, skipping\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Check for required files
        if isempty(dir(fullfile(analysis_subdir, 'LED_detector_*.mat')))
            fprintf('  [%d/%d] %s — no LED_detector, skipping\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        if ~exist(fullfile(exp_path, 'trx.mat'), 'file')
            fprintf('  [%d/%d] %s — no trx.mat, skipping\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        try
            fprintf('  [%d/%d] %s ... ', e, length(exp_dirs), exp_name);
            s = plot_speed_per_experiment_local(exp_path, ...
                'Protocol', prot_name, ...
                'PixelsPerMM', PIXELS_PER_MM, ...
                'FPS', FPS, ...
                'PreOnsetSec', PRE_ONSET_SEC, ...
                'SmoothWinSec', SMOOTH_WIN_SEC, ...
                'ShowPlots', false, ...
                'SavePlot', true);

            % Block overlay + probe overlay (place-learning protocols only)
            if ~isempty(s)
                try
                    plot_speed_block_overlay(s, 'ShowPlots', false, 'SavePlot', true);
                catch ME_blk
                    fprintf('  Block overlay error: %s\n', ME_blk.message);
                end
            end

            nPlotted = nPlotted + 1;
            fprintf('done\n');
        catch ME
            fprintf('Error: %s\n', ME.message);
            failed_list{end+1} = sprintf('[%s] %s: %s', prot_name, exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end
end

%% Summary
fprintf('\n========================================\n');
fprintf('SPEED BATCH PLOT SUMMARY\n');
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
