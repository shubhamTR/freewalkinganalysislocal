%% quick_plot.m
% Simple plotting with fly filtering

clear; clc;

% Set your experiment path
exp_path = '/Users/rathores/Documents/analysisdatalocal/P001/L3A_Rig1_20260225_162932';

%% Load data
fprintf('Loading %s...\n', basename(exp_path));
load(fullfile(exp_path, 'trx.mat'), 'trx');

fprintf('Original: %d flies\n', length(trx));

%% REMOVE INCOMPLETE FLIES
max_endframe = max([trx.endframe]);
fprintf('Video has %d total frames\n', max_endframe);

TOLERANCE = 30;
min_acceptable_end = max_endframe - TOLERANCE;

good_flies = [];
bad_flies = [];

for k = 1:length(trx)
    if trx(k).firstframe == 1 && trx(k).endframe >= min_acceptable_end
        good_flies = [good_flies, k];
    else
        bad_flies = [bad_flies, k];
        fprintf('  Removing Fly %d: frames %d-%d\n', k, trx(k).firstframe, trx(k).endframe);
    end
end

trx = trx(good_flies);
fprintf('After filtering: %d flies\n\n', length(trx));

%% Load arena (FIXED - make sure it loads properly)
analysis_dir = fullfile(exp_path, 'analysis');
arena_file = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));

if isempty(arena_file)
    fprintf('No arena calibration found - skipping trajectory plot\n');
    skip_trajectory_plot = true;
else
    arena_data = load(fullfile(analysis_dir, arena_file(1).name));
    
    % Extract arena_calib from the loaded structure
    if isfield(arena_data, 'arena_calib')
        arena_calib = arena_data.arena_calib;
        skip_trajectory_plot = false;
    elseif isfield(arena_data, 'saved_calib')
        arena_calib = arena_data.saved_calib;
        skip_trajectory_plot = false;
    else
        fprintf('Arena calibration structure not found - skipping trajectory plot\n');
        skip_trajectory_plot = true;
    end
end

%% Load LED
led_file = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
if ~isempty(led_file)
    led_data = load(fullfile(analysis_dir, led_file(1).name));
    if isfield(led_data, 'LED_detector')
        LED_detector = led_data.LED_detector;
    else
        LED_detector = led_data;
    end
    fprintf('Loaded LED: %d cycles\n\n', length(LED_detector.on_times));
end

%% Plot 1: Distance
fprintf('Generating distance plot...\n');

if ~isempty(led_file)
    pixels_per_mm = trx(1).pxpermm;
    num_flies = length(trx);
    num_cycles = length(LED_detector.on_times);
    distance_matrix = nan(num_flies, num_cycles);
    
    for f = 1:num_flies
        x_mm = trx(f).x / pixels_per_mm;
        y_mm = trx(f).y / pixels_per_mm;
        dx = diff(x_mm);
        dy = diff(y_mm);
        frame_dist = sqrt(dx.^2 + dy.^2);
        
        for c = 1:num_cycles
            start_frame = LED_detector.on_times(c);
            end_frame = min(LED_detector.off_times(c) - 1, length(frame_dist));
            
            if start_frame <= length(frame_dist)
                frames = start_frame:end_frame;
                distance_matrix(f, c) = nansum(frame_dist(frames));
            end
        end
    end
    
    % Plot
    figure('Position', [100 100 1400 600]);
    hold on;
    boxplot(distance_matrix, 'Colors', [0.5 0.5 0.5], 'Symbol', '');
    
    for c = 1:num_cycles
        x_jitter = c + (rand(num_flies, 1) - 0.5) * 0.3;
        scatter(x_jitter, distance_matrix(:, c), 30, [0.3 0.3 0.7], 'filled', 'MarkerFaceAlpha', 0.5);
    end
    
    xlabel('Stimulus Cycle', 'FontSize', 14);
    ylabel('Distance (mm)', 'FontSize', 14);
    title(sprintf('%s (n=%d)', basename(exp_path), num_flies), 'FontSize', 16, 'Interpreter', 'none');
    grid on; box on;
    
    saveas(gcf, fullfile(exp_path, 'distance_plot.png'));
    close(gcf);
    fprintf('  Saved: distance_plot.png\n');
end

%% Plot 2: Trajectories
if ~skip_trajectory_plot
    fprintf('Generating trajectory plot...\n');
    
    figure('Position', [100 100 800 800]);
    colors = lines(length(trx));
    
    for k = 1:length(trx)
        plot(trx(k).x_mm, trx(k).y_mm, 'Color', colors(k,:), 'LineWidth', 1);
        hold on;
    end
    
    % Arena circle
    theta = linspace(0, 2*pi, 360);
    xc_mm = arena_calib.xc / trx(1).pxpermm;
    yc_mm = arena_calib.yc / trx(1).pxpermm;
    r_mm = arena_calib.radius / trx(1).pxpermm;
    plot(xc_mm + r_mm*cos(theta), yc_mm + r_mm*sin(theta), 'k-', 'LineWidth', 2);
    
    axis equal;
    xlabel('X (mm)'); ylabel('Y (mm)');
    title(basename(exp_path), 'Interpreter', 'none');
    grid on;
    
    saveas(gcf, fullfile(exp_path, 'trajectories.png'));
    close(gcf);
    fprintf('  Saved: trajectories.png\n');
end

fprintf('\nDone!\n');

function name = basename(path)
    [~, name] = fileparts(path);
end