function summary = compute_speed_per_cycle_local(exp_path, varargin)
% COMPUTE_SPEED_PER_CYCLE_LOCAL  Per-fly speed (mm/s) for each LED cycle
%
%   summary = compute_speed_per_cycle_local(exp_path)
%   summary = compute_speed_per_cycle_local(exp_path, 'Name', Value, ...)
%
%   For each LED cycle, computes instantaneous speed (mm/s) per fly in a
%   window from PRE_ONSET_SEC before LED onset through LED offset.
%   Speed = euclidean frame-to-frame distance (mm) * fps.
%   Applies moving-average smoothing (default 0.5 s).
%
%   Uses QPI log for dead fly status (falls back to internal detection).
%
%   RETURNS
%     summary — struct with fields:
%       .experiment       — experiment name (char)
%       .genotype         — genotype shorthand (e.g., 'L2A')
%       .protocol         — protocol name (e.g., 'P008')
%       .pixels_per_mm    — conversion factor used
%       .fps              — frames per second (30.1)
%       .pre_onset_sec    — seconds before LED onset included
%       .smooth_win_sec   — moving average window (seconds)
%       .num_flies_total  — total flies spanning full recording
%       .num_dead         — number flagged dead by end
%       .fly_ids_original — original trx indices of retained flies
%       .fly_alive        — [num_flies x num_cycles] logical
%       .cycles           — struct array with per-cycle data:
%           .cycle_num, .label, .t_axis, .fr_on, .fr_off, .fr_start,
%           .fr_end, .alive_fly_ids, .speed_matrix (rows=alive flies,
%           cols=time), .mean_speed, .sem_speed, .n_alive
%
%   NAME-VALUE PARAMETERS
%     'Protocol'          — 'P001', 'P002', etc. (default: auto-detect)
%     'PixelsPerMM'       — px/mm conversion (read from trx.mat; override with explicit value)
%     'FPS'               — frames per second (default: 30.1)
%     'PreOnsetSec'       — seconds before LED onset (default: 10)
%     'SmoothWinSec'      — smoothing window in seconds (default: 0.5)
%     'ConsecutiveCycles' — dead fly detection window (default: 3)
%     'MoveThreshPx'      — dead fly pixel threshold (default: 5)

    %% Parse inputs
    p = inputParser;
    addRequired(p, 'exp_path', @ischar);
    addParameter(p, 'Protocol', '', @ischar);
    addParameter(p, 'PixelsPerMM', NaN, @isnumeric);
    addParameter(p, 'FPS', 30.1, @isnumeric);
    addParameter(p, 'PreOnsetSec', 10, @isnumeric);
    addParameter(p, 'SmoothWinSec', 0, @isnumeric);
    addParameter(p, 'ConsecutiveCycles', 3, @isnumeric);
    addParameter(p, 'MoveThreshPx', 5, @isnumeric);
    addParameter(p, 'FlyAlive', [], @(x) islogical(x) || isempty(x));
    parse(p, exp_path, varargin{:});

    opts = p.Results;
    [~, exp_name] = fileparts(exp_path);
    analysis_dir  = fullfile(exp_path, 'analysis');
    FPS           = opts.FPS;
    PRE_ONSET_SEC = opts.PreOnsetSec;
    PRE_ONSET_FR  = round(PRE_ONSET_SEC * FPS);
    SMOOTH_WIN_SEC = opts.SmoothWinSec;
    smooth_win    = round(SMOOTH_WIN_SEC * FPS);
    CONSECUTIVE_CYCLES = opts.ConsecutiveCycles;
    MOVE_THRESH_PX     = opts.MoveThreshPx;

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

    %% Extract genotype from experiment name
    tokens = strsplit(exp_name, '_');
    genotype = tokens{1};

    %% Get protocol labels
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

    fprintf('Speed: %s (genotype=%s, protocol=%s, px/mm=%.2f)\n', ...
        exp_name, genotype, protocol, pixels_per_mm);

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
        summary = [];
        return;
    end

    nframes = length(trx(1).x);

    %% Load LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    if isempty(led_files)
        error('No LED_detector found in %s', analysis_dir);
    end
    led_data = load(fullfile(analysis_dir, led_files(end).name));
    LED = led_data.LED_detector;
    on_times  = LED.on_times;
    off_times = LED.off_times;
    num_cycles = length(on_times);

    %% Dead fly status
    fly_alive = load_fly_alive(analysis_dir, num_flies, num_cycles, trx, LED, ...
        'FlyAlive', opts.FlyAlive, ...
        'ConsecutiveCycles', CONSECUTIVE_CYCLES, 'MoveThreshPx', MOVE_THRESH_PX);

    num_dead = sum(~fly_alive(:, end));
    fprintf('  Flies: %d total, %d dead, %d alive at end\n', ...
        num_flies, num_dead, num_flies - num_dead);

    %% Precompute per-fly frame-to-frame speed (mm/s)
    speed_all = NaN(num_flies, nframes - 1);
    for f = 1:num_flies
        dx = diff(trx(f).x) / pixels_per_mm;  % mm
        dy = diff(trx(f).y) / pixels_per_mm;  % mm
        dist_per_frame = sqrt(dx.^2 + dy.^2);  % mm per frame
        speed_all(f, :) = dist_per_frame * FPS; % mm/s
    end

    %% Filter out OM cycles
    om_mask = false(num_cycles, 1);
    for c = 1:num_cycles
        if c <= length(cycle_labels)
            lbl = cycle_labels{c};
            if strcmp(lbl, 'OM1') || strcmp(lbl, 'OM2')
                om_mask(c) = true;
            end
        end
    end
    keep_cycles = find(~om_mask);
    num_keep = length(keep_cycles);

    %% Build per-cycle speed data
    cycles_out = struct();
    for ci = 1:num_keep
        c = keep_cycles(ci);
        fr_on  = on_times(c);
        fr_off = min(off_times(c), nframes);

        fr_start = max(1, fr_on - PRE_ONSET_FR);
        fr_end   = min(fr_off, nframes - 1);

        if fr_start >= fr_end
            continue;
        end

        frames = fr_start:fr_end;
        n_fr = length(frames);
        t_axis = (frames - fr_on) / FPS;

        if c <= length(cycle_labels)
            lbl = cycle_labels{c};
        else
            lbl = sprintf('C%d', c);
        end

        % Collect smoothed speed for alive flies
        alive_mask = fly_alive(:, c);
        n_alive = sum(alive_mask);
        speed_matrix = NaN(n_alive, n_fr);
        alive_fly_ids = [];

        ai = 0;
        for f = 1:num_flies
            if ~alive_mask(f), continue; end
            ai = ai + 1;
            spd = speed_all(f, frames);
            if smooth_win > 1
                spd = movmean(spd, smooth_win, 'omitnan');
            end
            speed_matrix(ai, :) = spd;
            alive_fly_ids(ai) = fly_ids_original(f); %#ok<AGROW>
        end

        cycles_out(ci).cycle_num     = c;
        cycles_out(ci).label         = lbl;
        cycles_out(ci).t_axis        = t_axis;
        cycles_out(ci).fr_on         = fr_on;
        cycles_out(ci).fr_off        = fr_off;
        cycles_out(ci).fr_start      = fr_start;
        cycles_out(ci).fr_end        = fr_end;
        cycles_out(ci).alive_fly_ids = alive_fly_ids;
        cycles_out(ci).speed_matrix  = speed_matrix;
        cycles_out(ci).mean_speed    = mean(speed_matrix, 1, 'omitnan');
        cycles_out(ci).sem_speed     = std(speed_matrix, 0, 1, 'omitnan') / sqrt(max(n_alive, 1));
        cycles_out(ci).n_alive       = n_alive;
    end

    %% Build summary struct
    summary.experiment       = exp_name;
    summary.exp_path         = exp_path;
    summary.genotype         = genotype;
    summary.protocol         = protocol;
    summary.pixels_per_mm    = pixels_per_mm;
    summary.fps              = FPS;
    summary.pre_onset_sec    = PRE_ONSET_SEC;
    summary.smooth_win_sec   = SMOOTH_WIN_SEC;
    summary.num_flies_total  = num_flies;
    summary.num_dead         = num_dead;
    summary.fly_ids_original = fly_ids_original;
    summary.fly_alive        = fly_alive;
    summary.num_cycles_total = num_cycles;
    summary.num_cycles_kept  = num_keep;
    summary.cycle_labels_all = cycle_labels;
    summary.cycles           = cycles_out;

    %% Save .mat
    mat_file = fullfile(analysis_dir, sprintf('speed_%s.mat', exp_name));
    save(mat_file, '-struct', 'summary');
    fprintf('  Saved: %s\n', mat_file);
end


%% ======== LOCAL HELPERS ========

function [labels, colors, sections] = get_protocol_labels_speed(protocol)
    cfg = get_protocol_config(protocol);
    labels = cfg.labels;
    colors = cfg.colors;
    sections = cfg.sections;
end
