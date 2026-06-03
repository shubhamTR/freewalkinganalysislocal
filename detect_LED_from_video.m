function LED_detector = detect_LED_from_video(exp_path, network_root, varargin)
% DETECT_LED_FROM_VIDEO  Detect LED on/off cycles from video frames
%
%   LED_detector = detect_LED_from_video(exp_path, network_root)
%   LED_detector = detect_LED_from_video(exp_path, network_root, 'Name', Value, ...)
%
%   Reads the original .ufmf video from the network, extracts LED patch
%   intensities frame-by-frame, thresholds to binary, and detects on/off
%   transitions. Based on LED_detection_v5.m but wrapped as a reusable
%   function with saved LED positions for batch processing.
%
%   INPUTS
%     exp_path      — local experiment folder (e.g., analysisdatalocal/P001/L3A_Rig1_...)
%     network_root  — network path to video root
%                     (e.g., '/Volumes/ReiserLab/Shubham/Projects/Feature learning/2026/board4/videos')
%
%   NAME-VALUE PARAMETERS
%     'NumLEDs'         — number of LEDs to detect (default: 3)
%                         P001 uses 3 LEDs, P002 uses 1 LED
%     'PatchRadius'     — pixel radius for LED intensity patches (default: 10)
%     'VideoFilename'   — name of video file to look for (default: 'movie.ufmf')
%     'SavedLEDPos'     — [Nx2] matrix of saved LED positions [x1 y1; ...]
%                         If empty, user will be prompted to click NumLEDs positions.
%                         (default: [])
%     'ShowPlots'       — display diagnostic plots (default: true)
%     'SaveResults'     — save LED_detector .mat to analysis subfolder (default: true)
%
%   OUTPUT
%     LED_detector  — struct containing:
%       .LED_intensity_combined — [nframes x 3] mean patch intensity per LED
%       .LED_state              — [nframes x 1] binary LED state (OR of all 3)
%       .on_times               — frame indices where LED turns ON
%       .off_times              — frame indices where LED turns OFF
%       .transition_frames      — all transition frame indices
%       .LED_positions          — [3x2] LED pixel positions used
%       .patch_radius           — patch radius used
%       .nframes                — total number of frames
%       .source_video           — path to the video file used
%
%   USAGE
%     % Single experiment with manual LED clicking:
%     det = detect_LED_from_video('/path/to/exp', '/Volumes/ReiserLab/...');
%
%     % Batch: click once, reuse positions for rest:
%     det1 = detect_LED_from_video(exp1, netroot);
%     det2 = detect_LED_from_video(exp2, netroot, 'SavedLEDPos', det1.LED_positions);

    %% Parse inputs
    p = inputParser;
    addRequired(p, 'exp_path', @ischar);
    addRequired(p, 'network_root', @ischar);
    addParameter(p, 'NumLEDs', 3, @isnumeric);
    addParameter(p, 'PatchRadius', 10, @isnumeric);
    addParameter(p, 'VideoFilename', 'movie.ufmf', @ischar);
    addParameter(p, 'SavedLEDPos', [], @isnumeric);
    addParameter(p, 'ShowPlots', true, @islogical);
    addParameter(p, 'SaveResults', true, @islogical);
    parse(p, exp_path, network_root, varargin{:});

    opts = p.Results;
    num_leds = opts.NumLEDs;

    %% Locate the original video on the network
    % Read copy_metadata.txt to find the original folder name
    meta_file = fullfile(exp_path, 'copy_metadata.txt');
    if exist(meta_file, 'file')
        meta_text = fileread(meta_file);
        % Extract original folder name from metadata
        tokens = regexp(meta_text, 'Original Folder:\s*(\S+)', 'tokens');
        if ~isempty(tokens)
            original_folder = tokens{1}{1};
        else
            error('Could not parse Original Folder from copy_metadata.txt');
        end
    else
        % Fallback: try to reconstruct from experiment folder name
        % Folder format: Genotype_Rig_YYYYMMDD_HHMMSS
        [~, exp_name] = fileparts(exp_path);
        warning('No copy_metadata.txt found. Using folder name: %s', exp_name);
        original_folder = exp_name;
    end

    % Search for the video file recursively in the original network folder
    network_exp_path = fullfile(network_root, original_folder);
    if ~exist(network_exp_path, 'dir')
        % Also search in Rig subfolders
        rig_folders = dir(fullfile(network_root, 'Rig*'));
        found = false;
        for r = 1:length(rig_folders)
            candidate = fullfile(network_root, rig_folders(r).name, original_folder);
            if exist(candidate, 'dir')
                network_exp_path = candidate;
                found = true;
                break;
            end
        end
        if ~found
            error('Cannot find original experiment folder on network: %s', original_folder);
        end
    end

    % Find video file recursively
    video_matches = dir(fullfile(network_exp_path, '**', opts.VideoFilename));
    if isempty(video_matches)
        error('No %s found in %s', opts.VideoFilename, network_exp_path);
    end
    video_path = fullfile(video_matches(1).folder, video_matches(1).name);
    fprintf('Video found: %s\n', video_path);

    %% Load background image for LED position selection
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

    %% Get LED positions (click or reuse saved)
    if isempty(opts.SavedLEDPos)
        % Interactive: show background and click LED positions
        figure('Name', 'LED Position Selection', 'Position', [100 100 800 800]);
        imagesc(bg_img); axis image; colormap('gray'); hold on;
        title(sprintf('Click on the center of each of the %d LED(s)', num_leds));
        [LED_x, LED_y] = ginput(num_leds);
        plot(LED_x, LED_y, 'ro', 'MarkerSize', 12, 'LineWidth', 2);
        LED_positions = [LED_x(:), LED_y(:)];
        for k = 1:num_leds
            fprintf('  LED %d: [%.1f, %.1f]\n', k, LED_positions(k,1), LED_positions(k,2));
        end
    else
        LED_positions = opts.SavedLEDPos;
        num_leds = size(LED_positions, 1);  % match saved positions
        fprintf('Using saved LED positions (%d LEDs)\n', num_leds);
    end

    %% Build patch coordinate ranges
    patch_radius = opts.PatchRadius;
    LED_x_range = cell(1, num_leds);
    LED_y_range = cell(1, num_leds);
    for i = 1:num_leds
        LED_x_range{i} = round(LED_positions(i,1)) + (-patch_radius:patch_radius);
        LED_y_range{i} = round(LED_positions(i,2)) + (-patch_radius:patch_radius);
    end

    %% Read video and extract LED intensities frame-by-frame
    % Temporarily add JAABA to path for get_readframe_fcn (UFMF reader)
    jaaba_path = '/Users/rathores/Documents/MATLAB/JAABA';
    jaaba_added = false;
    if exist(jaaba_path, 'dir')
        addpath(genpath(jaaba_path));
        jaaba_added = true;
    end

    fprintf('Opening video: %s\n', video_path);
    [readframe, nframes, ~, ~] = get_readframe_fcn(video_path);
    fprintf('Total frames: %d\n', nframes);

    LED_intensity_combined = zeros(nframes, num_leds);

    fprintf('Extracting LED intensities (%d LEDs)...\n', num_leds);
    report_interval = round(nframes / 10);

    for fr_ind = 1:nframes
        curr_frame = readframe(fr_ind);

        for i = 1:num_leds
            LED_patch = double(curr_frame(LED_y_range{i}, LED_x_range{i}));
            LED_intensity_combined(fr_ind, i) = mean(LED_patch(:));
        end

        if mod(fr_ind, report_interval) == 0
            fprintf('  %d/%d frames (%.0f%%)\n', fr_ind, nframes, 100*fr_ind/nframes);
        end
    end
    fprintf('Intensity extraction complete.\n');

    % Remove JAABA from path (prevents savefig conflict in later analysis)
    if jaaba_added
        rmpath(genpath(jaaba_path));
    end

    %% Threshold: mean-subtract and binarize
    LED_intensity_thresh = LED_intensity_combined - ...
        repmat(mean(LED_intensity_combined), nframes, 1) > 0;

    % Combine into single binary state (OR across all LEDs)
    LED_state = any(LED_intensity_thresh, 2);

    %% Detect transitions
    transition_frames = find(abs(diff(LED_state)) > 0);
    on_times  = find(diff(LED_state) ==  1) + 1;
    off_times = find(diff(LED_state) == -1) + 1;

    % Clip to valid range
    max_frame = length(LED_state);
    on_times(on_times > max_frame) = [];
    off_times(off_times > max_frame) = [];

    fprintf('Detected %d ON events, %d OFF events\n', numel(on_times), numel(off_times));

    %% Plot LED on/off events and save figure
    [~, exp_name] = fileparts(exp_path);

    fig = figure('Name', sprintf('LED Events: %s', exp_name), ...
        'Position', [100 100 1200 400]);

    frames = 1:nframes;
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

    % Save figure to analysis folder
    analysis_dir = fullfile(exp_path, 'analysis');
    if ~exist(analysis_dir, 'dir')
        mkdir(analysis_dir);
    end
    fig_file = fullfile(analysis_dir, sprintf('LED_events_%s.png', exp_name));
    saveas(fig, fig_file);
    fprintf('Figure saved: %s\n', fig_file);

    if ~opts.ShowPlots
        close(fig);
    end

    %% Build output struct
    LED_detector = struct();
    LED_detector.LED_intensity_combined = LED_intensity_combined;
    LED_detector.LED_state              = LED_state;
    LED_detector.on_times               = on_times;
    LED_detector.off_times              = off_times;
    LED_detector.transition_frames      = transition_frames;
    LED_detector.LED_positions          = LED_positions;
    LED_detector.patch_radius           = patch_radius;
    LED_detector.nframes                = nframes;
    LED_detector.num_leds               = num_leds;
    LED_detector.source_video           = video_path;
    LED_detector.source                 = 'video_threshold';

    %% Save results
    if opts.SaveResults
        analysis_dir = fullfile(exp_path, 'analysis');
        if ~exist(analysis_dir, 'dir')
            mkdir(analysis_dir);
        end

        timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        save_file = fullfile(analysis_dir, sprintf('LED_detector_%s.mat', timestamp));
        save(save_file, 'LED_detector');
        fprintf('Saved: %s\n', save_file);
    end

end
