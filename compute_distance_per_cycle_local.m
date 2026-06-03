function summary = compute_distance_per_cycle_local(exp_path, varargin)
% COMPUTE_DISTANCE_PER_CYCLE_LOCAL  Distance per fly per LED cycle
%
%   summary = compute_distance_per_cycle_local(exp_path)
%   summary = compute_distance_per_cycle_local(exp_path, 'Name', Value, ...)
%
%   Loads trx.mat and LED_detector; reads the QPI log file to determine
%   which flies are alive per cycle (falls back to internal dead fly
%   detection if the log is not found). Computes frame-to-frame distance
%   (mm) per fly per LED cycle using only alive flies.
%
%   RETURNS
%     summary — struct with fields:
%       .experiment        — experiment name (char)
%       .genotype          — genotype shorthand, e.g. 'L1', 'L3A'
%       .protocol          — protocol name, e.g. 'P001'
%       .num_flies_total   — total flies spanning full recording
%       .num_dead          — number flagged dead by end
%       .fly_ids_original  — original trx indices of retained flies
%       .pixels_per_mm     — conversion factor used
%       .distance_per_fly  — [num_flies x num_cycles] distance in mm
%                            (NaN for dead fly-cycle pairs)
%       .cycle_table       — table with per-cycle summaries:
%           cycle, label, n_flies_alive, mean_dist_mm, sem_dist_mm
%
%   NAME-VALUE PARAMETERS
%     'Protocol'         — 'P001' or 'P002' (default: auto-detect)
%     'PixelsPerMM'      — px/mm conversion (read from trx.mat; override with explicit value)
%     'ConsecutiveCycles' — dead fly detection window (default: 3)
%     'MoveThreshPx'     — dead fly pixel threshold (default: 5)

    %% Parse inputs
    p = inputParser;
    addRequired(p, 'exp_path', @ischar);
    addParameter(p, 'Protocol', '', @ischar);
    addParameter(p, 'PixelsPerMM', NaN, @isnumeric);
    addParameter(p, 'ConsecutiveCycles', 3, @isnumeric);
    addParameter(p, 'MoveThreshPx', 5, @isnumeric);
    addParameter(p, 'FlyAlive', [], @(x) islogical(x) || isempty(x));
    parse(p, exp_path, varargin{:});

    opts = p.Results;
    [~, exp_name] = fileparts(exp_path);
    analysis_dir = fullfile(exp_path, 'analysis');

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

    %% Extract genotype from experiment name (e.g., L3A_Rig1_20260225_162932)
    tokens = strsplit(exp_name, '_');
    genotype = tokens{1};

    fprintf('Distance: %s (genotype=%s, protocol=%s)\n', exp_name, genotype, protocol);

    %% Get protocol config (centralized)
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
        summary = [];
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

    %% Dead fly status
    fly_alive = load_fly_alive(analysis_dir, num_flies, num_cycles, trx, LED, ...
        'FlyAlive', opts.FlyAlive, ...
        'ConsecutiveCycles', CONSECUTIVE_CYCLES, 'MoveThreshPx', MOVE_THRESH_PX);

    num_dead = sum(~fly_alive(:, end));
    fprintf('  Flies: %d total, %d dead, %d alive at end\n', ...
        num_flies, num_dead, num_flies - num_dead);

    %% Compute distance per fly per cycle
    %  Same logic as compute_distance_travelled.m:
    %    1. Convert x,y to mm
    %    2. frame_distance = sqrt(diff(x_mm)^2 + diff(y_mm)^2)
    %    3. distance = nansum(frame_distance) over LED-on frames
    %  Memory-efficient: frame_distance is a local variable per fly,
    %  not stored on the trx struct.

    distance_per_fly = NaN(num_flies, num_cycles);

    for f = 1:num_flies
        % Frame-to-frame distance in mm (local variable — not on trx struct)
        dx = diff(trx(f).x) / pixels_per_mm;
        dy = diff(trx(f).y) / pixels_per_mm;
        frame_distance = sqrt(dx.^2 + dy.^2);

        for c = 1:num_cycles
            if ~fly_alive(f, c), continue; end

            frames = on_times(c):min(off_times(c)-1, length(frame_distance));
            if ~isempty(frames)
                distance_per_fly(f, c) = sum(frame_distance(frames), 'omitnan');
            end
        end
    end

    %% Build per-cycle summary table
    cycle_num         = (1:num_cycles)';
    label             = cell(num_cycles, 1);
    n_flies_alive     = zeros(num_cycles, 1);
    mean_dist_mm      = NaN(num_cycles, 1);
    sem_dist_mm       = NaN(num_cycles, 1);

    for c = 1:num_cycles
        if c <= length(cycle_labels)
            label{c} = cycle_labels{c};
        else
            label{c} = sprintf('C%d', c);
        end

        alive_mask = fly_alive(:, c);
        n_alive = sum(alive_mask);
        n_flies_alive(c) = n_alive;

        if n_alive > 0
            d_vals = distance_per_fly(alive_mask, c);
            d_valid = d_vals(~isnan(d_vals));
            if ~isempty(d_valid)
                mean_dist_mm(c) = mean(d_valid);
                sem_dist_mm(c)  = std(d_valid) / sqrt(max(length(d_valid), 1));
            end
        end
    end

    cycle_table = table(cycle_num, label, n_flies_alive, ...
        mean_dist_mm, sem_dist_mm, ...
        'VariableNames', {'cycle', 'label', 'n_flies_alive', ...
            'mean_dist_mm', 'sem_dist_mm'});

    %% Build output summary
    summary.experiment       = exp_name;
    summary.genotype         = genotype;
    summary.protocol         = protocol;
    summary.num_flies_total  = num_flies;
    summary.num_dead         = num_dead;
    summary.fly_ids_original = fly_ids_original;
    summary.pixels_per_mm    = pixels_per_mm;
    summary.distance_per_fly = distance_per_fly;
    summary.cycle_table      = cycle_table;

    fprintf('  Done: %d cycles, %d alive / %d total\n', ...
        num_cycles, num_flies - num_dead, num_flies);

    %% Save summary as .mat
    if ~exist(analysis_dir, 'dir')
        mkdir(analysis_dir);
    end
    mat_file = fullfile(analysis_dir, sprintf('distance_%s.mat', exp_name));
    save(mat_file, '-struct', 'summary');
    fprintf('  Saved distance data: %s\n', mat_file);

end

%% ======== LOCAL HELPERS ========

function fly_alive = parse_qpi_log(log_file, num_flies, num_cycles, fly_ids_original)
% PARSE_QPI_LOG  Extract per-fly alive status from QPI log file
%
%   Parses lines like:
%     "Fly  2 (trx ID 3): DEAD from cycle 5 ..."
%   to build a [num_flies x num_cycles] logical alive matrix.

    fly_alive = true(num_flies, num_cycles);

    try
        fid = fopen(log_file, 'r');
        if fid == -1
            fly_alive = [];
            return;
        end

        while ~feof(fid)
            line = fgetl(fid);
            if ~ischar(line), continue; end

            % Match: "Fly  X (trx ID Y): DEAD from cycle Z"
            tok = regexp(line, 'Fly\s+(\d+)\s+\(trx ID\s+(\d+)\):\s+DEAD from cycle\s+(\d+)', 'tokens');
            if ~isempty(tok)
                fly_idx    = str2double(tok{1}{1});  % local fly index
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


function fly_alive = detect_dead_flies(trx, on_times, off_times, ...
    num_flies, num_cycles, nframes, CONSECUTIVE_CYCLES, MOVE_THRESH_PX)
% DETECT_DEAD_FLIES  Position-based dead fly detection
%   Same logic as plot_quadrant_preference_local.m

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


function [labels, colors, sections] = get_protocol_labels_dist(protocol)
    cfg = get_protocol_config(protocol);
    labels = cfg.labels;
    colors = cfg.colors;
    sections = cfg.sections;
end
