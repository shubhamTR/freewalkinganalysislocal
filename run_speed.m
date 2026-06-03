%% run_speed.m
% Compute speed and generate all speed plots for all place-learning protocols.
%
% Processes all place-learning protocols (skips P004, P012) using per-protocol pixel scaling.
%
% For each experiment:
%   - Computes per-fly speed per cycle (saves speed_<exp>.mat)
%   - Generates per-cycle plots (.png + .fig)
%   - Generates combined all-cycles figure (.fig + .png)
%   - Generates block-averaged training overlay (.png + .fig)
%   - Generates probe overlay (.png + .fig)

clearvars -except TARGET_PROTOCOLS; clc;


ANALYSIS_DIR  = '/Users/rathores/Documents/analysisdatalocal';
FPS           = 30.1;
PRE_ONSET_SEC = 10;
SMOOTH_WIN_SEC = 0.5;

% Per-protocol pixel scaling (computed from trx.mat per protocol)
pxpermm_map = containers.Map();

protocols = {'P001', 'P002', 'P003', 'P005', 'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P013', 'P014', 'P015', 'P016', 'P017', 'P019', 'P023', 'P024', 'P025'};
if ~exist('TARGET_PROTOCOLS', 'var'), TARGET_PROTOCOLS = {}; end
if ~isempty(TARGET_PROTOCOLS)
    protocols = protocols(ismember(protocols, TARGET_PROTOCOLS));
end

%% Experiments to exclude
EXCLUDE_EXPERIMENTS = get_exclude_experiments();

for p_idx = 1:length(protocols)
    PROTOCOL    = protocols{p_idx};
    if ~pxpermm_map.isKey(PROTOCOL)
        pxpermm_map(PROTOCOL) = get_mean_pxpermm(ANALYSIS_DIR, PROTOCOL);
    end
    PIXELS_PER_MM = pxpermm_map(PROTOCOL);
    prot_path   = fullfile(ANALYSIS_DIR, PROTOCOL);

    % Skip if protocol directory doesn't exist
    if ~exist(prot_path, 'dir')
        fprintf('Protocol %s directory not found, skipping.\n\n', PROTOCOL);
        continue;
    end

    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));

    % SAFEGUARD: Only process directories containing '_Rig' (experiment folders).
    % This prevents accidental processing of summary/output directories.
    exp_dirs = exp_dirs(~contains({exp_dirs.name}, 'summary') & ...
                         contains({exp_dirs.name}, '_Rig'));

    nPlotted = 0;
    nSkipped = 0;
    nFailed  = 0;
    failed_list = {};

    fprintf('=== %s (%d experiments, px/mm=%.2f) ===\n', PROTOCOL, length(exp_dirs), PIXELS_PER_MM);

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

        % Skip if speed .mat already exists
        speed_mat = fullfile(analysis_subdir, sprintf('speed_%s.mat', exp_name));
        if exist(speed_mat, 'file')
            fprintf('  [%d/%d] %s — speed .mat exists, skipping\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        try
            fprintf('  [%d/%d] %s ... ', e, length(exp_dirs), exp_name);

            s = plot_speed_per_experiment_local(exp_path, ...
                'Protocol', PROTOCOL, ...
                'PixelsPerMM', PIXELS_PER_MM, ...
                'FPS', FPS, ...
                'PreOnsetSec', PRE_ONSET_SEC, ...
                'SmoothWinSec', SMOOTH_WIN_SEC, ...
                'ShowPlots', false, ...
                'SavePlot', true);

            if ~isempty(s)
                plot_speed_block_overlay(s, 'ShowPlots', false, 'SavePlot', true);
            end

            nPlotted = nPlotted + 1;
            fprintf('done\n');
        catch ME
            fprintf('Error: %s\n', ME.message);
            failed_list{end+1} = sprintf('%s: %s', exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end

    fprintf('\n========================================\n');
    fprintf('%s SPEED SUMMARY\n', PROTOCOL);
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
    fprintf('========================================\n\n');
end

fprintf('All protocols processed.\n');
fprintf('Done: %s\n\n', datestr(now));
