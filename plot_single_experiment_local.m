function plot_single_experiment_local(exp_path)
% PLOT_SINGLE_EXPERIMENT - Generate plots for one experiment
%
% USAGE:
%   plot_single_experiment('/path/to/experiment/folder')
%
% EXAMPLE:
%   plot_single_experiment('/Users/rathores/Documents/2026/AnalysisData/P001/L3A_Rig1_20260225_162932')

    fprintf('\n========================================\n');
    fprintf('SINGLE EXPERIMENT ANALYSIS\n');
    fprintf('========================================\n');
    fprintf('Experiment: %s\n', basename(exp_path));
    fprintf('========================================\n\n');
    
    % Create output directory for plots
    plots_dir = fullfile(exp_path, 'plots');
    if ~exist(plots_dir, 'dir')
        mkdir(plots_dir);
    end
    
    %% Load data
    fprintf('Loading data...\n');
    
    % Load trx
    load(fullfile(exp_path, 'trx.mat'), 'trx');
    fprintf('  Loaded trx: %d flies\n', length(trx));
    
    % Load arena calibration
    analysis_dir = fullfile(exp_path, 'analysis');
    arena_file = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    load(fullfile(analysis_dir, arena_file(1).name), 'arena_calib');
    fprintf('  Loaded arena calibration\n');
    
    % Load LED detector
    led_file = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    load(fullfile(analysis_dir, led_file(1).name), 'LED_detector');
    fprintf('  Loaded LED detector: %d cycles\n', length(LED_detector.on_times));
    
    %% Compute metrics
    fprintf('\nComputing metrics...\n');
    
    % Get calibration
    if isfield(trx, 'pxpermm')
        pixels_per_mm = trx(1).pxpermm;
    else
        pixels_per_mm = 11.54;
    end
    fprintf('  Calibration: %.2f px/mm\n', pixels_per_mm);
    
    % Distance
    distance_matrix = compute_distance_simple(trx, LED_detector, pixels_per_mm);
    fprintf('  Distance computed\n');
    
    % Quadrant preference
    quad_PI = compute_quad_pref_simple(trx, arena_calib.all_masks, LED_detector);
    fprintf('  Quadrant preference computed\n');
    
    %% Generate plots
    fprintf('\nGenerating plots...\n');
    
    % Plot 1: Distance per cycle
    figure('Position', [100 100 1400 600]);
    
    [num_flies, num_cycles] = size(distance_matrix);
    
    hold on;
    boxplot(distance_matrix, 'Colors', [0.5 0.5 0.5], 'Symbol', '');
    
    % Scatter individual flies
    for c = 1:num_cycles
        x_jitter = c + (rand(num_flies, 1) - 0.5) * 0.3;
        scatter(x_jitter, distance_matrix(:, c), 30, [0.3 0.3 0.7], ...
            'filled', 'MarkerFaceAlpha', 0.5);
    end
    
    xlabel('Stimulus Cycle', 'FontSize', 14);
    ylabel('Distance Travelled (mm)', 'FontSize', 14);
    title(sprintf('%s - Distance (n=%d flies)', basename(exp_path), num_flies), ...
        'FontSize', 16, 'Interpreter', 'none');
    grid on; box on;
    
    saveas(gcf, fullfile(plots_dir, 'distance_per_cycle.png'));
    savefig(gcf, fullfile(plots_dir, 'distance_per_cycle.fig'));
    close(gcf);
    fprintf('  Saved: distance_per_cycle.png\n');
    
    % Plot 2: Quadrant preference over time
    figure('Position', [100 100 1400 600]);
    
    mean_qp = nanmean(quad_PI, 1);
    se_qp = nanstd(quad_PI, 0, 1) ./ sqrt(sum(~isnan(quad_PI), 1));
    
    hold on;
    plot([1 num_cycles], [0 0], 'k--', 'LineWidth', 1);
    errorbar(1:num_cycles, mean_qp, se_qp, 'o-', 'LineWidth', 2, ...
        'MarkerSize', 6, 'Color', [0 0.4 0.8], 'MarkerFaceColor', [0 0.5 1]);
    
    xlabel('Stimulus Cycle', 'FontSize', 14);
    ylabel('Quadrant Preference Index', 'FontSize', 14);
    title(sprintf('%s - Quadrant Preference', basename(exp_path)), ...
        'FontSize', 16, 'Interpreter', 'none');
    xlim([0.5 num_cycles+0.5]);
    ylim([-1.2 1.2]);
    grid on; box on;
    
    saveas(gcf, fullfile(plots_dir, 'quadrant_preference.png'));
    savefig(gcf, fullfile(plots_dir, 'quadrant_preference.fig'));
    close(gcf);
    fprintf('  Saved: quadrant_preference.png\n');
    
    fprintf('\n========================================\n');
    fprintf('Complete! Plots saved to:\n');
    fprintf('%s\n', plots_dir);
    fprintf('========================================\n\n');
end

%% Helper functions
function distance_matrix = compute_distance_simple(trx, LED_detector, pixels_per_mm)
    % Simple distance calculation
    
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
            end_frame = LED_detector.off_times(c) - 1;
            
            % Bounds check
            if start_frame > length(frame_dist) || end_frame > length(frame_dist)
                continue;
            end
            
            frames = start_frame:min(end_frame, length(frame_dist));
            distance_matrix(f, c) = nansum(frame_dist(frames));
        end
    end
end

function quad_PI = compute_quad_pref_simple(trx, all_masks, LED_detector)
    % Simple quadrant preference
    
    num_flies = length(trx);
    num_cycles = length(LED_detector.on_times);
    quad_PI = nan(num_flies, num_cycles);
    
    for k = 1:num_flies
        % Map to quadrants
        x_inds = round(trx(k).x);
        y_inds = round(trx(k).y);
        quad = nan(length(x_inds), 1);
        
        for fr = 1:length(x_inds)
            if ~isnan(x_inds(fr)) && ~isnan(y_inds(fr)) && ...
               x_inds(fr) >= 1 && x_inds(fr) <= size(all_masks, 2) && ...
               y_inds(fr) >= 1 && y_inds(fr) <= size(all_masks, 1)
                quad(fr) = all_masks(y_inds(fr), x_inds(fr));
            end
        end
        
        % Compute preference per cycle
        for c = 1:num_cycles
            start_frame = LED_detector.on_times(c);
            end_frame = LED_detector.off_times(c);
            
            if start_frame > length(quad) || end_frame > length(quad)
                continue;
            end
            
            q_slice = quad(start_frame:min(end_frame, length(quad)));
            q_slice = q_slice(~isnan(q_slice) & q_slice > 0);
            
            if ~isempty(q_slice)
                pair1 = sum(q_slice == 1) + sum(q_slice == 3);
                pair2 = sum(q_slice == 2) + sum(q_slice == 4);
                
                if pair1 + pair2 > 0
                    quad_PI(k, c) = (pair1 - pair2) / (pair1 + pair2);
                end
            end
        end
    end
end

function name = basename(path)
    [~, name] = fileparts(path);
end