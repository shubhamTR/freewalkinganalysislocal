function plot_quadrant_preference_local(exp_path, varargin)
% PLOT_QUADRANT_PREFERENCE_LOCAL  Frame-wise QPI with LED on/off overlay
%
%   plot_quadrant_preference_local(exp_path)
%   plot_quadrant_preference_local(exp_path, 'Name', Value, ...)
%
%   Loads trx.mat, arena_calib, and LED_detector for a single experiment,
%   maps fly positions to quadrants, detects and removes dead flies based
%   on position, computes frame-wise QPI, and plots with LED markers.
%   Saves PNG and a log file in the analysis folder.
%
%   QPI = (Q1+Q3 - Q2-Q4) / (Q1+Q3 + Q2+Q4)
%
%   Dead fly detection:
%     For each fly, slide a window of ConsecutiveCycles LED cycles.
%     If max displacement from mean position < MoveThreshPx for the
%     entire window, the fly is flagged dead from that cycle onward.
%
%   Protocol-aware LED labels:
%     P001: 3 colors (R/G/B), intensities [1,1,5,5,10,10,20,20,30,30,40,40,50,50]
%     P002: 1 color (R), intensities [10,10,12,12,15,15,18,18,20,20,25,25,30,30] x3
%
%   INPUTS
%     exp_path -- path to experiment folder in analysisdatalocal
%
%   NAME-VALUE PARAMETERS
%     'ShowPlots'        -- keep figure open (default: false)
%     'SavePlot'         -- save PNG to analysis folder (default: true)
%     'ConsecutiveCycles'-- cycles window for dead detection (default: 3)
%     'MoveThreshPx'     -- pixel threshold for dead detection (default: 5)
%     'Protocol'         -- 'P001' or 'P002' (default: auto-detect from path)
%
%   Requires: arena_calib_*.mat and LED_detector_*.mat in analysis/

    %% Parse inputs
    p = inputParser;
    addRequired(p, 'exp_path', @ischar);
    addParameter(p, 'ShowPlots', false, @islogical);
    addParameter(p, 'SavePlot', true, @islogical);
    addParameter(p, 'ConsecutiveCycles', 3, @isnumeric);
    addParameter(p, 'MoveThreshPx', 5, @isnumeric);
    addParameter(p, 'Protocol', '', @ischar);
    parse(p, exp_path, varargin{:});

    opts = p.Results;
    [~, exp_name] = fileparts(exp_path);
    analysis_dir = fullfile(exp_path, 'analysis');

    CONSECUTIVE_CYCLES = opts.ConsecutiveCycles;
    MOVE_THRESH_PX     = opts.MoveThreshPx;

    %% Auto-detect protocol from path if not provided
    protocol = opts.Protocol;
    if isempty(protocol)
        % Try to get protocol from parent folder name (e.g., .../P001/exp_name)
        [parent_dir, ~] = fileparts(exp_path);
        [~, parent_name] = fileparts(parent_dir);
        if startsWith(parent_name, 'P')
            protocol = parent_name;
        else
            protocol = 'unknown';
        end
    end

    %% Build protocol-specific cycle labels and colors
    cfg = get_protocol_config(protocol);

    % Try to get quad patterns from metadata first (ground truth for randomized protocols)
    [quad_patterns, training_patterns] = parse_metadata_led_patterns(exp_path);

    if isempty(quad_patterns)
        quad_patterns = cfg.quad_patterns;
        training_patterns = cfg.quad_patterns;
    end

    cycle_labels  = cfg.labels;
    cycle_colors  = cfg.colors;
    section_info  = cfg.sections;

    % Detect single-quadrant mode (P013, P017)
    is_single_quadrant = isfield(cfg, 'led_to_quad') && ~isempty(cfg.led_to_quad);

    %% Open log file
    log_file = fullfile(analysis_dir, sprintf('QPI_log_%s.txt', exp_name));
    fid = fopen(log_file, 'w');
    if fid == -1
        error('Cannot open log file: %s', log_file);
    end
    logf = @(varargin) fprintf_both(fid, varargin{:});

    logf('=== QPI Analysis: %s ===\n', exp_name);
    logf('    Date: %s\n', datestr(now));
    logf('    Protocol: %s\n', protocol);
    logf('    Dead fly threshold: <%d px over %d consecutive cycles\n\n', ...
        MOVE_THRESH_PX, CONSECUTIVE_CYCLES);

    %% Load trx
    trx_file = fullfile(exp_path, 'trx.mat');
    if ~exist(trx_file, 'file')
        logf('ERROR: trx.mat not found in %s\n', exp_path);
        fclose(fid);
        error('trx.mat not found in %s', exp_path);
    end
    trx_data = load(trx_file);
    trx = trx_data.trx;

    %% Filter flies -- keep only those spanning full recording
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
    logf('Flies spanning full recording: %d / %d\n', num_flies, length(trx_data.trx));
    logf('  Original trx IDs: %s\n', mat2str(fly_ids_original));

    if num_flies == 0
        logf('WARNING: No valid flies — skipping %s\n', exp_name);
        fclose(fid);
        warning('No valid flies — skipping %s', exp_name);
        return;
    end

    %% Load arena calibration
    arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    if isempty(arena_files)
        logf('ERROR: No arena_calib found in %s\n', analysis_dir);
        fclose(fid);
        error('No arena_calib found in %s', analysis_dir);
    end
    arena_data = load(fullfile(analysis_dir, arena_files(end).name));
    all_masks = arena_data.arena_calib.all_masks;

    %% Load LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    if isempty(led_files)
        logf('ERROR: No LED_detector found in %s\n', analysis_dir);
        fclose(fid);
        error('No LED_detector found in %s', analysis_dir);
    end
    led_data = load(fullfile(analysis_dir, led_files(end).name));
    LED = led_data.LED_detector;

    on_times  = LED.on_times;
    off_times = LED.off_times;
    num_cycles = length(on_times);
    logf('LED cycles: %d\n', num_cycles);
    logf('  Expected from protocol: %d\n\n', length(cycle_labels));

    %% Map flies to quadrants per frame
    nframes = length(trx(1).x);
    fly_quad = compute_fly_quad(trx, all_masks);

    %% Detect dead flies (position-based)
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

            x_valid = x_win(valid);
            y_valid = y_win(valid);

            mx = mean(x_valid);
            my = mean(y_valid);
            displacements = sqrt((x_valid - mx).^2 + (y_valid - my).^2);
            max_disp = max(displacements);

            if max_disp < MOVE_THRESH_PX
                fly_alive(k, w:end) = false;
                logf('  Fly %2d (trx ID %d): DEAD from cycle %d (max disp = %.1f px in cycles %d-%d)\n', ...
                    k, fly_ids_original(k), w, max_disp, w, w + CONSECUTIVE_CYCLES - 1);
                break;
            end
        end
    end

    num_dead = sum(~fly_alive(:, end));
    logf('\nDead flies removed: %d / %d\n', num_dead, num_flies);
    logf('Alive through entire recording: %d\n', sum(fly_alive(:, end)));

    dead_mask = ~fly_alive(:, end);
    logf('\n--- Fly Status Summary ---\n');
    logf('  ALIVE trx IDs: %s\n', mat2str(fly_ids_original(~dead_mask)));
    if any(dead_mask)
        logf('  DEAD  trx IDs: %s\n', mat2str(fly_ids_original(dead_mask)));
    else
        logf('  DEAD  trx IDs: none\n');
    end

    %% Recompute QPI with alive flies only

    % Map frame -> cycle index (0 if between cycles)
    frame_cycle = zeros(1, nframes);
    for c = 1:num_cycles
        fr_start = on_times(c);
        fr_end   = min(off_times(c), nframes);
        if fr_start <= nframes
            frame_cycle(fr_start:fr_end) = c;
        end
    end

    % Recount quadrants using only alive flies
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

    % Count alive flies per cycle
    flies_per_cycle = zeros(num_cycles, 1);
    for c = 1:num_cycles
        fr_start = on_times(c);
        fr_end   = min(off_times(c), nframes);
        if fr_start > nframes, continue; end
        alive_in_cycle = 0;
        for k = 1:num_flies
            if ~fly_alive(k, c), continue; end
            quads = fly_quad(k, fr_start:fr_end);
            if any(quads >= 1 & quads <= 4)
                alive_in_cycle = alive_in_cycle + 1;
            end
        end
        flies_per_cycle(c) = alive_in_cycle;
    end

    % Compute QPI
    quad_pref = zeros(nframes, 1);

    if is_single_quadrant
        % Single-quadrant QPI: (N_safe - N_other) / N_total
        % Safe quadrant changes per cycle based on quad_pattern + led_to_quad
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

            n_safe  = quad_counts_clean(fr, safe_quad + 1);  % +1 for 0-indexed column
            n_total = sum(quad_counts_clean(fr, 2:5));
            n_other = n_total - n_safe;
            if n_total > 0
                quad_pref(fr) = (n_safe - n_other) / n_total;
            end
        end
    else
        % Standard diagonal-pair QPI: (Q1+Q3 - Q2-Q4) / total
        pair1 = quad_counts_clean(:, 2) + quad_counts_clean(:, 4);  % Q1 + Q3
        pair2 = quad_counts_clean(:, 3) + quad_counts_clean(:, 5);  % Q2 + Q4
        denom = pair1 + pair2;
        valid_fr = denom > 0;
        quad_pref(valid_fr) = (pair1(valid_fr) - pair2(valid_fr)) ./ denom(valid_fr);
    end

    % Time axis
    if isfield(trx(1), 'timestamps') && ~isempty(trx(1).timestamps)
        timestamps = trx(1).timestamps(:)';
    else
        fps = trx(1).fps;
        timestamps = (0:nframes-1) / fps;
    end

    %% Plot
    fig = figure('Position', [100 100 1600 600], 'Visible', 'off');
    hold on;

    % LED on/off marker lines + per-cycle labels
    for c = 1:num_cycles
        if on_times(c) > nframes || off_times(c) > nframes
            continue;
        end
        t_on  = timestamps(on_times(c));
        t_off = timestamps(min(off_times(c), nframes));

        % Light shading for LED-on period
        if c <= length(cycle_colors)
            shade_color = cycle_colors{c} * 0.07 + 0.93;  % very faint tint
        else
            shade_color = [0.92 0.92 0.92];
        end
        patch([t_on t_off t_off t_on], [-1.1 -1.1 1.1 1.1], ...
            shade_color, 'EdgeColor', 'none');

        % ON/OFF marker lines
        plot([t_on t_on], [-1.1 1.1], 'b-', 'LineWidth', 0.3);
        plot([t_off t_off], [-1.1 1.1], 'm-', 'LineWidth', 0.3);

        % Cycle label (e.g., R1, G5, B10)
        mid_time = (t_on + t_off) / 2;
        if c <= length(cycle_labels)
            lbl = cycle_labels{c};
            lbl_color = cycle_colors{c};
        else
            lbl = sprintf('%d', c);
            lbl_color = [0.4 0.4 0.4];
        end
        text(mid_time, 1.18, lbl, ...
            'HorizontalAlignment', 'center', ...
            'FontSize', 10, 'FontWeight', 'bold', 'Color', lbl_color);

        % Fly count below the cycle label
        text(mid_time, 1.28, sprintf('n=%d', flies_per_cycle(c)), ...
            'HorizontalAlignment', 'center', ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', [0 0 0]);
    end

    % Color section headers (e.g., RED, GREEN, BLUE)
    for s = 1:length(section_info)
        sec = section_info(s);
        c_start = sec.start_cycle;
        c_end   = sec.end_cycle;
        if c_start > num_cycles, continue; end
        c_end = min(c_end, num_cycles);

        if on_times(c_start) <= nframes && off_times(c_end) <= nframes
            t_start = timestamps(on_times(c_start));
            t_end   = timestamps(min(off_times(c_end), nframes));
            text((t_start + t_end) / 2, 1.38, sec.label, ...
                'HorizontalAlignment', 'center', ...
                'FontSize', 12, 'FontWeight', 'bold', 'Color', sec.color);
        end
    end

    % Safe (white) and hot (red) zone rectangles per stimulus cycle
    for c = 1:num_cycles
        if on_times(c) > nframes || off_times(c) > nframes
            continue;
        end
        t_on  = timestamps(on_times(c));
        t_off = timestamps(min(off_times(c), nframes));

        % Get LED quadrant pattern for this cycle
        if c <= length(quad_patterns)
            qp = quad_patterns{c};
        else
            qp = '1111';
        end

        if is_single_quadrant
            % Use training_patterns to resolve safe quad for probes too
            if c <= length(training_patterns)
                tp = training_patterns{c};
            else
                tp = qp;
            end

            dark_pos = find(tp == '0');
            if length(dark_pos) == 1
                safe_quad = cfg.led_to_quad(dark_pos);

                if any(qp == '0')
                    % Training cycle — actual punishment: safe zone shading
                    patch([t_on t_off t_off t_on], [-1.1 -1.1 0 0], ...
                        [1 0.3 0.3], 'EdgeColor', 'none', 'FaceAlpha', 0.25);
                    patch([t_on t_off t_off t_on], [0 0 1.1 1.1], ...
                        [1 1 1], 'EdgeColor', 'none', 'FaceAlpha', 0.45);
                end

                % Label safe quadrant — green for training, blue for probe
                if strcmp(qp, '1111')
                    lbl_clr = [0.1 0.3 0.8];  % blue = probe (learned safe)
                else
                    lbl_clr = [0 0.6 0];      % green = training (actual safe)
                end
                text((t_on + t_off) / 2, 1.08, sprintf('Q%d', safe_quad), ...
                    'HorizontalAlignment', 'center', 'FontSize', 10, ...
                    'FontWeight', 'bold', 'Color', lbl_clr);
            end
            % OM cycles ('1111' with no paired training) get no label
        else
            % Diagonal-pair: map LED pattern to safe/hot zones
            [lit_quads, safe_quads] = led_pattern_to_quads(qp);

            if isempty(lit_quads) || isempty(safe_quads)
                continue;
            end

            lit_has_top = any(lit_quads == 1 | lit_quads == 3);
            lit_has_bottom = any(lit_quads == 2 | lit_quads == 4);

            if lit_has_bottom && ~lit_has_top
                hot_lo  = -1.1;  hot_hi  = 0;
                safe_lo = 0;     safe_hi = 1.1;
            elseif lit_has_top && ~lit_has_bottom
                hot_lo  = 0;     hot_hi  = 1.1;
                safe_lo = -1.1;  safe_hi = 0;
            else
                continue;
            end

            patch([t_on t_off t_off t_on], [hot_lo hot_lo hot_hi hot_hi], ...
                [1 0.3 0.3], 'EdgeColor', 'none', 'FaceAlpha', 0.25);
            patch([t_on t_off t_off t_on], [safe_lo safe_lo safe_hi safe_hi], ...
                [1 1 1], 'EdgeColor', 'none', 'FaceAlpha', 0.45);
        end
    end

    % Zero line
    plot([timestamps(1) timestamps(end)], [0 0], 'k--', 'LineWidth', 1);

    % QPI trace
    plot(timestamps, quad_pref, 'Color', [0 0 0], 'LineWidth', 1.5);

    set(gca, 'FontSize', 16);
    xlabel('Time (s)', 'FontSize', 18);
    if is_single_quadrant
        ylabel('QPI  (N_{safe} − N_{other}) / N_{total}', 'FontSize', 18);
    else
        ylabel('QPI  (Q1+Q3 − Q2−Q4) / total', 'FontSize', 18);
    end
    title(sprintf('%s — QPI [%s] (<%d px/%d cyc, %d/%d alive)', ...
        strrep(exp_name, '_', '\_'), protocol, MOVE_THRESH_PX, CONSECUTIVE_CYCLES, ...
        num_flies - num_dead, num_flies), 'FontSize', 20);
    ylim([-1.2 1.5]);
    xlim([timestamps(1) timestamps(end)]);
    grid on; box on;

    %% Save plot
    if opts.SavePlot
        out_base = fullfile(analysis_dir, sprintf('QPI_%s', exp_name));
        saveas(fig, [out_base '.png']);
        saveas(fig, [out_base '.svg']);
        savefig(fig, [out_base '.fig']);
        logf('\nSaved plot: %s\n', out_base);
    end

    if opts.ShowPlots
        set(fig, 'Visible', 'on');
    else
        close(fig);
    end

    %% Save .mat with all computed data
    mat_file = fullfile(analysis_dir, sprintf('QPI_%s.mat', exp_name));

    % Build per-cycle safe quadrant vector
    safe_quad_per_cycle = NaN(num_cycles, 1);
    if is_single_quadrant
        for c = 1:num_cycles
            if c <= length(training_patterns)
                tp = training_patterns{c};
            elseif c <= length(quad_patterns)
                tp = quad_patterns{c};
            else
                continue;
            end
            dp = find(tp == '0');
            if length(dp) == 1
                safe_quad_per_cycle(c) = cfg.led_to_quad(dp);
            end
        end
    end

    qpi_data = struct();
    qpi_data.experiment       = exp_name;
    qpi_data.protocol         = protocol;
    qpi_data.genotype         = strsplit(exp_name, '_'); qpi_data.genotype = qpi_data.genotype{1};
    qpi_data.timestamps       = timestamps;
    qpi_data.quad_pref        = quad_pref;              % [nframes x 1] frame-wise QPI
    qpi_data.fly_quad         = fly_quad;               % [num_flies x nframes] quadrant per fly per frame
    qpi_data.fly_alive        = fly_alive;              % [num_flies x num_cycles] alive status
    qpi_data.fly_ids_original = fly_ids_original;       % original trx indices
    qpi_data.num_flies        = num_flies;
    qpi_data.on_times         = on_times;
    qpi_data.off_times        = off_times;
    qpi_data.num_cycles       = num_cycles;
    qpi_data.quad_patterns    = quad_patterns;           % actual LED patterns per cycle
    qpi_data.training_patterns = training_patterns;      % training-equivalent patterns (for probes)
    qpi_data.safe_quad_per_cycle = safe_quad_per_cycle;  % safe quadrant number per cycle (NaN for OM)
    qpi_data.is_single_quadrant  = is_single_quadrant;
    qpi_data.cycle_labels     = cycle_labels;
    qpi_data.flies_per_cycle  = flies_per_cycle;
    qpi_data.quad_counts_clean = quad_counts_clean;      % [nframes x 5] per-quadrant fly counts (alive only)

    save(mat_file, '-struct', 'qpi_data');
    logf('\nSaved data: %s\n', mat_file);

    %% Per-cycle summary table in log
    logf('\n--- Per-cycle fly counts ---\n');
    logf('Cycle | Label | Alive flies | Alive trx IDs\n');
    logf('------+-------+-------------+-----------------------------\n');
    for c = 1:num_cycles
        alive_idx = find(fly_alive(:, c));
        alive_trx_ids = fly_ids_original(alive_idx);
        if c <= length(cycle_labels)
            lbl = cycle_labels{c};
        else
            lbl = '?';
        end
        logf(' %3d  | %-5s |     %2d      | %s\n', c, lbl, flies_per_cycle(c), mat2str(alive_trx_ids));
    end

    logf('\nSaved log: %s\n', log_file);
    logf('Done.\n');

    fclose(fid);

end

%% ======== LOCAL HELPERS ========

function fprintf_both(fid, varargin)
    fprintf(varargin{:});
    fprintf(fid, varargin{:});
end

function [labels, colors, sections, quad_patterns] = get_protocol_labels(protocol)
    cfg = get_protocol_config(protocol);
    labels = cfg.labels;
    colors = cfg.colors;
    sections = cfg.sections;
    quad_patterns = cfg.quad_patterns;
end
