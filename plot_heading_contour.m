function plot_heading_contour(exp_path, varargin)
% PLOT_HEADING_CONTOUR  Spatial heading angle heatmap overlaid on arena.
%
%   plot_heading_contour(exp_path)
%   plot_heading_contour(exp_path, 'Name', Value, ...)
%
%   Overlays fly heading angles on the arena background image during
%   training trials. The arena is divided into a spatial grid; each cell
%   shows the circular mean heading angle of all fly-frames in that cell.
%
%   Figure 1: Per-block (B1–B4), all 10 training trials combined.
%   Figure 2: Odd vs Even trials per block (2 rows × 4 cols).
%
%   NAME-VALUE PARAMETERS
%     'Protocol'   — e.g. 'P010' (auto-detected if empty)
%     'NGrid'      — spatial grid resolution (default: 40)
%     'ShowPlots'  — display figures (default: false)
%     'SavePlot'   — save .png to analysis/ (default: true)

    %% Parse
    p = inputParser;
    addRequired(p, 'exp_path', @ischar);
    addParameter(p, 'Protocol', '', @ischar);
    addParameter(p, 'NGrid', 40, @isnumeric);
    addParameter(p, 'ShowPlots', false, @islogical);
    addParameter(p, 'SavePlot', true, @islogical);
    parse(p, exp_path, varargin{:});
    opts = p.Results;

    [parent_dir, exp_name] = fileparts(exp_path);
    [~, protocol_from_dir] = fileparts(parent_dir);
    if isempty(opts.Protocol)
        opts.Protocol = protocol_from_dir;
    end

    analysis_dir = fullfile(exp_path, 'analysis');
    fprintf('Heading spatial map: %s\n', exp_name);

    %% Load background image
    bg_png = fullfile(analysis_dir, sprintf('background_%s.png', exp_name));
    bg_mat = fullfile(exp_path, 'movie-bg.mat');
    if exist(bg_png, 'file')
        backimg = imread(bg_png);
    elseif exist(bg_mat, 'file')
        B = load(bg_mat);
        fnames = fieldnames(B);
        backimg = B.(fnames{1});
    else
        error('No background image found');
    end
    if size(backimg, 3) == 1
        backimg = repmat(backimg, [1 1 3]);
    end
    [img_h, img_w, ~] = size(backimg);

    %% Load trx
    T = load(fullfile(exp_path, 'trx.mat'), 'trx');
    trx = T.trx;
    nFlies = numel(trx);

    max_end = max([trx.endframe]);
    good = [];
    for k = 1:nFlies
        if trx(k).firstframe == 1 && trx(k).endframe >= (max_end - 30)
            good = [good, k]; %#ok<AGROW>
        end
    end
    trx = trx(good);
    nFlies = length(trx);
    fps = trx(1).fps;

    %% Load arena calibration
    calib_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    C = load(fullfile(analysis_dir, calib_files(end).name));
    xc     = C.arena_calib.xc;
    yc     = C.arena_calib.yc;
    radius = C.arena_calib.radius;

    %% Load LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    L = load(fullfile(analysis_dir, led_files(end).name));
    if isfield(L, 'LED_detector')
        on_times  = double(L.LED_detector.on_times(:)');
        off_times = double(L.LED_detector.off_times(:)');
    elseif isfield(L, 'LED_detector_thresh')
        on_times  = double(L.LED_detector_thresh.on_times(:)');
        off_times = double(L.LED_detector_thresh.off_times(:)');
    else
        on_times  = double(L.on_times(:)');
        off_times = double(L.off_times(:)');
    end

    %% Dead fly info
    nCycles = length(on_times);
    fly_alive = true(nFlies, nCycles);
    log_file = fullfile(analysis_dir, sprintf('QPI_log_%s.txt', exp_name));
    if exist(log_file, 'file')
        fly_alive = parse_qpi_log_hc(log_file, nFlies, nCycles, good);
    end

    %% Build cycle labels and identify training blocks
    cycle_labels = build_labels(opts.Protocol, nCycles);

    blocks = struct();
    for blk = 1:4
        blocks(blk).odd_idx  = [];
        blocks(blk).even_idx = [];
        blocks(blk).all_idx  = [];
        for trial = 1:10
            ci = find(strcmp(cycle_labels, sprintf('B%d.%d', blk, trial)), 1);
            if ~isempty(ci)
                blocks(blk).all_idx(end+1) = ci;
                if mod(trial, 2) == 1
                    blocks(blk).odd_idx(end+1) = ci;
                else
                    blocks(blk).even_idx(end+1) = ci;
                end
            end
        end
    end

    %% Spatial grid (in pixel coordinates, centered on arena)
    nG = opts.NGrid;
    x_edges = linspace(xc - radius, xc + radius, nG + 1);
    y_edges = linspace(yc - radius, yc + radius, nG + 1);

    %% HSV colormap for circular heading angle
    % We'll use HSV since heading is circular [-pi, pi]
    % Map angle to hue [0, 1], fixed saturation & value

    %% ---- FIGURES: One per block, 2x5 grid of individual training trials ----
    for blk = 1:4
        fig_blk = figure('Units','normalized','Position',[0.02 0.05 0.95 0.55], 'Visible','off');

        trial_indices = blocks(blk).all_idx;  % 10 trials
        for t = 1:length(trial_indices)
            ci = trial_indices(t);
            ax = subplot(2, 5, t);

            [angle_map, count_map] = build_spatial_heading(trx, nFlies, fly_alive, ...
                on_times, off_times, ci, x_edges, y_edges, nG, xc, yc, radius);

            draw_heading_on_arena(ax, backimg, angle_map, count_map, ...
                x_edges, y_edges, xc, yc, radius);

            % Label: trial number and safe-quadrant info
            if mod(t, 2) == 1
                safe_str = 'Q2/Q4';
            else
                safe_str = 'Q1/Q3';
            end
            title(ax, sprintf('B%d.%d (%s)', blk, t, safe_str), ...
                'FontSize', 9, 'FontWeight', 'bold');
        end

        % Add circular colorbar legend
        add_hsv_colorwheel(fig_blk);

        sgtitle(fig_blk, sprintf('Heading — Block %d — %s', blk, ...
            strrep(exp_name, '_', '\_')), 'FontSize', 13, 'FontWeight', 'bold');

        if opts.SavePlot
            png_blk = fullfile(analysis_dir, ...
                sprintf('heading_spatial_block%d_%s.png', blk, exp_name));
            exportgraphics(fig_blk, png_blk, 'Resolution', 250);
            fprintf('  Saved: %s\n', png_blk);
        end
        if opts.ShowPlots, set(fig_blk, 'Visible', 'on'); else, close(fig_blk); end
    end

    fprintf('  Done: %d flies, %d cycles, 4 block figures\n', nFlies, nCycles);
end


%% ========================================================================
%  Build spatial circular-mean heading map
%  ========================================================================
function [angle_map, count_map] = build_spatial_heading(trx, nFlies, fly_alive, ...
    on_times, off_times, cycle_idx, x_edges, y_edges, nG, xc, yc, radius)

    % Accumulate sin and cos components for circular mean
    sin_sum = zeros(nG, nG);
    cos_sum = zeros(nG, nG);
    count_map = zeros(nG, nG);

    for ci = cycle_idx
        fr_on  = on_times(ci);
        fr_off = off_times(ci);

        for k = 1:nFlies
            if ~fly_alive(k, ci), continue; end

            xpos = double(trx(k).x(:));
            ypos = double(trx(k).y(:));
            theta = double(trx(k).theta(:));
            nfr = length(xpos);

            fr_end = min(fr_off, nfr);
            if fr_on > fr_end, continue; end
            frames = fr_on:fr_end;

            xx = xpos(frames);
            yy = ypos(frames);
            th = theta(frames);

            % Remove NaN
            valid = ~isnan(xx) & ~isnan(yy) & ~isnan(th);
            xx = xx(valid);
            yy = yy(valid);
            th = th(valid);

            if isempty(xx), continue; end

            % Check inside arena
            inside = (xx - xc).^2 + (yy - yc).^2 <= radius^2;
            xx = xx(inside);
            yy = yy(inside);
            th = th(inside);

            if isempty(xx), continue; end

            % Bin spatially
            x_bin = discretize(xx, x_edges);
            y_bin = discretize(yy, y_edges);

            good = ~isnan(x_bin) & ~isnan(y_bin);
            x_bin = x_bin(good);
            y_bin = y_bin(good);
            th    = th(good);

            for ii = 1:length(x_bin)
                r = y_bin(ii);
                c = x_bin(ii);
                sin_sum(r, c)   = sin_sum(r, c) + sin(th(ii));
                cos_sum(r, c)   = cos_sum(r, c) + cos(th(ii));
                count_map(r, c) = count_map(r, c) + 1;
            end
        end
    end

    % Circular mean
    angle_map = atan2(sin_sum, cos_sum);  % [-pi, pi]
end


%% ========================================================================
%  Draw heading overlay on arena background
%  ========================================================================
function draw_heading_on_arena(ax, backimg, angle_map, count_map, ...
    x_edges, y_edges, xc, yc, radius)

    [nG_r, nG_c] = size(angle_map);

    % Show background
    imshow(backimg, 'Parent', ax);
    hold(ax, 'on');
    axis(ax, 'image');

    % Build RGBA overlay image in pixel space
    [img_h, img_w, ~] = size(backimg);

    % Grid cell centers
    xc_grid = (x_edges(1:end-1) + x_edges(2:end)) / 2;
    yc_grid = (y_edges(1:end-1) + y_edges(2:end)) / 2;
    cell_w = x_edges(2) - x_edges(1);
    cell_h = y_edges(2) - y_edges(1);

    % Minimum count threshold to display
    min_count = 5;

    % Draw each grid cell as a colored rectangle
    for r = 1:nG_r
        for c = 1:nG_c
            if count_map(r, c) < min_count, continue; end

            % Check if cell center is inside arena
            cx = xc_grid(c);
            cy = yc_grid(r);
            if (cx - xc)^2 + (cy - yc)^2 > radius^2, continue; end

            % Map angle [-pi, pi] to hue [0, 1]
            hue = (angle_map(r, c) + pi) / (2*pi);
            rgb = hsv2rgb([hue, 0.9, 0.95]);

            % Alpha based on count (more observations = more opaque)
            alpha = min(count_map(r, c) / 200, 0.85);
            alpha = max(alpha, 0.3);

            % Draw filled rectangle
            rect_x = x_edges(c);
            rect_y = y_edges(r);
            patch(ax, [rect_x rect_x+cell_w rect_x+cell_w rect_x], ...
                      [rect_y rect_y rect_y+cell_h rect_y+cell_h], ...
                      rgb, 'EdgeColor', 'none', 'FaceAlpha', alpha);
        end
    end

    % Draw arena circle outline
    theta_c = linspace(0, 2*pi, 200);
    plot(ax, xc + radius*cos(theta_c), yc + radius*sin(theta_c), ...
        'w-', 'LineWidth', 1.5);

    hold(ax, 'off');
end


%% ========================================================================
%  Add HSV color wheel legend for heading direction
%  ========================================================================
function add_hsv_colorwheel(fig)
    % Small polar colorwheel in the corner
    ax_cw = axes(fig, 'Position', [0.92 0.02 0.07 0.12]);

    n = 64;
    theta_vals = linspace(-pi, pi, n);
    r_vals = linspace(0, 1, 10);
    [TH, RR] = meshgrid(theta_vals, r_vals);
    [XX, YY] = pol2cart(TH, RR);

    % Color by angle
    C = (TH + pi) / (2*pi);  % hue
    S = ones(size(C)) * 0.9;
    V = ones(size(C)) * 0.95;
    RGB = hsv2rgb(cat(3, C, S, V));

    surf(ax_cw, XX, YY, zeros(size(XX)), RGB, 'EdgeColor', 'none', 'FaceColor', 'texturemap');
    view(ax_cw, 2);
    axis(ax_cw, 'equal', 'off');
    xlim(ax_cw, [-1.3 1.3]);
    ylim(ax_cw, [-1.3 1.3]);

    % Cardinal direction labels
    text(ax_cw, 0, 1.15, '0°', 'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', 'w');
    text(ax_cw, 1.15, 0, '90°', 'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', 'w');
    text(ax_cw, 0, -1.15, '±180°', 'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', 'w');
    text(ax_cw, -1.2, 0, '-90°', 'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', 'w');

    title(ax_cw, 'Heading', 'FontSize', 8, 'Color', 'w');
end


%% ========================================================================
function labels = build_labels(protocol, nCycles)
    if ismember(protocol, {'P003', 'P005'})
        labels = {'PP', 'Ag'};
    elseif ismember(protocol, {'P006','P007','P008','P009','P010','P011','P014'})
        labels = {'OM1', 'PP', 'Ag'};
    else
        labels = {};
        for c = 1:nCycles, labels{c} = sprintf('C%d', c); end
        return;
    end
    for blk = 1:4
        for idx = 1:10
            labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
        end
        labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
    end
    if ismember(protocol, {'P006','P007','P008','P009','P010','P011','P014'})
        labels{end+1} = 'OM2';
    end
    if length(labels) > nCycles, labels = labels(1:nCycles); end
end


%% ========================================================================
function fly_alive = parse_qpi_log_hc(log_file, nFlies, nCycles, fly_ids)
    fly_alive = true(nFlies, nCycles);
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
                    if ~isempty(fi) && from_cycle <= nCycles
                        fly_alive(fi, from_cycle:end) = false;
                    end
                end
            end
        end
    catch
    end
end
