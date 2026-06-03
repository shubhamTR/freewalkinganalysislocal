%% LED_tracker_single.m
% Run full arena + LED pipeline on a single experiment with fresh clicks.
% Use this when an experiment has different background/LED positions
% than the rest of its protocol group.
%
% Requires: get_readframe_fcn (JAABA/FlyTracker) on MATLAB path
% Author: Shubham Rathore

clear; clc;

%% Configuration
NETWORK_ROOT = '/Volumes/ReiserLab/Shubham/Projects/Feature learning/2026/board4/videos';
ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

%% Select experiment
% Set the protocol and experiment folder name here
protocol    = 'P002';
exp_name    = 'L3A_Rig1_20260315_130019';

% Number of LEDs for this experiment
num_leds    = 1;

%% Run
exp_path = fullfile(ANALYSIS_DIR, protocol, exp_name);

if ~exist(exp_path, 'dir')
    error('Experiment folder not found: %s', exp_path);
end

fprintf('Experiment: %s/%s\n', protocol, exp_name);
fprintf('LEDs: %d\n\n', num_leds);

% Delete existing analysis files for this experiment (clean slate)
analysis_subdir = fullfile(exp_path, 'analysis');
if exist(analysis_subdir, 'dir')
    old_files = [dir(fullfile(analysis_subdir, 'LED_detector_*.mat')); ...
                 dir(fullfile(analysis_subdir, 'LED_events_*.png')); ...
                 dir(fullfile(analysis_subdir, 'arena_calib_*.mat')); ...
                 dir(fullfile(analysis_subdir, 'quadrant_masks_*.png')); ...
                 dir(fullfile(analysis_subdir, 'background_*.png'))];
    for f = 1:length(old_files)
        delete(fullfile(analysis_subdir, old_files(f).name));
        fprintf('Deleted old: %s\n', old_files(f).name);
    end
end

% Run full pipeline — will prompt for LED position clicks
r = arena_led_pipeline_local(exp_path, NETWORK_ROOT, ...
    'NumLEDs', num_leds, 'ShowPlots', true);

fprintf('\n========================================\n');
fprintf('RESULT: %s/%s\n', protocol, exp_name);
fprintf('  LEDs: %d\n', r.LED_detector.num_leds);
fprintf('  Frames: %d\n', r.LED_detector.nframes);
fprintf('  ON events: %d\n', numel(r.LED_detector.on_times));
fprintf('  OFF events: %d\n', numel(r.LED_detector.off_times));
fprintf('  Arena center: (%.0f, %.0f), radius: %.0f px\n', ...
    r.arena_calib.xc, r.arena_calib.yc, r.arena_calib.radius);
fprintf('========================================\n');
fprintf('Done: %s\n\n', datestr(now));
