function plot_probe_trajectories(protocol, varargin)
% PLOT_PROBE_TRAJECTORIES  Per-experiment probe trial trajectories
%
%   plot_probe_trajectories('P014')
%   plot_probe_trajectories('P016', 'ShowPlots', true)
%   plot_probe_trajectories('P008', 'Experiments', {'L2A_20250401_Rig2'})
%
%   For each experiment in the protocol, generates a figure with one panel
%   per probe trial (PP, B1.P, B2.P, B3.P, B4.P) showing the first 20s:
%     - Arena background (dimmed) with circle and quadrant dividers
%     - Safe quadrants shaded green (Q2+Q4 for diagonal-pair protocols)
%     - Per-fly trajectories for first 20 seconds of each probe
%     - Markers: filled circle = start, filled square = first safe entry, X = end
%     - Consistent fly colors across all panels within an experiment
%
%   Adapted from FreewalkingAnalysisPipeline/plot_trajectories_p013.m
%
%   NAME-VALUE PARAMETERS
%     'AnalysisDir' — data root (default: '/Users/rathores/Documents/analysisdatalocal')
%     'ShowPlots'   — keep figures visible (default: false)
%     'SavePlot'    — save PNG (default: true)
%     'Experiments' — cell array of experiment names to process (default: all)
%     'FPS'         — frame rate (default: 30.1)
%     'Duration'    — seconds to plot per probe (default: 20)

    p = inputParser;
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(p, 'ShowPlots', false, @islogical);
    addParameter(p, 'SavePlot', true, @islogical);
    addParameter(p, 'Experiments', {}, @iscell);
    addParameter(p, 'FPS', 30.1, @isnumeric);
    addParameter(p, 'Duration', 20, @isnumeric);  % seconds to plot
    parse(p, protocol, varargin{:});
    opts = p.Results;

    prot_dir = fullfile(opts.AnalysisDir, protocol);
    cfg = get_protocol_config(protocol);
    num_cycles_expected = cfg.num_cycles;

    %% Identify safe quadrants from protocol config
    % Diagonal-pair protocols (P006-P012, P014-P016): Q2+Q4 safe
    % Single-quad protocols (P013, P017): single dark quadrant per cycle
    is_single_quad = isfield(cfg, 'led_to_quad');
    if is_single_quad
        SAFE_QUADS = [];  % determined per-cycle in panel function
    else
        SAFE_QUADS = [2, 4];  % diagonal pair
    end

    %% Collect probe cycle indices: PP, B1.P–B4.P (no Ag)
    probe_cycles = [];
    probe_labels = {};
    for c = 1:num_cycles_expected
        if c <= length(cfg.labels)
            lbl = cfg.labels{c};
            if strcmp(lbl, 'PP') || endsWith(lbl, '.P')
                probe_cycles = [probe_cycles, c]; %#ok<AGROW>
                probe_labels{end+1} = lbl; %#ok<AGROW>
            end
        end
    end
    fprintf('Protocol %s — Probe cycles: %s\n', protocol, strjoin(probe_labels, ', '));

    %% Discover experiments
    exp_dirs = dir(prot_dir);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));
    % Filter to experiment folders only (contain '_Rig')
    keep = false(length(exp_dirs), 1);
    for d = 1:length(exp_dirs)
        name = exp_dirs(d).name;
        keep(d) = ~isempty(name) && isletter(name(1)) && contains(name, '_Rig');
    end
    exp_dirs = exp_dirs(keep);

    % Filter to user-specified experiments if provided
    if ~isempty(opts.Experiments)
        keep2 = ismember({exp_dirs.name}, opts.Experiments);
        exp_dirs = exp_dirs(keep2);
    end

    fprintf('Processing %d experiments in %s\n\n', length(exp_dirs), protocol);

    %% Fly color palette (consistent per fly index)
    fly_cmap = [
        0.12 0.47 0.71;   % blue
        0.89 0.10 0.11;   % red
        0.17 0.63 0.17;   % green
        1.00 0.50 0.05;   % orange
        0.58 0.40 0.74;   % purple
        0.55 0.34 0.29;   % brown
        0.89 0.47 0.76;   % pink
        0.50 0.50 0.50;   % grey
        0.74 0.74 0.13;   % olive
        0.09 0.75 0.81;   % cyan
        0.00 0.30 0.50;   % dark blue
        0.70 0.13 0.13;   % dark red
        0.30 0.70 0.50;   % teal
    ];

    %% Loop over experiments
    for ei = 1:length(exp_dirs)
        exp_name = exp_dirs(ei).name;
        exp_path = fullfile(prot_dir, exp_name);
        analysis_dir = fullfile(exp_path, 'analysis');
        plots_dir = fullfile(exp_path, 'plots');
        if ~exist(plots_dir, 'dir'), mkdir(plots_dir); end

        fprintf('[%d/%d] %s ... ', ei, length(exp_dirs), exp_name);

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
            arena_data = load(fullfile(analysis_dir, arena_files(end).name));
            if isfield(arena_data, 'arena_calib')
                ac = arena_data.arena_calib;
            else
                ac = arena_data;
            end
            xc = ac.xc; yc = ac.yc; radius = ac.radius;
            all_masks = ac.all_masks;

            %% Quad patterns: use training_patterns so probes show target safe zone
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
            led_data = load(fullfile(analysis_dir, led_files(end).name));
            if isfield(led_data, 'LED_detector')
                LED = led_data.LED_detector;
            else
                LED = led_data;
            end
            on_times  = LED.on_times;
            off_times = LED.off_times;
            num_cycles = length(on_times);

            %% Load dead fly info
            fly_alive = true(num_flies, num_cycles);
            log_file = fullfile(analysis_dir, sprintf('QPI_log_%s.txt', exp_name));
            if exist(log_file, 'file')
                fly_alive = parse_qpi_log(log_file, num_flies, num_cycles, good);
            end

            %% Background image
            bg = load_background(exp_path, analysis_dir);

            %% Fly colors (consistent across panels)
            fly_colors = fly_cmap(mod((1:num_flies)-1, size(fly_cmap,1)) + 1, :);

            %% Arena circle coordinates
            theta_c = linspace(0, 2*3.141592653589793, 200);
            arena_cx = xc + radius * cos(theta_c);
            arena_cy = yc + radius * sin(theta_c);

            %% Create figure: one panel per probe trial
            nP = length(probe_cycles);
            fig = figure('Units', 'normalized', ...
                'Position', [0.02 0.15 min(0.16 * nP, 0.95) 0.38], ...
                'Visible', 'off', 'Color', 'k', 'Renderer', 'painters');

            for pii = 1:nP
                ci = probe_cycles(pii);
                if ci > num_cycles, continue; end

                ax = subplot(1, nP, pii);
                plot_probe_panel(ax, ci, probe_labels{pii}, ...
                    trx, num_flies, fly_colors, fly_alive, ...
                    on_times, off_times, all_masks, ...
                    xc, yc, radius, arena_cx, arena_cy, bg, ...
                    cfg, is_single_quad, SAFE_QUADS, opts.FPS, opts.Duration, ...
                    quad_patterns);
            end

            % Extract genotype
            tokens = strsplit(exp_name, '_');
            genotype = tokens{1};

            sgtitle(fig, sprintf('%s — %s — Probe Trajectories (%d flies)', ...
                protocol, strrep(exp_name, '_', '\_'), num_flies), ...
                'FontSize', 13, 'FontWeight', 'bold', 'Color', 'w');

            if opts.SavePlot
                out_file = fullfile(plots_dir, ...
                    sprintf('probe_trajectories_%s_%s.png', protocol, exp_name));
                exportgraphics(fig, out_file, 'Resolution', 200, 'BackgroundColor', 'k');
                fprintf('saved\n');
            else
                fprintf('done\n');
            end

            if opts.ShowPlots
                set(fig, 'Visible', 'on');
            else
                close(fig);
            end

        catch ME
            fprintf('FAILED: %s\n', ME.message);
        end
    end

    fprintf('\nDone — %s probe trajectories.\n', protocol);
end


%% ========== Panel plotting ==========

function plot_probe_panel(ax, ci, clabel, trx, num_flies, fly_colors, fly_alive, ...
    on_times, ~, all_masks, xc, yc, radius, arena_cx, arena_cy, bg, ...
    cfg, is_single_quad, SAFE_QUADS, FPS, duration_s, quad_patterns)

    fr_on  = on_times(ci);
    fr_end_max = fr_on + round(duration_s * FPS) - 1;  % first 20s only

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
        imshow(bg * 0.35, 'Parent', ax);
        hold(ax, 'on');
    else
        hold(ax, 'on');
        set(ax, 'Color', [0.15 0.15 0.15]);
    end
    axis(ax, 'image');

    %% Arena circle + quadrant dividers
    plot(ax, arena_cx, arena_cy, 'w-', 'LineWidth', 0.8);
    plot(ax, [xc - radius, xc + radius], [yc, yc], 'w--', 'LineWidth', 0.4);
    plot(ax, [xc, xc], [yc - radius, yc + radius], 'w--', 'LineWidth', 0.4);

    %% Shade safe quadrants green
    for sq = safe_quads
        shade_safe_quadrant(ax, sq, xc, yc, radius);
    end

    %% Plot fly trajectories — first 20s
    n_plotted = 0;

    for fi = 1:num_flies
        xpos = double(trx(fi).x);
        ypos = double(trx(fi).y);
        nfr = length(xpos);
        fr_end = min(fr_end_max, nfr);
        if fr_on > nfr, continue; end
        if all(isnan(xpos(fr_on:fr_end))), continue; end
        n_plotted = n_plotted + 1;

        col = fly_colors(fi, :);
        is_dead = ~fly_alive(fi, ci);
        if is_dead
            col = col * 0.3;
        end

        % Draw full trajectory for the duration window
        plot(ax, xpos(fr_on:fr_end), ypos(fr_on:fr_end), '-', ...
            'Color', [col 0.7], 'LineWidth', 1.0);

        % Start marker: filled circle
        plot(ax, xpos(fr_on), ypos(fr_on), 'o', ...
            'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 4);

        % End marker: X
        plot(ax, xpos(fr_end), ypos(fr_end), 'x', ...
            'Color', col, 'MarkerSize', 6, 'LineWidth', 1.5);

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
                            'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 6);
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

    if ~isempty(safe_quads) && length(safe_quads) == 1
        title_str = sprintf('%s | Q%d safe | n=%d', clabel, safe_quads(1), n_plotted);
    elseif ~isempty(safe_quads)
        q_str = strjoin(arrayfun(@(q) sprintf('Q%d', q), safe_quads, 'Uni', false), '+');
        title_str = sprintf('%s | %s safe | n=%d', clabel, q_str, n_plotted);
    else
        title_str = sprintf('%s | n=%d', clabel, n_plotted);
    end
    title(ax, title_str, 'FontSize', 9, 'Color', 'w', 'FontWeight', 'bold');

    hold(ax, 'off');
end


%% ========== Helper functions ==========

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
    patch(ax, xx, yy, [0 0.8 0.3], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
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
        % fallback: assume all alive
    end
end
