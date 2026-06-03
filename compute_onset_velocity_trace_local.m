function result = compute_onset_velocity_trace_local(exp_path, varargin)
% COMPUTE_ONSET_VELOCITY_TRACE_LOCAL  Per-frame velocity aligned to LED onset
%
%   result = compute_onset_velocity_trace_local(exp_path)
%   result = compute_onset_velocity_trace_local(exp_path, 'Name', Value, ...)
%
%   For each LED cycle, extracts instantaneous velocity (3-point central
%   difference, mm/s) at every frame in a window around LED onset. All
%   traces are aligned so onset = time 0. Dead flies are excluded using
%   the QPI log (fallback to position-based detection).
%
%   RETURNS
%     result — struct with fields:
%       .experiment      — experiment name (char)
%       .genotype        — e.g. 'L1', 'L3A'
%       .protocol        — e.g. 'P001'
%       .fps             — frames per second
%       .time_vec        — [1 x T] seconds relative to onset (onset = 0)
%       .vel_traces      — [num_flies x T x num_cycles] velocity in mm/s
%                          (NaN for dead flies or out-of-range frames)
%       .fly_alive       — [num_flies x num_cycles] logical
%       .cycle_labels    — {num_cycles x 1} cell of label strings
%       .on_times        — [1 x num_cycles] frame indices of LED onset
%       .off_times       — [1 x num_cycles] frame indices of LED offset
%       .pre_sec         — seconds of pre-onset window used
%       .post_sec        — seconds of post-offset window used
%       .num_flies_total — total flies spanning full recording
%       .num_dead        — flies flagged dead by final cycle
%       .fly_ids_original — original trx indices of retained flies
%
%   NAME-VALUE PARAMETERS
%     'Protocol'          — 'P001' or 'P002' (default: auto-detect)
%     'PixelsPerMM'       — px/mm conversion (read from trx.mat; override with explicit value)
%     'PreOnsetSec'       — seconds before onset to include (default: 5)
%     'PostOffsetSec'     — seconds after LED offset to include (default: 5)
%     'ConsecutiveCycles' — dead fly detection window (default: 3)
%     'MoveThreshPx'      — dead fly pixel threshold (default: 5)

    %% Parse inputs
    p = inputParser;
    addRequired(p, 'exp_path', @ischar);
    addParameter(p, 'Protocol', '', @ischar);
    addParameter(p, 'PixelsPerMM', NaN, @isnumeric);
    addParameter(p, 'PreOnsetSec', 5, @isnumeric);
    addParameter(p, 'PostOffsetSec', 5, @isnumeric);
    addParameter(p, 'ConsecutiveCycles', 3, @isnumeric);
    addParameter(p, 'MoveThreshPx', 5, @isnumeric);
    addParameter(p, 'FlyAlive', [], @(x) islogical(x) || isempty(x));
    parse(p, exp_path, varargin{:});

    opts = p.Results;
    [~, exp_name] = fileparts(exp_path);
    analysis_dir = fullfile(exp_path, 'analysis');
    PRE_SEC  = opts.PreOnsetSec;
    POST_SEC = opts.PostOffsetSec;

    %% Auto-detect protocol
    protocol = opts.Protocol;
    if isempty(protocol)
        [parent_dir, ~] = fileparts(exp_path);
        [~, parent_name] = fileparts(parent_dir);
        if startsWith(parent_name, 'P')
            protocol = parent_name;
        else
            protocol = 'unknown';
        end
    end

    %% Genotype
    tokens = strsplit(exp_name, '_');
    genotype = tokens{1};

    fprintf('Onset velocity trace: %s (geno=%s, prot=%s)\n', exp_name, genotype, protocol);

    %% Protocol labels
    cfg = get_protocol_config(protocol);
    cycle_labels = cfg.labels;

    %% Load trx
    trx_data = load(fullfile(exp_path, 'trx.mat'));
    trx = trx_data.trx;

    % Read px/mm from trx (authoritative source)
    if isnan(opts.PixelsPerMM)
        pixels_per_mm = trx(1).pxpermm;
    else
        pixels_per_mm = opts.PixelsPerMM;
    end

    % Filter flies spanning full recording
    max_end = max([trx.endframe]);
    good = [];
    for k = 1:length(trx)
        if trx(k).firstframe == 1 && trx(k).endframe >= (max_end - 30)
            good = [good, k]; %#ok<AGROW>
        end
    end
    trx = trx(good);
    fly_ids_original = good;
    num_flies = length(trx);

    if num_flies == 0
        warning('No valid flies — skipping %s', exp_name);
        result = [];
        return;
    end

    %% Load LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    if isempty(led_files)
        error('No LED_detector found in %s', analysis_dir);
    end
    led_data = load(fullfile(analysis_dir, led_files(end).name));
    LED = led_data.LED_detector;

    on_times   = LED.on_times;
    off_times  = LED.off_times;
    num_cycles = length(on_times);
    nframes    = length(trx(1).x);

    %% Timestamps
    if isfield(trx(1), 'timestamps') && ~isempty(trx(1).timestamps)
        timestamps = trx(1).timestamps(:)';
    else
        fps = trx(1).fps;
        timestamps = (0:nframes-1) / fps;
    end
    fps = 1 / median(diff(timestamps));

    %% Dead fly status
    fly_alive = load_fly_alive(analysis_dir, num_flies, num_cycles, trx, LED, ...
        'FlyAlive', opts.FlyAlive, ...
        'ConsecutiveCycles', opts.ConsecutiveCycles, 'MoveThreshPx', opts.MoveThreshPx);

    num_dead = sum(~fly_alive(:, end));

    %% Compute per-frame velocity (3-point central difference) in mm/s
    for f = 1:num_flies
        x_mm = trx(f).x / pixels_per_mm;
        y_mm = trx(f).y / pixels_per_mm;
        n_pts = length(x_mm);
        trx(f).frame_vel = NaN(1, n_pts);
        for i = 2:n_pts-1
            x_prev = x_mm(i-1); x_next = x_mm(i+1);
            y_prev = y_mm(i-1); y_next = y_mm(i+1);
            if isnan(x_prev) || isnan(x_next) || isnan(y_prev) || isnan(y_next)
                continue;
            end
            dt3 = timestamps(i+1) - timestamps(i-1);
            if dt3 > 0
                trx(f).frame_vel(i) = sqrt((x_next - x_prev)^2 + ...
                    (y_next - y_prev)^2) / dt3;
            end
        end
    end

    %% Determine common time grid
    % Use the median LED-on duration across all cycles
    led_durations = zeros(1, num_cycles);
    for c = 1:num_cycles
        led_durations(c) = timestamps(min(off_times(c), nframes)) - timestamps(on_times(c));
    end
    median_dur = median(led_durations);

    % Number of frames for each segment
    pre_frames  = round(PRE_SEC * fps);
    led_frames  = round(median_dur * fps);
    post_frames = round(POST_SEC * fps);
    total_frames = pre_frames + led_frames + post_frames + 1;  % +1 for onset frame

    % Time vector relative to onset (onset = 0)
    time_vec = ((0:total_frames-1) - pre_frames) / fps;

    %% Extract aligned velocity traces
    vel_traces = NaN(num_flies, total_frames, num_cycles);

    for f = 1:num_flies
        n_vel = length(trx(f).frame_vel);
        for c = 1:num_cycles
            if ~fly_alive(f, c), continue; end

            fr_on = on_times(c);

            % Frame range to extract
            fr_start = fr_on - pre_frames;
            fr_end   = fr_on + led_frames + post_frames;

            for ti = 1:total_frames
                src_frame = fr_start + (ti - 1);
                if src_frame >= 1 && src_frame <= n_vel
                    vel_traces(f, ti, c) = trx(f).frame_vel(src_frame);
                end
            end
        end
    end

    %% Build output
    result.experiment       = exp_name;
    result.genotype         = genotype;
    result.protocol         = protocol;
    result.fps              = fps;
    result.time_vec         = time_vec;
    result.vel_traces       = vel_traces;
    result.fly_alive        = fly_alive;
    result.cycle_labels     = cycle_labels;
    result.on_times         = on_times;
    result.off_times        = off_times;
    result.pre_sec          = PRE_SEC;
    result.post_sec         = POST_SEC;
    result.led_duration_sec = median_dur;
    result.num_flies_total  = num_flies;
    result.num_dead         = num_dead;
    result.fly_ids_original = fly_ids_original;

    fprintf('  Done: %d cycles, %d alive / %d total, time grid %.1fs to %.1fs (%d frames)\n', ...
        num_cycles, num_flies - num_dead, num_flies, time_vec(1), time_vec(end), total_frames);

end


%% ======== LOCAL HELPERS ========

function fly_alive = parse_qpi_log_ovt(log_file, num_flies, num_cycles, ~)
    fly_alive = true(num_flies, num_cycles);
    try
        fid = fopen(log_file, 'r');
        if fid == -1, fly_alive = []; return; end
        while ~feof(fid)
            line = fgetl(fid);
            if ~ischar(line), continue; end
            tok = regexp(line, 'Fly\s+(\d+)\s+\(trx ID\s+(\d+)\):\s+DEAD from cycle\s+(\d+)', 'tokens');
            if ~isempty(tok)
                fly_idx    = str2double(tok{1}{1});
                dead_cycle = str2double(tok{1}{3});
                if fly_idx >= 1 && fly_idx <= num_flies && ...
                   dead_cycle >= 1 && dead_cycle <= num_cycles
                    fly_alive(fly_idx, dead_cycle:end) = false;
                end
            end
        end
        fclose(fid);
    catch
        fly_alive = [];
    end
end


function fly_alive = detect_dead_flies_ovt(trx, on_times, off_times, ...
    num_flies, num_cycles, nframes, CONSECUTIVE_CYCLES, MOVE_THRESH_PX)
    fly_alive = true(num_flies, num_cycles);
    for k = 1:num_flies
        xk = trx(k).x;
        yk = trx(k).y;
        for w = 1:(num_cycles - CONSECUTIVE_CYCLES + 1)
            fr_start = on_times(w);
            fr_end   = min(off_times(w + CONSECUTIVE_CYCLES - 1), nframes);
            if fr_start > nframes, continue; end
            x_win = xk(fr_start:fr_end);
            y_win = yk(fr_start:fr_end);
            valid = ~isnan(x_win) & ~isnan(y_win);
            if sum(valid) < 10, continue; end
            mx = mean(x_win(valid));
            my = mean(y_win(valid));
            displacements = sqrt((x_win(valid) - mx).^2 + (y_win(valid) - my).^2);
            if max(displacements) < MOVE_THRESH_PX
                fly_alive(k, w:end) = false;
                break;
            end
        end
    end
end


function [labels, colors, sections] = get_protocol_labels_ovt(protocol)
    cfg = get_protocol_config(protocol);
    labels = cfg.labels;
    colors = cfg.colors;
    sections = cfg.sections;
end
