%% plot_quad_pref_framewise.m
% Continuous QPI with LED intensity labels

clear; clc;

% Set experiment
exp_path = '/Users/rathores/Documents/analysisdatalocal/P001/L3A_Rig1_20260226_132927';

fprintf('Plotting: %s\n\n', basename(exp_path));

%% Load and filter trx
load(fullfile(exp_path, 'trx.mat'), 'trx');

max_end = max([trx.endframe]);
good = [];
for k = 1:length(trx)
    if trx(k).firstframe == 1 && trx(k).endframe >= (max_end - 30)
        good = [good, k];
    end
end
trx = trx(good);
fprintf('Using %d flies\n', length(trx));

%% Load preprocessing
analysis_dir = fullfile(exp_path, 'analysis');

arena_file = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
arena_data = load(fullfile(analysis_dir, arena_file(1).name));
if isfield(arena_data, 'ac')
    all_masks = arena_data.ac.all_masks;
else
    all_masks = arena_data.arena_calib.all_masks;
end

led_file = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
led_data = load(fullfile(analysis_dir, led_file(1).name));
if isfield(led_data, 'ld')
    LED = led_data.ld;
else
    LED = led_data.LED_detector;
end

fprintf('LED cycles: %d\n\n', length(LED.on_times));

%% Map to quadrants and compute frame-wise QPI
num_flies = length(trx);
nframes = length(trx(1).x);

quad_counts = zeros(nframes, 5);

for k = 1:num_flies
    x_inds = round(trx(k).x);
    y_inds = round(trx(k).y);
    
    for fr = 1:length(x_inds)
        if ~isnan(x_inds(fr)) && ~isnan(y_inds(fr)) && ...
           x_inds(fr) >= 1 && x_inds(fr) <= size(all_masks, 2) && ...
           y_inds(fr) >= 1 && y_inds(fr) <= size(all_masks, 1)
            q = all_masks(y_inds(fr), x_inds(fr));
            quad_counts(fr, q + 1) = quad_counts(fr, q + 1) + 1;
        end
    end
end

% QPI = (Q1+Q3 - Q2+Q4) / (Q1+Q3 + Q2+Q4)
pair1 = quad_counts(:,2) + quad_counts(:,4);  % Q1 + Q3
pair2 = quad_counts(:,3) + quad_counts(:,5);  % Q2 + Q4
quad_pref = (pair1 - pair2) ./ (pair1 + pair2);

timestamps = trx(1).timestamps;

%% Define LED intensity pattern
% Pattern: 1,1,5,5,10,10,20,20,30,30,40,40,50,50 (14 cycles per color)
% Repeats 3 times (R, G, B)
intensity_pattern = [1,1,5,5,10,10,20,20,30,30,40,40,50,50];
num_cycles = length(LED.on_times);

% Repeat for 3 colors
led_intensities = repmat(intensity_pattern, 1, ceil(num_cycles/14));
led_intensities = led_intensities(1:num_cycles);  % Trim to actual cycles

% Define colors (R, G, B blocks)
color_labels = cell(num_cycles, 1);
for c = 1:num_cycles
    if c <= 14
        color_labels{c} = 'R';
    elseif c <= 28
        color_labels{c} = 'G';
    elseif c <= 42
        color_labels{c} = 'B';
    else
        color_labels{c} = '';
    end
end

%% Plot
figure('Position', [100 100 1600 700]);

hold on;

% LED ON/OFF shading with intensity labels
for c = 1:num_cycles
    on_time = timestamps(LED.on_times(c));
    off_time = timestamps(LED.off_times(c));
    
    % Alternate shading
    if mod(c, 2) == 1
        y_shade = [0, 1.2];
        shade_color = [0.95 0.95 0.95];
    else
        y_shade = [-1.2, 0];
        shade_color = [0.92 0.92 0.92];
    end
    
    patch([on_time off_time off_time on_time], ...
          [y_shade(1) y_shade(1) y_shade(2) y_shade(2)], ...
          shade_color, 'EdgeColor', 'none');
    
    % ON/OFF lines
    plot([on_time on_time], [-1.2 1.2], 'b-', 'LineWidth', 0.5);
    plot([off_time off_time], [-1.2 1.2], 'm-', 'LineWidth', 0.5);
    
    % Intensity label at top
    mid_time = (on_time + off_time) / 2;
    intensity_text = sprintf('%s%d', color_labels{c}, led_intensities(c));
    
    text(mid_time, 1.15, intensity_text, ...
        'HorizontalAlignment', 'center', ...
        'FontSize', 9, ...
        'FontWeight', 'bold', ...
        'Color', 'k');
end

% Zero line
plot([timestamps(1) timestamps(end)], [0 0], 'k--', 'LineWidth', 1);

% Plot continuous QPI
plot(timestamps, quad_pref, 'Color', [0 0.5 0], 'LineWidth', 2.5);

xlabel('Time (s)', 'FontSize', 14);
ylabel('Quadrant Preference Index', 'FontSize', 14);
title(sprintf('%s - Continuous QPI (n=%d flies)', basename(exp_path), num_flies), ...
    'FontSize', 16, 'Interpreter', 'none');
ylim([-1.3 1.3]);
grid on; box on;

% Add color block labels
text(timestamps(LED.on_times(7)), 1.28, 'RED', 'FontSize', 11, 'FontWeight', 'bold', 'Color', 'r', 'HorizontalAlignment', 'center');
if num_cycles > 14
    text(timestamps(LED.on_times(21)), 1.28, 'GREEN', 'FontSize', 11, 'FontWeight', 'bold', 'Color', [0 0.6 0], 'HorizontalAlignment', 'center');
end
if num_cycles > 28
    text(timestamps(LED.on_times(35)), 1.28, 'BLUE', 'FontSize', 11, 'FontWeight', 'bold', 'Color', 'b', 'HorizontalAlignment', 'center');
end

saveas(gcf, fullfile(exp_path, 'quadrant_preference_continuous.png'));
savefig(gcf, fullfile(exp_path, 'quadrant_preference_continuous.fig'));
close(gcf);

fprintf('\nSaved: quadrant_preference_continuous.png\n\n');

function name = basename(path)
    [~, name] = fileparts(path);
end