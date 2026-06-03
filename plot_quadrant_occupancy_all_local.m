%% plot_quadrant_occupancy_all.m
% Plot quadrant occupancy (fraction of time in each quadrant) across all
% experiments that passed QC (have arena_calib + LED_detector files).
%
% Groups by genotype within each protocol.

clear; clc;

%% Configuration
ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';
FPS = 30;
FRAME_TOLERANCE = 30;

%% Find all valid experiments
fprintf('Scanning for valid experiments...\n');

protocols = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocols = protocols([protocols.isdir]);

experiments = struct('path', {}, 'protocol', {}, 'genotype', {}, 'name', {});

for p = 1:length(protocols)
    prot_name = protocols(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);

    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..', 'Summary_Plots'}));

    for e = 1:length(exp_dirs)
        exp_path = fullfile(prot_path, exp_dirs(e).name);
        analysis_dir = fullfile(exp_path, 'analysis');

        % Check for required preprocessing files
        has_arena = ~isempty(dir(fullfile(analysis_dir, 'arena_calib_*.mat')));
        has_led = ~isempty(dir(fullfile(analysis_dir, 'LED_detector_*.mat')));
        has_trx = exist(fullfile(exp_path, 'trx.mat'), 'file');

        if has_arena && has_led && has_trx
            % Extract genotype from folder name (first part before _Rig)
            parts = split(exp_dirs(e).name, '_');
            genotype = parts{1};

            entry.path = exp_path;
            entry.protocol = prot_name;
            entry.genotype = genotype;
            entry.name = exp_dirs(e).name;
            experiments(end+1) = entry;
        end
    end
end

fprintf('Found %d valid experiments\n\n', length(experiments));

if isempty(experiments)
    fprintf('No valid experiments found. Make sure preprocessing has been run.\n');
    return;
end

%% Compute quadrant occupancy for each experiment
% Store per-fly, per-cycle occupancy for each quadrant

all_genotypes = unique({experiments.genotype});
all_protocols = unique({experiments.protocol});

for prot_idx = 1:length(all_protocols)
    protocol = all_protocols{prot_idx};

    for geno_idx = 1:length(all_genotypes)
        genotype = all_genotypes{geno_idx};

        % Filter experiments for this protocol-genotype
        mask = strcmp({experiments.protocol}, protocol) & strcmp({experiments.genotype}, genotype);
        group_exps = experiments(mask);

        if isempty(group_exps)
            continue;
        end

        fprintf('=== %s / %s (%d experiments) ===\n', protocol, genotype, length(group_exps));

        % Collect occupancy across all flies in this group
        all_q1_frac = [];
        all_q2_frac = [];
        all_q3_frac = [];
        all_q4_frac = [];
        num_cycles_found = 0;

        for exp_idx = 1:length(group_exps)
            exp_path = group_exps(exp_idx).path;
            exp_name = group_exps(exp_idx).name;
            analysis_subdir = fullfile(exp_path, 'analysis');

            try
                % Load trx (filtered if available)
                filtered_trx_file = fullfile(analysis_subdir, 'trx_filtered.mat');
                if exist(filtered_trx_file, 'file')
                    load(filtered_trx_file, 'trx');
                else
                    load(fullfile(exp_path, 'trx.mat'), 'trx');

                    % Apply frame tolerance filter
                    max_endframe = max([trx.endframe]);
                    min_acceptable = max_endframe - FRAME_TOLERANCE;
                    good = [];
                    for k = 1:length(trx)
                        if trx(k).firstframe == 1 && trx(k).endframe >= min_acceptable
                            good = [good, k];
                        end
                    end
                    trx = trx(good);
                end

                num_flies = length(trx);
                if num_flies == 0
                    fprintf('  [%d] %s - No valid flies, skipping\n', exp_idx, exp_name);
                    continue;
                end

                % Load arena calibration
                arena_files = dir(fullfile(analysis_subdir, 'arena_calib_*.mat'));
                arena_data = load(fullfile(analysis_subdir, arena_files(1).name));
                if isfield(arena_data, 'arena_calib')
                    all_masks = arena_data.arena_calib.all_masks;
                elseif isfield(arena_data, 'ac')
                    all_masks = arena_data.ac.all_masks;
                elseif isfield(arena_data, 'saved_calib')
                    all_masks = arena_data.saved_calib.all_masks;
                else
                    fprintf('  [%d] %s - Cannot find arena masks, skipping\n', exp_idx, exp_name);
                    continue;
                end

                % Load LED detector
                led_files = dir(fullfile(analysis_subdir, 'LED_detector_*.mat'));
                led_data = load(fullfile(analysis_subdir, led_files(1).name));
                if isfield(led_data, 'LED_detector')
                    LED = led_data.LED_detector;
                elseif isfield(led_data, 'ld')
                    LED = led_data.ld;
                else
                    LED = led_data;
                end

                on_times = LED.on_times;
                off_times = LED.off_times;
                num_cycles = length(on_times);
                num_cycles_found = max(num_cycles_found, num_cycles);

                % Map each fly to quadrants
                for k = 1:num_flies
                    x_inds = round(trx(k).x);
                    y_inds = round(trx(k).y);
                    quad = nan(length(x_inds), 1);

                    for fr = 1:length(x_inds)
                        if ~isnan(x_inds(fr)) && ~isnan(y_inds(fr)) && ...
                           x_inds(fr) >= 1 && x_inds(fr) <= size(all_masks, 2) && ...
                           y_inds(fr) >= 1 && y_inds(fr) <= size(all_masks, 1)
                            quad(fr) = all_masks(y_inds(fr), x_inds(fr));
                        end
                    end

                    trx(k).quad = quad;
                end

                % Compute per-fly, per-cycle quadrant occupancy
                q1_frac = nan(num_flies, num_cycles);
                q2_frac = nan(num_flies, num_cycles);
                q3_frac = nan(num_flies, num_cycles);
                q4_frac = nan(num_flies, num_cycles);

                for k = 1:num_flies
                    for c = 1:num_cycles
                        start_f = on_times(c);
                        end_f = off_times(c);

                        if start_f > length(trx(k).quad) || end_f > length(trx(k).quad)
                            continue;
                        end

                        q_slice = trx(k).quad(start_f:end_f);
                        q_slice = q_slice(~isnan(q_slice) & q_slice > 0);
                        total = length(q_slice);

                        if total > 0
                            q1_frac(k, c) = sum(q_slice == 1) / total;
                            q2_frac(k, c) = sum(q_slice == 2) / total;
                            q3_frac(k, c) = sum(q_slice == 3) / total;
                            q4_frac(k, c) = sum(q_slice == 4) / total;
                        end
                    end
                end

                % Append to group data
                all_q1_frac = [all_q1_frac; q1_frac];
                all_q2_frac = [all_q2_frac; q2_frac];
                all_q3_frac = [all_q3_frac; q3_frac];
                all_q4_frac = [all_q4_frac; q4_frac];

                fprintf('  [%d] %s - %d flies, %d cycles\n', exp_idx, exp_name, num_flies, num_cycles);

            catch ME
                fprintf('  [%d] %s - Error: %s\n', exp_idx, exp_name, ME.message);
            end
        end

        if isempty(all_q1_frac)
            fprintf('  No data collected for %s/%s\n\n', protocol, genotype);
            continue;
        end

        num_total_flies = size(all_q1_frac, 1);
        num_cycles = num_cycles_found;

        fprintf('  Total: %d flies across %d experiments, %d cycles\n\n', ...
            num_total_flies, length(group_exps), num_cycles);

        %% Plot 1: Mean quadrant occupancy across cycles (line plot)

        mean_q1 = nanmean(all_q1_frac, 1);
        mean_q2 = nanmean(all_q2_frac, 1);
        mean_q3 = nanmean(all_q3_frac, 1);
        mean_q4 = nanmean(all_q4_frac, 1);

        se_q1 = nanstd(all_q1_frac, 0, 1) ./ sqrt(sum(~isnan(all_q1_frac), 1));
        se_q2 = nanstd(all_q2_frac, 0, 1) ./ sqrt(sum(~isnan(all_q2_frac), 1));
        se_q3 = nanstd(all_q3_frac, 0, 1) ./ sqrt(sum(~isnan(all_q3_frac), 1));
        se_q4 = nanstd(all_q4_frac, 0, 1) ./ sqrt(sum(~isnan(all_q4_frac), 1));

        % Colorblind-friendly (Wong 2011)
        c1 = [0.00 0.45 0.70];   % blue   - Q1
        c2 = [0.90 0.62 0.00];   % orange - Q2
        c3 = [0.00 0.62 0.45];   % teal   - Q3
        c4 = [0.80 0.47 0.65];   % purple - Q4

        fig1 = figure('Position', [50 50 1600 600], 'Visible', 'off');
        hold on;

        % Chance line
        plot([0.5 num_cycles+0.5], [0.25 0.25], 'k--', 'LineWidth', 1, 'HandleVisibility', 'off');

        % Shaded error bands + lines
        cycles = 1:num_cycles;

        fill_between(cycles, mean_q1, se_q1, c1, 0.15);
        fill_between(cycles, mean_q2, se_q2, c2, 0.15);
        fill_between(cycles, mean_q3, se_q3, c3, 0.15);
        fill_between(cycles, mean_q4, se_q4, c4, 0.15);

        h1 = plot(cycles, mean_q1, 'o-', 'Color', c1, 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', c1);
        h2 = plot(cycles, mean_q2, 's-', 'Color', c2, 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', c2);
        h3 = plot(cycles, mean_q3, 'd-', 'Color', c3, 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', c3);
        h4 = plot(cycles, mean_q4, '^-', 'Color', c4, 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', c4);

        xlabel('Stimulus Cycle', 'FontSize', 14);
        ylabel('Fraction of Time', 'FontSize', 14);
        title(sprintf('%s - %s: Quadrant Occupancy (n=%d flies, %d experiments)', ...
            protocol, genotype, num_total_flies, length(group_exps)), ...
            'FontSize', 15, 'Interpreter', 'none');

        legend([h1 h2 h3 h4], cellfun(@(n,l) sprintf('%s (%s)', n, l), {get_quadrant_layout().name}, {get_quadrant_layout().label}, 'UniformOutput', false), ...
            'Location', 'bestoutside', 'FontSize', 11);

        xlim([0.5 num_cycles+0.5]);
        ylim([0 max(0.6, max([mean_q1+se_q1, mean_q2+se_q2, mean_q3+se_q3, mean_q4+se_q4]) * 1.1)]);
        grid on; box on;
        set(gca, 'FontSize', 12);

        % Save
        plots_dir = fullfile(ANALYSIS_DIR, protocol, 'Summary_Plots');
        if ~exist(plots_dir, 'dir'), mkdir(plots_dir); end

        out_file1 = fullfile(plots_dir, sprintf('QuadOccupancy_Lines_%s_%s.png', protocol, genotype));
        saveas(fig1, out_file1);
        close(fig1);
        fprintf('  Saved: %s\n', out_file1);

        %% Plot 2: Stacked bar chart of mean quadrant occupancy

        fig2 = figure('Position', [50 50 1600 600], 'Visible', 'off');

        bar_data = [mean_q1(:), mean_q2(:), mean_q3(:), mean_q4(:)];

        b = bar(cycles, bar_data, 'stacked');
        b(1).FaceColor = c1;
        b(2).FaceColor = c2;
        b(3).FaceColor = c3;
        b(4).FaceColor = c4;

        % Chance line
        hold on;
        plot([0.5 num_cycles+0.5], [0.25 0.25], 'k--', 'LineWidth', 1.5);
        plot([0.5 num_cycles+0.5], [0.50 0.50], 'k:', 'LineWidth', 1);
        plot([0.5 num_cycles+0.5], [0.75 0.75], 'k:', 'LineWidth', 1);

        xlabel('Stimulus Cycle', 'FontSize', 14);
        ylabel('Cumulative Fraction', 'FontSize', 14);
        title(sprintf('%s - %s: Stacked Quadrant Occupancy (n=%d flies)', ...
            protocol, genotype, num_total_flies), ...
            'FontSize', 15, 'Interpreter', 'none');

        legend(cellfun(@(n,l) sprintf('%s (%s)', n, l), {get_quadrant_layout().name}, {get_quadrant_layout().label}, 'UniformOutput', false), ...
            'Location', 'bestoutside', 'FontSize', 11);

        xlim([0.5 num_cycles+0.5]);
        ylim([0 1.05]);
        grid on; box on;
        set(gca, 'FontSize', 12);

        out_file2 = fullfile(plots_dir, sprintf('QuadOccupancy_Stacked_%s_%s.png', protocol, genotype));
        saveas(fig2, out_file2);
        close(fig2);
        fprintf('  Saved: %s\n', out_file2);

        %% Plot 3: Paired quadrant occupancy (Q1+Q3 vs Q2+Q4)

        pair13 = all_q1_frac + all_q3_frac;
        pair24 = all_q2_frac + all_q4_frac;

        mean_p13 = nanmean(pair13, 1);
        mean_p24 = nanmean(pair24, 1);
        se_p13 = nanstd(pair13, 0, 1) ./ sqrt(sum(~isnan(pair13), 1));
        se_p24 = nanstd(pair24, 0, 1) ./ sqrt(sum(~isnan(pair24), 1));

        c_pair13 = [0.34 0.71 0.91];  % sky blue
        c_pair24 = [0.94 0.89 0.26];  % yellow

        fig3 = figure('Position', [50 50 1600 600], 'Visible', 'off');
        hold on;

        % Chance line
        plot([0.5 num_cycles+0.5], [0.5 0.5], 'k--', 'LineWidth', 1);

        fill_between(cycles, mean_p13, se_p13, c_pair13, 0.2);
        fill_between(cycles, mean_p24, se_p24, c_pair24, 0.2);

        h13 = plot(cycles, mean_p13, 'o-', 'Color', c_pair13 * 0.8, 'LineWidth', 2.5, ...
            'MarkerSize', 6, 'MarkerFaceColor', c_pair13);
        h24 = plot(cycles, mean_p24, 's-', 'Color', c_pair24 * 0.8, 'LineWidth', 2.5, ...
            'MarkerSize', 6, 'MarkerFaceColor', c_pair24);

        xlabel('Stimulus Cycle', 'FontSize', 14);
        ylabel('Fraction of Time', 'FontSize', 14);
        title(sprintf('%s - %s: Paired Quadrant Occupancy (n=%d flies)', ...
            protocol, genotype, num_total_flies), ...
            'FontSize', 15, 'Interpreter', 'none');

        legend([h13 h24], {'Q1+Q3 (diagonal pair)', 'Q2+Q4 (diagonal pair)'}, ...
            'Location', 'bestoutside', 'FontSize', 11);

        xlim([0.5 num_cycles+0.5]);
        ylim([0 1]);
        grid on; box on;
        set(gca, 'FontSize', 12);

        out_file3 = fullfile(plots_dir, sprintf('QuadOccupancy_Paired_%s_%s.png', protocol, genotype));
        saveas(fig3, out_file3);
        close(fig3);
        fprintf('  Saved: %s\n\n', out_file3);
    end
end

fprintf('Done!\n');

%% Helper function: shaded error band
function fill_between(x, y_mean, y_se, color, alpha)
    x_fill = [x, fliplr(x)];
    y_fill = [y_mean + y_se, fliplr(y_mean - y_se)];

    % Remove NaN
    valid = ~isnan(y_fill);
    if sum(valid) < 3, return; end

    fill(x_fill, y_fill, color, 'FaceAlpha', alpha, 'EdgeColor', 'none', 'HandleVisibility', 'off');
end
