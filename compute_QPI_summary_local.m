function summary = compute_QPI_summary_local(exp_path, varargin)
% COMPUTE_QPI_SUMMARY_LOCAL  Per-cycle mean QPI (first/last half) for one experiment
%
%   summary = compute_QPI_summary_local(exp_path)
%   summary = compute_QPI_summary_local(exp_path, 'Name', Value, ...)
%
%   Loads trx, arena_calib, LED_detector; applies dead fly removal;
%   computes mean QPI for the first and second half of each LED cycle.
%   Cycle duration is determined from LED on/off times, so this works
%   for any protocol regardless of trial length.
%
%   RETURNS
%     summary — struct with fields:
%       .experiment     — experiment name (char)
%       .genotype       — genotype shorthand, e.g. 'L1', 'L3A' (char)
%       .protocol       — protocol name, e.g. 'P001' (char)
%       .num_flies_total— total flies spanning full recording
%       .cycle_table    — table with one row per cycle:
%           cycle, label, n_flies, mean_QPI_firsthalf, mean_QPI_secondhalf
%
%   NAME-VALUE PARAMETERS
%     'Protocol'         — 'P001' or 'P002' (default: auto-detect)
%     'ConsecutiveCycles'— dead fly detection window (default: 3)
%     'MoveThreshPx'     — dead fly pixel threshold (default: 5)

    %% Parse inputs
    p = inputParser;
    addRequired(p, 'exp_path', @ischar);
    addParameter(p, 'Protocol', '', @ischar);
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

    %% Extract genotype from experiment name
    % Format: L3A_Rig1_20260225_162932 -> genotype = L3A
    tokens = strsplit(exp_name, '_');
    genotype = tokens{1};  % e.g., 'L1', 'L2A', 'L3A'

    fprintf('QPI summary: %s (genotype=%s, protocol=%s)\n', exp_name, genotype, protocol);

    %% Get protocol config
    cfg = get_protocol_config(protocol);
    cycle_labels = cfg.labels;

    % Quad patterns: use training_patterns so probes resolve to the paired
    % training LED pattern (critical for P017/P019 where safe quad varies).
    [metadata_patterns, metadata_training] = parse_metadata_led_patterns(exp_path);
    if ~isempty(metadata_training)
        quad_patterns = metadata_training;
    elseif ~isempty(metadata_patterns)
        quad_patterns = metadata_patterns;
    else
        quad_patterns = cfg.quad_patterns;
    end

    % Detect single-quadrant mode (P013, P017)
    is_single_quadrant = isfield(cfg, 'led_to_quad') && ~isempty(cfg.led_to_quad);

    %% Load data
    trx_data = load(fullfile(exp_path, 'trx.mat'));
    trx = trx_data.trx;

    % Filter flies spanning full recording
    max_end = max([trx.endframe]);
    good = [];
    for k = 1:length(trx)
        if trx(k).firstframe == 1 && trx(k).endframe >= (max_end - 30)
            good = [good, k]; %#ok<AGROW>
        end
    end
    trx = trx(good);
    num_flies = length(trx);

    % Arena calibration
    arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    arena_data  = load(fullfile(analysis_dir, arena_files(end).name));
    all_masks   = arena_data.arena_calib.all_masks;

    % LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    led_data  = load(fullfile(analysis_dir, led_files(end).name));
    LED       = led_data.LED_detector;

    on_times   = LED.on_times;
    off_times  = LED.off_times;
    num_cycles = length(on_times);
    nframes    = length(trx(1).x);

    %% Time axis
    if isfield(trx(1), 'timestamps') && ~isempty(trx(1).timestamps)
        timestamps = trx(1).timestamps(:)';
    else
        fps = trx(1).fps;
        timestamps = (0:nframes-1) / fps;
    end

    %% Map flies to quadrants per frame
    fly_quad = compute_fly_quad(trx, all_masks);

    %% Dead fly status
    fly_alive = load_fly_alive(analysis_dir, num_flies, num_cycles, trx, LED, ...
        'FlyAlive', opts.FlyAlive, ...
        'ConsecutiveCycles', CONSECUTIVE_CYCLES, 'MoveThreshPx', MOVE_THRESH_PX);

    %% Compute per-frame QPI using only alive flies (per-cycle basis)
    % Map frame -> cycle
    frame_cycle = zeros(1, nframes);
    for c = 1:num_cycles
        fr_start = on_times(c);
        fr_end   = min(off_times(c), nframes);
        if fr_start <= nframes
            frame_cycle(fr_start:fr_end) = c;
        end
    end

    % Quadrant counts with dead fly removal
    quad_counts_clean = zeros(nframes, 5);
    for k = 1:num_flies
        for fr = 1:nframes
            c = frame_cycle(fr);
            if c == 0
                if fr < on_times(1)
                    c_ref = 1;
                else
                    c_ref = find(on_times <= fr, 1, 'last');
                    if isempty(c_ref), c_ref = 1; end
                end
                if ~fly_alive(k, c_ref), continue; end
            else
                if ~fly_alive(k, c), continue; end
            end
            q = fly_quad(k, fr);
            if q >= 0 && q <= 4
                quad_counts_clean(fr, q + 1) = quad_counts_clean(fr, q + 1) + 1;
            end
        end
    end

    % Frame-wise QPI
    quad_pref = zeros(nframes, 1);

    if is_single_quadrant
        % Single-quadrant QPI: (N_safe - N_other) / N_total
        for fr = 1:nframes
            c = frame_cycle(fr);
            if c == 0, continue; end

            if c <= length(quad_patterns)
                qp = quad_patterns{c};
            else
                qp = '1111';
            end
            dark_pos = find(qp == '0');
            if length(dark_pos) == 1
                safe_quad = cfg.led_to_quad(dark_pos);
            elseif isfield(cfg, 'probe_target_quad')
                safe_quad = cfg.probe_target_quad;
            else
                continue;
            end

            n_safe  = quad_counts_clean(fr, safe_quad + 1);
            n_total = sum(quad_counts_clean(fr, 2:5));
            n_other = n_total - n_safe;
            if n_total > 0
                quad_pref(fr) = (n_safe - n_other) / n_total;
            end
        end
    else
        % Standard diagonal-pair QPI
        pair1 = quad_counts_clean(:, 2) + quad_counts_clean(:, 4);
        pair2 = quad_counts_clean(:, 3) + quad_counts_clean(:, 5);
        denom = pair1 + pair2;
        valid_fr = denom > 0;
        quad_pref(valid_fr) = (pair1(valid_fr) - pair2(valid_fr)) ./ denom(valid_fr);
    end

    %% Compute mean QPI for first half / second half of each cycle
    cycle_num       = (1:num_cycles)';
    label           = cell(num_cycles, 1);
    n_flies_cycle   = zeros(num_cycles, 1);
    mean_QPI_first  = NaN(num_cycles, 1);
    mean_QPI_second = NaN(num_cycles, 1);

    for c = 1:num_cycles
        % Label
        if c <= length(cycle_labels)
            label{c} = cycle_labels{c};
        else
            label{c} = sprintf('C%d', c);
        end

        fr_on  = on_times(c);
        fr_off = min(off_times(c), nframes);
        if fr_on > nframes, continue; end

        % Count alive flies in this cycle
        alive_count = 0;
        for k = 1:num_flies
            if ~fly_alive(k, c), continue; end
            quads = fly_quad(k, fr_on:fr_off);
            if any(quads >= 1 & quads <= 4)
                alive_count = alive_count + 1;
            end
        end
        n_flies_cycle(c) = alive_count;

        % Time range of this cycle — split at midpoint
        t_on  = timestamps(fr_on);
        t_off = timestamps(fr_off);
        t_mid = (t_on + t_off) / 2;
        cycle_ts = timestamps(fr_on:fr_off);

        % First half
        first_mask = cycle_ts >= t_on & cycle_ts < t_mid;
        qpi_first = quad_pref(fr_on:fr_off);
        qpi_first = qpi_first(first_mask);
        if ~isempty(qpi_first)
            % abs() for diagonal-pair protocols (sign depends on which pair is safe);
            % signed for single-quadrant protocols (safe quad already identified)
            if is_single_quadrant
                mean_QPI_first(c) = mean(qpi_first, 'omitnan');
            else
                mean_QPI_first(c) = mean(abs(qpi_first), 'omitnan');
            end
        end

        % Second half
        second_mask = cycle_ts >= t_mid & cycle_ts <= t_off;
        qpi_second = quad_pref(fr_on:fr_off);
        qpi_second = qpi_second(second_mask);
        if ~isempty(qpi_second)
            if is_single_quadrant
                mean_QPI_second(c) = mean(qpi_second, 'omitnan');
            else
                mean_QPI_second(c) = mean(abs(qpi_second), 'omitnan');
            end
        end
    end

    cycle_table = table(cycle_num, label, n_flies_cycle, mean_QPI_first, mean_QPI_second, ...
        'VariableNames', {'cycle', 'label', 'n_flies', 'mean_QPI_firsthalf', 'mean_QPI_secondhalf'});

    %% Build output
    summary.experiment      = exp_name;
    summary.genotype        = genotype;
    summary.protocol        = protocol;
    summary.num_flies_total = num_flies;
    summary.num_dead        = sum(~fly_alive(:, end));
    summary.cycle_table     = cycle_table;

    fprintf('  Done: %d cycles, %d alive / %d total flies\n', ...
        num_cycles, num_flies - summary.num_dead, num_flies);

end

%% ======== LOCAL HELPER ========
function [labels, colors, sections] = get_protocol_labels_summary(protocol)
    cfg = get_protocol_config(protocol);
    labels = cfg.labels;
    colors = cfg.colors;
    sections = cfg.sections;
end
