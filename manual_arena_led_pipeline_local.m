function results = manual_arena_led_pipeline_local(exp_path)
% DEPRECATED — Use arena_led_pipeline_local() instead.
%   This function is kept for backward compatibility only.
%   arena_led_pipeline_local(exp_path, network_root) does the same thing
%   with more options (SavedCalib, SavedLEDPos, NumLEDs, per-step skip).
%
% MANUAL_ARENA_LED_PIPELINE - Manual 5-point calibration for one experiment
    warning('manual_arena_led_pipeline_local:deprecated', ...
        'DEPRECATED: Use arena_led_pipeline_local() instead.');
    
    fprintf('=== MANUAL ARENA CALIBRATION ===\n');
    fprintf('Experiment: %s\n\n', basename(exp_path));
    
    % Create analysis directory
    analysis_dir = fullfile(exp_path, 'analysis');
    if ~exist(analysis_dir, 'dir')
        mkdir(analysis_dir);
    end
    
    run_timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    
    %% Load background
    fprintf('Loading background image...\n');
    
    bg_file = fullfile(exp_path, 'movie-bg.mat');
    bg_data = load(bg_file);
    if isfield(bg_data, 'bg') && isfield(bg_data.bg, 'bg_mean')
        backimg = bg_data.bg.bg_mean;
    elseif isfield(bg_data, 'bg_mean')
        backimg = bg_data.bg_mean;
    end
    
    imwrite(backimg, fullfile(analysis_dir, 'background.png'));
    
    %% Manual 5-point calibration
    fprintf('Click 5 points: Top, Right, Bottom, Left, Center\n\n');
    
    figure('Name', 'Arena Calibration', 'Position', [100 100 1000 1000]);
    imshow(backimg);
    imagesc(backimg);
    axis image;
    hold on;
    
    title('Click 5 points: Top, Right, Bottom, Left intersections, then Center');
    [pts_x, pts_y] = ginput(5);
    
    % Plot points
    plot(pts_x, pts_y, 'ro', 'MarkerSize', 12, 'LineWidth', 2);
    text(pts_x(1), pts_y(1), ' Top', 'Color', 'yellow', 'FontSize', 12);
    text(pts_x(2), pts_y(2), ' Right', 'Color', 'yellow', 'FontSize', 12);
    text(pts_x(3), pts_y(3), ' Bottom', 'Color', 'yellow', 'FontSize', 12);
    text(pts_x(4), pts_y(4), ' Left', 'Color', 'yellow', 'FontSize', 12);
    text(pts_x(5), pts_y(5), ' Center', 'Color', 'yellow', 'FontSize', 12);
    
    % Extract coordinates
    top_x = pts_x(1);    top_y = pts_y(1);
    right_x = pts_x(2);  right_y = pts_y(2);
    bottom_x = pts_x(3); bottom_y = pts_y(3);
    left_x = pts_x(4);   left_y = pts_y(4);
    center_x = pts_x(5); center_y = pts_y(5);
    
    % Fit circle to edge points
    [xc, yc, radius] = fit_circle_to_points_local(pts_x(1:4), pts_y(1:4));
    
    fprintf('Fitted circle: center=(%.1f, %.1f), radius=%.1f px\n', xc, yc, radius);
    
    % Plot circle
    theta = linspace(0, 2*pi, 360);
    plot(xc + radius*cos(theta), yc + radius*sin(theta), 'r-', 'LineWidth', 3);
    plot(xc, yc, 'r+', 'MarkerSize', 20, 'LineWidth', 3);
    
    % Fit lines
    vert_x = [top_x; center_x; bottom_x];
    vert_y = [top_y; center_y; bottom_y];
    vert_line_coef = polyfit(vert_y, vert_x, 1);
    
    horiz_x = [left_x; center_x; right_x];
    horiz_y = [left_y; center_y; right_y];
    horiz_line_coef = polyfit(horiz_x, horiz_y, 1);
    
    % Plot lines
    y_span = linspace(1, size(backimg, 1), 200);
    x_vert = polyval(vert_line_coef, y_span);
    plot(x_vert, y_span, 'g-', 'LineWidth', 2);
    
    x_span = linspace(1, size(backimg, 2), 200);
    y_horiz = polyval(horiz_line_coef, x_span);
    plot(x_span, y_horiz, 'g-', 'LineWidth', 2);
    
    title(sprintf('Manual Fit: center=(%.0f,%.0f) r=%.0f px', xc, yc, radius));
    
    %% Generate masks
    [h, w] = size(backimg);
    [X, Y] = meshgrid(1:w, 1:h);
    
    circle_mask = ((X - xc).^2 + (Y - yc).^2) <= radius^2;
    
    vert_x_fit = vert_line_coef(1) * Y + vert_line_coef(2);
    right_of_vert = X >= vert_x_fit;
    
    horiz_y_fit = horiz_line_coef(1) * X + horiz_line_coef(2);
    below_horiz = Y >= horiz_y_fit;
    
    Q1 = circle_mask & right_of_vert & ~below_horiz;
    Q2 = circle_mask & ~right_of_vert & ~below_horiz;
    Q3 = circle_mask & ~right_of_vert & below_horiz;
    Q4 = circle_mask & right_of_vert & below_horiz;
    outside_mask = ~circle_mask;
    
    all_masks = zeros(h, w);
    all_masks(Q1) = 1;
    all_masks(Q2) = 2;
    all_masks(Q3) = 3;
    all_masks(Q4) = 4;
    
    % Visualize
    figure('Name', 'Quadrant Masks');
    subplot(2,3,1); imshow(circle_mask); title('Circle');
    subplot(2,3,2); imshow(Q1); title('Q1');
    subplot(2,3,3); imshow(Q2); title('Q2');
    subplot(2,3,4); imshow(Q3); title('Q3');
    subplot(2,3,5); imshow(Q4); title('Q4');
    subplot(2,3,6); imagesc(all_masks); axis image; colormap(jet); colorbar; title('All');
    
    %% Save arena calibration
    arena_calib = struct();
    arena_calib.source = 'manual_5point';
    arena_calib.xc = xc;
    arena_calib.yc = yc;
    arena_calib.radius = radius;
    arena_calib.vert_line_coef = vert_line_coef;
    arena_calib.horiz_line_coef = horiz_line_coef;
    arena_calib.calibration_points = struct(...
        'top', [top_x, top_y], ...
        'right', [right_x, right_y], ...
        'bottom', [bottom_x, bottom_y], ...
        'left', [left_x, left_y], ...
        'center', [center_x, center_y]);
    arena_calib.all_masks = all_masks;
    arena_calib.Q1 = Q1;
    arena_calib.Q2 = Q2;
    arena_calib.Q3 = Q3;
    arena_calib.Q4 = Q4;
    arena_calib.circle_mask = circle_mask;
    
    mask_file = fullfile(analysis_dir, sprintf('arena_calib_%s.mat', run_timestamp));
    save(mask_file, 'arena_calib');
    
    %% LED detection from video
    fprintf('Detecting LED timing from video...\n');

    network_root = '/Volumes/ReiserLab/Shubham/Projects/2026/Feature learning/Board4';
    LED_detector = detect_LED_from_video(exp_path, network_root, ...
        'NumLEDs', 3, 'ShowPlots', true, 'SaveResults', false);

    led_file = fullfile(analysis_dir, sprintf('LED_detector_%s.mat', run_timestamp));
    save(led_file, 'LED_detector');
    fprintf('  Found %d stimulus cycles\n', length(LED_detector.on_times));
    
    %% Return results
    results = struct();
    results.arena_calib = arena_calib;
    results.LED_detector = LED_detector;
    results.analysis_dir = analysis_dir;
    results.run_timestamp = run_timestamp;
end

function results = apply_saved_calibration(exp_path, saved_calib)
    % Apply saved calibration to new experiment (no clicking)
    
    % Create analysis directory
    analysis_dir = fullfile(exp_path, 'analysis');
    if ~exist(analysis_dir, 'dir')
        mkdir(analysis_dir);
    end
    
    run_timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    
    % Load background for this experiment
    bg_file = fullfile(exp_path, 'movie-bg.mat');
    bg_data = load(bg_file);
    if isfield(bg_data, 'bg') && isfield(bg_data.bg, 'bg_mean')
        backimg = bg_data.bg.bg_mean;
    elseif isfield(bg_data, 'bg_mean')
        backimg = bg_data.bg_mean;
    end
    
    % Apply saved calibration parameters to generate masks
    xc = saved_calib.xc;
    yc = saved_calib.yc;
    radius = saved_calib.radius;
    vert_line_coef = saved_calib.vert_line_coef;
    horiz_line_coef = saved_calib.horiz_line_coef;
    
    [h, w] = size(backimg);
    [X, Y] = meshgrid(1:w, 1:h);
    
    circle_mask = ((X - xc).^2 + (Y - yc).^2) <= radius^2;
    
    vert_x_fit = vert_line_coef(1) * Y + vert_line_coef(2);
    right_of_vert = X >= vert_x_fit;
    
    horiz_y_fit = horiz_line_coef(1) * X + horiz_line_coef(2);
    below_horiz = Y >= horiz_y_fit;
    
    Q1 = circle_mask & right_of_vert & ~below_horiz;
    Q2 = circle_mask & ~right_of_vert & ~below_horiz;
    Q3 = circle_mask & ~right_of_vert & below_horiz;
    Q4 = circle_mask & right_of_vert & below_horiz;
    
    all_masks = zeros(h, w);
    all_masks(Q1) = 1;
    all_masks(Q2) = 2;
    all_masks(Q3) = 3;
    all_masks(Q4) = 4;
    
    % Create new arena_calib for this experiment
    arena_calib = saved_calib;
    arena_calib.all_masks = all_masks;
    arena_calib.Q1 = Q1;
    arena_calib.Q2 = Q2;
    arena_calib.Q3 = Q3;
    arena_calib.Q4 = Q4;
    arena_calib.circle_mask = circle_mask;
    
    % Save
    mask_file = fullfile(analysis_dir, sprintf('arena_calib_%s.mat', run_timestamp));
    save(mask_file, 'arena_calib');
    
    % LED detection from video
    network_root = '/Volumes/ReiserLab/Shubham/Projects/2026/Feature learning/Board4';
    LED_detector = detect_LED_from_video(exp_path, network_root, ...
        'NumLEDs', 3, 'ShowPlots', false, 'SaveResults', false);

    led_file = fullfile(analysis_dir, sprintf('LED_detector_%s.mat', run_timestamp));
    save(led_file, 'LED_detector');

    % Return
    results = struct();
    results.arena_calib = arena_calib;
    results.LED_detector = LED_detector;
    results.analysis_dir = analysis_dir;
    results.run_timestamp = run_timestamp;
end

function name = basename(path)
    [~, name] = fileparts(path);
end