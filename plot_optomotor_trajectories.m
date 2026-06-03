%% plot_optomotor_trajectories.m
% Fly trajectory overlay on arena background during CW and CCW optomotor.
% Works for P006, P007, P008, P009, P010, P011, P014.
%
% For each genotype: 2 figures (OM1 pre-training, OM2 post-training).
% Each figure: 2 panels (CW, CCW) with background image and fly paths.
% Fly selection: picks flies whose mean angular velocity during CW+CCW
%   falls closest to the per-experiment median (selects representative flies).
%
% Uses X,Y from trx.mat, background PNG from analysis/, timing from
% LED detector + metadata (same as analyze_optomotor.m).

clearvars -except TARGET_PROTOCOLS; clc;


ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';
PROTOCOLS    = {'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P014', 'P015', 'P016'};

if ~exist('TARGET_PROTOCOLS', 'var'), TARGET_PROTOCOLS = {}; end
if ~isempty(TARGET_PROTOCOLS)
    PROTOCOLS = PROTOCOLS(ismember(PROTOCOLS, TARGET_PROTOCOLS));
end
FPS          = 30.1;
N_FLIES_PER_EXP = 3;   % number of median-range flies to plot per experiment
TRAJECTORY_SEC  = 50;   % first N seconds of CW / CCW to plot
TRAJECTORY_ALPHA = 0.8; % transparency for trajectory lines
LINE_WIDTH   = 1.2;

% Fixed fly colors: dark green, orange, purple
FLY_COLORS = [
    0.00  0.39  0.00;   % dark green
    0.93  0.49  0.00;   % orange
    0.50  0.00  0.50;   % purple
];

%% ========================================================================
%  PROTOCOL LOOP
%  ========================================================================

for pp = 1:length(PROTOCOLS)
    PROTOCOL = PROTOCOLS{pp};
    prot_path = fullfile(ANALYSIS_DIR, PROTOCOL);

    % Skip if protocol directory doesn't exist
    if ~exist(prot_path, 'dir')
        fprintf('Protocol %s directory not found, skipping.\n', PROTOCOL);
        continue;
    end

    summary_dir = fullfile(prot_path, 'summary', 'trajectories');
    if ~exist(summary_dir, 'dir'), mkdir(summary_dir); end

    %% Find all experiments
    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));

    % SAFEGUARD: Only process directories containing '_Rig' (experiment folders).
    % This prevents accidental processing of summary/output directories.
    exp_dirs = exp_dirs(~contains({exp_dirs.name}, 'summary') & ...
                         ~contains({exp_dirs.name}, 'distance') & ...
                         ~contains({exp_dirs.name}, 'latency') & ...
                         ~contains({exp_dirs.name}, 'dist_to_safe') & ...
                         contains({exp_dirs.name}, '_Rig'));

    fprintf('=== Optomotor Trajectory Plots: %s (%d experiments) ===\n\n', ...
        PROTOCOL, length(exp_dirs));

    %% Process each experiment — collect trajectory segments
    all_data = {};

    for e = 1:length(exp_dirs)
        exp_name = exp_dirs(e).name;
        exp_path = fullfile(prot_path, exp_name);
        analysis_dir = fullfile(exp_path, 'analysis');

        fprintf('[%d/%d] %s ... ', e, length(exp_dirs), exp_name);

        try
            %% Load trx
            trx_data = load(fullfile(exp_path, 'trx.mat'));
            trx = trx_data.trx;

            % Filter flies spanning full recording
            max_end = max([trx.endframe]);
            good = [];
            for k = 1:length(trx)
                if trx(k).firstframe == 1 && trx(k).endframe >= (max_end - 30)
                    good = [good, k]; %#ok<AGROW>
                end
            end
            trx = trx(good);
            num_flies = length(trx);
            nframes = length(trx(1).x);

            %% Load background image (note: no per-experiment skip here —
            %  this script aggregates across experiments for per-genotype plots)
            bg_files = dir(fullfile(analysis_dir, 'background_*.png'));
            if isempty(bg_files)
                warning('No background image found, skipping.');
                continue;
            end
            bg_img = imread(fullfile(analysis_dir, bg_files(1).name));

            %% Load LED detector
            led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
            led_data  = load(fullfile(analysis_dir, led_files(end).name));
            LED = led_data.LED_detector;
            on_times  = LED.on_times;
            off_times = LED.off_times;

            om1_led_on  = on_times(1);
            om1_led_off = off_times(1);
            om2_led_on  = on_times(end);
            om2_led_off = off_times(end);

            %% Parse metadata for CW/CCW transition frames
            meta_file = fullfile(exp_path, 'original_metadata.txt');
            [p1_cw_end, p1_ccw_start, p2_cw_end, p2_ccw_start] = parse_om_metadata(meta_file);

            %% Load dead fly info
            fly_alive_om1 = true(num_flies, 1);
            fly_alive_om2 = true(num_flies, 1);
            log_file = fullfile(analysis_dir, sprintf('QPI_log_%s.txt', exp_name));
            if exist(log_file, 'file')
                num_cycles = length(on_times);
                fly_alive_all = parse_qpi_log_om(log_file, num_flies, num_cycles, good);
                if ~isempty(fly_alive_all)
                    fly_alive_om1 = fly_alive_all(:, 1);
                    fly_alive_om2 = fly_alive_all(:, end);
                end
            end

            %% Extract genotype
            tokens = strsplit(exp_name, '_');
            genotype = tokens{1};

            %% Define CW/CCW frame windows for OM1 and OM2
            phases = struct();
            phases(1).name       = 'OM1';
            phases(1).cw_start   = om1_led_on;
            phases(1).cw_end     = p1_cw_end;
            phases(1).ccw_start  = p1_ccw_start;
            phases(1).ccw_end    = om1_led_off;
            phases(1).alive      = fly_alive_om1;

            phases(2).name       = 'OM2';
            phases(2).cw_start   = om2_led_on;
            phases(2).cw_end     = p2_cw_end;
            phases(2).ccw_start  = p2_ccw_start;
            phases(2).ccw_end    = om2_led_off;
            phases(2).alive      = fly_alive_om2;

            %% Extract all alive fly trajectories (first TRAJECTORY_SEC) + angular velocity
            rec = struct();
            rec.experiment = exp_name;
            rec.genotype   = genotype;
            rec.bg_img     = bg_img;

            for pi = 1:2
                alive = phases(pi).alive;
                alive_idx = find(alive);

                max_frames = round(TRAJECTORY_SEC * FPS);
                cw_frames  = phases(pi).cw_start : min(phases(pi).cw_start + max_frames - 1, min(phases(pi).cw_end, nframes));
                ccw_frames = phases(pi).ccw_start : min(phases(pi).ccw_start + max_frames - 1, min(phases(pi).ccw_end, nframes));

                rec.phases(pi).name = phases(pi).name;
                n_alive = length(alive_idx);
                rec.phases(pi).fly_ids = alive_idx;

                for ai = 1:n_alive
                    fi = alive_idx(ai);
                    rec.phases(pi).cw_x{ai}  = trx(fi).x(cw_frames);
                    rec.phases(pi).cw_y{ai}  = trx(fi).y(cw_frames);
                    rec.phases(pi).ccw_x{ai} = trx(fi).x(ccw_frames);
                    rec.phases(pi).ccw_y{ai} = trx(fi).y(ccw_frames);

                    % Mean |angular velocity| for this fly across CW+CCW
                    theta_cw  = trx(fi).theta(cw_frames);
                    theta_ccw = trx(fi).theta(ccw_frames);
                    av_cw  = abs(diff(unwrap(theta_cw))) * FPS;
                    av_ccw = abs(diff(unwrap(theta_ccw))) * FPS;
                    rec.phases(pi).fly_angvel(ai) = mean([av_cw(:); av_ccw(:)], 'omitnan');
                end
            end

            all_data{end+1} = rec; %#ok<SAGROW>
            fprintf('OK (n_alive: OM1=%d, OM2=%d)\n', sum(fly_alive_om1), sum(fly_alive_om2));

        catch ME
            fprintf('FAILED: %s\n', ME.message);
        end
    end

    %% Group by genotype
    genotypes = {};
    for i = 1:length(all_data)
        genotypes{end+1} = all_data{i}.genotype; %#ok<SAGROW>
    end
    unique_genos = unique(genotypes);

    fprintf('\n=== Generating per-genotype trajectory plots ===\n');

    for gi = 1:length(unique_genos)
        geno = unique_genos{gi};
        geno_idx = find(strcmp(genotypes, geno));
        nExp = length(geno_idx);

        fprintf('  %s (%d experiments) ... ', geno, nExp);

        % Use background from first experiment of this genotype
        bg_img = all_data{geno_idx(1)}.bg_img;

        %% Select 3 flies from OM1 data (genotype-wide median angular velocity)
        pool_angvel_om1 = [];
        pool_exp_idx    = [];   % which experiment index in geno_idx
        pool_trx_id     = [];   % actual trx row index (consistent across phases)
        pool_fly_id     = {};

        for ei = 1:nExp
            idx = geno_idx(ei);
            rec = all_data{idx};
            n_flies = length(rec.phases(1).cw_x);

            for fi = 1:n_flies
                pool_angvel_om1(end+1) = rec.phases(1).fly_angvel(fi); %#ok<SAGROW>
                pool_exp_idx(end+1)    = ei;                           %#ok<SAGROW>
                pool_trx_id(end+1)     = rec.phases(1).fly_ids(fi);   %#ok<SAGROW>
                pool_fly_id{end+1}     = sprintf('%s fly%d', ...
                    rec.experiment, rec.phases(1).fly_ids(fi));        %#ok<SAGROW>
            end
        end

        med_val = median(pool_angvel_om1, 'omitnan');
        [~, sorted_i] = sort(abs(pool_angvel_om1 - med_val));

        % For L2 and L3 genotypes, skip the first 3 and take the next 3
        % Generic check: does genotype string start with 'L2' or 'L3'
        if (strncmp(geno, 'L2', 2) || strncmp(geno, 'L3', 2)) && length(sorted_i) > 2 * N_FLIES_PER_EXP
            offset = N_FLIES_PER_EXP;
        else
            offset = 0;
        end
        n_pick = min(N_FLIES_PER_EXP, length(sorted_i) - offset);
        pick = sorted_i(offset+1 : offset+n_pick);

        %% Generate OM1 and OM2 figures using the SAME 3 flies
        for pi = 1:2
            phase_name = all_data{geno_idx(1)}.phases(pi).name;

            fig = figure('Position', [50 50 1600 800], 'Visible', 'off');

            %% --- CW panel ---
            ax1 = subplot(1, 2, 1, 'Parent', fig);
            imshow(bg_img, 'Parent', ax1);
            hold(ax1, 'on');
            title(ax1, sprintf('%s — CW (first %ds)', phase_name, TRAJECTORY_SEC), 'FontSize', 18);

            for si = 1:n_pick
                col = FLY_COLORS(si, :);
                ei  = pool_exp_idx(pick(si));
                trx_id = pool_trx_id(pick(si));
                rec = all_data{geno_idx(ei)};

                % Find this trx ID in the current phase's fly_ids
                fi = find(rec.phases(pi).fly_ids == trx_id, 1);
                if isempty(fi), continue; end  % fly dead in this phase

                px = rec.phases(pi).cw_x{fi};
                py = rec.phases(pi).cw_y{fi};

                plot(ax1, px, py, '-', 'Color', [col, TRAJECTORY_ALPHA], ...
                    'LineWidth', LINE_WIDTH, 'HandleVisibility', 'off');
                plot(ax1, px(1), py(1), 'o', 'Color', col, ...
                    'MarkerSize', 8, 'MarkerFaceColor', col, ...
                    'HandleVisibility', 'off');
                plot(ax1, px(end), py(end), 's', 'Color', col, ...
                    'MarkerSize', 8, 'MarkerFaceColor', col, ...
                    'HandleVisibility', 'off');
                plot(ax1, NaN, NaN, '-', 'Color', col, 'LineWidth', 2.5, ...
                    'DisplayName', sprintf('%s (%.1f deg/s)', ...
                    pool_fly_id{pick(si)}, pool_angvel_om1(pick(si))));
            end
            lg1 = legend(ax1, 'Location', 'none', 'FontSize', 12, ...
                'TextColor', 'k', 'Interpreter', 'none', 'Orientation', 'horizontal');
            lg1.Position(2) = 0.88;  % between title and images
            lg1.Position(1) = 0.05;  % left-align with some margin
            hold(ax1, 'off');

            %% --- CCW panel ---
            ax2 = subplot(1, 2, 2, 'Parent', fig);
            imshow(bg_img, 'Parent', ax2);
            hold(ax2, 'on');
            title(ax2, sprintf('%s — CCW (first %ds)', phase_name, TRAJECTORY_SEC), 'FontSize', 18);

            for si = 1:n_pick
                col = FLY_COLORS(si, :);
                ei  = pool_exp_idx(pick(si));
                trx_id = pool_trx_id(pick(si));
                rec = all_data{geno_idx(ei)};

                fi = find(rec.phases(pi).fly_ids == trx_id, 1);
                if isempty(fi), continue; end

                px = rec.phases(pi).ccw_x{fi};
                py = rec.phases(pi).ccw_y{fi};

                plot(ax2, px, py, '-', 'Color', [col, TRAJECTORY_ALPHA], ...
                    'LineWidth', LINE_WIDTH, 'HandleVisibility', 'off');
                plot(ax2, px(1), py(1), 'o', 'Color', col, ...
                    'MarkerSize', 8, 'MarkerFaceColor', col, ...
                    'HandleVisibility', 'off');
                plot(ax2, px(end), py(end), 's', 'Color', col, ...
                    'MarkerSize', 8, 'MarkerFaceColor', col, ...
                    'HandleVisibility', 'off');
                plot(ax2, NaN, NaN, '-', 'Color', col, 'LineWidth', 2.5, ...
                    'DisplayName', sprintf('%s (%.1f deg/s)', ...
                    pool_fly_id{pick(si)}, pool_angvel_om1(pick(si))));
            end
            legend(ax2, 'off');  % only need legend once (on CW panel)
            hold(ax2, 'off');

            sgtitle(fig, sprintf('%s  %s — Fly trajectories (first %ds, 3 median flies, n=%d exp)', ...
                geno, phase_name, TRAJECTORY_SEC, nExp), ...
                'FontSize', 20, 'FontWeight', 'bold');

            % Save per genotype
            out_png = fullfile(summary_dir, sprintf('trajectories_%s_%s_%s.png', ...
                PROTOCOL, geno, phase_name));
            out_fig = fullfile(summary_dir, sprintf('trajectories_%s_%s_%s.fig', ...
                PROTOCOL, geno, phase_name));
            out_svg = fullfile(summary_dir, sprintf('trajectories_%s_%s_%s.svg', ...
                PROTOCOL, geno, phase_name));
            exportgraphics(fig, out_png, 'Resolution', 200);
            saveas(fig, out_svg);
            savefig(fig, out_fig);
            close(fig);
        end

        fprintf('saved.\n');
    end

    fprintf('\nDone. Trajectory plots saved to:\n  %s\n\n', summary_dir);

end  % PROTOCOL LOOP

fprintf('========================================\n');
fprintf('ALL PROTOCOLS COMPLETE\n');
fprintf('========================================\n');


%% ========================================================================
%  Helper functions (same as analyze_optomotor.m)
%  ========================================================================

function [p1_cw_end, p1_ccw_start, p2_cw_end, p2_ccw_start] = parse_om_metadata(meta_file)
    p1_cw_end    = NaN;
    p1_ccw_start = NaN;
    p2_cw_end    = NaN;
    p2_ccw_start = NaN;

    fid = fopen(meta_file, 'r');
    if fid < 0
        error('Cannot open metadata file: %s', meta_file);
    end
    raw = textscan(fid, '%s', 'Delimiter', '\n');
    fclose(fid);
    lines = raw{1};

    for li = 1:length(lines)
        ln = lines{li};

        if contains(ln, 'Phase1 CW end')
            tok = regexp(ln, 'camera frame\s+(\d+)', 'tokens');
            if ~isempty(tok), p1_cw_end = str2double(tok{1}{1}); end

        elseif contains(ln, 'Phase1 CCW start')
            tok = regexp(ln, 'camera frame\s+(\d+)', 'tokens');
            if ~isempty(tok), p1_ccw_start = str2double(tok{1}{1}); end

        elseif contains(ln, 'Phase2 CW end')
            tok = regexp(ln, 'camera frame\s+(\d+)', 'tokens');
            if ~isempty(tok), p2_cw_end = str2double(tok{1}{1}); end

        elseif contains(ln, 'Phase2 CCW start')
            tok = regexp(ln, 'camera frame\s+(\d+)', 'tokens');
            if ~isempty(tok), p2_ccw_start = str2double(tok{1}{1}); end
        end
    end

    if isnan(p1_cw_end) || isnan(p1_ccw_start) || isnan(p2_cw_end) || isnan(p2_ccw_start)
        error('Could not parse all CW/CCW frame numbers from metadata');
    end
end


function fly_alive = parse_qpi_log_om(log_file, num_flies, num_cycles, fly_ids)
    fly_alive = true(num_flies, num_cycles);
    try
        fid = fopen(log_file, 'r');
        if fid < 0, fly_alive = []; return; end
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
        fly_alive = [];
    end
end
