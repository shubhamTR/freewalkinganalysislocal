%% run_transit_density.m
% Compute per-experiment transit density and generate per-genotype summaries
% for all applicable protocols.
%
% For each experiment in each protocol:
%   1. Computes per-cycle spatial density on a 20x20 rotated grid
%   2. Saves transit_density_<exp>.mat + .png to analysis/
%
% Then calls summary_transit_density to combine per genotype and generate
% V2-style per-cycle heatmaps (white → purple colormap).
%
% Protocols: P001-P011, P014 (skip P004, P012, P013)

clear; clc;


ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';
NGRID = 20;       % 20x20 grid

protocols = {'P001', 'P002', 'P003', 'P005', 'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P013', 'P014', 'P015', 'P016', 'P017', 'P019', 'P023', 'P024', 'P025'};
if ~exist('TARGET_PROTOCOLS', 'var'), TARGET_PROTOCOLS = {}; end
if ~isempty(TARGET_PROTOCOLS)
    protocols = protocols(ismember(protocols, TARGET_PROTOCOLS));
end

t_start = tic;

fprintf('==============================================================\n');
fprintf('  TRANSIT DENSITY — All Protocols\n');
fprintf('  Started: %s\n', datestr(now));
fprintf('==============================================================\n\n');

for p_idx = 1:length(protocols)
    PROTOCOL = protocols{p_idx};
    prot_path = fullfile(ANALYSIS_DIR, PROTOCOL);

    if ~exist(prot_path, 'dir')
        fprintf('Protocol %s directory not found, skipping.\n\n', PROTOCOL);
        continue;
    end

    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));

    % SAFEGUARD: Only process experiment directories (contain '_Rig' in name)
    exp_dirs = exp_dirs(contains({exp_dirs.name}, '_Rig'));

    nProcessed = 0;
    nSkipped   = 0;
    nFailed    = 0;
    failed_list = {};

    fprintf('=== %s (%d experiments) ===\n', PROTOCOL, length(exp_dirs));

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        exp_name = exp_dirs(e).name;
        analysis_subdir = fullfile(exp_path, 'analysis');

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

        if isempty(dir(fullfile(analysis_subdir, 'arena_calib_*.mat')))
            fprintf('  [%d/%d] %s — no arena_calib, skipping\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Skip if transit density .mat already exists
        td_mat = fullfile(analysis_subdir, sprintf('transit_density_%s.mat', exp_name));
        if exist(td_mat, 'file')
            fprintf('  [%d/%d] %s — transit_density exists, skipping\n', e, length(exp_dirs), exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        try
            fprintf('  [%d/%d] %s ... ', e, length(exp_dirs), exp_name);

            compute_transit_density(exp_path,...
                'Protocol', PROTOCOL, ...
                'NGrid', NGRID, ...
                'ShowPlots', false, ...
                'SavePlot', true);

            nProcessed = nProcessed + 1;
            fprintf('\n');
        catch ME
            fprintf('ERROR: %s\n', ME.message);
            failed_list{end+1} = sprintf('%s: %s', exp_name, ME.message); %#ok<AGROW>
            nFailed = nFailed + 1;
        end
    end

    fprintf('\n--- %s Per-Experiment Summary ---\n', PROTOCOL);
    fprintf('Processed: %d\n', nProcessed);
    fprintf('Skipped:   %d\n', nSkipped);
    fprintf('Failed:    %d\n', nFailed);
    if ~isempty(failed_list)
        fprintf('\nFailed experiments:\n');
        for fi = 1:length(failed_list)
            fprintf('  %s\n', failed_list{fi});
        end
    end
    fprintf('-----------------------------------\n\n');
end

%% Now run the summary (per-genotype V2-style heatmaps)
fprintf('\n>>> Generating per-genotype summary heatmaps <<<\n\n');
try
    summary_transit_density;
    fprintf('\n  summary_transit_density completed successfully.\n\n');
catch ME
    fprintf('\n  summary_transit_density FAILED: %s\n', ME.message);
    fprintf('  Stack:\n');
    for si = 1:length(ME.stack)
        fprintf('    %s (line %d)\n', ME.stack(si).name, ME.stack(si).line);
    end
end

%% Done
elapsed = toc(t_start);
fprintf('==============================================================\n');
fprintf('  TRANSIT DENSITY COMPLETE\n');
fprintf('  Total time: %.1f minutes (%.0f seconds)\n', elapsed/60, elapsed);
fprintf('  Finished: %s\n', datestr(now));
fprintf('==============================================================\n');
