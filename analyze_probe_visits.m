%% analyze_probe_visits.m
% Count per-fly visits to correct quadrants (Q2, Q4) during probe trials.
% Works for all place-learning protocols: P003, P005, P006, P007, P008, P009, P010, P011, P014, P015, P016.
%
% A "visit" = a continuous run of frames where the fly is in Q2 or Q4,
% preceded by at least one frame in Q1 or Q3 (or start of probe).
% The first time the fly is found in Q2/Q4 at probe onset also counts as
% a visit (even if the fly was already there).
%
% Uses arena calibration masks for quadrant lookup (same as latency pipeline).
%
% Output per genotype per protocol:
%   - Bar chart: mean visits to correct quads per probe (PP, B1.P–B4.P)
%   - Per-fly scatter overlay
%   - .mat with all data
%
% Output saved to <PROTOCOL>/summary/probe_visits/

clearvars -except TARGET_PROTOCOLS; clc;


ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';
PROTOCOLS    = {'P014', 'P015', 'P016'};

if ~exist('TARGET_PROTOCOLS', 'var'), TARGET_PROTOCOLS = {}; end
if ~isempty(TARGET_PROTOCOLS)
    PROTOCOLS = PROTOCOLS(ismember(PROTOCOLS, TARGET_PROTOCOLS));
end
FPS          = 30.1;
CORRECT_QUADS = [2, 4];   % trained safe quadrants

% Probe labels are the same for all protocols
probe_labels = {'PP', 'B1.P', 'B2.P', 'B3.P', 'B4.P'};

%% ========================================================================
%  Loop over all protocols
%  ========================================================================

for prot_i = 1:length(PROTOCOLS)
    PROTOCOL = PROTOCOLS{prot_i};
    prot_path = fullfile(ANALYSIS_DIR, PROTOCOL);

    % Skip protocols that don't exist
    if ~exist(prot_path, 'dir')
        fprintf('Protocol %s directory not found; skipping.\n', PROTOCOL);
        continue;
    end

    summary_dir = fullfile(prot_path, 'summary', 'probe_visits');
    if ~exist(summary_dir, 'dir'), mkdir(summary_dir); end

    % (skip check removed — always recompute)

    %% Build full cycle label list for this protocol
    all_labels = build_protocol_labels(PROTOCOL);

    % Map probe labels to cycle indices
    probe_cycle_idx = [];
    for pi = 1:length(probe_labels)
        idx = find(strcmp(all_labels, probe_labels{pi}));
        if ~isempty(idx)
            probe_cycle_idx(end+1) = idx; %#ok<SAGROW>
        end
    end
    fprintf('Protocol %s — Probe cycle indices: %s\n', PROTOCOL, mat2str(probe_cycle_idx));

    %% Find all experiments (exclude known summary/analysis directories)
    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));

    % SAFEGUARD: Only process directories containing '_Rig' (experiment folders).
    % This prevents accidental processing of summary/output directories.
    % Keep only directories whose names start with a letter AND contain '_Rig'
    exp_dirs_filt = [];
    for d = 1:length(exp_dirs)
        name = exp_dirs(d).name;
        if ischar(name) && ~isempty(name) && isletter(name(1)) && contains(name, '_Rig')
            exp_dirs_filt = [exp_dirs_filt, d]; %#ok<AGROW>
        end
    end
    exp_dirs = exp_dirs(exp_dirs_filt);

    fprintf('\n=== Probe Visit Analysis: %s (%d experiments) ===\n\n', ...
        PROTOCOL, length(exp_dirs));

    all_results = {};

    for e = 1:length(exp_dirs)
        exp_name = exp_dirs(e).name;
        exp_path = fullfile(prot_path, exp_name);
        analysis_dir = fullfile(exp_path, 'analysis');

        fprintf('[%d/%d] %s ... ', e, length(exp_dirs), exp_name);

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
            nframes = length(trx(1).x);

            %% Load arena calibration
            arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
            arena_data  = load(fullfile(analysis_dir, arena_files(end).name));
            all_masks   = arena_data.arena_calib.all_masks;

            %% Map flies to quadrants per frame
            fly_quad = compute_fly_quad(trx, all_masks);

            %% Load LED detector
            led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
            led_data  = load(fullfile(analysis_dir, led_files(end).name));
            LED = led_data.LED_detector;
            on_times  = LED.on_times;
            off_times = LED.off_times;

            %% Load dead fly info
            fly_alive = true(num_flies, length(on_times));
            log_file = fullfile(analysis_dir, sprintf('QPI_log_%s.txt', exp_name));
            if exist(log_file, 'file')
                fly_alive = parse_qpi_log(log_file, num_flies, length(on_times), good);
            end

            %% Extract genotype
            tokens = strsplit(exp_name, '_');
            genotype = tokens{1};

            %% Count visits to correct (Q2/Q4) and incorrect (Q1/Q3) quadrants during probes
            INCORRECT_QUADS = [1, 3];
            n_probes = length(probe_cycle_idx);
            visits_per_fly      = NaN(num_flies, n_probes);  % visits to Q2/Q4
            time_in_correct     = NaN(num_flies, n_probes);  % fraction in Q2/Q4
            visits_incorrect_per_fly = NaN(num_flies, n_probes);  % visits to Q1/Q3
            time_in_incorrect   = NaN(num_flies, n_probes);  % fraction in Q1/Q3

            for pi = 1:n_probes
                ci = probe_cycle_idx(pi);
                if ci > length(on_times), continue; end

                fr_on  = on_times(ci);
                fr_off = off_times(ci);
                probe_frames = fr_on:fr_off;

                for f = 1:num_flies
                    if ~fly_alive(f, ci), continue; end

                    quad_seq = fly_quad(f, probe_frames);

                    % Correct quadrants (Q2/Q4)
                    in_correct = ismember(quad_seq, CORRECT_QUADS);
                    entries_correct = diff([0, in_correct]) == 1;
                    visits_per_fly(f, pi) = sum(entries_correct);
                    time_in_correct(f, pi) = mean(in_correct);

                    % Incorrect quadrants (Q1/Q3)
                    in_incorrect = ismember(quad_seq, INCORRECT_QUADS);
                    entries_incorrect = diff([0, in_incorrect]) == 1;
                    visits_incorrect_per_fly(f, pi) = sum(entries_incorrect);
                    time_in_incorrect(f, pi) = mean(in_incorrect);
                end
            end

            rec = struct();
            rec.experiment      = exp_name;
            rec.genotype        = genotype;
            rec.num_flies       = num_flies;
            rec.fly_ids         = good;
            rec.probe_labels    = {probe_labels};
            rec.visits_per_fly  = visits_per_fly;
            rec.time_in_correct = time_in_correct;
            rec.visits_incorrect_per_fly = visits_incorrect_per_fly;
            rec.time_in_incorrect = time_in_incorrect;
            rec.fly_alive       = fly_alive;

            % Per-probe means (across alive flies)
            rec.mean_visits = NaN(1, n_probes);
            rec.sem_visits  = NaN(1, n_probes);
            rec.mean_time_correct = NaN(1, n_probes);
            rec.sem_time_correct  = NaN(1, n_probes);
            rec.mean_visits_incorrect = NaN(1, n_probes);
            rec.sem_visits_incorrect  = NaN(1, n_probes);
            rec.mean_time_incorrect = NaN(1, n_probes);
            rec.sem_time_incorrect  = NaN(1, n_probes);
            for pi = 1:n_probes
                alive_vals = visits_per_fly(~isnan(visits_per_fly(:, pi)), pi);
                if ~isempty(alive_vals)
                    rec.mean_visits(pi) = mean(alive_vals);
                    rec.sem_visits(pi)  = std(alive_vals) / sqrt(length(alive_vals));
                end
                alive_tc = time_in_correct(~isnan(time_in_correct(:, pi)), pi);
                if ~isempty(alive_tc)
                    rec.mean_time_correct(pi) = mean(alive_tc);
                    rec.sem_time_correct(pi)  = std(alive_tc) / sqrt(length(alive_tc));
                end
                alive_vi = visits_incorrect_per_fly(~isnan(visits_incorrect_per_fly(:, pi)), pi);
                if ~isempty(alive_vi)
                    rec.mean_visits_incorrect(pi) = mean(alive_vi);
                    rec.sem_visits_incorrect(pi)  = std(alive_vi) / sqrt(length(alive_vi));
                end
                alive_ti = time_in_incorrect(~isnan(time_in_incorrect(:, pi)), pi);
                if ~isempty(alive_ti)
                    rec.mean_time_incorrect(pi) = mean(alive_ti);
                    rec.sem_time_incorrect(pi)  = std(alive_ti) / sqrt(length(alive_ti));
                end
            end

            all_results{end+1} = rec; %#ok<SAGROW>
            fprintf('OK (%d flies, mean visits PP=%.1f, B4.P=%.1f)\n', ...
                num_flies, rec.mean_visits(1), rec.mean_visits(end));

        catch ME
            fprintf('FAILED: %s\n', ME.message);
        end
    end

    %% Group by genotype
    genotypes = {};
    for i = 1:length(all_results)
        genotypes{end+1} = all_results{i}.genotype; %#ok<SAGROW>
    end
    unique_genos = unique(genotypes);

    fprintf('\n=== Per-genotype probe visit summary ===\n');

    % Colors for probes: grey (PP), light→dark blue (B1.P–B4.P)
    probe_colors = [
        0.60 0.60 0.60;   % PP — grey
        0.65 0.81 0.94;   % B1.P — light blue
        0.39 0.58 0.93;   % B2.P
        0.20 0.40 0.80;   % B3.P
        0.10 0.20 0.60;   % B4.P — dark blue
    ];

    for gi = 1:length(unique_genos)
        geno = unique_genos{gi};
        geno_idx = find(strcmp(genotypes, geno));
        nExp = length(geno_idx);

        fprintf('  %s (%d experiments)\n', geno, nExp);

        n_probes = length(probe_labels);

        % Collect experiment-level means for genotype averaging
        exp_mean_visits = NaN(nExp, n_probes);
        exp_mean_time   = NaN(nExp, n_probes);
        exp_mean_visits_inc = NaN(nExp, n_probes);
        exp_mean_time_inc   = NaN(nExp, n_probes);

        for ei = 1:nExp
            rec = all_results{geno_idx(ei)};
            exp_mean_visits(ei, :)     = rec.mean_visits;
            exp_mean_time(ei, :)       = rec.mean_time_correct;
            exp_mean_visits_inc(ei, :) = rec.mean_visits_incorrect;
            exp_mean_time_inc(ei, :)   = rec.mean_time_incorrect;
        end

        % Genotype mean ± SEM (experiment = unit of replication)
        geno_mean_visits     = mean(exp_mean_visits, 1, 'omitnan');
        geno_sem_visits      = std(exp_mean_visits, 0, 1, 'omitnan') / sqrt(max(nExp, 1));
        geno_mean_time       = mean(exp_mean_time, 1, 'omitnan');
        geno_sem_time        = std(exp_mean_time, 0, 1, 'omitnan') / sqrt(max(nExp, 1));
        geno_mean_visits_inc = mean(exp_mean_visits_inc, 1, 'omitnan');
        geno_sem_visits_inc  = std(exp_mean_visits_inc, 0, 1, 'omitnan') / sqrt(max(nExp, 1));
        geno_mean_time_inc   = mean(exp_mean_time_inc, 1, 'omitnan');
        geno_sem_time_inc    = std(exp_mean_time_inc, 0, 1, 'omitnan') / sqrt(max(nExp, 1));

        x_pos = 1:n_probes;
        bar_w = 0.35;  % half-width for grouped bars

        %% Figure 1: Visits — Q2/Q4 vs Q1/Q3 side by side
        fig1 = figure('Position', [50 50 1000 500], 'Visible', 'off');
        ax1 = axes(fig1);
        hold(ax1, 'on');

        for pi = 1:n_probes
            % Q2/Q4 bar (left)
            bar(ax1, x_pos(pi) - bar_w/2, geno_mean_visits(pi), bar_w, ...
                'FaceColor', [0.2 0.5 0.8], 'EdgeColor', 'k', ...
                'HandleVisibility', 'off');
            % Q1/Q3 bar (right)
            bar(ax1, x_pos(pi) + bar_w/2, geno_mean_visits_inc(pi), bar_w, ...
                'FaceColor', [0.85 0.33 0.10], 'EdgeColor', 'k', ...
                'HandleVisibility', 'off');
        end
        errorbar(ax1, x_pos - bar_w/2, geno_mean_visits, geno_sem_visits, 'k.', ...
            'LineWidth', 1.5, 'MarkerSize', 1, 'HandleVisibility', 'off');
        errorbar(ax1, x_pos + bar_w/2, geno_mean_visits_inc, geno_sem_visits_inc, 'k.', ...
            'LineWidth', 1.5, 'MarkerSize', 1, 'HandleVisibility', 'off');

        % Scatter experiment means
        for ei = 1:nExp
            jit = (ei - (nExp+1)/2) * 0.04;
            scatter(ax1, x_pos - bar_w/2 + jit, exp_mean_visits(ei, :), 25, 'k', 'filled', ...
                'MarkerFaceAlpha', 0.5, 'HandleVisibility', 'off');
            scatter(ax1, x_pos + bar_w/2 + jit, exp_mean_visits_inc(ei, :), 25, 'k', 'filled', ...
                'MarkerFaceAlpha', 0.5, 'HandleVisibility', 'off');
        end

        % Legend dummies
        bar(ax1, NaN, NaN, 'FaceColor', [0.2 0.5 0.8], 'EdgeColor', 'k', ...
            'DisplayName', 'Q2+Q4 (correct)');
        bar(ax1, NaN, NaN, 'FaceColor', [0.85 0.33 0.10], 'EdgeColor', 'k', ...
            'DisplayName', 'Q1+Q3 (incorrect)');
        legend(ax1, 'Location', 'NorthEastOutside', 'FontSize', 10);

        set(ax1, 'XTick', x_pos, 'XTickLabel', probe_labels);
        xlabel(ax1, 'Probe trial');
        ylabel(ax1, 'Number of visits');
        title(ax1, sprintf('%s — Quadrant visits during probes (n=%d exp)', geno, nExp), ...
            'FontSize', 12);
        grid(ax1, 'on'); box(ax1, 'on');
        hold(ax1, 'off');

        out_png1 = fullfile(summary_dir, sprintf('probe_visits_%s_%s.png', PROTOCOL, geno));
        out_fig1 = fullfile(summary_dir, sprintf('probe_visits_%s_%s.fig', PROTOCOL, geno));
        exportgraphics(fig1, out_png1, 'Resolution', 150);
        savefig(fig1, out_fig1);
        close(fig1);

        %% Figure 2: Time fraction — Q2/Q4 vs Q1/Q3 side by side
        fig2 = figure('Position', [50 50 1000 500], 'Visible', 'off');
        ax2 = axes(fig2);
        hold(ax2, 'on');

        for pi = 1:n_probes
            bar(ax2, x_pos(pi) - bar_w/2, geno_mean_time(pi), bar_w, ...
                'FaceColor', [0.2 0.5 0.8], 'EdgeColor', 'k', ...
                'HandleVisibility', 'off');
            bar(ax2, x_pos(pi) + bar_w/2, geno_mean_time_inc(pi), bar_w, ...
                'FaceColor', [0.85 0.33 0.10], 'EdgeColor', 'k', ...
                'HandleVisibility', 'off');
        end
        errorbar(ax2, x_pos - bar_w/2, geno_mean_time, geno_sem_time, 'k.', ...
            'LineWidth', 1.5, 'MarkerSize', 1, 'HandleVisibility', 'off');
        errorbar(ax2, x_pos + bar_w/2, geno_mean_time_inc, geno_sem_time_inc, 'k.', ...
            'LineWidth', 1.5, 'MarkerSize', 1, 'HandleVisibility', 'off');

        for ei = 1:nExp
            jit = (ei - (nExp+1)/2) * 0.04;
            scatter(ax2, x_pos - bar_w/2 + jit, exp_mean_time(ei, :), 25, 'k', 'filled', ...
                'MarkerFaceAlpha', 0.5, 'HandleVisibility', 'off');
            scatter(ax2, x_pos + bar_w/2 + jit, exp_mean_time_inc(ei, :), 25, 'k', 'filled', ...
                'MarkerFaceAlpha', 0.5, 'HandleVisibility', 'off');
        end

        yline(ax2, 0.5, 'k--', 'LineWidth', 1, 'HandleVisibility', 'off');  % chance

        bar(ax2, NaN, NaN, 'FaceColor', [0.2 0.5 0.8], 'EdgeColor', 'k', ...
            'DisplayName', 'Q2+Q4 (correct)');
        bar(ax2, NaN, NaN, 'FaceColor', [0.85 0.33 0.10], 'EdgeColor', 'k', ...
            'DisplayName', 'Q1+Q3 (incorrect)');
        legend(ax2, 'Location', 'NorthEastOutside', 'FontSize', 10);

        set(ax2, 'XTick', x_pos, 'XTickLabel', probe_labels);
        xlabel(ax2, 'Probe trial');
        ylabel(ax2, 'Fraction of time');
        title(ax2, sprintf('%s — Time in quadrants during probes (n=%d exp)', geno, nExp), ...
            'FontSize', 12);
        ylim(ax2, [0 1]);
        grid(ax2, 'on'); box(ax2, 'on');
        hold(ax2, 'off');

        out_png2 = fullfile(summary_dir, sprintf('probe_time_%s_%s.png', PROTOCOL, geno));
        out_fig2 = fullfile(summary_dir, sprintf('probe_time_%s_%s.fig', PROTOCOL, geno));
        exportgraphics(fig2, out_png2, 'Resolution', 150);
        savefig(fig2, out_fig2);
        close(fig2);

        %% Save genotype .mat
        geno_data = struct();
        geno_data.genotype              = geno;
        geno_data.probe_labels          = probe_labels;
        geno_data.n_experiments         = nExp;
        geno_data.exp_mean_visits       = exp_mean_visits;
        geno_data.exp_mean_time         = exp_mean_time;
        geno_data.exp_mean_visits_inc   = exp_mean_visits_inc;
        geno_data.exp_mean_time_inc     = exp_mean_time_inc;
        geno_data.geno_mean_visits      = geno_mean_visits;
        geno_data.geno_sem_visits       = geno_sem_visits;
        geno_data.geno_mean_time        = geno_mean_time;
        geno_data.geno_sem_time         = geno_sem_time;
        geno_data.geno_mean_visits_inc  = geno_mean_visits_inc;
        geno_data.geno_sem_visits_inc   = geno_sem_visits_inc;
        geno_data.geno_mean_time_inc    = geno_mean_time_inc;
        geno_data.geno_sem_time_inc     = geno_sem_time_inc;
        geno_data.all_results           = {all_results{geno_idx}}; %#ok<CCAT1>

        mat_file = fullfile(summary_dir, sprintf('probe_visits_%s_%s.mat', PROTOCOL, geno));
        save(mat_file, '-struct', 'geno_data');

        fprintf('    mean visits: PP=%.1f, B1.P=%.1f, B2.P=%.1f, B3.P=%.1f, B4.P=%.1f\n', ...
            geno_mean_visits);
    end

    fprintf('\nDone with %s. Saved to:\n  %s\n\n', PROTOCOL, summary_dir);

end  % end protocol loop

fprintf('=== All protocols complete. ===\n');


%% ========================================================================
%  Helper functions
%  ========================================================================

function labels = build_protocol_labels(protocol)
% Build full cycle label list for a given place-learning protocol.
%
% P003, P005: 46 cycles (no optomotor)
%   {PP, Ag, B1.1..B1.10, B1.P, B2.1..B2.10, B2.P, B3.1..B3.10, B3.P, B4.1..B4.10, B4.P}
%
% P006, P007, P008, P009, P010, P011, P014, P015, P016: 48 cycles (with optomotor)
%   {OM1, PP, Ag, B1.1..B1.10, B1.P, ..., B4.P, OM2}

    if ismember(protocol, {'P003', 'P005'})
        % 46 cycles: no optomotor
        labels = {'PP', 'Ag'};
        for blk = 1:4
            for idx = 1:10
                labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
            end
            labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
        end
    elseif ismember(protocol, {'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P014', 'P015', 'P016'})
        % 48 cycles: with optomotor (OM1 and OM2)
        labels = {'OM1', 'PP', 'Ag'};
        for blk = 1:4
            for idx = 1:10
                labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
            end
            labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
        end
        labels{end+1} = 'OM2';
    else
        error('build_protocol_labels: Unknown protocol %s', protocol);
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
