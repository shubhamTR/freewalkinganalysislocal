function summary = compute_distance_to_safe_local(exp_path, varargin)
% COMPUTE_DISTANCE_TO_SAFE_LOCAL  Distance travelled to reach a safe (dark) quadrant
%
%   summary = compute_distance_to_safe_local(exp_path)
%   summary = compute_distance_to_safe_local(exp_path, 'Name', Value, ...)
%
%   For each LED cycle, accumulates frame-to-frame displacement (mm) from
%   LED onset until the fly first enters a dark (correct) quadrant it was
%   not already in.  Combines:
%     - Quadrant awareness from compute_latency_per_cycle_local (arena_calib,
%       fly_quad mapping, per-quadrant logic from compute_latency_to_dark)
%     - Frame-to-frame distance from compute_distance_per_cycle_local
%       (dx/dy diff, sqrt)
%
%   PER-QUADRANT LOGIC (from compute_latency_to_dark):
%     For each dark quadrant independently:
%       - If fly starts IN that quadrant at LED onset → skip that quadrant
%       - Otherwise find the first frame the fly enters that quadrant
%     Take the earliest entry across all dark quads the fly wasn't already in.
%     Instead of recording the timestamp at entry (latency), record the
%     cumulative frame-to-frame distance from onset to that entry frame.
%     NaN if the fly never enters any new dark quadrant.
%
%   Uses QPI log for dead fly status (falls back to internal detection).
%   Loads arena_calib for quadrant masks.
%
%   RETURNS
%     summary — struct with fields:
%       .experiment          — experiment name (char)
%       .genotype            — genotype shorthand
%       .protocol            — protocol name
%       .num_flies_total     — total flies spanning full recording
%       .num_dead            — number flagged dead by end
%       .fly_ids_original    — original trx indices of retained flies
%       .pixels_per_mm       — conversion factor used
%       .dist_to_safe_per_fly — [num_flies x num_cycles] distance in mm
%                               to FIRST entry into a new dark quadrant.
%                               NaN for dead flies or flies that never
%                               enter a new dark quadrant.
%       .dist_to_safe_last_per_fly — [num_flies x num_cycles] distance in mm
%                               to LAST entry into any dark quadrant before
%                               stimulus turns off. Captures total path
%                               including back-and-forth excursions.
%                               NaN for dead flies or flies that never
%                               enter any dark quadrant.
%       .safe_zone_occupancy — [num_flies x num_cycles] fraction of stim
%                               frames spent in any dark (correct) quadrant.
%                               Same logic as plot_quadrant_occupancy_all.m.
%       .already_in_correct  — [num_flies x num_cycles] logical
%       .lit_quads           — {num_cycles x 1} cell
%       .correct_quads       — {num_cycles x 1} cell
%       .cycle_table         — table with per-cycle summaries:
%           cycle, label, n_flies_alive, n_responded, n_already_correct,
%           mean_dist_to_safe_mm, sem_dist_to_safe_mm, median_dist_to_safe_mm,
%           n_responded_last, mean_dist_to_safe_last_mm,
%           sem_dist_to_safe_last_mm, median_dist_to_safe_last_mm
%
%   NAME-VALUE PARAMETERS
%     'Protocol'           — protocol name (default: auto-detect)
%     'PixelsPerMM'        — px/mm conversion (read from trx.mat; override with explicit value)
%     'ConsecutiveCycles'  — dead fly detection window (default: 3)
%     'MoveThreshPx'       — dead fly pixel threshold (default: 5)

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

    %% Extract genotype
    tokens = strsplit(exp_name, '_');
    genotype = tokens{1};

    fprintf('DistToSafe: %s (genotype=%s, protocol=%s)\n', exp_name, genotype, protocol);

    %% Get protocol labels and quad patterns
    cfg = get_protocol_config(protocol);
    cycle_labels = cfg.labels;
    sections = cfg.sections;

    % Quad patterns: use training_patterns so probes resolve to the paired
    % training LED pattern (critical for randomized single-quad protocols
    % like P017/P019 where the safe quadrant varies per trial).
    [metadata_patterns, metadata_training] = parse_metadata_led_patterns(exp_path);
    if ~isempty(metadata_training)
        quad_patterns_proto = metadata_training;
    elseif ~isempty(metadata_patterns)
        quad_patterns_proto = metadata_patterns;
    else
        fprintf('  WARNING: No metadata — using config quad patterns\n');
        quad_patterns_proto = cfg.quad_patterns;
    end

    % Detect single-quadrant mode (P013, P017, P019)
    is_single_quadrant = isfield(cfg, 'led_to_quad') && ~isempty(cfg.led_to_quad);

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

    %% Load arena calibration (for quadrant masks)
    arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    if isempty(arena_files)
        error('No arena_calib found in %s', analysis_dir);
    end
    arena_data = load(fullfile(analysis_dir, arena_files(end).name));
    all_masks = arena_data.arena_calib.all_masks;

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

    %% Map flies to quadrants per frame (same as latency function)
    fly_quad = compute_fly_quad(trx, all_masks);

    %% Dead fly status
    fly_alive = load_fly_alive(analysis_dir, num_flies, num_cycles, trx, LED, ...
        'FlyAlive', opts.FlyAlive, ...
        'ConsecutiveCycles', CONSECUTIVE_CYCLES, 'MoveThreshPx', MOVE_THRESH_PX);

    num_dead = sum(~fly_alive(:, end));
    fprintf('  Flies: %d total, %d dead, %d alive at end\n', ...
        num_flies, num_dead, num_flies - num_dead);

    %% Build lit/correct quadrant assignments per cycle (same as latency)
    lit_quads     = cell(num_cycles, 1);
    correct_quads = cell(num_cycles, 1);

    for c = 1:num_cycles
        if ~isempty(quad_patterns_proto) && c <= length(quad_patterns_proto)
            qp = quad_patterns_proto{c};
            [lit_quads{c}, correct_quads{c}] = led_pattern_to_quads(qp);

            % For probes still showing '1111' (pairing unresolved or
            % diagonal-pair protocols): set correct quads from context
            if strcmp(qp, '1111')
                if c <= length(cycle_labels) && ...
                   (strcmp(cycle_labels{c}, 'PP') || endsWith(cycle_labels{c}, '.P'))
                    if is_single_quadrant && isfield(cfg, 'probe_target_quad')
                        correct_quads{c} = cfg.probe_target_quad;
                    else
                        correct_quads{c} = [2, 4];
                    end
                else
                    correct_quads{c} = [];  % OM or non-probe
                end
            end
        else
            % Fallback: alternating within block (P001/P002 convention)
            pos_in_block = c;
            for s = 1:length(sections)
                if c >= sections(s).start_cycle && c <= sections(s).end_cycle
                    pos_in_block = c - sections(s).start_cycle + 1;
                    break;
                end
            end
            if mod(pos_in_block, 2) == 1
                [lit_quads{c}, correct_quads{c}] = led_pattern_to_quads('1010');
            else
                [lit_quads{c}, correct_quads{c}] = led_pattern_to_quads('0101');
            end
        end
    end

    %% Compute frame-to-frame distance vectors per fly (local variables)
    %  Memory-efficient: store as cell array, not on trx struct
    fly_frame_dist = cell(num_flies, 1);
    for f = 1:num_flies
        dx = diff(trx(f).x) / pixels_per_mm;
        dy = diff(trx(f).y) / pixels_per_mm;
        fly_frame_dist{f} = sqrt(dx.^2 + dy.^2);
    end

    %% Compute distance-to-safe per fly per cycle
    %  Per-quadrant logic (from compute_latency_to_dark):
    %    For each dark quadrant independently:
    %      - If fly starts IN that quadrant → skip that quadrant
    %      - Otherwise find the first frame the fly enters that quadrant
    %    Take the earliest entry across all dark quads the fly wasn't
    %    already in. Accumulate frame-to-frame distance from LED onset
    %    to the entry frame.  NaN if fly never enters a new dark quad.

    dist_to_safe_per_fly      = NaN(num_flies, num_cycles);
    dist_to_safe_last_per_fly = NaN(num_flies, num_cycles);
    safe_zone_occupancy       = NaN(num_flies, num_cycles);  % fraction of stim frames in dark quads
    already_in_correct        = false(num_flies, num_cycles);

    for f = 1:num_flies
        frame_distance = fly_frame_dist{f};

        for c = 1:num_cycles
            if ~fly_alive(f, c), continue; end

            fr_on  = on_times(c);
            fr_off = min(off_times(c), nframes);
            if fr_on > nframes, continue; end

            stim_frames = fr_on:fr_off;
            if isempty(stim_frames), continue; end

            quad_during_stim = fly_quad(f, stim_frames);
            cq = correct_quads{c};
            if isempty(cq), continue; end  % OM cycles — no correct quad

            onset_quad = quad_during_stim(1);
            if ismember(onset_quad, cq)
                already_in_correct(f, c) = true;
            end

            % ---- SAFE ZONE OCCUPANCY ----
            % Fraction of stim frames in any correct (dark) quadrant.
            % Same logic as plot_quadrant_occupancy_all.m:
            %   q_slice filtered to valid, count in dark / total
            valid_quads = quad_during_stim(quad_during_stim > 0 & ~isnan(quad_during_stim));
            if ~isempty(valid_quads)
                safe_zone_occupancy(f, c) = sum(ismember(valid_quads, cq)) / length(valid_quads);
            end

            % ---- FIRST ENTRY (per-quadrant logic) ----
            % For each dark quad, skip if fly already there at onset,
            % find first frame of entry. Take the earliest across quads.
            min_entry_idx = [];
            for qi = 1:length(cq)
                q = cq(qi);
                if onset_quad == q
                    continue;  % skip this quad — fly already there
                end
                entry_idx = find(quad_during_stim == q, 1, 'first');
                if ~isempty(entry_idx)
                    if isempty(min_entry_idx) || entry_idx < min_entry_idx
                        min_entry_idx = entry_idx;
                    end
                end
            end

            if ~isempty(min_entry_idx)
                entry_frame = stim_frames(min_entry_idx);
                dist_frames = fr_on:min(entry_frame - 1, length(frame_distance));
                if ~isempty(dist_frames)
                    dist_to_safe_per_fly(f, c) = sum(frame_distance(dist_frames), 'omitnan');
                else
                    dist_to_safe_per_fly(f, c) = 0;
                end
            end

            % ---- LAST ENTRY ----
            % Find every transition from non-dark to dark quadrant during
            % the stimulus period.  A "transition" = frame i is in a dark
            % quad AND frame i-1 is NOT in a dark quad.  Take the last
            % such transition.  Accumulate frame-to-frame distance from
            % LED onset to that frame.
            in_dark = ismember(quad_during_stim, cq);
            % Detect rising edges (not-dark → dark)
            last_entry_idx = [];
            for idx = 2:length(in_dark)
                if in_dark(idx) && ~in_dark(idx - 1)
                    last_entry_idx = idx;
                end
            end
            % Also check frame 1: counts as entry only if fly is in dark
            % but was NOT already there before stim (i.e. it moved in
            % between cycles).  However, since we check the onset quad
            % and this is frame 1, the fly hasn't moved yet — so frame 1
            % is never an "entry" transition.  Only transitions from frame
            % 2 onward count.

            if ~isempty(last_entry_idx)
                last_entry_frame = stim_frames(last_entry_idx);
                dist_frames_last = fr_on:min(last_entry_frame - 1, length(frame_distance));
                if ~isempty(dist_frames_last)
                    dist_to_safe_last_per_fly(f, c) = sum(frame_distance(dist_frames_last), 'omitnan');
                else
                    dist_to_safe_last_per_fly(f, c) = 0;
                end
            end
            % If fly never transitions into a dark quad → stays NaN
        end
    end

    %% Build per-cycle summary table
    cycle_num              = (1:num_cycles)';
    label                  = cell(num_cycles, 1);
    n_flies_alive          = zeros(num_cycles, 1);
    n_responded            = zeros(num_cycles, 1);
    n_already_correct      = zeros(num_cycles, 1);
    mean_dist_to_safe_mm   = NaN(num_cycles, 1);
    sem_dist_to_safe_mm    = NaN(num_cycles, 1);
    median_dist_to_safe_mm = NaN(num_cycles, 1);
    n_responded_last            = zeros(num_cycles, 1);
    mean_dist_to_safe_last_mm   = NaN(num_cycles, 1);
    sem_dist_to_safe_last_mm    = NaN(num_cycles, 1);
    median_dist_to_safe_last_mm = NaN(num_cycles, 1);
    mean_safe_occupancy         = NaN(num_cycles, 1);
    sem_safe_occupancy          = NaN(num_cycles, 1);

    for c = 1:num_cycles
        if c <= length(cycle_labels)
            label{c} = cycle_labels{c};
        else
            label{c} = sprintf('C%d', c);
        end

        alive_mask = fly_alive(:, c);
        n_alive = sum(alive_mask);
        n_flies_alive(c) = n_alive;
        n_already_correct(c) = sum(already_in_correct(alive_mask, c));

        if n_alive > 0
            % First-entry stats
            d_vals = dist_to_safe_per_fly(alive_mask, c);
            valid_vals = d_vals(~isnan(d_vals));
            n_responded(c) = length(valid_vals);

            if ~isempty(valid_vals)
                mean_dist_to_safe_mm(c) = mean(valid_vals);
                median_dist_to_safe_mm(c) = median(valid_vals);
                if length(valid_vals) > 1
                    sem_dist_to_safe_mm(c) = std(valid_vals) / sqrt(length(valid_vals));
                else
                    sem_dist_to_safe_mm(c) = 0;
                end
            end

            % Last-entry stats
            d_vals_last = dist_to_safe_last_per_fly(alive_mask, c);
            valid_last = d_vals_last(~isnan(d_vals_last));
            n_responded_last(c) = length(valid_last);

            if ~isempty(valid_last)
                mean_dist_to_safe_last_mm(c) = mean(valid_last);
                median_dist_to_safe_last_mm(c) = median(valid_last);
                if length(valid_last) > 1
                    sem_dist_to_safe_last_mm(c) = std(valid_last) / sqrt(length(valid_last));
                else
                    sem_dist_to_safe_last_mm(c) = 0;
                end
            end

            % Safe zone occupancy stats
            occ_vals = safe_zone_occupancy(alive_mask, c);
            valid_occ = occ_vals(~isnan(occ_vals));
            if ~isempty(valid_occ)
                mean_safe_occupancy(c) = mean(valid_occ);
                if length(valid_occ) > 1
                    sem_safe_occupancy(c) = std(valid_occ) / sqrt(length(valid_occ));
                else
                    sem_safe_occupancy(c) = 0;
                end
            end
        end
    end

    cycle_table = table(cycle_num, label, n_flies_alive, n_responded, ...
        n_already_correct, mean_dist_to_safe_mm, sem_dist_to_safe_mm, ...
        median_dist_to_safe_mm, n_responded_last, ...
        mean_dist_to_safe_last_mm, sem_dist_to_safe_last_mm, ...
        median_dist_to_safe_last_mm, mean_safe_occupancy, sem_safe_occupancy, ...
        'VariableNames', {'cycle', 'label', 'n_flies_alive', 'n_responded', ...
            'n_already_correct', 'mean_dist_to_safe_mm', 'sem_dist_to_safe_mm', ...
            'median_dist_to_safe_mm', 'n_responded_last', ...
            'mean_dist_to_safe_last_mm', 'sem_dist_to_safe_last_mm', ...
            'median_dist_to_safe_last_mm', 'mean_safe_occupancy', ...
            'sem_safe_occupancy'});

    %% Build output summary
    summary.experiment          = exp_name;
    summary.genotype            = genotype;
    summary.protocol            = protocol;
    summary.num_flies_total     = num_flies;
    summary.num_dead            = num_dead;
    summary.fly_ids_original    = fly_ids_original;
    summary.pixels_per_mm       = pixels_per_mm;
    summary.dist_to_safe_per_fly      = dist_to_safe_per_fly;
    summary.dist_to_safe_last_per_fly = dist_to_safe_last_per_fly;
    summary.safe_zone_occupancy       = safe_zone_occupancy;
    summary.already_in_correct        = already_in_correct;
    summary.lit_quads           = lit_quads;
    summary.correct_quads       = correct_quads;
    summary.cycle_table         = cycle_table;

    fprintf('  Done: %d cycles, %d alive / %d total\n', ...
        num_cycles, num_flies - num_dead, num_flies);

    %% Save summary as .mat
    if ~exist(analysis_dir, 'dir')
        mkdir(analysis_dir);
    end
    mat_file = fullfile(analysis_dir, sprintf('distance_to_safe_%s.mat', exp_name));
    save(mat_file, '-struct', 'summary');
    fprintf('  Saved distance-to-safe data: %s\n', mat_file);

end

%% ======== LOCAL HELPERS ========

function fly_alive = parse_qpi_log(log_file, num_flies, num_cycles, fly_ids_original)
% PARSE_QPI_LOG  Extract per-fly alive status from QPI log file

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


function fly_alive = detect_dead_flies(trx, on_times, off_times, ...
    num_flies, num_cycles, nframes, CONSECUTIVE_CYCLES, MOVE_THRESH_PX)
% DETECT_DEAD_FLIES  Position-based dead fly detection

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


function [labels, colors, sections, quad_patterns] = get_protocol_labels_lat(protocol)
    cfg = get_protocol_config(protocol);
    labels = cfg.labels;
    colors = cfg.colors;
    sections = cfg.sections;
    quad_patterns = cfg.quad_patterns;
end
