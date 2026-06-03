function qc_qpi_frames(exp_path, varargin)
% QC_QPI_FRAMES  Visual QC for QPI — random frame snapshots per cycle
%
%   qc_qpi_frames(exp_path)
%   qc_qpi_frames(exp_path, 'Name', Value, ...)
%
%   Builds a per-cycle LUT from original_metadata.txt (ground truth) that
%   maps each cycle to: lit quadrants, safe quadrants, LED pattern, cycle
%   label, ON/OFF frame range, and sampled frame numbers with fly positions.
%
%   For each LED cycle, pulls N random frames from the LAST HALF of the
%   ON period. Each frame is rendered as:
%     - Arena background (dimmed)
%     - Lit quadrants tinted red
%     - Safe (dark) quadrants left as dimmed background (no color)
%     - Fly positions as colored dots
%     - Dead flies marked with X
%     - Frame number label above each panel
%
%   Also saves a QC LUT text file alongside the PNGs.
%
%   Saves into <exp>/analysis/qc_qpi_frames/.
%
%   NAME-VALUE PARAMETERS
%     'Protocol'        — protocol name (default: auto-detect from path)
%     'NumFrames'       — frames to sample per cycle (default: 4)
%     'ShowPlots'       — display figures (default: false)

    %% Parse inputs
    ip = inputParser;
    addRequired(ip, 'exp_path', @ischar);
    addParameter(ip, 'Protocol', '', @ischar);
    addParameter(ip, 'NumFrames', 4, @isnumeric);
    addParameter(ip, 'ShowPlots', false, @islogical);
    parse(ip, exp_path, varargin{:});
    opts = ip.Results;

    [~, exp_name] = fileparts(exp_path);
    analysis_dir = fullfile(exp_path, 'analysis');

    %% Auto-detect protocol
    protocol = opts.Protocol;
    if isempty(protocol)
        [parent_dir, ~] = fileparts(exp_path);
        [~, protocol] = fileparts(parent_dir);
    end

    fprintf('QC QPI frames: %s (%s)\n', exp_name, protocol);

    %% ---- Build quad pattern LUT from metadata (ground truth) ----
    % Primary source: original_metadata.txt via parse_metadata_led_patterns
    % Fallback: get_protocol_config (with warning)
    metadata_patterns = parse_metadata_led_patterns(exp_path);
    cfg = get_protocol_config(protocol);
    cycle_labels = cfg.labels;

    if ~isempty(metadata_patterns)
        quad_patterns = metadata_patterns;
        pattern_source = 'metadata';
        fprintf('  Quad patterns: from original_metadata.txt (%d cycles)\n', length(quad_patterns));
    else
        quad_patterns = cfg.quad_patterns;
        pattern_source = 'config';
        fprintf('  WARNING: No metadata — using config quad patterns (VERIFY MANUALLY)\n');
    end

    %% Load trx
    trx_data = load(fullfile(exp_path, 'trx.mat'), 'trx');
    trx = trx_data.trx;

    % Filter full-span flies
    max_end = max([trx.endframe]);
    good = [];
    for k = 1:length(trx)
        if trx(k).firstframe == 1 && trx(k).endframe >= (max_end - 30)
            good = [good, k]; %#ok<AGROW>
        end
    end
    trx = trx(good);
    nFlies = length(trx);

    %% Load background
    bg_files = dir(fullfile(analysis_dir, 'background_*.png'));
    if isempty(bg_files)
        error('No background PNG in %s', analysis_dir);
    end
    bg = imread(fullfile(analysis_dir, bg_files(1).name));
    if size(bg, 3) == 1, bg = repmat(bg, [1 1 3]); end

    %% Load arena calibration
    calib_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    if isempty(calib_files)
        error('No arena_calib in %s', analysis_dir);
    end
    C = load(fullfile(analysis_dir, calib_files(end).name));
    xc     = C.arena_calib.xc;
    yc     = C.arena_calib.yc;
    radius = C.arena_calib.radius;
    all_masks = C.arena_calib.all_masks;

    %% Load LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    if isempty(led_files)
        error('No LED_detector in %s', analysis_dir);
    end
    L = load(fullfile(analysis_dir, led_files(end).name));
    if isfield(L, 'LED_detector')
        on_times  = double(L.LED_detector.on_times(:)');
        off_times = double(L.LED_detector.off_times(:)');
    elseif isfield(L, 'LED_detector_thresh')
        on_times  = double(L.LED_detector_thresh.on_times(:)');
        off_times = double(L.LED_detector_thresh.off_times(:)');
    end
    nCycles = length(on_times);
    nframes = length(trx(1).x);

    %% Dead fly info — same priority chain as rest of pipeline
    fly_alive = [];

    % Priority 1: dead_fly_report.mat
    dead_fly_file = fullfile(analysis_dir, 'dead_fly_report.mat');
    if exist(dead_fly_file, 'file')
        loaded = load(dead_fly_file, 'dead_report');
        if isfield(loaded, 'dead_report') && isfield(loaded.dead_report, 'fly_alive')
            fly_alive = loaded.dead_report.fly_alive;
            fprintf('  Dead fly info: dead_fly_report.mat\n');
        end
    end

    % Priority 2: detect_dead_flies_posture (runtime)
    if isempty(fly_alive)
        if isfield(L, 'LED_detector')
            LED = L.LED_detector;
        else
            LED = L.LED_detector_thresh;
        end
        fprintf('  Dead fly info: running detect_dead_flies_posture\n');
        [fly_alive, ~] = detect_dead_flies_posture(trx, LED);
    end

    % Ensure dimensions match after filtering
    if size(fly_alive, 1) ~= nFlies
        fprintf('  WARNING: fly_alive has %d rows but %d flies — resetting to all alive\n', ...
            size(fly_alive, 1), nFlies);
        fly_alive = true(nFlies, nCycles);
    end

    %% ---- Build the full LUT ----
    % Struct array: one entry per cycle with all QC-relevant info
    lut = struct();
    for c = 1:nCycles
        % LED pattern for this cycle
        if c <= length(quad_patterns)
            qp = quad_patterns{c};
        else
            qp = '1111';
            fprintf('  WARNING: Cycle %d beyond metadata — defaulting to 1111\n', c);
        end

        % Map LED pattern to physical quadrants (hardware mapping)
        [lit_q, safe_q] = led_pattern_to_quads(qp);

        % Cycle label
        if c <= length(cycle_labels)
            lbl = cycle_labels{c};
        else
            lbl = sprintf('C%d', c);
        end

        % Frame range
        fr_on  = on_times(c);
        fr_off = min(off_times(c), nframes);

        lut(c).cycle       = c;
        lut(c).label       = lbl;
        lut(c).led_pattern = qp;
        lut(c).lit_quads   = lit_q;
        lut(c).safe_quads  = safe_q;
        lut(c).frame_on    = fr_on;
        lut(c).frame_off   = fr_off;
        lut(c).source      = pattern_source;
    end

    %% Fly colors — no red or green to avoid confusion with quadrant overlay
    fly_cmap = [
        0.12 0.47 0.71;   % blue
        1.00 0.50 0.05;   % orange
        0.58 0.40 0.74;   % purple
        0.55 0.34 0.29;   % brown
        0.89 0.47 0.76;   % pink
        0.09 0.75 0.81;   % cyan
        0.74 0.74 0.13;   % olive
        0.50 0.50 0.50;   % grey
        0.00 0.30 0.50;   % dark blue
        1.00 0.75 0.00;   % gold
        0.40 0.20 0.60;   % indigo
        0.80 0.60 0.40;   % tan
    ];

    %% Create output directory
    save_dir = fullfile(analysis_dir, 'qc_qpi_frames');
    if ~exist(save_dir, 'dir'), mkdir(save_dir); end

    theta_c = linspace(0, 2*pi, 200);
    N = opts.NumFrames;

    %% Open LUT text file for writing
    lut_file = fullfile(save_dir, sprintf('qc_lut_%s.txt', exp_name));
    fid_lut = fopen(lut_file, 'w');
    fprintf(fid_lut, 'QC LUT — %s (%s)\n', exp_name, protocol);
    fprintf(fid_lut, 'Pattern source: %s\n', pattern_source);
    fprintf(fid_lut, 'Date: %s\n', datestr(now));
    fprintf(fid_lut, '============================================================\n');
    fprintf(fid_lut, '%-6s %-8s %-8s %-14s %-14s %-12s %-12s\n', ...
        'Cycle', 'Label', 'LED', 'Lit_Quads', 'Safe_Quads', 'Frame_ON', 'Frame_OFF');
    fprintf(fid_lut, '------------------------------------------------------------\n');

    %% Process each cycle
    for c = 1:nCycles
        qp        = lut(c).led_pattern;
        lit_quads  = lut(c).lit_quads;
        safe_quads = lut(c).safe_quads;
        lbl        = lut(c).label;
        fr_on      = lut(c).frame_on;
        fr_off     = lut(c).frame_off;

        if fr_on >= nframes, continue; end

        % Format quad lists for display
        lit_str  = strjoin(arrayfun(@(q) sprintf('Q%d', q), lit_quads, 'UniformOutput', false), ',');
        safe_str = strjoin(arrayfun(@(q) sprintf('Q%d', q), safe_quads, 'UniformOutput', false), ',');
        if isempty(safe_str), safe_str = 'none'; end

        % Write LUT line
        fprintf(fid_lut, '%-6d %-8s %-8s %-14s %-14s %-12d %-12d\n', ...
            c, lbl, qp, lit_str, safe_str, fr_on, fr_off);

        % Last half of the ON period
        mid = round((fr_on + fr_off) / 2);
        candidate_frames = mid:fr_off;
        if length(candidate_frames) < N
            candidate_frames = fr_on:fr_off;
        end

        % Pick N random frames
        if length(candidate_frames) <= N
            sample_frames = candidate_frames;
        else
            idx = randperm(length(candidate_frames), N);
            sample_frames = sort(candidate_frames(idx));
        end

        % Write sampled frames + fly positions to LUT
        fprintf(fid_lut, '  Sampled frames: [%s]\n', num2str(sample_frames));
        for fi = 1:length(sample_frames)
            fr = sample_frames(fi);
            for k = 1:nFlies
                fx = double(trx(k).x(fr));
                fy = double(trx(k).y(fr));
                alive_str = 'alive';
                if ~fly_alive(k, c), alive_str = 'DEAD'; end
                fprintf(fid_lut, '    Frame %d | Fly %d (trx %d): x=%.1f y=%.1f [%s]\n', ...
                    fr, k, good(k), fx, fy, alive_str);
            end
        end

        % Human-readable pattern description for title
        if strcmp(qp, '1111')
            pattern_str = sprintf('ALL ON (probe) — %s', lit_str);
        else
            pattern_str = sprintf('%s lit | %s safe', lit_str, safe_str);
        end

        % Build figure: 1 row × N columns
        fig = figure('Units', 'pixels', 'Position', [50 50 N*350 450], 'Visible', 'off');

        for fi = 1:length(sample_frames)
            fr = sample_frames(fi);

            ax = subplot(1, N, fi);

            % Dimmed background
            bg_dim = uint8(double(bg) * 0.4);

            % Red overlay on LIT quadrants only; safe quads stay dimmed
            overlay = double(bg_dim);
            red_tint = [0.6, 0.05, 0.05];

            for qi = lit_quads
                mask_qi = (all_masks == qi);
                for ch = 1:3
                    channel = overlay(:,:,ch);
                    channel(mask_qi) = channel(mask_qi) * 0.6 + red_tint(ch) * 255 * 0.4;
                    overlay(:,:,ch) = channel;
                end
            end

            imshow(uint8(overlay), 'Parent', ax);
            hold(ax, 'on');
            axis(ax, 'image');

            % Arena circle
            plot(ax, xc + radius*cos(theta_c), yc + radius*sin(theta_c), ...
                'w-', 'LineWidth', 0.8);

            % Quadrant dividing lines
            if isfield(C.arena_calib, 'vert_coef') && isfield(C.arena_calib, 'horiz_coef')
                vc = C.arena_calib.vert_coef;
                hc = C.arena_calib.horiz_coef;
            elseif isfield(C.arena_calib, 'vert_line_coef') && isfield(C.arena_calib, 'horiz_line_coef')
                vc = C.arena_calib.vert_line_coef;
                hc = C.arena_calib.horiz_line_coef;
            else
                vc = []; hc = [];
            end

            if ~isempty(vc) && ~isempty(hc)
                y_range = [yc - radius, yc + radius];
                x_vert = polyval(vc, y_range);
                plot(ax, x_vert, y_range, 'w--', 'LineWidth', 0.5);

                x_range = [xc - radius, xc + radius];
                y_horiz = polyval(hc, x_range);
                plot(ax, x_range, y_horiz, 'w--', 'LineWidth', 0.5);
            end

            % Quadrant labels — positions from canonical layout
            q_layout = get_quadrant_layout();
            for qi = 1:4
                qx = xc + q_layout(qi).sign_x * radius * 0.45;
                qy = yc + q_layout(qi).sign_y * radius * 0.45;
                if ismember(qi, lit_quads)
                    q_label = sprintf('%s (lit)', q_layout(qi).name);
                else
                    q_label = sprintf('%s (safe)', q_layout(qi).name);
                end
                text(ax, qx, qy, q_label, 'Color', 'w', 'FontSize', 6, ...
                    'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            end

            % Plot fly positions at this frame
            for k = 1:nFlies
                fx = double(trx(k).x(fr));
                fy = double(trx(k).y(fr));
                col = fly_cmap(mod(k-1, size(fly_cmap,1)) + 1, :);

                if ~fly_alive(k, c)
                    % Dead fly: X marker
                    plot(ax, fx, fy, 'x', 'Color', [0.7 0.0 0.0], ...
                        'MarkerSize', 8, 'LineWidth', 2);
                else
                    % Alive fly: filled circle with black edge
                    plot(ax, fx, fy, 'o', 'Color', 'k', ...
                        'MarkerFaceColor', col, 'MarkerSize', 7, 'LineWidth', 0.8);
                end
            end

            % Crop to arena with margin
            margin = radius * 0.08;
            xlim(ax, [xc - radius - margin, xc + radius + margin]);
            ylim(ax, [yc - radius - margin, yc + radius + margin]);
            set(ax, 'XTick', [], 'YTick', []);
            title(ax, sprintf('Frame %d', fr), 'FontSize', 10, 'FontWeight', 'bold', 'Color', 'k');

            hold(ax, 'off');
        end

        % Super title with cycle info + pattern source + fly count
        n_alive = sum(fly_alive(:, c));
        sgtitle(fig, sprintf('%s — Cycle %d (%s) — %s — n=%d flies', ...
            strrep(exp_name, '_', '\_'), c, lbl, pattern_str, n_alive), ...
            'FontSize', 10, 'FontWeight', 'bold');

        % Save
        out_png = fullfile(save_dir, sprintf('qc_cycle%02d_%s.png', c, lbl));
        exportgraphics(fig, out_png, 'Resolution', 150);
        if opts.ShowPlots
            drawnow;
        else
            close(fig);
        end
    end

    fclose(fid_lut);
    fprintf('  Saved %d QC frames + LUT to: %s\n', nCycles, save_dir);
end


%% (parse_qpi_log_qc removed — dead fly info now uses dead_fly_report.mat
%%  or detect_dead_flies_posture, same priority chain as rest of pipeline)
