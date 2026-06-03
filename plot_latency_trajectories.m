function plot_latency_trajectories(varargin)
% PLOT_LATENCY_TRAJECTORIES  Per-fly trajectories from onset to first safe entry.
%
%   plot_latency_trajectories()
%   plot_latency_trajectories('Protocols', {'P008','P010','P011','P014'})
%
%   For each experiment, generates one figure per training block (4 figures).
%   Each figure is a 2×5 grid of trials. Each panel shows the arena
%   background with fly trajectories drawn from stimulus onset until the
%   fly first enters the safe quadrant (latency path). Trajectory color
%   = fly identity. A dot marks onset position, a square marks safe entry.
%   Flies already in the safe zone at onset are shown as a single dot.

    ip = inputParser;
    addParameter(ip, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(ip, 'Protocols', {'P008', 'P010', 'P011', 'P014'}, @iscell);
    addParameter(ip, 'Genotype', 'L2A', @ischar);
    addParameter(ip, 'ShowPlots', false, @islogical);
    parse(ip, varargin{:});
    opts = ip.Results;

    ADIR = opts.AnalysisDir;
    GENO = opts.Genotype;

    % Fly colors — 12 distinct colors
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

    cond_labels = containers.Map();
    cond_labels('P008') = 'Coupled';
    cond_labels('P010') = 'Uncoupled';
    cond_labels('P011') = 'Dark';
    cond_labels('P014') = 'Inverted Coupled';

    for pi = 1:length(opts.Protocols)
        prot = opts.Protocols{pi};
        prot_path = fullfile(ADIR, prot);
        if ~exist(prot_path, 'dir'), continue; end

        cond_label = cond_labels(prot);

        save_dir = fullfile(prot_path, 'summary', 'latency_trajectories');
        if ~exist(save_dir, 'dir'), mkdir(save_dir); end

        % Get quad patterns from metadata
        cfg = get_protocol_config(prot);

        exp_dirs = dir(prot_path);
        exp_dirs = exp_dirs([exp_dirs.isdir] & contains({exp_dirs.name}, '_Rig') & contains({exp_dirs.name}, GENO));

        for e = 1:length(exp_dirs)
            exp_name = exp_dirs(e).name;
            exp_path = fullfile(prot_path, exp_name);
            analysis_dir = fullfile(exp_path, 'analysis');

            fprintf('[%s] %s ... ', prot, exp_name);

            %% Load data
            try
                trx_data = load(fullfile(exp_path, 'trx.mat'), 'trx');
                trx = trx_data.trx;
            catch
                fprintf('no trx.mat\n');
                continue;
            end

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

            % Background
            bg_files = dir(fullfile(analysis_dir, 'background_*.png'));
            if isempty(bg_files), fprintf('no background\n'); continue; end
            bg = imread(fullfile(analysis_dir, bg_files(1).name));
            if size(bg, 3) == 1, bg = repmat(bg, [1 1 3]); end

            % Arena calibration
            calib_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
            C = load(fullfile(analysis_dir, calib_files(end).name));
            xc = C.arena_calib.xc;
            yc = C.arena_calib.yc;
            radius = C.arena_calib.radius;
            all_masks = C.arena_calib.all_masks;

            % LED detector
            led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
            L = load(fullfile(analysis_dir, led_files(end).name));
            if isfield(L, 'LED_detector')
                on_times  = double(L.LED_detector.on_times(:)');
                off_times = double(L.LED_detector.off_times(:)');
            elseif isfield(L, 'LED_detector_thresh')
                on_times  = double(L.LED_detector_thresh.on_times(:)');
                off_times = double(L.LED_detector_thresh.off_times(:)');
            end

            % Quad patterns: use training_patterns so probes show target safe zone
            [metadata_patterns, metadata_training] = parse_metadata_led_patterns(exp_path);
            if ~isempty(metadata_training)
                quad_patterns = metadata_training;
            elseif ~isempty(metadata_patterns)
                quad_patterns = metadata_patterns;
            else
                quad_patterns = cfg.quad_patterns;
            end

            % Dead fly info
            nCycles = length(on_times);
            fly_alive = true(nFlies, nCycles);
            log_file = fullfile(analysis_dir, sprintf('QPI_log_%s.txt', exp_name));
            if exist(log_file, 'file')
                fly_alive = parse_qpi_log_lt(log_file, nFlies, nCycles, good);
            end

            %% Map correct quads per cycle
            correct_quads = cell(nCycles, 1);
            cycle_labels = cfg.labels;
            for c = 1:nCycles
                if c <= length(quad_patterns)
                    qp = quad_patterns{c};
                    [~, correct_quads{c}] = led_pattern_to_quads(qp);

                    % For probes ('1111'): use trained safe zone (Q2,Q4)
                    if strcmp(qp, '1111')
                        if c <= length(cycle_labels) && ...
                           (strcmp(cycle_labels{c}, 'PP') || endsWith(cycle_labels{c}, '.P'))
                            correct_quads{c} = [2, 4];
                        else
                            correct_quads{c} = [];
                        end
                    end
                end
            end

            %% Generate one figure per block
            for blk = 1:4
                fig = figure('Units', 'normalized', 'Position', [0.01 0.05 0.98 0.55], 'Visible', 'off');

                for trial = 1:10
                    ci = 3 + (blk - 1) * 11 + trial;  % cycle index (1-based)
                    if ci > nCycles, continue; end

                    ax = subplot(2, 5, trial);
                    imshow(bg * 0.35, 'Parent', ax);
                    hold(ax, 'on');
                    axis(ax, 'image');

                    % Arena circle
                    theta_c = linspace(0, 2*pi, 200);
                    plot(ax, xc + radius*cos(theta_c), yc + radius*sin(theta_c), ...
                        'w-', 'LineWidth', 0.5);

                    cq = correct_quads{ci};
                    fr_on  = on_times(ci);
                    fr_off = off_times(ci);

                    for fi = 1:nFlies
                        if ~fly_alive(fi, ci), continue; end

                        col = fly_cmap(mod(fi-1, size(fly_cmap,1)) + 1, :);
                        xpos = double(trx(fi).x);
                        ypos = double(trx(fi).y);
                        nfr = length(xpos);
                        fr_end = min(fr_off, nfr);

                        if fr_on > nfr, continue; end

                        % Check onset quadrant
                        onset_x = round(xpos(fr_on));
                        onset_y = round(ypos(fr_on));
                        if onset_y >= 1 && onset_y <= size(all_masks,1) && ...
                           onset_x >= 1 && onset_x <= size(all_masks,2)
                            onset_q = all_masks(onset_y, onset_x);
                        else
                            onset_q = 0;
                        end

                        if isempty(cq)
                            % OM or non-training cycle — skip
                            continue;
                        end

                        % Find first safe entry (same logic as compute functions)
                        entry_frame = [];
                        for fr = fr_on:fr_end
                            xi = round(xpos(fr));
                            yi = round(ypos(fr));
                            if yi >= 1 && yi <= size(all_masks,1) && ...
                               xi >= 1 && xi <= size(all_masks,2)
                                q = all_masks(yi, xi);
                                if ismember(q, cq) && ~(fr == fr_on && ismember(onset_q, cq) && onset_q == q)
                                    entry_frame = fr;
                                    break;
                                end
                            end
                        end

                        JITTER_FRAMES = round(1.0 * 30.1);  % 1 second post-entry

                        if ismember(onset_q, cq)
                            % Already in safe — show 1s of movement
                            jit_end = min(fr_on + JITTER_FRAMES, fr_end);
                            frames = fr_on:jit_end;
                            plot(ax, xpos(frames), ypos(frames), '-', ...
                                'Color', [col 0.4], 'LineWidth', 0.6);
                            plot(ax, xpos(fr_on), ypos(fr_on), 'o', ...
                                'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 4);
                        elseif ~isempty(entry_frame)
                            % Draw trajectory from onset to first safe entry
                            frames = fr_on:entry_frame;
                            plot(ax, xpos(frames), ypos(frames), '-', ...
                                'Color', [col 0.7], 'LineWidth', 1.0);
                            % 1s jitter past entry (dimmer)
                            jit_end = min(entry_frame + JITTER_FRAMES, fr_end);
                            if jit_end > entry_frame
                                jit_frames = entry_frame:jit_end;
                                plot(ax, xpos(jit_frames), ypos(jit_frames), '-', ...
                                    'Color', [col 0.3], 'LineWidth', 0.6);
                            end
                            % Onset dot
                            plot(ax, xpos(fr_on), ypos(fr_on), 'o', ...
                                'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 3);
                            % Entry square
                            plot(ax, xpos(entry_frame), ypos(entry_frame), 's', ...
                                'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 4);
                        else
                            % Never reached safe — draw full trajectory, mark with X
                            frames = fr_on:fr_end;
                            plot(ax, xpos(frames), ypos(frames), '-', ...
                                'Color', [col 0.3], 'LineWidth', 0.5);
                            plot(ax, xpos(fr_on), ypos(fr_on), 'o', ...
                                'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 3);
                            plot(ax, xpos(fr_end), ypos(fr_end), 'x', ...
                                'Color', col, 'MarkerSize', 5, 'LineWidth', 1.5);
                        end
                    end

                    % Crop to arena
                    xlim(ax, [xc-radius*1.05, xc+radius*1.05]);
                    ylim(ax, [yc-radius*1.05, yc+radius*1.05]);
                    set(ax, 'XTick', [], 'YTick', []);

                    safe_str = '';
                    if ~isempty(cq), safe_str = sprintf(' Q%s', num2str(cq)); end
                    title(ax, sprintf('B%d.%d%s', blk, trial, safe_str), ...
                        'FontSize', 8, 'Color', 'w');

                    hold(ax, 'off');
                end

                sgtitle(fig, sprintf('%s — %s — Block %d — Onset to Safe Entry', ...
                    cond_label, strrep(exp_name, '_', '\_'), blk), ...
                    'FontSize', 11, 'FontWeight', 'bold');

                out_png = fullfile(save_dir, sprintf('latency_traj_block%d_%s.png', blk, exp_name));
                exportgraphics(fig, out_png, 'Resolution', 200);
                savefig(fig, strrep(out_png, '.png', '.fig'));
                close(fig);
            end

            fprintf('done\n');
        end
    end

    fprintf('Done.\n');
end


%% ========================================================================
function fly_alive = parse_qpi_log_lt(log_file, nFlies, nCycles, fly_ids)
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
