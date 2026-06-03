function results = arena_led_pipeline_local(exp_path, network_root, varargin)
% ARENA_LED_PIPELINE  Background → Arena mask → LED detection (FlyTracker)
%
%   results = arena_led_pipeline(exp_path, network_root)
%   results = arena_led_pipeline(exp_path, network_root, 'Name', Value, ...)
%
%   Full preprocessing pipeline for a single FlyTracker experiment:
%     Step 1: Load background image from movie-bg.mat, save as PNG
%     Step 2: Load arena calibration from movie-calibration.mat,
%             build quadrant masks, save mask overlay as PNG
%     Step 3: Detect LED on/off events from video (movie.ufmf)
%
%   All outputs are saved into an analysis subfolder within the experiment.
%
%   INPUTS
%     exp_path      — local experiment folder
%                     (e.g., '/Users/rathores/Documents/analysisdatalocal/P001/L3A_Rig1_...')
%     network_root  — network path to video root
%                     (e.g., '/Volumes/ReiserLab/Shubham/Projects/Feature learning/2026/board4/videos')
%
%   NAME-VALUE PARAMETERS
%     'NumLEDs'         — number of LEDs to detect (default: 3)
%     'SavedLEDPos'     — [Nx2] saved LED positions to skip clicking (default: [])
%     'SavedCalib'      — saved arena_calib struct to reuse (default: [])
%     'AngleDeg'        — rotation of quadrant dividers in degrees (default: 0)
%     'PatchRadius'     — LED patch radius in pixels (default: 10)
%     'ShowPlots'       — keep figures open (default: true)
%
%   OUTPUT
%     results — struct containing:
%       .arena_calib   — arena calibration (center, radius, quadrant masks)
%       .LED_detector  — LED detection (state, on/off times, intensities)
%       .analysis_dir  — path where files were saved
%       .run_timestamp — timestamp string for this run
%
%   EXAMPLES
%     % Full pipeline — click LEDs on first call:
%     r = arena_led_pipeline(exp_path, netroot, 'NumLEDs', 3);
%
%     % Reuse LED positions from a previous run:
%     r2 = arena_led_pipeline(exp_path2, netroot, ...
%           'SavedLEDPos', r.LED_detector.LED_positions);

    %% Parse inputs
    p = inputParser;
    addRequired(p, 'exp_path', @ischar);
    addRequired(p, 'network_root', @ischar);
    addParameter(p, 'NumLEDs', 3, @isnumeric);
    addParameter(p, 'SavedLEDPos', [], @isnumeric);
    addParameter(p, 'SavedCalib', [], @(x) isempty(x) || isstruct(x));
    addParameter(p, 'AngleDeg', 0, @isnumeric);
    addParameter(p, 'PatchRadius', 10, @isnumeric);
    addParameter(p, 'ShowPlots', true, @islogical);
    parse(p, exp_path, network_root, varargin{:});

    opts = p.Results;
    [~, exp_name] = fileparts(exp_path);

    % Analysis directory
    analysis_dir = fullfile(exp_path, 'analysis');

    %% Check what already exists — skip per step
    existing_bg    = dir(fullfile(analysis_dir, sprintf('background_%s.png', exp_name)));
    existing_calib = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    existing_led   = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));

    skip_bg  = ~isempty(existing_bg);
    skip_cal = ~isempty(existing_calib);
    skip_led = ~isempty(existing_led);

    % If everything exists, skip entirely and return loaded results
    if skip_bg && skip_cal && skip_led
        fprintf('SKIP: %s — all outputs already exist\n', exp_name);
        tmp = load(fullfile(existing_led(end).folder, existing_led(end).name), 'LED_detector');
        results.LED_detector = tmp.LED_detector;
        tmp2 = load(fullfile(existing_calib(end).folder, existing_calib(end).name), 'arena_calib');
        results.arena_calib = tmp2.arena_calib;
        results.analysis_dir  = analysis_dir;
        results.run_timestamp = '';
        results.skipped       = true;
        return;
    end

    % Shared timestamp for all saved files
    run_timestamp = datestr(now, 'yyyymmdd_HHMMSS');

    % Create analysis directory
    if ~exist(analysis_dir, 'dir')
        mkdir(analysis_dir);
    end

    fprintf('\n========================================\n');
    fprintf('ARENA + LED PIPELINE: %s\n', exp_name);
    fprintf('========================================\n');

    %% STEP 1: Load background image from movie-bg.mat
    % Always load bg_img (needed for Step 2 mask building)
    bg_file = fullfile(exp_path, 'movie-bg.mat');
    if ~exist(bg_file, 'file')
        error('movie-bg.mat not found in %s', exp_path);
    end

    bg_data = load(bg_file);
    if isfield(bg_data, 'bg') && isfield(bg_data.bg, 'bg_mean')
        bg_img = bg_data.bg.bg_mean;
    elseif isfield(bg_data, 'bg_mean')
        bg_img = bg_data.bg_mean;
    else
        error('Cannot find bg_mean in movie-bg.mat');
    end

    if skip_bg
        bg_png = fullfile(analysis_dir, existing_bg(end).name);
        fprintf('Step 1: SKIP — background PNG already exists\n');
    else
        fprintf('\n=== STEP 1: Background Image ===\n');
        bg_img_norm = uint8(255 * mat2gray(bg_img));
        bg_png = fullfile(analysis_dir, sprintf('background_%s.png', exp_name));
        imwrite(bg_img_norm, bg_png);
        fprintf('Background saved: %s\n', bg_png);
    end

    %% STEP 2: Arena calibration + quadrant masks
    if skip_cal
        fprintf('Step 2: SKIP — arena_calib already exists\n');
        tmp_cal = load(fullfile(existing_calib(end).folder, existing_calib(end).name), 'arena_calib');
        arena_calib = tmp_cal.arena_calib;
        calib_save = fullfile(existing_calib(end).folder, existing_calib(end).name);
    else
        fprintf('\n=== STEP 2: Arena Calibration ===\n');

        [h, w] = size(bg_img);

        if ~isempty(opts.SavedCalib)
            % ---- Reuse saved calibration ----
            arena_calib = opts.SavedCalib;
            xc     = arena_calib.xc;
            yc     = arena_calib.yc;
            radius = arena_calib.radius;
            vert_coef  = arena_calib.vert_coef;
            horiz_coef = arena_calib.horiz_coef;
            circle_mask = arena_calib.circle_mask;
            fprintf('Using saved calibration: center=(%.1f,%.1f) r=%.1f\n', xc, yc, radius);

            % Rebuild quadrant masks at this image size
            [X, Y] = meshgrid(1:w, 1:h);
            right_of_vert = X >= (vert_coef(1)*Y + vert_coef(2));
            below_horiz   = Y >= (horiz_coef(1)*X + horiz_coef(2));
        else
            % ---- Manual 5-point clicking (from quadrant_masks_from_image) ----
            fig_click = figure('Name', sprintf('Arena Calibration: %s', exp_name));
            imagesc(bg_img); axis image; colormap('gray'); hold on;
            title('Click 5 points: Top, Right, Bottom, Left rim + Center');

            [pts_x, pts_y] = ginput(5);

            % Points: 1=Top, 2=Right, 3=Bottom, 4=Left, 5=Center
            center_x = pts_x(5);
            center_y = pts_y(5);

            % Fit circle to the 4 rim points
            [xc, yc, radius] = fit_circle_to_points_local(pts_x(1:4), pts_y(1:4));

            % Plot fitted circle and center
            theta = linspace(0, 2*pi, 360);
            plot(xc + radius*cos(theta), yc + radius*sin(theta), 'r-', 'LineWidth', 2);
            plot(center_x, center_y, 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');

            % Fit vertical line through top, center, bottom
            vert_coef  = polyfit([pts_y(1); center_y; pts_y(3)], ...
                                 [pts_x(1); center_x; pts_x(3)], 1);

            % Fit horizontal line through left, center, right
            horiz_coef = polyfit([pts_x(4); center_x; pts_x(2)], ...
                                 [pts_y(4); center_y; pts_y(2)], 1);

            % Plot fitted lines
            y_span = linspace(1, h, 200);
            plot(polyval(vert_coef, y_span), y_span, 'g-', 'LineWidth', 2);
            x_span = linspace(1, w, 200);
            plot(x_span, polyval(horiz_coef, x_span), 'g-', 'LineWidth', 2);
            title(sprintf('Arena: center=(%.0f,%.0f) r=%.0f', xc, yc, radius));

            fprintf('Circle fit: center=(%.1f,%.1f) r=%.1f px\n', xc, yc, radius);

            if ~opts.ShowPlots
                close(fig_click);
            end

            % Circle mask from fitted circle
            [X, Y] = meshgrid(1:w, 1:h);
            circle_mask = ((X - xc).^2 + (Y - yc).^2) <= radius^2;

            % Which side of each line
            right_of_vert = X >= (vert_coef(1)*Y + vert_coef(2));
            below_horiz   = Y >= (horiz_coef(1)*X + horiz_coef(2));
        end

        % Build quadrant masks
        Q1 = circle_mask &  right_of_vert & ~below_horiz;  % Top-Right
        Q2 = circle_mask & ~right_of_vert & ~below_horiz;  % Top-Left
        Q3 = circle_mask & ~right_of_vert &  below_horiz;  % Bottom-Left
        Q4 = circle_mask &  right_of_vert &  below_horiz;  % Bottom-Right

        all_masks = zeros(h, w);
        all_masks(Q1) = 1;
        all_masks(Q2) = 2;
        all_masks(Q3) = 3;
        all_masks(Q4) = 4;

        % Build arena_calib struct
        arena_calib.source      = 'manual 5-point click';
        arena_calib.xc          = xc;
        arena_calib.yc          = yc;
        arena_calib.radius      = radius;
        arena_calib.vert_coef   = vert_coef;
        arena_calib.horiz_coef  = horiz_coef;
        arena_calib.angle_deg   = opts.AngleDeg;
        arena_calib.all_masks   = all_masks;
        arena_calib.Q1          = Q1;
        arena_calib.Q2          = Q2;
        arena_calib.Q3          = Q3;
        arena_calib.Q4          = Q4;
        arena_calib.circle_mask = circle_mask;

        % Save arena calibration .mat
        calib_save = fullfile(analysis_dir, sprintf('arena_calib_%s.mat', run_timestamp));
        save(calib_save, 'arena_calib');
        fprintf('Arena calibration saved: %s\n', calib_save);

        % Create and save mask overlay image as PNG
        fig_mask = figure('Name', sprintf('Quadrant Masks: %s', exp_name), ...
            'Position', [100 100 1000 500]);

        subplot(1,2,1);
        imagesc(bg_img); axis image; colormap('gray'); hold on;
        theta = linspace(0, 2*pi, 360);
        plot(xc + radius*cos(theta), yc + radius*sin(theta), 'r-', 'LineWidth', 2);
        plot(xc, yc, 'r+', 'MarkerSize', 14, 'LineWidth', 2);
        y_span = linspace(1, h, 200);
        plot(polyval(vert_coef, y_span), y_span, 'g-', 'LineWidth', 1.5);
        x_span = linspace(1, w, 200);
        plot(x_span, polyval(horiz_coef, x_span), 'g-', 'LineWidth', 1.5);
        title(sprintf('Arena: center=(%.0f,%.0f) r=%.0f', xc, yc, radius));

        subplot(1,2,2);
        imagesc(all_masks); axis image;
        colormap(gca, [0 0 0; 1 0 0; 0 1 0; 0 0 1; 1 1 0]);
        colorbar('Ticks', [0 1 2 3 4], 'TickLabels', {'Outside','Q1-TR','Q2-TL','Q3-BL','Q4-BR'});
        title('Quadrant Masks');

        sgtitle(strrep(exp_name, '_', '\_'));

        mask_png = fullfile(analysis_dir, sprintf('quadrant_masks_%s.png', exp_name));
        saveas(fig_mask, mask_png);
        savefig(fig_mask, strrep(mask_png, '.png', '.fig'));
        fprintf('Mask image saved: %s\n', mask_png);

        if ~opts.ShowPlots
            close(fig_mask);
        end
    end

    %% STEP 3: LED detection from video
    if skip_led
        fprintf('Step 3: SKIP — LED_detector already exists\n');
        tmp_led = load(fullfile(existing_led(end).folder, existing_led(end).name), 'LED_detector');
        LED_detector = tmp_led.LED_detector;
    else
        fprintf('\n=== STEP 3: LED Detection (from video) ===\n');

        LED_detector = detect_LED_from_video(exp_path, network_root, ...
            'NumLEDs',      opts.NumLEDs, ...
            'SavedLEDPos',  opts.SavedLEDPos, ...
            'PatchRadius',  opts.PatchRadius, ...
            'ShowPlots',    opts.ShowPlots, ...
            'SaveResults',  true);
    end

    %% SUMMARY
    fprintf('\n========================================\n');
    fprintf('PIPELINE COMPLETE: %s\n', exp_name);
    fprintf('========================================\n');
    fprintf('  Background   : %s\n', bg_png);
    fprintf('  Arena calib  : %s\n', calib_save);
    if ~skip_led
        fprintf('  LED events   : %d ON / %d OFF\n', numel(LED_detector.on_times), numel(LED_detector.off_times));
    else
        fprintf('  LED events   : (loaded from existing file)\n');
    end
    fprintf('  Timestamp    : %s\n', run_timestamp);
    fprintf('========================================\n\n');

    % Return results
    results.arena_calib   = arena_calib;
    results.LED_detector  = LED_detector;
    results.analysis_dir  = analysis_dir;
    results.run_timestamp = run_timestamp;
    results.skipped       = false;

end
