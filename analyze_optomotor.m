function analyze_optomotor(protocols, varargin)
% ANALYZE_OPTOMOTOR  Optomotor response analysis (config-driven).
%
%   analyze_optomotor({'P008','P017','P019'})
%   analyze_optomotor({'P017'}, 'SmoothWinSec', 1.0)
%
%   Measures angular velocity (deg/s) from theta in trx.mat during OM1 and OM2.
%   Each OM phase: CW (~100s) -> 5s gap -> CCW (~100s).
%
%   Uses get_protocol_config to identify which protocols have optomotor and
%   which cycles are OM1/OM2. Only processes protocols with has_optomotor=true.
%
%   Produces TWO sets of trace plots per experiment:
%     1. Raw angular velocity (no smoothing)
%     2. Smoothed angular velocity (movmean, default 0.5 s window)
%
%   Required:
%     protocols — cell array of protocol names, e.g. {'P008','P017','P019'}
%
%   Name-Value pairs:
%     'AnalysisDir'   — path to analysis root (default: ~/Documents/analysisdatalocal)
%     'FPS'           — frames per second (default: 30.1)
%     'SmoothWinSec'  — smoothing window in seconds for smoothed plots (default: 0.5)
%     'ForceRerun'    — logical, reprocess even if output exists (default: false)
%     'ShowPlots'     — logical (default: false)
%
%   Outputs per experiment (in <exp>/analysis/optomotor/):
%     optomotor_<exp>.mat              — angular velocity data (raw + smoothed)
%     optomotor_<exp>_traces_raw.png   — raw OM1/OM2 traces
%     optomotor_<exp>_traces_smooth.png — smoothed OM1/OM2 traces
%     optomotor_<exp>_summary.png      — bar chart (CW/gap/CCW means)
%
%   Summary per genotype (in <protocol>/summary/optomotor/):
%     summary_optomotor_<geno>.mat/.png — genotype bar chart
%     summary_optomotor_comparison_<geno>_raw.png    — OM1 vs OM2 overlay (raw)
%     summary_optomotor_comparison_<geno>_smooth.png  — OM1 vs OM2 overlay (smoothed)

    %% Parse inputs
    ip = inputParser;
    addRequired(ip, 'protocols', @iscell);
    addParameter(ip, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(ip, 'FPS', 30.1, @isnumeric);
    addParameter(ip, 'SmoothWinSec', 0.5, @isnumeric);
    addParameter(ip, 'ForceRerun', false, @islogical);
    addParameter(ip, 'ShowPlots', false, @islogical);
    parse(ip, protocols, varargin{:});
    opts = ip.Results;

    ANALYSIS_DIR   = opts.AnalysisDir;
    FPS            = opts.FPS;
    SMOOTH_WIN_SEC = opts.SmoothWinSec;
    smooth_win     = round(SMOOTH_WIN_SEC * FPS);

    %% Display-name maps
    [prot_display, geno_display] = get_display_names();
    gname = @(g) map_or_default(geno_display, g);
    pname = @(p) map_or_default(prot_display, p);

    %% ====================================================================
    %  PROTOCOL LOOP
    %  ====================================================================
    for pp = 1:length(protocols)
        PROTOCOL = protocols{pp};
        prot_path = fullfile(ANALYSIS_DIR, PROTOCOL);

        % Validate protocol has optomotor via config
        cfg = get_protocol_config(PROTOCOL);
        if ~cfg.has_optomotor
            fprintf('Protocol %s has no optomotor — skipping.\n', PROTOCOL);
            continue;
        end

        if ~exist(prot_path, 'dir')
            fprintf('Protocol %s directory not found, skipping.\n', PROTOCOL);
            continue;
        end

        % Identify OM cycle indices from config
        om_cycles = cfg.om_cycles;
        if length(om_cycles) < 2
            fprintf('Protocol %s has fewer than 2 OM cycles — skipping.\n', PROTOCOL);
            continue;
        end
        om1_cycle = om_cycles(1);
        om2_cycle = om_cycles(end);
        fprintf('Protocol %s: OM1=cycle %d (%s), OM2=cycle %d (%s)\n', ...
            PROTOCOL, om1_cycle, cfg.labels{om1_cycle}, om2_cycle, cfg.labels{om2_cycle});

        summary_dir = fullfile(prot_path, 'summary', 'optomotor');
        if ~exist(summary_dir, 'dir'), mkdir(summary_dir); end

        %% Find all experiments
        exp_dirs = dir(prot_path);
        exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));
        exp_dirs = exp_dirs(~contains({exp_dirs.name}, 'summary') & ...
                             contains({exp_dirs.name}, '_Rig'));

        all_results = {};
        nProcessed = 0;
        nFailed = 0;
        failed_list = {};

        fprintf('=== Optomotor Analysis: %s (%s) — %d experiments ===\n\n', ...
            PROTOCOL, pname(PROTOCOL), length(exp_dirs));

        for e = 1:length(exp_dirs)
            exp_name = exp_dirs(e).name;
            exp_path = fullfile(prot_path, exp_name);
            analysis_dir = fullfile(exp_path, 'analysis');

            % Skip if output already exists (unless ForceRerun)
            opto_dir = fullfile(analysis_dir, 'optomotor');
            opto_check = fullfile(opto_dir, sprintf('optomotor_%s_summary.png', exp_name));
            if exist(opto_check, 'file') && ~opts.ForceRerun
                fprintf('[%d/%d] %s — exists, skipping\n', e, length(exp_dirs), exp_name);
                nProcessed = nProcessed + 1;
                continue;
            end

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

                %% Load LED detector
                led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
                led_data  = load(fullfile(analysis_dir, led_files(end).name));
                LED = led_data.LED_detector;
                on_times  = LED.on_times;
                off_times = LED.off_times;

                % OM1/OM2 LED boundaries from cycle indices
                om1_led_on  = on_times(om1_cycle);
                om1_led_off = off_times(om1_cycle);
                om2_led_on  = on_times(om2_cycle);
                om2_led_off = off_times(om2_cycle);

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
                        fly_alive_om1 = fly_alive_all(:, om1_cycle);
                        fly_alive_om2 = fly_alive_all(:, om2_cycle);
                    end
                end

                %% Extract genotype
                tokens = strsplit(exp_name, '_');
                genotype = tokens{1};

                %% Compute angular velocity for OM1 and OM2
                POST_CCW_SEC = 10;
                POST_CCW_FR  = round(POST_CCW_SEC * FPS);
                PRE_OM2_SEC  = 10;
                PRE_OM2_FR   = round(PRE_OM2_SEC * FPS);

                phases = struct();
                phases(1).name      = 'OM1';
                phases(1).fr_start  = 1;
                phases(1).fr_end    = min(om1_led_off + POST_CCW_FR, nframes);
                phases(1).led_on    = om1_led_on;
                phases(1).cw_end    = p1_cw_end;
                phases(1).ccw_start = p1_ccw_start;
                phases(1).led_off   = om1_led_off;
                phases(1).alive     = fly_alive_om1;

                phases(2).name      = 'OM2';
                phases(2).fr_start  = max(1, om2_led_on - PRE_OM2_FR);
                phases(2).fr_end    = min(om2_led_off + POST_CCW_FR, nframes);
                phases(2).led_on    = om2_led_on;
                phases(2).cw_end    = p2_cw_end;
                phases(2).ccw_start = p2_ccw_start;
                phases(2).led_off   = om2_led_off;
                phases(2).alive     = fly_alive_om2;

                result = struct();
                result.experiment    = exp_name;
                result.genotype      = genotype;
                result.protocol      = PROTOCOL;
                result.num_flies     = num_flies;
                result.fly_ids       = good;
                result.fps           = FPS;
                result.smooth_win_sec = SMOOTH_WIN_SEC;
                result.fly_alive_om1 = fly_alive_om1;
                result.fly_alive_om2 = fly_alive_om2;

                for pi = 1:2
                    fr_s = max(1, phases(pi).fr_start);
                    fr_e = min(phases(pi).fr_end, nframes);
                    frames = fr_s:fr_e;
                    n_fr = length(frames);

                    alive = phases(pi).alive;
                    n_alive = sum(alive);

                    led_on_frame = phases(pi).led_on;
                    t_axis = (frames - led_on_frame) / FPS;

                    t_cw_end    = (phases(pi).cw_end - led_on_frame) / FPS;
                    t_ccw_start = (phases(pi).ccw_start - led_on_frame) / FPS;
                    t_led_off   = (phases(pi).led_off - led_on_frame) / FPS;

                    % Raw angular velocity per fly
                    angvel_raw = NaN(n_alive, n_fr);
                    ai = 0;
                    for f = 1:num_flies
                        if ~alive(f), continue; end
                        ai = ai + 1;

                        theta_seg = trx(f).theta(frames);
                        theta_uw  = unwrap(theta_seg);
                        dtheta    = [0; diff(theta_uw)];
                        angvel_degs = rad2deg(dtheta) * FPS;
                        angvel_raw(ai, :) = angvel_degs';
                    end

                    % Smoothed angular velocity
                    angvel_smooth = NaN(n_alive, n_fr);
                    if smooth_win > 1
                        for ai2 = 1:n_alive
                            angvel_smooth(ai2, :) = movmean(angvel_raw(ai2, :), smooth_win, 'omitnan');
                        end
                    else
                        angvel_smooth = angvel_raw;
                    end

                    % Sub-phase indices (1-based within window)
                    led_on_idx    = led_on_frame - fr_s + 1;
                    cw_end_idx    = phases(pi).cw_end - fr_s + 1;
                    ccw_start_idx = phases(pi).ccw_start - fr_s + 1;
                    led_off_idx   = phases(pi).led_off - fr_s + 1;

                    led_on_idx    = min(max(led_on_idx, 1), n_fr);
                    cw_end_idx    = min(max(cw_end_idx, 1), n_fr);
                    ccw_start_idx = min(max(ccw_start_idx, 1), n_fr);
                    led_off_idx   = min(max(led_off_idx, 1), n_fr);

                    % Sub-phase scalar means (from raw data)
                    cw_mean_per_fly  = mean(angvel_raw(:, led_on_idx:cw_end_idx), 2, 'omitnan');
                    gap_mean_per_fly = mean(angvel_raw(:, cw_end_idx:ccw_start_idx), 2, 'omitnan');
                    ccw_mean_per_fly = mean(angvel_raw(:, ccw_start_idx:led_off_idx), 2, 'omitnan');

                    ph = struct();
                    ph.name            = phases(pi).name;
                    ph.fr_start        = fr_s;
                    ph.fr_end          = fr_e;
                    ph.led_on_frame    = led_on_frame;
                    ph.led_off_frame   = phases(pi).led_off;
                    ph.cw_end_frame    = phases(pi).cw_end;
                    ph.ccw_start_frame = phases(pi).ccw_start;
                    ph.t_axis          = t_axis;
                    ph.t_cw_end        = t_cw_end;
                    ph.t_ccw_start     = t_ccw_start;
                    ph.t_led_off       = t_led_off;
                    ph.n_alive         = n_alive;

                    % Raw traces + stats
                    ph.angvel_raw      = angvel_raw;
                    ph.mean_angvel_raw = mean(angvel_raw, 1, 'omitnan');
                    ph.sem_angvel_raw  = std(angvel_raw, 0, 1, 'omitnan') / sqrt(max(n_alive, 1));

                    % Smoothed traces + stats
                    ph.angvel_smooth      = angvel_smooth;
                    ph.mean_angvel_smooth = mean(angvel_smooth, 1, 'omitnan');
                    ph.sem_angvel_smooth  = std(angvel_smooth, 0, 1, 'omitnan') / sqrt(max(n_alive, 1));

                    % Sub-phase summaries (from raw)
                    ph.cw_mean_per_fly  = cw_mean_per_fly;
                    ph.gap_mean_per_fly = gap_mean_per_fly;
                    ph.ccw_mean_per_fly = ccw_mean_per_fly;
                    ph.cw_grand_mean    = mean(cw_mean_per_fly, 'omitnan');
                    ph.cw_grand_sem     = std(cw_mean_per_fly, 0, 1) / sqrt(max(n_alive, 1));
                    ph.gap_grand_mean   = mean(gap_mean_per_fly, 'omitnan');
                    ph.gap_grand_sem    = std(gap_mean_per_fly, 0, 1) / sqrt(max(n_alive, 1));
                    ph.ccw_grand_mean   = mean(ccw_mean_per_fly, 'omitnan');
                    ph.ccw_grand_sem    = std(ccw_mean_per_fly, 0, 1) / sqrt(max(n_alive, 1));

                    result.phases(pi) = ph;
                end

                %% Save per-experiment .mat
                out_dir = fullfile(analysis_dir, 'optomotor');
                if ~exist(out_dir, 'dir'), mkdir(out_dir); end

                mat_file = fullfile(out_dir, sprintf('optomotor_%s.mat', exp_name));
                save(mat_file, '-struct', 'result');

                %% Plot 1a: Raw angular velocity traces (2 panels: OM1, OM2)
                plot_traces(result, out_dir, exp_name, 'raw', opts.ShowPlots);

                %% Plot 1b: Smoothed angular velocity traces
                plot_traces(result, out_dir, exp_name, 'smooth', opts.ShowPlots);

                %% Plot 2: Summary bar chart — CW / gap / CCW per OM phase
                plot_summary_bar(result, out_dir, exp_name, opts.ShowPlots);

                all_results{end+1} = result; %#ok<AGROW>
                nProcessed = nProcessed + 1;
                fprintf('done\n');

            catch ME
                fprintf('Error: %s\n', ME.message);
                failed_list{end+1} = sprintf('%s: %s', exp_name, ME.message); %#ok<AGROW>
                nFailed = nFailed + 1;
            end
        end

        %% ======== GENOTYPE SUMMARY ========
        fprintf('\n--- Generating genotype summaries for %s ---\n', PROTOCOL);

        genotypes = {};
        geno_idx  = {};
        for ei = 1:length(all_results)
            geno = all_results{ei}.genotype;
            gi = find(strcmp(genotypes, geno), 1);
            if isempty(gi)
                genotypes{end+1} = geno; %#ok<AGROW>
                geno_idx{end+1}  = ei;   %#ok<AGROW>
            else
                geno_idx{gi} = [geno_idx{gi}, ei]; %#ok<AGROW>
            end
        end

        for gi = 1:length(genotypes)
            geno = genotypes{gi};
            exp_indices = geno_idx{gi};
            nExp = length(exp_indices);

            fprintf('  %s (%s): %d experiments\n', geno, gname(geno), nExp);

            % Per-experiment sub-phase means: [nExp x 6]
            exp_means = NaN(nExp, 6);
            for k = 1:nExp
                r = all_results{exp_indices(k)};
                exp_means(k, 1) = r.phases(1).cw_grand_mean;
                exp_means(k, 2) = r.phases(1).gap_grand_mean;
                exp_means(k, 3) = r.phases(1).ccw_grand_mean;
                exp_means(k, 4) = r.phases(2).cw_grand_mean;
                exp_means(k, 5) = r.phases(2).gap_grand_mean;
                exp_means(k, 6) = r.phases(2).ccw_grand_mean;
            end

            geno_mean = mean(exp_means, 1, 'omitnan');
            geno_sem  = std(exp_means, 0, 1, 'omitnan') / sqrt(max(nExp, 1));

            %% Summary bar chart per genotype
            plot_genotype_bar(geno, gname(geno), PROTOCOL, pname(PROTOCOL), ...
                exp_means, geno_mean, geno_sem, nExp, summary_dir, opts.ShowPlots);

            %% OM1 vs OM2 comparison: overlaid traces per genotype
            % Build common time axis
            t_min = 0; t_max = 0;
            for k = 1:nExp
                r = all_results{exp_indices(k)};
                t_min = min(t_min, r.phases(1).t_axis(1));
                t_min = min(t_min, r.phases(2).t_axis(1));
                t_max = max(t_max, r.phases(1).t_axis(end));
                t_max = max(t_max, r.phases(2).t_axis(end));
            end
            dt = 1 / FPS;
            t_common = t_min:dt:t_max;

            t_cw_ends    = NaN(nExp, 2);
            t_ccw_starts = NaN(nExp, 2);
            t_led_offs   = NaN(nExp, 2);

            % Raw overlay traces
            om1_raw = NaN(nExp, length(t_common));
            om2_raw = NaN(nExp, length(t_common));
            % Smoothed overlay traces
            om1_smooth = NaN(nExp, length(t_common));
            om2_smooth = NaN(nExp, length(t_common));

            for k = 1:nExp
                r = all_results{exp_indices(k)};
                om1_raw(k, :) = interp1(r.phases(1).t_axis, r.phases(1).mean_angvel_raw, ...
                    t_common, 'linear', NaN);
                om2_raw(k, :) = interp1(r.phases(2).t_axis, r.phases(2).mean_angvel_raw, ...
                    t_common, 'linear', NaN);
                om1_smooth(k, :) = interp1(r.phases(1).t_axis, r.phases(1).mean_angvel_smooth, ...
                    t_common, 'linear', NaN);
                om2_smooth(k, :) = interp1(r.phases(2).t_axis, r.phases(2).mean_angvel_smooth, ...
                    t_common, 'linear', NaN);

                t_cw_ends(k, 1)    = r.phases(1).t_cw_end;
                t_ccw_starts(k, 1) = r.phases(1).t_ccw_start;
                t_led_offs(k, 1)   = r.phases(1).t_led_off;
                t_cw_ends(k, 2)    = r.phases(2).t_cw_end;
                t_ccw_starts(k, 2) = r.phases(2).t_ccw_start;
                t_led_offs(k, 2)   = r.phases(2).t_led_off;
            end

            % Raw comparison plot
            plot_om_comparison(t_common, om1_raw, om2_raw, nExp, ...
                t_cw_ends, t_ccw_starts, t_led_offs, ...
                geno, gname(geno), PROTOCOL, pname(PROTOCOL), ...
                'raw', summary_dir, opts.ShowPlots);

            % Smoothed comparison plot
            plot_om_comparison(t_common, om1_smooth, om2_smooth, nExp, ...
                t_cw_ends, t_ccw_starts, t_led_offs, ...
                geno, gname(geno), PROTOCOL, pname(PROTOCOL), ...
                sprintf('smooth_%.1fs', SMOOTH_WIN_SEC), summary_dir, opts.ShowPlots);

            %% Save genotype summary .mat
            geno_data = struct();
            geno_data.genotype         = geno;
            geno_data.protocol         = PROTOCOL;
            geno_data.n_experiments    = nExp;
            geno_data.smooth_win_sec   = SMOOTH_WIN_SEC;
            geno_data.experiment_names = {};
            for k = 1:nExp
                geno_data.experiment_names{k} = all_results{exp_indices(k)}.experiment;
            end
            geno_data.sub_phase_names = {'OM1-CW','OM1-gap','OM1-CCW','OM2-CW','OM2-gap','OM2-CCW'};
            geno_data.exp_means       = exp_means;
            geno_data.geno_mean       = geno_mean;
            geno_data.geno_sem        = geno_sem;
            geno_data.t_common        = t_common;
            geno_data.om1_traces_raw    = om1_raw;
            geno_data.om2_traces_raw    = om2_raw;
            geno_data.om1_traces_smooth = om1_smooth;
            geno_data.om2_traces_smooth = om2_smooth;
            geno_data.t_cw_ends       = t_cw_ends;
            geno_data.t_ccw_starts    = t_ccw_starts;

            mat_out = fullfile(summary_dir, sprintf('summary_optomotor_%s.mat', geno));
            save(mat_out, '-struct', 'geno_data');
            fprintf('  Saved: %s\n', mat_out);
        end

        %% Final report
        fprintf('\n========================================\n');
        fprintf('OPTOMOTOR ANALYSIS SUMMARY: %s (%s)\n', PROTOCOL, pname(PROTOCOL));
        fprintf('========================================\n');
        fprintf('Processed: %d\n', nProcessed);
        fprintf('Failed:    %d\n', nFailed);
        if ~isempty(failed_list)
            fprintf('\nFailed experiments:\n');
            for fi = 1:length(failed_list)
                fprintf('  %s\n', failed_list{fi});
            end
        end
        fprintf('\nPer-experiment outputs in: <exp>/analysis/optomotor/\n');
        fprintf('Genotype summaries in:    %s\n', summary_dir);
        fprintf('Done: %s\n\n', datestr(now));
    end

    fprintf('========================================\n');
    fprintf('ALL PROTOCOLS COMPLETE\n');
    fprintf('========================================\n');
end


%% ======== PLOTTING HELPERS ========

function plot_traces(result, out_dir, exp_name, mode, show)
% PLOT_TRACES  2-panel OM1/OM2 angular velocity traces (raw or smooth)
    fig = figure('Position', [50 50 1600 800], 'Visible', 'off');

    is_smooth = strcmp(mode, 'smooth');
    if is_smooth
        mode_label = sprintf('Smoothed (%.1f s)', result.smooth_win_sec);
    else
        mode_label = 'Raw';
    end

    for pi = 1:2
        ax = subplot(1, 2, pi, 'Parent', fig);
        hold(ax, 'on');

        ph = result.phases(pi);

        if is_smooth
            angvel = ph.angvel_smooth;
            m = ph.mean_angvel_smooth;
            s = ph.sem_angvel_smooth;
        else
            angvel = ph.angvel_raw;
            m = ph.mean_angvel_raw;
            s = ph.sem_angvel_raw;
        end

        % Grey individual traces
        for fi = 1:ph.n_alive
            plot(ax, ph.t_axis, angvel(fi, :), ...
                'Color', [0.75 0.75 0.75 0.4], 'LineWidth', 0.5);
        end

        % SEM ribbon
        valid = ~isnan(m) & ~isnan(s);
        t_v = ph.t_axis(valid);
        if ~isempty(t_v)
            fill(ax, [t_v, fliplr(t_v)], ...
                [m(valid)+s(valid), fliplr(m(valid)-s(valid))], ...
                [0.2 0.4 0.8], 'FaceAlpha', 0.3, 'EdgeColor', 'none');
        end

        % Mean line
        plot(ax, ph.t_axis, m, 'Color', [0.1 0.2 0.7], 'LineWidth', 1);

        % Zero line
        yline(ax, 0, 'k-', 'LineWidth', 0.5, 'HandleVisibility', 'off');

        % Markers
        xline(ax, 0, 'r-', 'LED on', 'LineWidth', 1.5, ...
            'FontSize', 18, 'LabelOrientation', 'horizontal', 'HandleVisibility', 'off');
        xline(ax, ph.t_cw_end, 'Color', [0.8 0.0 0.8], ...
            'Label', 'CW end', 'LineWidth', 1.2, 'FontSize', 18, ...
            'LabelVerticalAlignment', 'bottom', 'LabelHorizontalAlignment', 'left', ...
            'HandleVisibility', 'off');
        xline(ax, ph.t_ccw_start, 'Color', [0.0 0.4 0.0], ...
            'Label', 'CCW start', 'LineWidth', 1.2, 'FontSize', 18, ...
            'LabelVerticalAlignment', 'top', 'LabelHorizontalAlignment', 'right', ...
            'HandleVisibility', 'off');
        xline(ax, ph.t_led_off, 'r-', 'LED off', 'LineWidth', 1.5, ...
            'FontSize', 18, 'LabelOrientation', 'horizontal', 'HandleVisibility', 'off');

        xlim(ax, [ph.t_axis(1)-2, ph.t_axis(end)+2]);
        set(ax, 'FontSize', 22);
        xlabel(ax, 'Time relative to LED onset (s)', 'FontSize', 22);
        ylabel(ax, 'Angular velocity (deg/s)', 'FontSize', 22);
        title(ax, sprintf('%s  (CW=%.1f, CCW=%.1f deg/s, n=%d)', ...
            ph.name, ph.cw_grand_mean, ph.ccw_grand_mean, ph.n_alive), 'FontSize', 22);
        box(ax, 'off');
        hold(ax, 'off');
    end

    sgtitle(fig, sprintf('%s — Optomotor angular velocity [%s]', ...
        strrep(exp_name, '_', '\_'), mode_label), 'FontSize', 22, 'FontWeight', 'bold');

    out_base = fullfile(out_dir, sprintf('optomotor_%s_traces_%s', exp_name, mode));
    exportgraphics(fig, [out_base '.png'], 'Resolution', 150);
    saveas(fig, [out_base '.svg']);
    savefig(fig, [out_base '.fig']);
    if show, set(fig, 'Visible', 'on'); else, close(fig); end
end


function plot_summary_bar(result, out_dir, exp_name, show)
% PLOT_SUMMARY_BAR  CW / gap / CCW bar chart per OM phase
    fig = figure('Position', [100 100 800 800], 'Visible', 'off');
    ax = axes(fig);
    hold(ax, 'on');

    bar_vals = [result.phases(1).cw_grand_mean, result.phases(1).gap_grand_mean, result.phases(1).ccw_grand_mean, ...
                result.phases(2).cw_grand_mean, result.phases(2).gap_grand_mean, result.phases(2).ccw_grand_mean];
    bar_errs = [result.phases(1).cw_grand_sem, result.phases(1).gap_grand_sem, result.phases(1).ccw_grand_sem, ...
                result.phases(2).cw_grand_sem, result.phases(2).gap_grand_sem, result.phases(2).ccw_grand_sem];
    bar_colors = [0.3 0.6 0.9; 0.6 0.6 0.6; 0.9 0.4 0.3; ...
                  0.3 0.6 0.9; 0.6 0.6 0.6; 0.9 0.4 0.3];

    b = bar(ax, 1:6, bar_vals, 0.6, 'FaceColor', 'flat');
    b.CData = bar_colors;
    errorbar(ax, 1:6, bar_vals, bar_errs, 'k.', 'LineWidth', 1.5, 'CapSize', 8);

    % Individual fly scatter
    fly_data = {result.phases(1).cw_mean_per_fly, result.phases(1).gap_mean_per_fly, ...
                result.phases(1).ccw_mean_per_fly, result.phases(2).cw_mean_per_fly, ...
                result.phases(2).gap_mean_per_fly, result.phases(2).ccw_mean_per_fly};
    for bi = 1:6
        vals = fly_data{bi};
        jitter = (rand(length(vals), 1) - 0.5) * 0.3;
        scatter(ax, bi + jitter, vals, 20, [0.4 0.4 0.4], ...
            'filled', 'MarkerFaceAlpha', 0.4);
    end

    yline(ax, 0, 'k-', 'LineWidth', 0.5, 'HandleVisibility', 'off');
    set(ax, 'XTick', 1:6, 'XTickLabel', ...
        {'OM1-CW', 'OM1-gap', 'OM1-CCW', 'OM2-CW', 'OM2-gap', 'OM2-CCW'});
    set(ax, 'FontSize', 22);
    ylabel(ax, 'Mean angular velocity (deg/s)', 'FontSize', 22);
    title(ax, sprintf('%s — Optomotor summary (n=%d flies)', ...
        strrep(exp_name, '_', '\_'), result.num_flies), 'FontSize', 22, 'FontWeight', 'bold');
    grid(ax, 'on'); box(ax, 'on');
    hold(ax, 'off');

    out_base = fullfile(out_dir, sprintf('optomotor_%s_summary', exp_name));
    exportgraphics(fig, [out_base '.png'], 'Resolution', 150);
    saveas(fig, [out_base '.svg']);
    savefig(fig, [out_base '.fig']);
    if show, set(fig, 'Visible', 'on'); else, close(fig); end
end


function plot_genotype_bar(geno, geno_disp, protocol, prot_disp, ...
    exp_means, geno_mean, geno_sem, nExp, summary_dir, show)
% PLOT_GENOTYPE_BAR  Genotype-level summary bar chart
    fig = figure('Position', [100 100 800 800], 'Visible', 'off');
    ax = axes(fig);
    hold(ax, 'on');

    bar_colors = [0.3 0.6 0.9; 0.6 0.6 0.6; 0.9 0.4 0.3; ...
                  0.3 0.6 0.9; 0.6 0.6 0.6; 0.9 0.4 0.3];
    b = bar(ax, 1:6, geno_mean, 0.6, 'FaceColor', 'flat');
    b.CData = bar_colors;
    errorbar(ax, 1:6, geno_mean, geno_sem, 'k.', 'LineWidth', 1.5, 'CapSize', 8);

    for bi = 1:6
        jitter = (rand(nExp, 1) - 0.5) * 0.3;
        scatter(ax, bi + jitter, exp_means(:, bi), 40, [0.3 0.3 0.3], ...
            'filled', 'MarkerFaceAlpha', 0.5);
    end

    yline(ax, 0, 'k-', 'LineWidth', 0.5, 'HandleVisibility', 'off');
    set(ax, 'XTick', 1:6, 'XTickLabel', ...
        {'OM1-CW', 'OM1-gap', 'OM1-CCW', 'OM2-CW', 'OM2-gap', 'OM2-CCW'});
    set(ax, 'FontSize', 22);
    ylabel(ax, 'Mean angular velocity (deg/s)', 'FontSize', 22);
    title(ax, sprintf('%s %s (%s) — Optomotor response (n=%d experiments)', ...
        prot_disp, geno_disp, protocol, nExp), 'FontSize', 22, 'FontWeight', 'bold');
    grid(ax, 'on'); box(ax, 'on');
    hold(ax, 'off');

    out_base = fullfile(summary_dir, sprintf('summary_optomotor_%s', geno));
    exportgraphics(fig, [out_base '.png'], 'Resolution', 150);
    saveas(fig, [out_base '.svg']);
    savefig(fig, [out_base '.fig']);
    if show, set(fig, 'Visible', 'on'); else, close(fig); end
end


function plot_om_comparison(t, om1_traces, om2_traces, nExp, ...
    t_cw_ends, t_ccw_starts, t_led_offs, ...
    geno, geno_disp, protocol, prot_disp, mode_tag, summary_dir, show)
% PLOT_OM_COMPARISON  OM1 vs OM2 overlay (raw or smoothed)

    n_t = length(t);
    if size(om1_traces, 2) < n_t
        om1_traces(:, end+1:n_t) = NaN;
    end
    if size(om2_traces, 2) < n_t
        om2_traces(:, end+1:n_t) = NaN;
    end
    om1_traces = om1_traces(:, 1:n_t);
    om2_traces = om2_traces(:, 1:n_t);

    fig = figure('Position', [50 50 900 900], 'Visible', 'off');
    ax = axes(fig);
    hold(ax, 'on');

    % OM1: blue
    m1 = mean(om1_traces, 1, 'omitnan');
    s1 = std(om1_traces, 0, 1, 'omitnan') / sqrt(max(nExp, 1));
    valid1 = ~isnan(m1) & ~isnan(s1);
    t_v1 = t(valid1);
    if ~isempty(t_v1)
        fill(ax, [t_v1, fliplr(t_v1)], ...
            [m1(valid1)+s1(valid1), fliplr(m1(valid1)-s1(valid1))], ...
            [0.2 0.4 0.8], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    end
    h1 = plot(ax, t(valid1), m1(valid1), 'Color', [0.1 0.2 0.7], 'LineWidth', 1);

    % OM2: red
    m2 = mean(om2_traces, 1, 'omitnan');
    s2 = std(om2_traces, 0, 1, 'omitnan') / sqrt(max(nExp, 1));
    valid2 = ~isnan(m2) & ~isnan(s2);
    t_v2 = t(valid2);
    if ~isempty(t_v2)
        fill(ax, [t_v2, fliplr(t_v2)], ...
            [m2(valid2)+s2(valid2), fliplr(m2(valid2)-s2(valid2))], ...
            [0.8 0.3 0.2], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    end
    h2 = plot(ax, t(valid2), m2(valid2), 'Color', [0.7 0.15 0.1], 'LineWidth', 1);

    yline(ax, 0, 'k-', 'LineWidth', 0.5, 'HandleVisibility', 'off');

    % Transition markers
    xline(ax, 0, 'r-', 'LED on', 'LineWidth', 1.5, ...
        'FontSize', 18, 'LabelOrientation', 'horizontal', 'HandleVisibility', 'off');
    xline(ax, mean(t_cw_ends(:, 1), 'omitnan'), 'Color', [0.8 0.0 0.8], ...
        'Label', 'CW end', 'LineWidth', 1, 'FontSize', 18, ...
        'LabelVerticalAlignment', 'bottom', 'LabelHorizontalAlignment', 'left', ...
        'HandleVisibility', 'off');
    xline(ax, mean(t_ccw_starts(:, 1), 'omitnan'), 'Color', [0.0 0.4 0.0], ...
        'Label', 'CCW start', 'LineWidth', 1, 'FontSize', 18, ...
        'LabelVerticalAlignment', 'top', 'LabelHorizontalAlignment', 'right', ...
        'HandleVisibility', 'off');
    xline(ax, mean(t_led_offs(:, 1), 'omitnan'), 'r-', 'LED off', 'LineWidth', 1.5, ...
        'FontSize', 18, 'LabelOrientation', 'horizontal', 'HandleVisibility', 'off');

    xlim(ax, [t(1)-2, t(end)+2]);

    set(ax, 'FontSize', 22);
    legend(ax, [h1, h2], {'OM1 (pre-learning)', 'OM2 (post-learning)'}, ...
        'Location', 'NorthEastOutside', 'FontSize', 22);

    xlabel(ax, 'Time relative to LED onset (s)', 'FontSize', 22);
    ylabel(ax, 'Angular velocity (deg/s)', 'FontSize', 22);
    title(ax, sprintf('%s %s (%s) — OM1 vs OM2 [%s] (n=%d experiments)', ...
        prot_disp, geno_disp, protocol, strrep(mode_tag, '_', ' '), nExp), ...
        'FontSize', 22, 'FontWeight', 'bold');
    box(ax, 'off');
    hold(ax, 'off');

    out_base = fullfile(summary_dir, sprintf('summary_optomotor_comparison_%s_%s', geno, mode_tag));
    exportgraphics(fig, [out_base '.png'], 'Resolution', 150);
    saveas(fig, [out_base '.svg']);
    savefig(fig, [out_base '.fig']);
    if show, set(fig, 'Visible', 'on'); else, close(fig); end
end


%% ======== DATA HELPERS ========

function [p1_cw_end, p1_ccw_start, p2_cw_end, p2_ccw_start] = parse_om_metadata(meta_file)
% PARSE_OM_METADATA  Extract CW/CCW transition frame numbers from metadata log
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
% PARSE_QPI_LOG_OM  Extract per-fly alive status from QPI log
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


