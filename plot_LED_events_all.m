%% plot_LED_events_all.m
% Generate LED on/off event plots for all experiments that already have
% LED_detector_*.mat files. Does NOT re-process videos.
%
% Author: Shubham Rathore

clear; clc;

%% Configuration
ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

%% Find all experiment folders
protocol_dirs = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocol_dirs = protocol_dirs([protocol_dirs.isdir]);

nPlotted = 0;
nSkipped = 0;

for p = 1:length(protocol_dirs)
    prot_path = fullfile(ANALYSIS_DIR, protocol_dirs(p).name);
    exp_dirs = dir(prot_path);
    % SAFEGUARD: Only process experiment directories (contain '_Rig' in name)
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}) & contains({exp_dirs.name}, '_Rig')]);

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        exp_name = exp_dirs(e).name;
        analysis_subdir = fullfile(exp_path, 'analysis');

        % Find LED_detector file
        led_files = dir(fullfile(analysis_subdir, 'LED_detector_*.mat'));
        if isempty(led_files)
            fprintf('[SKIP] No LED data: %s\n', exp_name);
            nSkipped = nSkipped + 1;
            continue;
        end

        % Load the most recent one
        [~, idx] = sort({led_files.name});
        led_file = fullfile(analysis_subdir, led_files(idx(end)).name);
        data = load(led_file);
        det = data.LED_detector;

        % Extract fields
        LED_state = det.LED_state;
        on_times  = det.on_times;
        off_times = det.off_times;
        nframes   = numel(LED_state);
        frames    = 1:nframes;

        % Plot
        fig = figure('Name', sprintf('LED Events: %s', exp_name), ...
            'Position', [100 100 1200 400]);

        plot(frames, LED_state, '.', 'Color', [0.7 0.7 0.7], 'MarkerSize', 4);
        hold on;
        plot(frames(on_times),  LED_state(on_times),  '.g', 'MarkerSize', 20);
        plot(frames(off_times), LED_state(off_times), '.r', 'MarkerSize', 20);
        xlabel('Frame Number');
        ylabel('LED ON (1) / OFF (0)');
        title(sprintf('LED ON/OFF Events — %s  (%d ON, %d OFF)', ...
            strrep(exp_name, '_', '\_'), numel(on_times), numel(off_times)));
        legend({'LED state', 'ON', 'OFF'}, 'Location', 'best');
        ylim([-0.1 1.1]);

        % Save figure
        fig_file = fullfile(analysis_subdir, sprintf('LED_events_%s.png', exp_name));
        saveas(fig, fig_file);
        close(fig);

        fprintf('[OK] %s — %d ON / %d OFF\n', exp_name, numel(on_times), numel(off_times));
        nPlotted = nPlotted + 1;
    end
end

%% Summary
fprintf('\n========================================\n');
fprintf('Plotted: %d experiments\n', nPlotted);
fprintf('Skipped: %d (no LED data)\n', nSkipped);
fprintf('========================================\n');
