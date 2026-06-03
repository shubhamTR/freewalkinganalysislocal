%% batch_plot_QPI.m
% Generate quadrant preference index plots for all experiments.
% Requires arena_calib and LED_detector in each experiment's analysis/ folder.
%
% Author: Shubham Rathore

clc;

ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

% Set to true to regenerate all QPI plots (e.g., after changing plot style)
if ~exist('FORCE_REPLOT', 'var'), FORCE_REPLOT = false; end

% Optional: restrict to specific protocols (empty = all protocols)
TARGET_PROTOCOLS = {'P001','P002','P008','P010','P011','P013','P014','P015','P016','P017','P019'};

%% Find all protocols
protocol_dirs = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocol_dirs = protocol_dirs([protocol_dirs.isdir]);
protocol_dirs = protocol_dirs(~cellfun('isempty', regexp({protocol_dirs.name}, '^P\d+$', 'once')));

% Filter to target protocols if specified
if ~isempty(TARGET_PROTOCOLS)
    protocol_dirs = protocol_dirs(ismember({protocol_dirs.name}, TARGET_PROTOCOLS));
end

nPlotted = 0;
nSkipped = 0;
nFailed  = 0;
failed_list = {};

for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);

    exp_dirs = dir(prot_path);
    % SAFEGUARD: Only process experiment directories (contain '_Rig' in name)
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}) & contains({exp_dirs.name}, '_Rig'));

    fprintf('\n=== %s (%d experiments) ===\n', prot_name, length(exp_dirs));

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        exp_name = exp_dirs(e).name;

        % Skip if QPI plot already exists (unless FORCE_REPLOT is true)
        analysis_subdir = fullfile(exp_path, 'analysis');
        if ~FORCE_REPLOT && ~isempty(dir(fullfile(analysis_subdir, sprintf('QPI_%s.png', exp_name))))
            fprintf('  [%d/%d] %s — QPI plot exists, skipping\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        try
            fprintf('  [%d/%d] ', e, length(exp_dirs));
            plot_quadrant_preference_local(exp_path, 'Protocol', prot_name);
            nPlotted = nPlotted + 1;
        catch ME
            fprintf('  [%d/%d] %s — Error: %s\n', e, length(exp_dirs), exp_name, ME.message);
            failed_list{end+1} = sprintf('[%s] %s: %s', prot_name, exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end
end

%% Summary
fprintf('\n========================================\n');
fprintf('QPI BATCH SUMMARY\n');
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
