%% cumulative_occupancy.m
% Cumulative occupancy analysis for all place-learning protocols (P003, P005–P011, P014).
%
% Adapted from CumulativeOccupancy_V3.m / CumulativeOccupancyAll_v4.m.
%
% For each probe trial (PP, B1.P–B4.P), computes the cumulative running
% average of time spent in Q2+Q4 (correct) and Q1+Q3 (incorrect) in
% 2-second bins. Plots per-fly traces + genotype mean ± SEM.
%
% Uses arena calibration masks for quadrant lookup (same as latency pipeline).

clearvars -except TARGET_PROTOCOLS; clc;


ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';
PROTOCOLS    = {'P003', 'P005', 'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P014', 'P015', 'P016'};

if ~exist('TARGET_PROTOCOLS', 'var'), TARGET_PROTOCOLS = {}; end
if ~isempty(TARGET_PROTOCOLS)
    PROTOCOLS = PROTOCOLS(ismember(PROTOCOLS, TARGET_PROTOCOLS));
end
FPS          = 30.1;
BIN_SEC      = 2;           % 2-second bins
BIN_FRAMES   = round(BIN_SEC * FPS);
CORRECT_QUADS   = [2, 4];
INCORRECT_QUADS = [1, 3];

% Probe cycle indices are the same for all protocols
probe_labels = {'PP', 'B1.P', 'B2.P', 'B3.P', 'B4.P'};

%% Loop over all protocols
for prot_i = 1:length(PROTOCOLS)
    PROTOCOL = PROTOCOLS{prot_i};
    prot_path = fullfile(ANALYSIS_DIR, PROTOCOL);

    % Skip if protocol directory doesn't exist
    if ~exist(prot_path, 'dir')
        fprintf('Protocol %s not found, skipping.\n', PROTOCOL);
        continue;
    end

    summary_dir = fullfile(prot_path, 'summary', 'cumulative_occupancy');
    if ~exist(summary_dir, 'dir'), mkdir(summary_dir); end

    %% Build protocol-specific labels
    all_labels = build_protocol_labels(PROTOCOL);

    % Find probe cycle indices in the label list
    probe_cycle_idx = [];
    for pi = 1:length(probe_labels)
        idx = find(strcmp(all_labels, probe_labels{pi}));
        if ~isempty(idx), probe_cycle_idx(end+1) = idx; end %#ok<SAGROW>
    end
    n_probes = length(probe_cycle_idx);

    %% Find experiments
    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));

    % SAFEGUARD: Only process directories containing '_Rig' (experiment folders).
    % This prevents accidental processing of summary/output directories.
    exp_dirs = exp_dirs(~contains({exp_dirs.name}, 'summary') & ...
                         ~contains({exp_dirs.name}, 'distance') & ...
                         ~contains({exp_dirs.name}, 'latency') & ...
                         ~contains({exp_dirs.name}, 'dist_to_safe') & ...
                         ~contains({exp_dirs.name}, 'QPI') & ...
                         ~contains({exp_dirs.name}, 'speed') & ...
                         ~contains({exp_dirs.name}, 'optomotor') & ...
                         contains({exp_dirs.name}, '_Rig'));

    % Skip if summary .mat files already exist for this protocol
    summary_dir_check = fullfile(prot_path, 'summary', 'cumulative_occupancy');
    existing_mats = dir(fullfile(summary_dir_check, '*.mat'));
    if ~isempty(existing_mats)
        fprintf('=== Cumulative Occupancy: %s — summaries exist (%d .mat), skipping ===\n\n', ...
            PROTOCOL, length(existing_mats));
        continue;
    end

    fprintf('=== Cumulative Occupancy: %s (%d experiments) ===\n\n', ...
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

            %% Compute cumulative occupancy per fly per probe
            rec = struct();
            rec.experiment = exp_name;
            rec.genotype   = genotype;
            rec.num_flies  = num_flies;

            for pi = 1:n_probes
                ci = probe_cycle_idx(pi);
                if ci > length(on_times)
                    rec.probes(pi).cum_correct   = {};
                    rec.probes(pi).cum_incorrect = {};
                    rec.probes(pi).t_bins        = [];
                    rec.probes(pi).n_bins        = 0;
                    continue;
                end

                fr_on  = on_times(ci);
                fr_off = off_times(ci);
                probe_frames = fr_on:fr_off;
                n_fr = length(probe_frames);
                n_bins = ceil(n_fr / BIN_FRAMES);

                rec.probes(pi).label = probe_labels{pi};
                rec.probes(pi).n_bins = n_bins;
                rec.probes(pi).t_bins = ((0:n_bins-1) * BIN_FRAMES) / FPS;  % time axis in seconds

                for f = 1:num_flies
                    if ~fly_alive(f, ci)
                        rec.probes(pi).cum_correct{f}   = NaN(1, n_bins);
                        rec.probes(pi).cum_incorrect{f}  = NaN(1, n_bins);
                        continue;
                    end

                    qvec = fly_quad(f, probe_frames);

                    % Per-bin occupancy fraction
                    occ_correct   = zeros(1, n_bins);
                    occ_incorrect = zeros(1, n_bins);

                    for b = 1:n_bins
                        b_start = (b-1)*BIN_FRAMES + 1;
                        b_end   = min(b*BIN_FRAMES, n_fr);
                        bin_q   = qvec(b_start:b_end);

                        occ_correct(b)   = mean(ismember(bin_q, CORRECT_QUADS));
                        occ_incorrect(b) = mean(ismember(bin_q, INCORRECT_QUADS));
                    end

                    % Cumulative running average
                    rec.probes(pi).cum_correct{f}   = cumsum(occ_correct)   ./ (1:n_bins);
                    rec.probes(pi).cum_incorrect{f}  = cumsum(occ_incorrect) ./ (1:n_bins);
                end
            end

            all_results{end+1} = rec; %#ok<SAGROW>
            fprintf('OK\n');

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

    fprintf('\n=== Generating per-genotype cumulative occupancy plots ===\n');

    for gi = 1:length(unique_genos)
        geno = unique_genos{gi};
        geno_idx = find(strcmp(genotypes, geno));
        nExp = length(geno_idx);

        fprintf('  %s (%d experiments) ... ', geno, nExp);

        %% Figure: 5 probes as subplots, Q2+Q4 and Q1+Q3 overlaid
        fig = figure('Position', [50 50 1800 400], 'Visible', 'off');

        for pi = 1:n_probes
            ax = subplot(1, n_probes, pi);
            hold(ax, 'on');

            % Collect all fly curves across experiments for this genotype+probe
            % Find max n_bins across experiments
            max_bins = 0;
            for ei = 1:nExp
                rec = all_results{geno_idx(ei)};
                if rec.probes(pi).n_bins > max_bins
                    max_bins = rec.probes(pi).n_bins;
                end
            end

            if max_bins == 0, continue; end

            all_correct   = [];
            all_incorrect = [];

            for ei = 1:nExp
                rec = all_results{geno_idx(ei)};
                n_flies = rec.num_flies;
                for f = 1:n_flies
                    cc = rec.probes(pi).cum_correct{f};
                    ci_data = rec.probes(pi).cum_incorrect{f};

                    % Pad to max_bins
                    cc_padded = NaN(1, max_bins);
                    ci_padded = NaN(1, max_bins);
                    n = min(length(cc), max_bins);
                    cc_padded(1:n) = cc(1:n);
                    ci_padded(1:n) = ci_data(1:n);

                    all_correct   = [all_correct; cc_padded];   %#ok<AGROW>
                    all_incorrect = [all_incorrect; ci_padded]; %#ok<AGROW>
                end
            end

            % Time axis from first experiment with data
            t_bins = ((0:max_bins-1) * BIN_FRAMES) / FPS;

            % Grey individual fly traces
            for fi = 1:size(all_correct, 1)
                plot(ax, t_bins, all_correct(fi, :), '-', ...
                    'Color', [0.75 0.75 0.75 0.3], 'LineWidth', 0.5, ...
                    'HandleVisibility', 'off');
            end

            % Mean ± SEM for Q2+Q4 (correct) — blue
            m_corr = mean(all_correct, 1, 'omitnan');
            s_corr = std(all_correct, 0, 1, 'omitnan') ./ sqrt(sum(~isnan(all_correct), 1));
            valid = ~isnan(m_corr);
            tv = t_bins(valid);
            fill(ax, [tv, fliplr(tv)], ...
                [m_corr(valid)+s_corr(valid), fliplr(m_corr(valid)-s_corr(valid))], ...
                [0.2 0.5 0.8], 'FaceAlpha', 0.3, 'EdgeColor', 'none', 'HandleVisibility', 'off');
            h1 = plot(ax, tv, m_corr(valid), '-', 'Color', [0.1 0.3 0.7], 'LineWidth', 1.5);

            % Mean ± SEM for Q1+Q3 (incorrect) — red/orange
            m_inc = mean(all_incorrect, 1, 'omitnan');
            s_inc = std(all_incorrect, 0, 1, 'omitnan') ./ sqrt(sum(~isnan(all_incorrect), 1));
            valid2 = ~isnan(m_inc);
            tv2 = t_bins(valid2);
            fill(ax, [tv2, fliplr(tv2)], ...
                [m_inc(valid2)+s_inc(valid2), fliplr(m_inc(valid2)-s_inc(valid2))], ...
                [0.85 0.33 0.10], 'FaceAlpha', 0.3, 'EdgeColor', 'none', 'HandleVisibility', 'off');
            h2 = plot(ax, tv2, m_inc(valid2), '-', 'Color', [0.75 0.2 0.05], 'LineWidth', 1.5);

            % Chance line
            yline(ax, 0.5, 'k--', 'LineWidth', 1, 'HandleVisibility', 'off');

            xlabel(ax, 'Time (s)');
            if pi == 1
                ylabel(ax, 'Cumulative occupancy');
            end
            title(ax, probe_labels{pi}, 'FontSize', 11);
            ylim(ax, [0 1]);
            grid(ax, 'on'); box(ax, 'on');

            if pi == n_probes
                legend(ax, [h1, h2], {'Q2+Q4 (correct)', 'Q1+Q3 (incorrect)'}, ...
                    'Location', 'NorthEastOutside', 'FontSize', 9);
            end
        end

        sgtitle(fig, sprintf('%s — Cumulative occupancy during probes (%ds bins, n=%d exp)', ...
            geno, BIN_SEC, nExp), 'FontSize', 13, 'FontWeight', 'bold');

        out_png = fullfile(summary_dir, sprintf('cumulative_occ_%s_%s.png', PROTOCOL, geno));
        out_fig = fullfile(summary_dir, sprintf('cumulative_occ_%s_%s.fig', PROTOCOL, geno));
        exportgraphics(fig, out_png, 'Resolution', 200);
        savefig(fig, out_fig);
        close(fig);

        %% Save .mat
        geno_data = struct();
        geno_data.genotype     = geno;
        geno_data.probe_labels = probe_labels;
        geno_data.bin_sec      = BIN_SEC;
        geno_data.n_experiments = nExp;
        geno_data.results      = {all_results{geno_idx}}; %#ok<CCAT1>

        mat_file = fullfile(summary_dir, sprintf('cumulative_occ_%s_%s.mat', PROTOCOL, geno));
        save(mat_file, '-struct', 'geno_data');

        fprintf('saved.\n');
    end

    fprintf('\nDone. Saved to:\n  %s\n\n', summary_dir);
end

fprintf('All protocols processed.\n');


%% ========================================================================
%  Helper functions
%  ========================================================================

function labels = build_protocol_labels(protocol)
    % Build full cycle label list for a given protocol.
    % P003, P005: 46 cycles (no optomotor) — PP, Ag, B1.1–B1.10, B1.P, ..., B4.P
    % P006, P007, P008, P009: 48 cycles (with optomotor) — OM1, PP, Ag, B1.1–B1.10, B1.P, ..., B4.P, OM2

    if ismember(protocol, {'P003', 'P005'})
        % No optomotor for P003, P005
        labels = {'PP', 'Ag'};
    else
        % Optomotor for P006, P007, P008, P009
        labels = {'OM1', 'PP', 'Ag'};
    end

    % Add blocks
    for blk = 1:4
        for idx = 1:10
            labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
        end
        labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
    end

    % Add final optomotor for P006, P007, P008, P009, P010, P011, P014
    if ismember(protocol, {'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P014'})
        labels{end+1} = 'OM2';
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
