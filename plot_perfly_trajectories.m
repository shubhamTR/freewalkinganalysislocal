function plot_perfly_trajectories(protocol, varargin)
% PLOT_PERFLY_TRAJECTORIES  Per-fly trajectory dashboard for all cycles
%
%   plot_perfly_trajectories('P008')
%   plot_perfly_trajectories('P019', 'ShowPlots', true, 'Experiments', {'L2A_Rig1_...'})
%
%   For each experiment in the protocol, generates one figure per fly showing
%   trajectory in every LED cycle. Layout is a tiled grid (cols x rows) where
%   each tile = one cycle. Cycle panels are color-coded by type (training,
%   probe, OM, Ag) using get_protocol_config colors.
%
%   Inspired by Plottrajectoryandvelocity_V1.m per-cycle trajectory logic.
%
%   OUTPUT
%     Saved to <protocol>/<exp_name>/perflytrajectories/fly<NN>_<exp_name>.png
%
%   NAME-VALUE PARAMETERS
%     'AnalysisDir' — data root (default: '/Users/rathores/Documents/analysisdatalocal')
%     'ShowPlots'   — keep figures visible (default: false)
%     'SavePlot'    — save PNG (default: true)
%     'Experiments' — cell array of experiment names to process (default: all)
%     'FPS'         — frame rate (default: 30.1)
%     'Cols'        — number of tile columns (default: auto from num_cycles)
%     'FlyIndex'    — vector of fly indices to plot (default: [] = all alive)

    p = inputParser;
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(p, 'ShowPlots', false, @islogical);
    addParameter(p, 'SavePlot', true, @islogical);
    addParameter(p, 'Experiments', {}, @iscell);
    addParameter(p, 'FPS', 30.1, @isnumeric);
    addParameter(p, 'Cols', 0, @isnumeric);
    addParameter(p, 'FlyIndex', [], @isnumeric);
    parse(p, protocol, varargin{:});
    opts = p.Results;

    prot_dir = fullfile(opts.AnalysisDir, protocol);
    cfg = get_protocol_config(protocol);
    num_cycles_expected = cfg.num_cycles;

    %% Determine grid layout
    if opts.Cols > 0
        ncols = opts.Cols;
    else
        ncols = choose_cols(num_cycles_expected);
    end
    nrows = ceil(num_cycles_expected / ncols);

    %% Safe zone info
    is_single_quad = isfield(cfg, 'led_to_quad') && ~isempty(cfg.led_to_quad);
    if ~is_single_quad
        SAFE_QUADS = [2, 4];
    else
        SAFE_QUADS = [];
    end

    %% Discover experiments
    exp_dirs = dir(prot_dir);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));
    keep = false(length(exp_dirs), 1);
    for d = 1:length(exp_dirs)
        name = exp_dirs(d).name;
        keep(d) = ~isempty(name) && isletter(name(1)) && contains(name, '_Rig');
    end
    exp_dirs = exp_dirs(keep);

    if ~isempty(opts.Experiments)
        keep2 = ismember({exp_dirs.name}, opts.Experiments);
        exp_dirs = exp_dirs(keep2);
    end

    fprintf('=== Per-Fly Trajectory Dashboard: %s ===\n', protocol);
    fprintf('%d cycles (%d x %d grid), %d experiments\n\n', ...
        num_cycles_expected, nrows, ncols, length(exp_dirs));

    %% Fly color palette
    fly_cmap = [
        0.12 0.47 0.71;  0.89 0.10 0.11;  0.17 0.63 0.17;
        1.00 0.50 0.05;  0.58 0.40 0.74;  0.55 0.34 0.29;
        0.89 0.47 0.76;  0.50 0.50 0.50;  0.74 0.74 0.13;
        0.09 0.75 0.81;  0.00 0.30 0.50;  0.70 0.13 0.13;
        0.30 0.70 0.50;
    ];

    %% Section color map for panel borders
    section_colors = build_section_colormap(cfg);

    %% Loop experiments
    for ei = 1:length(exp_dirs)
        exp_name = exp_dirs(ei).name;
        exp_path = fullfile(prot_dir, exp_name);
        analysis_dir = fullfile(exp_path, 'analysis');

        % Output directory (inside experiment folder)
        out_dir = fullfile(exp_path, 'perflytrajectories');
        if ~exist(out_dir, 'dir'), mkdir(out_dir); end

        fprintf('[%d/%d] %s\n', ei, length(exp_dirs), exp_name);

        try
            %% Load trx
            trx_data = load(fullfile(exp_path, 'trx.mat'));
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
            num_flies = length(trx);

            %% Load arena calibration
            arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
            if isempty(arena_files)
                fprintf('  SKIP — no arena_calib\n');
                continue;
            end
            arena_data = load(fullfile(analysis_dir, arena_files(end).name));
            if isfield(arena_data, 'arena_calib')
                ac = arena_data.arena_calib;
            else
                ac = arena_data;
            end
            xc = ac.xc; yc = ac.yc; radius = ac.radius;
            all_masks = ac.all_masks;

            %% Quad patterns: metadata is ground truth, config is fallback
            %  training_patterns gives the *paired* LED for probes (from ori),
            %  so safe-zone shading reflects what the fly learned, not what's displayed.
            [metadata_patterns, metadata_training] = parse_metadata_led_patterns(exp_path);
            if ~isempty(metadata_training)
                quad_patterns = metadata_training;
            elseif ~isempty(metadata_patterns)
                quad_patterns = metadata_patterns;
            else
                quad_patterns = cfg.quad_patterns;
            end

            %% Load LED detector
            led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
            if isempty(led_files)
                fprintf('  SKIP — no LED_detector\n');
                continue;
            end
            led_data = load(fullfile(analysis_dir, led_files(end).name));
            if isfield(led_data, 'LED_detector')
                LED = led_data.LED_detector;
            else
                LED = led_data;
            end
            on_times  = LED.on_times;
            off_times = LED.off_times;
            num_cycles = min(length(on_times), length(off_times));

            %% Load dead fly info
            fly_alive = true(num_flies, num_cycles);
            log_file = fullfile(analysis_dir, sprintf('QPI_log_%s.txt', exp_name));
            if exist(log_file, 'file')
                fly_alive = parse_qpi_log(log_file, num_flies, num_cycles, good);
            end

            %% Background image
            bg = load_background(exp_path, analysis_dir);

            %% Arena circle coordinates
            theta_c = linspace(0, 2*3.141592653589793, 200);
            arena_cx = xc + radius * cos(theta_c);
            arena_cy = yc + radius * sin(theta_c);

            %% Determine which flies to plot
            if ~isempty(opts.FlyIndex)
                fly_list = opts.FlyIndex(opts.FlyIndex <= num_flies);
            else
                fly_list = 1:num_flies;
            end

            %% Generate one figure per fly
            for fi = fly_list
                col = fly_cmap(mod(fi - 1, size(fly_cmap, 1)) + 1, :);

                fig = figure('Units', 'normalized', ...
                    'Position', [0.02 0.02 0.95 0.90], ...
                    'Visible', 'off', 'Color', 'k', 'Renderer', 'painters');

                t = tiledlayout(nrows, ncols, ...
                    'TileSpacing', 'compact', 'Padding', 'compact');

                for ci = 1:num_cycles_expected
                    ax = nexttile(t);

                    if ci > num_cycles
                        % Cycle not detected (LED mismatch)
                        set(ax, 'Color', [0.1 0.1 0.1], 'XTick', [], 'YTick', []);
                        title(ax, sprintf('C%d (no data)', ci), ...
                            'FontSize', 7, 'Color', [0.5 0.5 0.5]);
                        continue;
                    end

                    plot_cycle_panel(ax, fi, ci, trx, fly_alive, ...
                        on_times, off_times, all_masks, ...
                        xc, yc, radius, arena_cx, arena_cy, bg, ...
                        cfg, is_single_quad, SAFE_QUADS, col, ...
                        section_colors, opts.FPS, quad_patterns);
                end

                % Is fly dead at any point?
                first_dead = find(~fly_alive(fi, :), 1, 'first');
                if isempty(first_dead)
                    dead_str = 'alive';
                else
                    dead_str = sprintf('dead from cycle %d', first_dead);
                end

                title(t, sprintf('%s — %s — Fly %d (%s)', ...
                    protocol, strrep(exp_name, '_', '\_'), fi, dead_str), ...
                    'FontSize', 13, 'FontWeight', 'bold', 'Color', 'w', ...
                    'Interpreter', 'none');

                if opts.SavePlot
                    out_file = fullfile(out_dir, ...
                        sprintf('fly%02d_%s.png', fi, exp_name));
                    exportgraphics(fig, out_file, 'Resolution', 150, ...
                        'BackgroundColor', 'k');
                end

                if opts.ShowPlots
                    set(fig, 'Visible', 'on');
                else
                    close(fig);
                end
            end

            fprintf('  %d flies saved to %s/perflytrajectories/\n', ...
                length(fly_list), exp_name);

        catch ME
            fprintf('  FAILED: %s\n', ME.message);
        end
    end

    fprintf('\nDone — %s per-fly trajectories.\n', protocol);
end


%% ========== Cycle panel ==========

function plot_cycle_panel(ax, fi, ci, trx, fly_alive, ...
    on_times, off_times, all_masks, ...
    xc, yc, radius, arena_cx, arena_cy, bg, ...
    cfg, is_single_quad, SAFE_QUADS, fly_color, ...
    section_colors, ~, quad_patterns)

    fr_on  = on_times(ci);
    fr_off = off_times(ci);

    %% Determine safe quadrants (from metadata patterns)
    if is_single_quad
        if ci <= length(quad_patterns)
            qp = quad_patterns{ci};
        else
            qp = '1111';
        end
        dark_pos = find(qp == '0');
        if length(dark_pos) == 1 && isfield(cfg, 'led_to_quad')
            safe_quads = cfg.led_to_quad(dark_pos);
        elseif isfield(cfg, 'probe_target_quad')
            safe_quads = cfg.probe_target_quad;
        else
            safe_quads = [];
        end
    else
        safe_quads = SAFE_QUADS;
    end

    %% Background
    if ~isempty(bg)
        imshow(bg * 0.30, 'Parent', ax);
        hold(ax, 'on');
    else
        hold(ax, 'on');
        set(ax, 'Color', [0.1 0.1 0.1]);
    end
    axis(ax, 'image');

    %% Arena circle
    plot(ax, arena_cx, arena_cy, 'w-', 'LineWidth', 0.5);
    % Quadrant dividers (thin)
    plot(ax, [xc - radius, xc + radius], [yc, yc], 'w--', 'LineWidth', 0.3);
    plot(ax, [xc, xc], [yc - radius, yc + radius], 'w--', 'LineWidth', 0.3);

    %% Shade safe quadrants
    for sq = safe_quads
        shade_safe_quadrant(ax, sq, xc, yc, radius);
    end

    %% Trajectory
    xpos = double(trx(fi).x);
    ypos = double(trx(fi).y);
    nfr = length(xpos);
    fr_end = min(fr_off, nfr);

    is_dead = ~fly_alive(fi, ci);

    if fr_on <= nfr && ~all(isnan(xpos(fr_on:fr_end)))
        col = fly_color;
        if is_dead
            col = col * 0.3;
        end

        % Trajectory line
        plot(ax, xpos(fr_on:fr_end), ypos(fr_on:fr_end), '-', ...
            'Color', [col 0.8], 'LineWidth', 1.2);

        % Start marker: filled circle
        plot(ax, xpos(fr_on), ypos(fr_on), 'o', ...
            'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 5);

        % End marker: X
        plot(ax, xpos(fr_end), ypos(fr_end), 'x', ...
            'Color', col, 'MarkerSize', 7, 'LineWidth', 1.5);

        % First entry into safe quadrant: filled square
        if ~isempty(safe_quads)
            for fr = fr_on:fr_end
                xi = round(xpos(fr)); yi = round(ypos(fr));
                if ~isnan(xi) && ~isnan(yi) && ...
                   yi >= 1 && yi <= size(all_masks,1) && ...
                   xi >= 1 && xi <= size(all_masks,2)
                    q = all_masks(yi, xi);
                    if ismember(q, safe_quads)
                        plot(ax, xpos(fr), ypos(fr), 's', ...
                            'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 5);
                        break;
                    end
                end
            end
        end
    end

    %% Format
    xlim(ax, [xc - radius * 1.08, xc + radius * 1.08]);
    ylim(ax, [yc - radius * 1.08, yc + radius * 1.08]);
    set(ax, 'XTick', [], 'YTick', []);

    % Cycle label and type color
    if ci <= length(cfg.labels)
        lbl = cfg.labels{ci};
    else
        lbl = sprintf('C%d', ci);
    end

    % Get section color for title
    if ci <= length(section_colors)
        title_col = section_colors(ci, :);
    else
        title_col = [0.7 0.7 0.7];
    end

    if is_dead
        lbl = [lbl ' (dead)'];
        title_col = [0.4 0.4 0.4];
    end

    title(ax, lbl, 'FontSize', 7, 'Color', title_col, 'FontWeight', 'bold');

    hold(ax, 'off');
end


%% ========== Helpers ==========

function ncols = choose_cols(num_cycles)
    % Pick a reasonable number of columns for the grid
    if num_cycles <= 12
        ncols = 4;
    elseif num_cycles <= 24
        ncols = 6;
    elseif num_cycles <= 37
        ncols = 8;
    elseif num_cycles <= 48
        ncols = 10;
    else
        ncols = 10;
    end
end


function section_colors = build_section_colormap(cfg)
    % Map each cycle index to the color from get_protocol_config
    n = cfg.num_cycles;
    section_colors = repmat([0.7 0.7 0.7], n, 1);  % default grey
    for ci = 1:min(n, length(cfg.colors))
        c = cfg.colors{ci};
        if ~isempty(c) && isnumeric(c) && length(c) == 3
            section_colors(ci, :) = c;
        end
    end
end


function shade_safe_quadrant(ax, quad_num, xc, yc, radius)
    r = radius * 1.05;
    switch quad_num
        case 1  % Top-Right
            xx = [xc, xc + r, xc + r, xc];
            yy = [yc, yc, yc - r, yc - r];
        case 2  % Top-Left
            xx = [xc, xc - r, xc - r, xc];
            yy = [yc, yc, yc - r, yc - r];
        case 3  % Bottom-Left
            xx = [xc, xc - r, xc - r, xc];
            yy = [yc, yc, yc + r, yc + r];
        case 4  % Bottom-Right
            xx = [xc, xc + r, xc + r, xc];
            yy = [yc, yc, yc + r, yc + r];
    end
    patch(ax, xx, yy, [0 0.8 0.3], 'FaceAlpha', 0.20, 'EdgeColor', 'none');
end


function bg = load_background(exp_path, analysis_dir)
    bg = [];
    movie_bg_file = fullfile(exp_path, 'movie-bg.mat');
    if exist(movie_bg_file, 'file')
        movie_bg_data = load(movie_bg_file);
        if isfield(movie_bg_data, 'bg') && isfield(movie_bg_data.bg, 'bg_mean')
            bg_raw = movie_bg_data.bg.bg_mean;
        elseif isfield(movie_bg_data, 'bg_mean')
            bg_raw = movie_bg_data.bg_mean;
        else
            bg_raw = [];
        end
        if ~isempty(bg_raw)
            bg_raw = double(bg_raw);
            if max(bg_raw(:)) <= 1.0
                bg_raw = bg_raw * 255;
            end
            bg = uint8(bg_raw);
            if size(bg, 3) == 1, bg = repmat(bg, [1 1 3]); end
        end
    end
    if isempty(bg)
        bg_search = {
            dir(fullfile(analysis_dir, 'background_*.png'))
            dir(fullfile(exp_path, 'background_*.png'))
        };
        for si = 1:length(bg_search)
            bf = bg_search{si};
            if ~isempty(bf)
                bg = imread(fullfile(bf(1).folder, bf(1).name));
                if size(bg, 3) == 1, bg = repmat(bg, [1 1 3]); end
                break;
            end
        end
    end
end


function fly_alive = parse_qpi_log(log_file, num_flies, num_cycles, fly_ids)
    fly_alive = true(num_flies, num_cycles);
    try
        fid = fopen(log_file, 'r');
        if fid < 0, return; end
        raw = textscan(fid, '%s', 'Delimiter', '\n');
        fclose(fid);
        lines = raw{1};

        for li = 1:length(lines)
            ln = strtrim(lines{li});
            if startsWith(ln, 'Dead fly detected:')
                tok1 = regexp(ln, 'trx index (\d+)', 'tokens');
                tok2 = regexp(ln, 'from cycle (\d+)', 'tokens');
                if ~isempty(tok1) && ~isempty(tok2)
                    trx_idx = str2double(tok1{1}{1});
                    from_cycle = str2double(tok2{1}{1});
                    fi = find(fly_ids == trx_idx, 1);
                    if ~isempty(fi) && from_cycle <= num_cycles
                        fly_alive(fi, from_cycle:end) = false;
                    end
                end
            end
        end
    catch
    end
end
