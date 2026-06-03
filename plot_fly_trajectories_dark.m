%% plot_fly_trajectories_dark.m
% Plot individual fly trajectories on arena background.
%
% Generates per experiment:
%   4 figures — one per training block (2 rows × 5 cols = 10 trials each)
%   1 figure  — all probe trials (PP, B1.P, B2.P, B3.P, B4.P)
%
% Each panel shows one fly's trajectory during that trial, with a color
% gradient from dim (start) to bright (end). Dead flies show "DEAD".
%
% Cycle layout (48-cycle protocols: P006–P012, P014):
%   1=OM1, 2=PP, 3=Ag
%   4-13=B1.1–B1.10, 14=B1.P
%   15-24=B2.1–B2.10, 25=B2.P
%   26-35=B3.1–B3.10, 36=B3.P
%   37-46=B4.1–B4.10, 47=B4.P
%   48=OM2

clear; clc;


ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';
PROTOCOL     = 'P014';
prot_path    = fullfile(ANALYSIS_DIR, PROTOCOL);

% Block structure: 4 blocks, 10 training trials each
% Training cycle indices per block
block_cycles = {4:13, 15:24, 26:35, 37:46};
block_labels = cell(1, 4);
for blk = 1:4
    block_labels{blk} = arrayfun(@(t) sprintf('B%d.%d', blk, t), 1:10, 'UniformOutput', false);
end

% Probe cycle indices: PP=2, B1.P=14, B2.P=25, B3.P=36, B4.P=47
probe_cycles = [2, 14, 25, 36, 47];
probe_labels = {'PP', 'B1.P', 'B2.P', 'B3.P', 'B4.P'};

save_dir = fullfile(prot_path, 'summary', 'trajectories_dark');
if ~exist(save_dir, 'dir'), mkdir(save_dir); end

% Per-fly colors (12 distinct, wraps if more flies)
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
];

exp_dirs = dir(prot_path);
exp_dirs = exp_dirs([exp_dirs.isdir] & contains({exp_dirs.name}, '_Rig'));

fprintf('=== Trajectory plots: %s (%d experiments) ===\n\n', PROTOCOL, length(exp_dirs));

for e = 1:length(exp_dirs)
    exp_name = exp_dirs(e).name;
    exp_path = fullfile(prot_path, exp_name);
    analysis_dir = fullfile(exp_path, 'analysis');

    fprintf('[%d/%d] %s\n', e, length(exp_dirs), exp_name);

    %% Load trx
    try
        trx_data = load(fullfile(exp_path, 'trx.mat'), 'trx');
        trx = trx_data.trx;
    catch
        fprintf('  no trx.mat, skipping\n');
        continue;
    end
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
        fprintf('  no background, skipping\n');
        continue;
    end
    bg = imread(fullfile(analysis_dir, bg_files(1).name));
    if size(bg, 3) == 1, bg = repmat(bg, [1 1 3]); end

    %% Load LED detector
    led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
    if isempty(led_files)
        fprintf('  no LED detector, skipping\n');
        continue;
    end
    L = load(fullfile(analysis_dir, led_files(end).name));
    if isfield(L, 'LED_detector')
        on_times  = double(L.LED_detector.on_times(:)');
        off_times = double(L.LED_detector.off_times(:)');
    elseif isfield(L, 'LED_detector_thresh')
        on_times  = double(L.LED_detector_thresh.on_times(:)');
        off_times = double(L.LED_detector_thresh.off_times(:)');
    end

    %% Load arena calibration
    calib_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    if isempty(calib_files)
        fprintf('  no arena calib, skipping\n');
        continue;
    end
    C = load(fullfile(analysis_dir, calib_files(end).name));
    xc = C.arena_calib.xc;
    yc = C.arena_calib.yc;
    radius = C.arena_calib.radius;

    %% Dead fly info
    nCycles = length(on_times);
    fly_alive = true(nFlies, nCycles);
    log_file = fullfile(analysis_dir, sprintf('QPI_log_%s.txt', exp_name));
    if exist(log_file, 'file')
        fly_alive = parse_qpi_log_traj(log_file, nFlies, nCycles, good);
    end

    theta_c = linspace(0, 2*pi, 200);

    %% --- 4 Training block figures (2 rows × 5 cols) ---
    for blk = 1:4
        cycles = block_cycles{blk};
        labels = block_labels{blk};
        nTrials = length(cycles);

        % 2×5 grid, one panel per trial, all flies overlaid with distinct colors
        fig = figure('Units', 'normalized', 'Position', [0.01 0.01 0.98 0.70], 'Visible', 'off');

        for ti = 1:nTrials
            ci = cycles(ti);
            if ci > nCycles, continue; end
            fr_on  = on_times(ci);
            fr_off = off_times(ci);

            ax = subplot(2, 5, ti);
            imshow(bg * 0.4, 'Parent', ax);
            hold(ax, 'on');
            axis(ax, 'image');

            % Arena circle
            plot(ax, xc + radius*cos(theta_c), yc + radius*sin(theta_c), ...
                'w-', 'LineWidth', 0.5);

            for fi = 1:nFlies
                if ~fly_alive(fi, ci), continue; end

                fly_col = fly_cmap(mod(fi-1, size(fly_cmap,1)) + 1, :);

                xpos = double(trx(fi).x);
                ypos = double(trx(fi).y);
                nfr = length(xpos);
                fr_end = min(fr_off, nfr);
                if fr_on > nfr, continue; end
                frames = fr_on:fr_end;

                xx = xpos(frames);
                yy = ypos(frames);

                % Flat color per fly
                if length(xx) > 1
                    plot(ax, xx, yy, '-', 'Color', [fly_col 0.7], 'LineWidth', 0.8);
                    % Start dot (white) and end square (fly color)
                    plot(ax, xx(1), yy(1), 'o', 'Color', 'w', ...
                        'MarkerFaceColor', 'w', 'MarkerSize', 2);
                    plot(ax, xx(end), yy(end), 's', 'Color', fly_col, ...
                        'MarkerFaceColor', fly_col, 'MarkerSize', 3);
                end
            end

            xlim(ax, [xc-radius*1.05, xc+radius*1.05]);
            ylim(ax, [yc-radius*1.05, yc+radius*1.05]);
            set(ax, 'XTick', [], 'YTick', []);
            title(ax, labels{ti}, 'FontSize', 8, 'Color', 'w', 'FontWeight', 'bold');

            hold(ax, 'off');
        end

        sgtitle(fig, sprintf('%s Block %d — %s', PROTOCOL, blk, strrep(exp_name, '_', '\_')), ...
            'FontSize', 12, 'FontWeight', 'bold');

        out_png = fullfile(save_dir, sprintf('traj_block%d_%s.png', blk, exp_name));
        exportgraphics(fig, out_png, 'Resolution', 200);
        savefig(fig, strrep(out_png, '.png', '.fig'));
        close(fig);
        fprintf('  Block %d saved\n', blk);
    end

    %% --- Probe figure (1 row × 5 cols: PP, B1.P, B2.P, B3.P, B4.P) ---
    fig = figure('Units', 'normalized', 'Position', [0.01 0.20 0.98 0.45], 'Visible', 'off');

    for pi = 1:length(probe_cycles)
        ci = probe_cycles(pi);
        if ci > nCycles, continue; end
        fr_on  = on_times(ci);
        fr_off = off_times(ci);

        ax = subplot(1, 5, pi);
        imshow(bg * 0.4, 'Parent', ax);
        hold(ax, 'on');
        axis(ax, 'image');

        % Arena circle
        plot(ax, xc + radius*cos(theta_c), yc + radius*sin(theta_c), ...
            'w-', 'LineWidth', 0.5);

        for fi = 1:nFlies
            if ~fly_alive(fi, ci), continue; end

            fly_col = fly_cmap(mod(fi-1, size(fly_cmap,1)) + 1, :);

            xpos = double(trx(fi).x);
            ypos = double(trx(fi).y);
            nfr = length(xpos);
            fr_end = min(fr_off, nfr);
            if fr_on > nfr, continue; end
            frames = fr_on:fr_end;

            xx = xpos(frames);
            yy = ypos(frames);

            % Flat color per fly
            if length(xx) > 1
                plot(ax, xx, yy, '-', 'Color', [fly_col 0.7], 'LineWidth', 0.8);
                plot(ax, xx(1), yy(1), 'o', 'Color', 'w', ...
                    'MarkerFaceColor', 'w', 'MarkerSize', 2);
                plot(ax, xx(end), yy(end), 's', 'Color', fly_col, ...
                    'MarkerFaceColor', fly_col, 'MarkerSize', 3);
            end
        end

        xlim(ax, [xc-radius*1.05, xc+radius*1.05]);
        ylim(ax, [yc-radius*1.05, yc+radius*1.05]);
        set(ax, 'XTick', [], 'YTick', []);
        title(ax, probe_labels{pi}, 'FontSize', 9, 'Color', 'w', 'FontWeight', 'bold');

        hold(ax, 'off');
    end

    sgtitle(fig, sprintf('%s Probes — %s', PROTOCOL, strrep(exp_name, '_', '\_')), ...
        'FontSize', 12, 'FontWeight', 'bold');

    out_png = fullfile(save_dir, sprintf('traj_probes_%s.png', exp_name));
    exportgraphics(fig, out_png, 'Resolution', 200);
    savefig(fig, strrep(out_png, '.png', '.fig'));
    close(fig);
    fprintf('  Probes saved\n');
end

fprintf('\nDone. Saved to: %s\n', save_dir);


%% ========================================================================
function fly_alive = parse_qpi_log_traj(log_file, nFlies, nCycles, fly_ids)
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
