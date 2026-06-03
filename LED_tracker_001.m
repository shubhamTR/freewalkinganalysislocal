%% LED_tracker_001.m
% Batch arena calibration + LED detection for all experiments.
% Processes per protocol — prompts for number of LEDs and clicks once per protocol.
%
%   For each experiment:
%     1. Extracts background from movie-bg.mat → saves PNG
%     2. Loads arena from movie-calibration.mat → builds quadrant masks → saves PNG
%     3. Detects LED on/off from video (movie.ufmf) → saves LED_detector .mat + PNG
%
% Requires: get_readframe_fcn (JAABA/FlyTracker) on MATLAB path
% Author: Shubham Rathore

clear; clc;

%% Configuration
NETWORK_ROOT = '/Volumes/ReiserLab/Shubham/Projects/Feature learning/2026/board4/videos';
ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

%% Find all protocols
protocol_dirs = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocol_dirs = protocol_dirs([protocol_dirs.isdir]);

nProcessed = 0;
nSkipped = 0;
nFailed = 0;
nTotal = 0;

%% Process each protocol separately
for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);

    % Find experiments in this protocol
    exp_dirs = dir(prot_path);
    % SAFEGUARD: Only process experiment directories (contain '_Rig' in name)
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}) & contains({exp_dirs.name}, '_Rig'));

    if isempty(exp_dirs)
        continue;
    end

    fprintf('\n========================================\n');
    fprintf('PROTOCOL: %s (%d experiments)\n', prot_name, length(exp_dirs));
    fprintf('========================================\n');

    % Ask how many LEDs for this protocol
    num_leds = input(sprintf('  How many LEDs does %s use? (e.g., 1 or 3): ', prot_name));
    fprintf('  Using %d LED(s) for %s\n\n', num_leds, prot_name);

    saved_LED_pos = [];
    saved_calib   = [];

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        exp_name = exp_dirs(e).name;
        nTotal = nTotal + 1;

        fprintf('[%d/%d] %s\n', e, length(exp_dirs), exp_name);

        % Skip if already fully processed (has both arena_calib and LED_detector)
        analysis_subdir = fullfile(exp_path, 'analysis');
        has_calib = exist(analysis_subdir, 'dir') && ~isempty(dir(fullfile(analysis_subdir, 'arena_calib_*.mat')));
        has_led   = exist(analysis_subdir, 'dir') && ~isempty(dir(fullfile(analysis_subdir, 'LED_detector_*.mat')));
        if has_calib && has_led
            fprintf('  Already processed — skipping\n');
            nSkipped = nSkipped + 1;
            continue;
        end

        try
            if isempty(saved_LED_pos)
                % First experiment: click 5 arena points + LED positions
                r = arena_led_pipeline_local(exp_path, NETWORK_ROOT, ...
                    'NumLEDs', num_leds, 'ShowPlots', true);

                saved_LED_pos = r.LED_detector.LED_positions;
                saved_calib   = r.arena_calib;

                % Ask to reuse for remaining in this protocol
                if e < length(exp_dirs)
                    response = input(sprintf('  Reuse clicks for remaining %s experiments? (y/n): ', prot_name), 's');
                    if ~strcmpi(response, 'y')
                        saved_LED_pos = [];
                        saved_calib   = [];
                    end
                end
            else
                % Reuse saved arena calib + LED positions
                r = arena_led_pipeline_local(exp_path, NETWORK_ROOT, ...
                    'NumLEDs', num_leds, ...
                    'SavedLEDPos', saved_LED_pos, ...
                    'SavedCalib', saved_calib, ...
                    'ShowPlots', false);
            end

            fprintf('  ✓ %d ON / %d OFF events\n', ...
                numel(r.LED_detector.on_times), numel(r.LED_detector.off_times));
            nProcessed = nProcessed + 1;

        catch ME
            fprintf('  ✗ Error: %s\n', ME.message);
            nFailed = nFailed + 1;
        end
    end
end

%% Summary
fprintf('\n========================================\n');
fprintf('BATCH PIPELINE SUMMARY\n');
fprintf('========================================\n');
fprintf('Total experiments: %d\n', nTotal);
fprintf('Processed: %d\n', nProcessed);
fprintf('Skipped (already done): %d\n', nSkipped);
fprintf('Failed: %d\n', nFailed);
fprintf('========================================\n');
fprintf('Done: %s\n\n', datestr(now));
