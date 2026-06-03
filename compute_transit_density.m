function result = compute_transit_density(exp_path, varargin)
% COMPUTE_TRANSIT_DENSITY  Per-experiment spatial density on a rotated grid.
%
%   result = compute_transit_density(exp_path)
%   result = compute_transit_density(exp_path, 'Name', Value, ...)
%
%   Overlays a rotated NxN grid on the arena circle, maps fly positions
%   to grid cells for each LED-on cycle, and computes per-cycle density
%   (fly frame count per cell / pixel count per cell).
%
%   REQUIRED FILES IN exp_path:
%     trx.mat                           — fly tracking data
%     analysis/arena_calib_*.mat        — arena calibration (xc, yc, radius)
%     analysis/LED_detector_*.mat       — LED on/off cycle timing
%
%   OPTIONAL FILES (for dead fly filtering):
%     analysis/QPI_log_*.txt            — dead fly log
%
%   NAME-VALUE PARAMETERS
%     'Protocol'     — e.g. 'P008' (auto-detected from parent dir if empty)
%     'NGrid'        — grid resolution (default: 20 → 20x20 grid)
%     'RotationDeg'  — grid rotation in degrees (default: from arena_calib)
%     'ShowPlots'    — display figures (default: false)
%     'SavePlot'     — save .mat + .png to analysis/ (default: true)
%
%   OUTPUT STRUCT
%     result.experiment         — experiment name
%     result.genotype           — genotype string
%     result.protocol           — protocol ID
%     result.nRows, .nCols      — grid dimensions
%     result.xc, .yc, .radius  — arena geometry
%     result.rotation_deg       — grid rotation angle
%     result.x_edges, .y_edges  — grid edge vectors (in rotated coords)
%     result.PixelCountMap      — [nRows x nCols] pixel count per cell
%     result.FlyCountMap_Cycle  — [nRows x nCols x nCycles] fly frame counts
%     result.DensityMap_Cycle   — [nRows x nCols x nCycles] density values
%     result.cycle_labels       — cell array of cycle names
%     result.on_times, .off_times — LED cycle frame ranges
%     result.fly_alive          — [nFlies x nCycles] logical
%     result.num_flies_total    — total flies tracked
%     result.num_dead           — number of dead flies detected

    %% Parse inputs
    p = inputParser;
    addRequired(p, 'exp_path', @ischar);
    addParameter(p, 'Protocol', '', @ischar);
    addParameter(p, 'NGrid', 20, @isnumeric);
    addParameter(p, 'RotationDeg', NaN, @isnumeric);
    addParameter(p, 'ShowPlots', false, @islogical);
    addParameter(p, 'SavePlot', true, @islogical);
    parse(p, exp_path, varargin{:});
    opts = p.Results;

    %% Detect protocol and genotype from directory structure
    [parent_dir, exp_name] = fileparts(exp_path);
    [~, protocol_from_dir] = fileparts(parent_dir);

    if isempty(opts.Protocol)
        opts.Protocol = protocol_from_dir;
    end

    genotype = regexp(exp_name, '^([A-Za-z0-9]+)_Rig', 'tokens', 'once');
    if ~isempty(genotype)
        genotype = genotype{1};
    else
        genotype = 'unknown';
    end

    analysis_dir = fullfile(exp_path, 'analysis');
    fprintf('  Transit density: %s (geno=%s, prot=%s)\n', exp_name, genotype, opts.Protocol);

    %% Load trx.mat
    trx_file = fullfile(exp_path, 'trx.mat');
    if ~exist(trx_file, 'file')
        error('trx.mat not found in %s', exp_path);
    end
    T = load(trx_file, 'trx');
    trx = T.trx;
    nFlies = numel(trx);

    %% Load arena calibration
    calib_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    if isempty(calib_files)
        error('No arena_calib_*.mat found in %s', analysis_dir);
    end
    calib_file = fullfile(analysis_dir, calib_files(end).name);
    C = load(calib_file);

    % Extract arena geometry
    if isfield(C, 'arena_calib')
        xc     = C.arena_calib.xc;
        yc     = C.arena_calib.yc;
        radius = C.arena_calib.radius;
        if isfield(C.arena_calib, 'angle_deg') && isnan(opts.RotationDeg)
            opts.RotationDeg = C.arena_calib.angle_deg;
        end
    elseif isfield(C, 'xc')
        xc     = C.xc;
        yc     = C.yc;
        radius = C.radius;
    else
        error('Cannot find xc/yc/radius in arena_calib file');
    end

    % Default rotation if not available
    if isnan(opts.RotationDeg)
        opts.RotationDeg = 0;
    end

    %% Load LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    if isempty(led_files)
        error('No LED_detector_*.mat found in %s', analysis_dir);
    end
    led_file = fullfile(analysis_dir, led_files(end).name);
    L = load(led_file);

    % Handle both struct-wrapped and direct variables
    if isfield(L, 'LED_detector')
        on_times  = L.LED_detector.on_times(:)';
        off_times = L.LED_detector.off_times(:)';
    elseif isfield(L, 'LED_detector_thresh')
        on_times  = L.LED_detector_thresh.on_times(:)';
        off_times = L.LED_detector_thresh.off_times(:)';
    elseif isfield(L, 'on_times')
        on_times  = L.on_times(:)';
        off_times = L.off_times(:)';
    else
        error('Cannot find on_times/off_times in LED_detector file');
    end

    nCycles = length(on_times);

    %% Build cycle labels
    cycle_labels = build_cycle_labels(opts.Protocol, nCycles);

    %% Dead fly detection (from QPI log)
    fly_alive = true(nFlies, nCycles);
    qpi_logs = dir(fullfile(analysis_dir, 'QPI_log_*.txt'));
    if ~isempty(qpi_logs)
        fly_alive = parse_qpi_log_td(fullfile(analysis_dir, qpi_logs(end).name), ...
                                      nFlies, nCycles);
    end
    num_dead = sum(~fly_alive(:, end));

    %% Grid definition
    nRows = opts.NGrid;
    nCols = opts.NGrid;
    rotation_deg = opts.RotationDeg;

    x_edges = linspace(-radius, radius, nCols+1);
    y_edges = linspace(-radius, radius, nRows+1);

    theta_rot = deg2rad(rotation_deg);
    R = [cos(theta_rot) -sin(theta_rot); sin(theta_rot) cos(theta_rot)];

    %% Map fly positions to grid cells (in rotated coords)
    %  For each fly, rotate positions into grid-aligned coordinates,
    %  then use edge binning to assign grid cell.
    fly_gridID = cell(nFlies, 1);

    for k = 1:nFlies
        x_pos = trx(k).x(:)';
        y_pos = trx(k).y(:)';

        % Rotate into grid-aligned coordinate system
        coords = [x_pos - xc; y_pos - yc];
        rot_coords = R' * coords;   % inverse rotation

        rotX = rot_coords(1,:);   % centered, grid-aligned
        rotY = rot_coords(2,:);

        nFrames = length(rotX);
        gridID = zeros(1, nFrames);

        for f = 1:nFrames
            col = find(rotX(f) >= x_edges(1:end-1) & rotX(f) < x_edges(2:end), 1);
            row = find(rotY(f) >= y_edges(1:end-1) & rotY(f) < y_edges(2:end), 1);
            if ~isempty(row) && ~isempty(col)
                gid = (row-1)*nCols + col;
                % Verify within arena circle
                if rotX(f)^2 + rotY(f)^2 <= radius^2
                    gridID(f) = gid;
                end
            end
        end

        fly_gridID{k} = gridID;
    end

    %% Compute PixelCountMap (how many pixels per grid cell within the arena)
    %  This normalizes density by cell area (edge cells have fewer pixels).
    PixelCountMap = zeros(nRows, nCols);
    for i = 1:nCols
        for j = 1:nRows
            % Sample pixel count using the grid cell boundaries
            x_min = x_edges(i);  x_max = x_edges(i+1);
            y_min = y_edges(j);  y_max = y_edges(j+1);
            cx = (x_min + x_max) / 2;
            cy = (y_min + y_max) / 2;
            cell_w = x_max - x_min;
            cell_h = y_max - y_min;

            % Approximate pixel count: full cell area if centroid is inside circle,
            % otherwise estimate fraction inside circle
            dist_from_center = sqrt(cx^2 + cy^2);
            if dist_from_center + sqrt(cell_w^2 + cell_h^2)/2 <= radius
                % Cell fully inside circle
                PixelCountMap(j, i) = cell_w * cell_h;
            elseif dist_from_center - sqrt(cell_w^2 + cell_h^2)/2 >= radius
                % Cell fully outside circle
                PixelCountMap(j, i) = 0;
            else
                % Partial cell — use Monte Carlo-like grid sampling
                n_samp = 10;
                xs = linspace(x_min, x_max, n_samp);
                ys = linspace(y_min, y_max, n_samp);
                [gx, gy] = meshgrid(xs, ys);
                frac = sum(gx(:).^2 + gy(:).^2 <= radius^2) / numel(gx);
                PixelCountMap(j, i) = frac * cell_w * cell_h;
            end
        end
    end

    %% Compute per-cycle fly count and density maps
    FlyCountMap_Cycle = zeros(nRows, nCols, nCycles);

    for c = 1:nCycles
        frames = on_times(c) : off_times(c);

        for k = 1:nFlies
            if ~fly_alive(k, c), continue; end

            nFramesFly = numel(fly_gridID{k});
            valid_frames = frames(frames >= 1 & frames <= nFramesFly);
            if isempty(valid_frames), continue; end

            flyIDs = fly_gridID{k}(valid_frames);
            flyIDs = flyIDs(flyIDs > 0);

            for ID = flyIDs
                if ID <= 0 || ID > nRows*nCols || isnan(ID), continue; end
                row = ceil(ID / nCols);
                col = mod(ID-1, nCols) + 1;
                FlyCountMap_Cycle(row, col, c) = FlyCountMap_Cycle(row, col, c) + 1;
            end
        end
    end

    % Density = fly frames per unit area
    DensityMap_Cycle = zeros(nRows, nCols, nCycles);
    for c = 1:nCycles
        tmp = FlyCountMap_Cycle(:,:,c) ./ PixelCountMap;
        tmp(isnan(tmp) | isinf(tmp)) = 0;
        DensityMap_Cycle(:,:,c) = tmp;
    end

    %% Build result struct
    result.experiment        = exp_name;
    result.genotype          = genotype;
    result.protocol          = opts.Protocol;
    result.nRows             = nRows;
    result.nCols             = nCols;
    result.xc                = xc;
    result.yc                = yc;
    result.radius            = radius;
    result.rotation_deg      = rotation_deg;
    result.x_edges           = x_edges;
    result.y_edges           = y_edges;
    result.PixelCountMap     = PixelCountMap;
    result.FlyCountMap_Cycle = FlyCountMap_Cycle;
    result.DensityMap_Cycle  = DensityMap_Cycle;
    result.cycle_labels      = cycle_labels;
    result.on_times          = on_times;
    result.off_times         = off_times;
    result.fly_alive         = fly_alive;
    result.num_flies_total   = nFlies;
    result.num_dead          = num_dead;

    %% Save
    if opts.SavePlot
        if ~exist(analysis_dir, 'dir'), mkdir(analysis_dir); end
        out_file = fullfile(analysis_dir, sprintf('transit_density_%s.mat', exp_name));
        save(out_file, '-struct', 'result');
        fprintf('    Saved: %s\n', out_file);
    end

    %% Optional: per-experiment heatmap figure
    if opts.ShowPlots || opts.SavePlot
        fig = plot_density_heatmaps(result);

        if opts.SavePlot
            png_file = fullfile(analysis_dir, sprintf('transit_density_%s.png', exp_name));
            exportgraphics(fig, png_file, 'Resolution', 200);
            fprintf('    Saved: %s\n', png_file);
        end

        if opts.ShowPlots
            set(fig, 'Visible', 'on');
        else
            close(fig);
        end
    end

    fprintf('    Done: %d flies, %d cycles, %d dead\n', nFlies, nCycles, num_dead);
end


%% ========================================================================
%  HELPER: Plot per-cycle density heatmaps (condensed, blue → mustard)
%  ========================================================================
function fig = plot_density_heatmaps(result)
    % Condense alternate training bouts
    [condensed_maps, condensed_labels] = condense_training_bouts_local( ...
        result.DensityMap_Cycle, result.cycle_labels);

    nPanels = size(condensed_maps, 3);

    % Blue → Mustard Yellow colormap
    nColors = 256;
    cmap = [linspace(0.1,0.9,nColors)', ...
            linspace(0.1,0.75,nColors)', ...
            linspace(0.4,0.1,nColors)'];

    globalMax = max(condensed_maps(:));
    if globalMax == 0, globalMax = 1; end

    fig = figure('Units','normalized','Position',[0.02 0.1 0.95 0.55], 'Visible','off');

    maxCols = min(nPanels, 16);
    tiledCols = maxCols;
    tiledRows = ceil(nPanels / tiledCols);

    t = tiledlayout(tiledRows, tiledCols, 'Padding','compact', 'TileSpacing','compact');

    for c = 1:nPanels
        ax = nexttile;
        imagesc(condensed_maps(:,:,c));
        axis image off;
        title(condensed_labels{c}, 'FontSize', 9, 'FontWeight', 'bold');
        colormap(ax, cmap);
        clim([0 globalMax]);
    end

    hcb = colorbar;
    hcb.Layout.Tile = 'east';
    ylabel(hcb, 'Density (Flies / Area)');
    hcb.FontSize = 10;

    sgtitle(sprintf('Transit Density — %s (%s)', ...
        strrep(result.experiment, '_', '\_'), result.protocol), ...
        'FontSize', 12, 'FontWeight', 'bold');
end


%% ========================================================================
%  HELPER: Condense training bouts (average odd + even within each block)
%  ========================================================================
function [condensed_maps, condensed_labels] = condense_training_bouts_local(DensityMap_Cycle, cycle_labels)
    nCycles = size(DensityMap_Cycle, 3);
    has_blocks = any(contains(cycle_labels, 'B1.1'));

    if ~has_blocks
        condensed_maps = DensityMap_Cycle;
        condensed_labels = cycle_labels;
        return;
    end

    condensed_maps   = [];
    condensed_labels = {};
    ci = 1;

    while ci <= nCycles
        lbl = cycle_labels{ci};
        tok = regexp(lbl, '^B(\d+)\.(\d+)$', 'tokens', 'once');

        if ~isempty(tok)
            blk_num = str2double(tok{1});
            odd_idx  = [];
            even_idx = [];
            probe_ci = [];

            while ci <= nCycles
                lbl_i = cycle_labels{ci};
                tok_i = regexp(lbl_i, sprintf('^B%d\\.(\\d+)$', blk_num), 'tokens', 'once');
                if ~isempty(tok_i)
                    trial_num = str2double(tok_i{1});
                    if mod(trial_num, 2) == 1
                        odd_idx(end+1) = ci; %#ok<AGROW>
                    else
                        even_idx(end+1) = ci; %#ok<AGROW>
                    end
                    ci = ci + 1;
                elseif strcmp(lbl_i, sprintf('B%d.P', blk_num))
                    probe_ci = ci;
                    ci = ci + 1;
                    break;
                else
                    break;
                end
            end

            if ~isempty(odd_idx)
                condensed_maps = cat(3, condensed_maps, mean(DensityMap_Cycle(:,:,odd_idx), 3));
                condensed_labels{end+1} = sprintf('B%d.Odd', blk_num);
            end
            if ~isempty(even_idx)
                condensed_maps = cat(3, condensed_maps, mean(DensityMap_Cycle(:,:,even_idx), 3));
                condensed_labels{end+1} = sprintf('B%d.Even', blk_num);
            end
            if ~isempty(probe_ci)
                condensed_maps = cat(3, condensed_maps, DensityMap_Cycle(:,:,probe_ci));
                condensed_labels{end+1} = sprintf('B%d.P', blk_num);
            end
        else
            condensed_maps = cat(3, condensed_maps, DensityMap_Cycle(:,:,ci));
            condensed_labels{end+1} = lbl;
            ci = ci + 1;
        end
    end
end


%% ========================================================================
%  HELPER: Build cycle labels for any protocol
%  ========================================================================
function labels = build_cycle_labels(protocol, nCycles)
    if ismember(protocol, {'P003', 'P005'})
        % 46 cycles: no optomotor
        labels = {'PP', 'Ag'};
        for blk = 1:4
            for idx = 1:10
                labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
            end
            labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
        end
    elseif ismember(protocol, {'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P014'})
        % 48 cycles: with optomotor
        labels = {'OM1', 'PP', 'Ag'};
        for blk = 1:4
            for idx = 1:10
                labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
            end
            labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
        end
        labels{end+1} = 'OM2';
    elseif ismember(protocol, {'P001', 'P002'})
        % Intensity ramp — 42 cycles, 14 per block × 3 blocks
        labels = cell(1, nCycles);
        for c = 1:nCycles
            labels{c} = sprintf('C%d', c);
        end
    else
        % Fallback: numbered cycles
        labels = cell(1, nCycles);
        for c = 1:nCycles
            labels{c} = sprintf('C%d', c);
        end
    end

    % Trim or extend to match actual cycle count
    if length(labels) > nCycles
        labels = labels(1:nCycles);
    elseif length(labels) < nCycles
        for c = (length(labels)+1):nCycles
            labels{c} = sprintf('C%d', c);
        end
    end
end


%% ========================================================================
%  HELPER: Parse QPI log for dead fly detection
%  ========================================================================
function fly_alive = parse_qpi_log_td(log_file, nFlies, nCycles)
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
                tok2 = regexp(ln, 'cycle (\d+)', 'tokens');
                if ~isempty(tok1) && ~isempty(tok2)
                    fly_idx = str2double(tok1{1}{1});
                    dead_cycle = str2double(tok2{1}{1});
                    if fly_idx >= 1 && fly_idx <= nFlies && dead_cycle >= 1
                        dead_cycle = min(dead_cycle, nCycles);
                        fly_alive(fly_idx, dead_cycle:end) = false;
                    end
                end
            end
        end
    catch
        % If parsing fails, assume all alive
    end
end
