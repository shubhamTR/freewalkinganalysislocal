function diagnose_cycle(protocol, genotype_filter, target_cycle, varargin)
% DIAGNOSE_CYCLE  Per-fly breakdown of QPI, distance, and latency for a single cycle
%
%   diagnose_cycle('P008', 'L2A', 20)
%   diagnose_cycle('P008', 'L2A', 20, 'PixelsPerMM', 8.21)
%
%   Loads every experiment matching genotype_filter under the given protocol,
%   then prints detailed per-fly information for the specified cycle:
%     - Fly alive/dead status
%     - Quadrant at LED onset
%     - Quadrant time-series during stim (abbreviated)
%     - QPI value (first half & second half)
%     - Total distance travelled (mm)
%     - Latency to dark quadrant (s)
%     - Whether fly was already in a correct quadrant at onset
%
%   NAME-VALUE PARAMETERS
%     'DataRoot'     — path to protocol data (default: auto from pwd)
%     'PixelsPerMM'  — px/mm conversion (read from trx.mat; override with explicit value)
%     'ConsecutiveCycles' — dead fly detection window (default: 3)
%     'MoveThreshPx'      — dead fly pixel threshold (default: 5)

    %% Parse
    p = inputParser;
    addRequired(p, 'protocol', @ischar);
    addRequired(p, 'genotype_filter', @ischar);
    addRequired(p, 'target_cycle', @isnumeric);
    addParameter(p, 'DataRoot', '', @ischar);
    addParameter(p, 'PixelsPerMM', NaN, @isnumeric);
    addParameter(p, 'ConsecutiveCycles', 3, @isnumeric);
    addParameter(p, 'MoveThreshPx', 5, @isnumeric);
    parse(p, protocol, genotype_filter, target_cycle, varargin{:});
    opts = p.Results;
    CONSECUTIVE_CYCLES = opts.ConsecutiveCycles;
    MOVE_THRESH_PX     = opts.MoveThreshPx;

    %% Find data root
    if ~isempty(opts.DataRoot)
        proto_dir = opts.DataRoot;
    else
        proto_dir = fullfile(pwd, protocol);
        if ~exist(proto_dir, 'dir')
            proto_dir = pwd;
        end
    end

    %% Get protocol labels (for cycle label and quad patterns)
    % Use metadata as ground truth; fall back to internal subfunction if empty
    quad_patterns = {};
    if ~isempty(proto_dir) && exist(proto_dir, 'dir')
        % Try to get patterns from first experiment's metadata
        d_temp = dir(fullfile(proto_dir, [genotype_filter '_*']));
        d_temp = d_temp([d_temp.isdir]);
        if ~isempty(d_temp)
            first_exp = fullfile(proto_dir, d_temp(1).name);
            quad_patterns = parse_metadata_led_patterns(first_exp);
        end
    end
    % Fall back to protocol labels if metadata is empty
    [cycle_labels, ~, ~, fallback_patterns] = get_protocol_labels_lat(protocol);
    if isempty(quad_patterns)
        quad_patterns = fallback_patterns;
    end

    %% Find experiments matching genotype
    d = dir(fullfile(proto_dir, [genotype_filter '_*']));
    d = d([d.isdir]);
    if isempty(d)
        fprintf('No experiments matching %s in %s\n', genotype_filter, proto_dir);
        return;
    end

    fprintf('\n============================================================\n');
    fprintf('CYCLE %d DIAGNOSIS  |  %s  |  %s\n', target_cycle, genotype_filter, protocol);
    if target_cycle <= length(cycle_labels)
        fprintf('Cycle label: %s\n', cycle_labels{target_cycle});
    end
    if ~isempty(quad_patterns) && target_cycle <= length(quad_patterns)
        qp = quad_patterns{target_cycle};
        if strcmp(qp, 'probe')
            fprintf('Probe trial (no LED)\n');
        elseif strcmp(qp, 'opto')
            fprintf('Opto trial\n');
        else
            [lit_quads, dark_quads] = led_pattern_to_quads(qp);
            if ~isempty(lit_quads)
                fprintf('Lit quads: Q%s  |  Dark (correct): Q%s\n', ...
                    sprintf('%d,', lit_quads), sprintf('%d,', dark_quads));
            else
                fprintf('Quad pattern: %s\n', qp);
            end
        end
    end
    fprintf('Experiments found: %d\n', length(d));
    fprintf('============================================================\n');

    %% Determine correct quadrants for this cycle
    correct_quads = [];
    lit_quads = [];
    if ~isempty(quad_patterns) && target_cycle <= length(quad_patterns)
        qp = quad_patterns{target_cycle};
        if ~strcmp(qp, 'probe') && ~strcmp(qp, 'opto')
            [lit_quads, correct_quads] = led_pattern_to_quads(qp);
        end
    end

    %% Process each experiment
    for ei = 1:length(d)
        exp_path = fullfile(proto_dir, d(ei).name);
        exp_name = d(ei).name;
        analysis_dir = fullfile(exp_path, 'analysis');

        fprintf('\n------------------------------------------------------------\n');
        fprintf('EXPERIMENT: %s\n', exp_name);
        fprintf('------------------------------------------------------------\n');

        %% Load trx
        trx_data = load(fullfile(exp_path, 'trx.mat'));
        trx = trx_data.trx;

        % Read px/mm from trx (authoritative source)
        if isnan(opts.PixelsPerMM)
            pixels_per_mm = trx(1).pxpermm;
        else
            pixels_per_mm = opts.PixelsPerMM;
        end

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
            fprintf('  No valid flies — skipping.\n');
            continue;
        end

        %% Load arena calibration
        arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
        if isempty(arena_files)
            fprintf('  No arena_calib — skipping.\n');
            continue;
        end
        arena_data = load(fullfile(analysis_dir, arena_files(end).name));
        all_masks = arena_data.arena_calib.all_masks;

        %% Load LED detector
        led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
        if isempty(led_files)
            fprintf('  No LED_detector — skipping.\n');
            continue;
        end
        led_data = load(fullfile(analysis_dir, led_files(end).name));
        LED = led_data.LED_detector;

        on_times  = LED.on_times;
        off_times = LED.off_times;
        num_cycles = length(on_times);
        nframes   = length(trx(1).x);

        if target_cycle > num_cycles
            fprintf('  Only %d cycles — target cycle %d out of range.\n', num_cycles, target_cycle);
            continue;
        end

        %% Time axis
        if isfield(trx(1), 'timestamps') && ~isempty(trx(1).timestamps)
            timestamps = trx(1).timestamps(:)';
        else
            fps = trx(1).fps;
            timestamps = (0:nframes-1) / fps;
        end

        fr_on  = on_times(target_cycle);
        fr_off = min(off_times(target_cycle), nframes);
        t_on   = timestamps(fr_on);
        t_off  = timestamps(fr_off);
        t_mid  = (t_on + t_off) / 2;
        stim_dur = t_off - t_on;

        fprintf('  LED on: frame %d (%.2fs)  |  off: frame %d (%.2fs)  |  duration: %.2fs\n', ...
            fr_on, t_on, fr_off, t_off, stim_dur);
        fprintf('  Total flies: %d  (original IDs: %s)\n', num_flies, mat2str(fly_ids_original));

        %% Map flies to quadrants per frame
        fly_quad = compute_fly_quad(trx, all_masks);

        %% Dead fly detection — use QPI log or fallback
        fly_alive = [];
        log_file = fullfile(analysis_dir, sprintf('QPI_log_%s.txt', exp_name));
        if exist(log_file, 'file')
            fly_alive = parse_qpi_log(log_file, num_flies, num_cycles, fly_ids_original);
        end
        if isempty(fly_alive)
            fly_alive = detect_dead_flies(trx, on_times, off_times, ...
                num_flies, num_cycles, nframes, CONSECUTIVE_CYCLES, MOVE_THRESH_PX);
        end

        n_alive = sum(fly_alive(:, target_cycle));
        n_dead  = num_flies - n_alive;
        fprintf('  Alive at cycle %d: %d  |  Dead: %d\n', target_cycle, n_alive, n_dead);

        %% ---- QPI computation (same as compute_QPI_summary_local) ----
        % Build frame-wise QPI for this cycle
        % Need quad_counts for alive flies only
        cycle_frames = fr_on:fr_off;
        quad_counts = zeros(length(cycle_frames), 5);
        for k = 1:num_flies
            if ~fly_alive(k, target_cycle), continue; end
            for fi = 1:length(cycle_frames)
                fr = cycle_frames(fi);
                q = fly_quad(k, fr);
                if q >= 0 && q <= 4
                    quad_counts(fi, q + 1) = quad_counts(fi, q + 1) + 1;
                end
            end
        end

        pair1 = quad_counts(:, 2) + quad_counts(:, 4);  % Q1+Q3
        pair2 = quad_counts(:, 3) + quad_counts(:, 5);  % Q2+Q4
        denom = pair1 + pair2;
        qpi_trace = zeros(length(cycle_frames), 1);
        valid_fr = denom > 0;
        qpi_trace(valid_fr) = (pair1(valid_fr) - pair2(valid_fr)) ./ denom(valid_fr);

        cycle_ts = timestamps(cycle_frames);
        first_mask  = cycle_ts >= t_on & cycle_ts < t_mid;
        second_mask = cycle_ts >= t_mid & cycle_ts <= t_off;

        qpi_firsthalf  = mean(abs(qpi_trace(first_mask)), 'omitnan');
        qpi_secondhalf = mean(abs(qpi_trace(second_mask)), 'omitnan');

        fprintf('\n  === AGGREGATE QPI (this cycle) ===\n');
        fprintf('  |QPI| first half:  %.4f\n', qpi_firsthalf);
        fprintf('  |QPI| second half: %.4f\n', qpi_secondhalf);

        %% ---- Per-fly breakdown ----
        fprintf('\n  === PER-FLY BREAKDOWN ===\n');
        fprintf('  %-5s %-6s %-8s %-10s %-12s %-12s %-12s %-10s %-10s\n', ...
            'Fly', 'Alive', 'OnsetQ', 'InCorrect', 'Dist(mm)', 'Lat(s)', ...
            'QuadPath', 'TimeInDk', 'DkOccup');
        fprintf('  %s\n', repmat('-', 1, 100));

        for f = 1:num_flies
            alive_str = 'Y';
            if ~fly_alive(f, target_cycle)
                alive_str = 'N';
            end

            % Onset quadrant
            onset_quad = fly_quad(f, fr_on);

            % Already in correct?
            already_correct = false;
            if ~isempty(correct_quads) && ismember(onset_quad, correct_quads)
                already_correct = true;
            end

            % Distance travelled during stim (mm)
            dx = diff(trx(f).x) / pixels_per_mm;
            dy = diff(trx(f).y) / pixels_per_mm;
            frame_distance = sqrt(dx.^2 + dy.^2);
            dist_frames = fr_on:min(fr_off - 1, length(frame_distance));
            total_dist = NaN;
            if fly_alive(f, target_cycle) && ~isempty(dist_frames)
                total_dist = sum(frame_distance(dist_frames), 'omitnan');
            end

            % Latency to dark quadrant (same logic as compute_latency_per_cycle_local)
            latency = NaN;
            if fly_alive(f, target_cycle) && ~isempty(correct_quads)
                stim_frames = fr_on:fr_off;
                quad_during_stim = fly_quad(f, stim_frames);

                min_entry_idx = [];
                for qi = 1:length(correct_quads)
                    q = correct_quads(qi);
                    if onset_quad == q, continue; end  % skip if already there
                    entry_idx = find(quad_during_stim == q, 1, 'first');
                    if ~isempty(entry_idx)
                        if isempty(min_entry_idx) || entry_idx < min_entry_idx
                            min_entry_idx = entry_idx;
                        end
                    end
                end
                if ~isempty(min_entry_idx)
                    entry_frame = stim_frames(min_entry_idx);
                    latency = timestamps(entry_frame) - timestamps(fr_on);
                end
            end

            % Quadrant path (abbreviated: first 10 + last 5 positions)
            stim_quads = fly_quad(f, fr_on:fr_off);
            % Compress to transitions
            quad_path = compress_quad_path(stim_quads);

            % Time in dark quadrants (occupancy)
            dark_occ = NaN;
            if fly_alive(f, target_cycle) && ~isempty(correct_quads)
                stim_quads_valid = stim_quads(stim_quads > 0 & ~isnan(stim_quads));
                if ~isempty(stim_quads_valid)
                    dark_occ = sum(ismember(stim_quads_valid, correct_quads)) / length(stim_quads_valid);
                end
            end

            % Format
            correct_str = '  ';
            if already_correct, correct_str = 'YES'; end

            fprintf('  %-5d %-6s Q%-7d %-10s %-12s %-12s %-28s %-10s\n', ...
                fly_ids_original(f), alive_str, onset_quad, correct_str, ...
                format_val(total_dist, '%.1f'), ...
                format_val(latency, '%.2f'), ...
                quad_path, ...
                format_val(dark_occ, '%.2f'));
        end

        %% ---- Summary stats ----
        fprintf('\n  === SUMMARY STATS (alive flies only) ===\n');

        % Collect per-fly values for alive flies
        alive_dists = [];
        alive_lats  = [];
        alive_occ   = [];
        n_already_correct = 0;
        n_responded = 0;

        for f = 1:num_flies
            if ~fly_alive(f, target_cycle), continue; end

            onset_quad = fly_quad(f, fr_on);
            if ~isempty(correct_quads) && ismember(onset_quad, correct_quads)
                n_already_correct = n_already_correct + 1;
            end

            % Distance
            dx = diff(trx(f).x) / pixels_per_mm;
            dy = diff(trx(f).y) / pixels_per_mm;
            frame_distance = sqrt(dx.^2 + dy.^2);
            dist_frames = fr_on:min(fr_off - 1, length(frame_distance));
            if ~isempty(dist_frames)
                alive_dists = [alive_dists; sum(frame_distance(dist_frames), 'omitnan')]; %#ok<AGROW>
            end

            % Latency
            if ~isempty(correct_quads)
                stim_frames = fr_on:fr_off;
                quad_during_stim = fly_quad(f, stim_frames);
                min_entry_idx = [];
                for qi = 1:length(correct_quads)
                    q = correct_quads(qi);
                    if onset_quad == q, continue; end
                    entry_idx = find(quad_during_stim == q, 1, 'first');
                    if ~isempty(entry_idx)
                        if isempty(min_entry_idx) || entry_idx < min_entry_idx
                            min_entry_idx = entry_idx;
                        end
                    end
                end
                if ~isempty(min_entry_idx)
                    entry_frame = stim_frames(min_entry_idx);
                    lat_val = timestamps(entry_frame) - timestamps(fr_on);
                    alive_lats = [alive_lats; lat_val]; %#ok<AGROW>
                    n_responded = n_responded + 1;
                end
            end

            % Dark occupancy
            stim_quads = fly_quad(f, fr_on:fr_off);
            sq_valid = stim_quads(stim_quads > 0 & ~isnan(stim_quads));
            if ~isempty(sq_valid) && ~isempty(correct_quads)
                alive_occ = [alive_occ; sum(ismember(sq_valid, correct_quads))/length(sq_valid)]; %#ok<AGROW>
            end
        end

        fprintf('  Alive flies:          %d\n', n_alive);
        fprintf('  Already in correct Q: %d\n', n_already_correct);
        fprintf('  Responded (latency):  %d\n', n_responded);
        fprintf('\n');
        fprintf('  Distance (mm):  mean=%.1f  sem=%.1f  median=%.1f  [n=%d]\n', ...
            mean(alive_dists, 'omitnan'), ...
            std(alive_dists, 'omitnan')/sqrt(max(length(alive_dists),1)), ...
            median(alive_dists, 'omitnan'), length(alive_dists));
        fprintf('  Latency (s):    mean=%.2f  sem=%.2f  median=%.2f  [n=%d]\n', ...
            mean(alive_lats, 'omitnan'), ...
            std(alive_lats, 'omitnan')/sqrt(max(length(alive_lats),1)), ...
            median(alive_lats, 'omitnan'), length(alive_lats));
        fprintf('  Dark occupancy: mean=%.3f  sem=%.3f  [n=%d]\n', ...
            mean(alive_occ, 'omitnan'), ...
            std(alive_occ, 'omitnan')/sqrt(max(length(alive_occ),1)), length(alive_occ));
        fprintf('  |QPI| 1st half: %.4f   |  2nd half: %.4f\n', qpi_firsthalf, qpi_secondhalf);
    end

    fprintf('\n============================================================\n');
    fprintf('Done.\n');
end
function diagnose_fly(protocol, experiment_name, fly_id, varargin)
% DIAGNOSE_FLY  Track a single fly across ALL cycles in one experiment
%
%   diagnose_fly('P008', 'L2A_Rig1_20260409_122638', 7)
%   diagnose_fly('P008', 'L2A_Rig1_20260409_122638', 7, 'PixelsPerMM', 8.21)
%
%   Prints per-cycle breakdown for one fly across the entire experiment:
%     - Alive/dead status
%     - Quadrant at LED onset
%     - Already in correct quadrant?
%     - Distance travelled (mm)
%     - Latency to dark quadrant (s)
%     - Dark quadrant occupancy
%     - Quadrant path with absolute frame numbers
%
%   fly_id is the ORIGINAL trx index (as shown in diagnose_cycle output).
%
%   NAME-VALUE PARAMETERS
%     'DataRoot'     — path to protocol data (default: auto from pwd)
%     'PixelsPerMM'  — px/mm conversion (read from trx.mat; override with explicit value)
%     'ConsecutiveCycles' — dead fly detection window (default: 3)
%     'MoveThreshPx'      — dead fly pixel threshold (default: 5)

    %% Parse
    p = inputParser;
    addRequired(p, 'protocol', @ischar);
    addRequired(p, 'experiment_name', @ischar);
    addRequired(p, 'fly_id', @isnumeric);
    addParameter(p, 'DataRoot', '', @ischar);
    addParameter(p, 'PixelsPerMM', NaN, @isnumeric);
    addParameter(p, 'ConsecutiveCycles', 3, @isnumeric);
    addParameter(p, 'MoveThreshPx', 5, @isnumeric);
    parse(p, protocol, experiment_name, fly_id, varargin{:});
    opts = p.Results;
    CONSECUTIVE_CYCLES = opts.ConsecutiveCycles;
    MOVE_THRESH_PX     = opts.MoveThreshPx;

    %% Find data root
    if ~isempty(opts.DataRoot)
        proto_dir = opts.DataRoot;
    else
        proto_dir = fullfile(pwd, protocol);
        if ~exist(proto_dir, 'dir')
            proto_dir = pwd;
        end
    end

    exp_path = fullfile(proto_dir, experiment_name);
    if ~exist(exp_path, 'dir')
        fprintf('Experiment not found: %s\n', exp_path);
        return;
    end

    analysis_dir = fullfile(exp_path, 'analysis');

    %% Get protocol labels
    % Use metadata as ground truth; fall back to internal subfunction if empty
    quad_patterns = parse_metadata_led_patterns(exp_path);
    if isempty(quad_patterns)
        [cycle_labels, ~, ~, quad_patterns] = get_protocol_labels_lat(protocol);
    else
        [cycle_labels, ~, ~, ~] = get_protocol_labels_lat(protocol);
    end

    %% Load trx
    trx_data = load(fullfile(exp_path, 'trx.mat'));
    trx = trx_data.trx;

    % Read px/mm from trx (authoritative source)
    if isnan(opts.PixelsPerMM)
        pixels_per_mm = trx(1).pxpermm;
    else
        pixels_per_mm = opts.PixelsPerMM;
    end

    max_end = max([trx.endframe]);
    good = [];
    for k = 1:length(trx)
        if trx(k).firstframe == 1 && trx(k).endframe >= (max_end - 30)
            good = [good, k]; %#ok<AGROW>
        end
    end

    % Find which index in the filtered array corresponds to fly_id
    fly_idx = find(good == fly_id);
    if isempty(fly_idx)
        fprintf('Fly %d not found among valid flies (IDs: %s)\n', fly_id, mat2str(good));
        return;
    end

    trx = trx(good);
    fly_ids_original = good;
    num_flies = length(trx);

    %% Load arena calibration
    arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    if isempty(arena_files)
        fprintf('No arena_calib found.\n');
        return;
    end
    arena_data = load(fullfile(analysis_dir, arena_files(end).name));
    all_masks = arena_data.arena_calib.all_masks;

    %% Load LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    if isempty(led_files)
        fprintf('No LED_detector found.\n');
        return;
    end
    led_data = load(fullfile(analysis_dir, led_files(end).name));
    LED = led_data.LED_detector;

    on_times  = LED.on_times;
    off_times = LED.off_times;
    num_cycles = length(on_times);
    nframes   = length(trx(1).x);

    %% Time axis
    if isfield(trx(1), 'timestamps') && ~isempty(trx(1).timestamps)
        timestamps = trx(1).timestamps(:)';
    else
        fps = trx(1).fps;
        timestamps = (0:nframes-1) / fps;
    end

    %% Map this fly to quadrants per frame
    fly_quad_vec = zeros(1, nframes);
    x_inds = round(trx(fly_idx).x);
    y_inds = round(trx(fly_idx).y);
    for fr = 1:length(x_inds)
        xi = x_inds(fr);
        yi = y_inds(fr);
        if ~isnan(xi) && ~isnan(yi) && ...
           xi >= 1 && xi <= size(all_masks, 2) && ...
           yi >= 1 && yi <= size(all_masks, 1)
            fly_quad_vec(fr) = all_masks(yi, xi);
        end
    end

    %% Dead fly detection
    fly_alive_all = [];
    log_file = fullfile(analysis_dir, sprintf('QPI_log_%s.txt', experiment_name));
    if exist(log_file, 'file')
        fly_alive_all = parse_qpi_log(log_file, num_flies, num_cycles, fly_ids_original);
    end
    if isempty(fly_alive_all)
        fly_alive_all = detect_dead_flies(trx, on_times, off_times, ...
            num_flies, num_cycles, nframes, CONSECUTIVE_CYCLES, MOVE_THRESH_PX);
    end

    %% Frame-to-frame distance for this fly
    dx = diff(trx(fly_idx).x) / pixels_per_mm;
    dy = diff(trx(fly_idx).y) / pixels_per_mm;
    frame_distance = sqrt(dx.^2 + dy.^2);

    %% Print header
    fprintf('\n============================================================\n');
    fprintf('FLY %d TRACKER  |  %s  |  %s\n', fly_id, experiment_name, protocol);
    fprintf('Total cycles: %d  |  px/mm: %.2f\n', num_cycles, pixels_per_mm);

    % When does fly die?
    alive_vec = fly_alive_all(fly_idx, :);
    death_cycle = find(~alive_vec, 1, 'first');
    if isempty(death_cycle)
        fprintf('Status: ALIVE throughout all %d cycles\n', num_cycles);
    else
        fprintf('Status: DEAD from cycle %d onward', death_cycle);
        if death_cycle <= length(cycle_labels)
            fprintf(' (%s)', cycle_labels{death_cycle});
        end
        fprintf('\n');
    end
    fprintf('============================================================\n\n');

    fprintf('  %-5s %-8s %-6s %-8s %-10s %-10s %-10s %-8s  %s\n', ...
        'Cyc', 'Label', 'Alive', 'OnsetQ', 'InCorrect', 'Dist(mm)', 'Lat(s)', ...
        'DkOcc', 'QuadPath (with frame numbers)');
    fprintf('  %s\n', repmat('-', 1, 130));

    %% Loop over all cycles
    for c = 1:num_cycles
        fr_on  = on_times(c);
        fr_off = min(off_times(c), nframes);

        % Label
        if c <= length(cycle_labels)
            lbl = cycle_labels{c};
        else
            lbl = sprintf('C%d', c);
        end

        % Alive?
        alive = fly_alive_all(fly_idx, c);
        alive_str = 'Y';
        if ~alive, alive_str = 'N'; end

        % Correct quads for this cycle
        cq = [];
        if ~isempty(quad_patterns) && c <= length(quad_patterns)
            qp = quad_patterns{c};
            if ~strcmp(qp, 'probe') && ~strcmp(qp, 'opto')
                [~, cq] = led_pattern_to_quads(qp);
            end
        end

        % Onset quadrant
        onset_quad = fly_quad_vec(fr_on);

        % Already correct?
        already_correct = false;
        correct_str = '  ';
        if ~isempty(cq) && ismember(onset_quad, cq)
            already_correct = true;
            correct_str = 'YES';
        end

        % Distance
        total_dist = NaN;
        if alive
            d_frames = fr_on:min(fr_off - 1, length(frame_distance));
            if ~isempty(d_frames)
                total_dist = sum(frame_distance(d_frames), 'omitnan');
            end
        end

        % Latency (same per-quadrant logic)
        latency = NaN;
        if alive && ~isempty(cq)
            stim_frames = fr_on:fr_off;
            quad_during_stim = fly_quad_vec(stim_frames);

            min_entry_idx = [];
            for qi = 1:length(cq)
                q = cq(qi);
                if onset_quad == q, continue; end
                entry_idx = find(quad_during_stim == q, 1, 'first');
                if ~isempty(entry_idx)
                    if isempty(min_entry_idx) || entry_idx < min_entry_idx
                        min_entry_idx = entry_idx;
                    end
                end
            end
            if ~isempty(min_entry_idx)
                entry_frame = stim_frames(min_entry_idx);
                latency = timestamps(entry_frame) - timestamps(fr_on);
            end
        end

        % Dark occupancy
        dark_occ = NaN;
        if alive && ~isempty(cq)
            sq = fly_quad_vec(fr_on:fr_off);
            sq_valid = sq(sq > 0 & ~isnan(sq));
            if ~isempty(sq_valid)
                dark_occ = sum(ismember(sq_valid, cq)) / length(sq_valid);
            end
        end

        % Quad path with frame numbers
        stim_quads = fly_quad_vec(fr_on:fr_off);
        quad_path = compress_quad_path_frames(stim_quads, fr_on);

        fprintf('  %-5d %-8s %-6s Q%-7d %-10s %-10s %-10s %-8s  %s\n', ...
            c, lbl, alive_str, onset_quad, correct_str, ...
            format_val(total_dist, '%.1f'), ...
            format_val(latency, '%.2f'), ...
            format_val(dark_occ, '%.2f'), ...
            quad_path);
    end

    fprintf('\n============================================================\n');
    fprintf('Done.\n');
end


%% ===== HELPER: Compress quadrant path to transitions =====
function path_str = compress_quad_path(quads)
    % Shows quadrant transitions as "Q2(45fr)->Q1(12fr)->Q4(80fr)..."
    if isempty(quads)
        path_str = '(empty)';
        return;
    end
    segments = {};
    current_q = quads(1);
    count = 1;
    for i = 2:length(quads)
        if quads(i) == current_q
            count = count + 1;
        else
            segments{end+1} = sprintf('Q%d(%d)', current_q, count); %#ok<AGROW>
            current_q = quads(i);
            count = 1;
        end
    end
    segments{end+1} = sprintf('Q%d(%d)', current_q, count);

    % Truncate if too many transitions
    if length(segments) > 6
        path_str = [strjoin(segments(1:3), '>'), '...', strjoin(segments(end-1:end), '>')];
    else
        path_str = strjoin(segments, '>');
    end
end


%% ===== HELPER: Compress quadrant path with frame numbers =====
function path_str = compress_quad_path_frames(quads, start_frame)
    % Shows quadrant transitions with absolute frame numbers at each transition
    % e.g. "Q2(fr29372-29722, 351fr) > Q3(fr29723-30571, 849fr)"
    if isempty(quads)
        path_str = '(empty)';
        return;
    end
    segments = {};
    current_q = quads(1);
    seg_start = 1;
    count = 1;
    for i = 2:length(quads)
        if quads(i) == current_q
            count = count + 1;
        else
            fr_s = start_frame + seg_start - 1;
            fr_e = start_frame + seg_start + count - 2;
            segments{end+1} = sprintf('Q%d(fr%d-%d, %dfr)', current_q, fr_s, fr_e, count); %#ok<AGROW>
            current_q = quads(i);
            seg_start = i;
            count = 1;
        end
    end
    fr_s = start_frame + seg_start - 1;
    fr_e = start_frame + seg_start + count - 2;
    segments{end+1} = sprintf('Q%d(fr%d-%d, %dfr)', current_q, fr_s, fr_e, count);

    path_str = strjoin(segments, ' > ');
end


%% ===== HELPER: Format value or NaN =====
function s = format_val(val, fmt)
    if isnan(val)
        s = 'NaN';
    else
        s = sprintf(fmt, val);
    end
end


%% ===== HELPER: parse QPI log (same as compute_latency_per_cycle_local) =====
function fly_alive = parse_qpi_log(log_file, num_flies, num_cycles, fly_ids_original)
    fly_alive = [];
    try
        fid = fopen(log_file, 'r');
        if fid == -1, return; end
        raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
        fclose(fid);
        lines = raw{1};

        alive_matrix = true(max(fly_ids_original), num_cycles);
        for li = 1:length(lines)
            line = strtrim(lines{li});
            if startsWith(line, 'Cycle')
                tok = regexp(line, 'Cycle\s+(\d+).*Dead flies:\s*\[(.*?)\]', 'tokens');
                if ~isempty(tok)
                    c = str2double(tok{1}{1});
                    dead_str = strtrim(tok{1}{2});
                    if ~isempty(dead_str)
                        dead_ids = str2num(dead_str); %#ok<ST2NM>
                        if ~isempty(dead_ids) && c <= num_cycles
                            alive_matrix(dead_ids, c:end) = false;
                        end
                    end
                end
            end
        end

        fly_alive = alive_matrix(fly_ids_original, :);
    catch
        fly_alive = [];
    end
end


%% ===== HELPER: detect dead flies (same as compute scripts) =====
function fly_alive = detect_dead_flies(trx, on_times, off_times, ...
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


%% ===== HELPER: protocol labels (same as compute_latency_per_cycle_local) =====
function [labels, colors, sections, quad_patterns] = get_protocol_labels_lat(protocol)
    cfg = get_protocol_config(protocol);
    labels = cfg.labels;
    colors = cfg.colors;
    sections = cfg.sections;
    quad_patterns = cfg.quad_patterns;
end
