function plot_distance_intensity_local(distance_summary, protocol, varargin)
% PLOT_DISTANCE_INTENSITY_LOCAL  Distance vs intensity: control (L1) vs test genotypes
%
%   plot_distance_intensity_local(distance_summary, protocol)
%   plot_distance_intensity_local(distance_summary, protocol, 'Name', Value, ...)
%
%   Plots mean distance (mm) vs stimulus intensity, grouped by LED color
%   block. L1 is control (grey), other genotypes (L2A, L3A) are colored.
%   Shaded ribbons show +/- SEM across experimental replicates.
%
%   Same layout as plot_QPI_intensity_local (subplots per color block).
%
%   INPUTS
%     distance_summary — table from batch_distance_summary (columns:
%                        experiment, genotype, cycle, label, n_flies_alive,
%                        mean_dist_mm, sem_dist_mm,
%                        mean_speed_on, sem_speed_on, mean_speed_off, sem_speed_off)
%     protocol         — 'P001' or 'P002'
%
%   NAME-VALUE PARAMETERS
%     'SavePath'    — folder to save PNG (default: '' = no save)
%     'ShowPlots'   — keep figure visible (default: true)
%     'ControlGeno' — control genotype name (default: 'L1')
%     'Metric'      — 'mean_dist_mm' (default)
%     'PlotName'    — custom filename prefix (default: auto from Metric)

    %% Parse
    p = inputParser;
    addRequired(p, 'distance_summary');
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    addParameter(p, 'ControlGeno', 'L1', @ischar);
    addParameter(p, 'Metric', 'mean_dist_mm', @ischar);
    addParameter(p, 'PlotName', '', @ischar);
    parse(p, distance_summary, protocol, varargin{:});
    opts = p.Results;

    T = distance_summary;
    CONTROL = opts.ControlGeno;
    METRIC  = opts.Metric;

    %% Protocol definitions — use get_protocol_config for gating (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_intensity
        fprintf('  %s: Not an intensity-ramp protocol — skipping intensity plot.\n', protocol);
        return;
    end

    switch upper(protocol)
        case 'P001'
            intensities_per_block = [1, 1, 5, 5, 10, 10, 20, 20, 30, 30, 40, 40, 50, 50];
            block_names   = {'Red', 'Green', 'Blue'};
            block_colors  = {[0.8 0 0], [0 0.5 0], [0 0 0.8]};
            block_fill    = {[1 0.6 0.6], [0.6 0.9 0.6], [0.6 0.6 1]};
            n_blocks = 3;

        case 'P002'
            intensities_per_block = [10, 10, 12, 12, 15, 15, 18, 18, 20, 20, 25, 25, 30, 30];
            block_names   = {'Red (rep 1)', 'Red (rep 2)', 'Red (rep 3)'};
            block_colors  = {[0.8 0 0], [0.7 0 0], [0.6 0 0]};
            block_fill    = {[1 0.6 0.6], [1 0.6 0.6], [1 0.6 0.6]};
            n_blocks = 3;

        otherwise
            % Other intensity protocols (P018, P020, P021, P022) — extend here as needed
            warning('Intensity protocol %s: plot layout not yet defined.', protocol);
            return;
    end

    cycles_per_block = length(intensities_per_block);

    % Unique intensities and mapping
    unique_int = unique(intensities_per_block, 'sorted');
    n_int = length(unique_int);

    int_cycle_map = cell(n_int, 1);
    for i = 1:n_int
        int_cycle_map{i} = find(intensities_per_block == unique_int(i));
    end

    %% Identify genotypes
    all_genos = unique(T.genotype);
    is_control = strcmp(all_genos, CONTROL);
    test_genos = all_genos(~is_control);
    geno_order = [test_genos; all_genos(is_control)];

    %% Y-axis label and plot naming
    switch METRIC
        case 'mean_dist_mm'
            y_label = 'Mean Distance (mm)';
            plot_suffix = 'distance_intensity';
            plot_title_prefix = 'Distance vs Intensity';
            auto_ylim = true;
        otherwise
            y_label = strrep(METRIC, '_', ' ');
            plot_suffix = 'distance_intensity';
            plot_title_prefix = strrep(METRIC, '_', ' ');
            auto_ylim = true;
    end

    % Override plot suffix with custom name if provided
    if ~isempty(opts.PlotName)
        plot_suffix = opts.PlotName;
    end

    %% Create figure
    fig = figure('Position', [50 50 500*n_blocks 500], 'Visible', 'off');

    for b = 1:n_blocks
        ax = subplot(1, n_blocks, b);
        hold on;

        cycle_range = ((b-1)*cycles_per_block + 1) : (b*cycles_per_block);

        legend_entries = {};
        legend_handles = [];

        for gi = 1:length(geno_order)
            geno = geno_order{gi};
            geno_rows = strcmp(T.genotype, geno);

            exps = unique(T.experiment(geno_rows));
            n_exps = length(exps);
            if n_exps == 0, continue; end

            % For each experiment, average repeated cycles per intensity
            exp_means = NaN(n_exps, n_int);
            exp_nflies = zeros(n_exps, 1);

            for ei = 1:n_exps
                exp_mask = strcmp(T.experiment, exps{ei});

                % Total flies = max alive flies in this block
                block_mask = exp_mask & ismember(T.cycle, cycle_range);
                if any(block_mask)
                    exp_nflies(ei) = max(T.n_flies_alive(block_mask));
                end

                for ii = 1:n_int
                    abs_cycles = cycle_range(int_cycle_map{ii});
                    row_mask = exp_mask & ismember(T.cycle, abs_cycles);

                    if any(row_mask)
                        vals = T.(METRIC)(row_mask);
                        exp_means(ei, ii) = mean(vals, 'omitnan');
                    end
                end
            end

            total_flies = sum(exp_nflies);

            % Mean +/- SEM across experiments
            n_valid = sum(~isnan(exp_means), 1);
            m  = mean(exp_means, 1, 'omitnan');
            se = std(exp_means, 0, 1, 'omitnan') ./ sqrt(n_valid);

            % Colors
            if strcmp(geno, CONTROL)
                line_color = [0.5 0.5 0.5];
                fill_color = [0.8 0.8 0.8];
            else
                line_color = get_genotype_color(geno);
                fill_color = line_color * 0.4 + 0.6;
            end

            x = 1:n_int;

            % SEM ribbon
            ribbon_hi = m + se;
            ribbon_lo = m - se;
            valid_pts = ~isnan(m);
            if sum(valid_pts) > 1
                xf = x(valid_pts);
                fill([xf fliplr(xf)], [ribbon_hi(valid_pts) fliplr(ribbon_lo(valid_pts))], ...
                    fill_color, 'EdgeColor', 'none', 'FaceAlpha', 0.35);
            end

            % Mean line
            h = plot(x(valid_pts), m(valid_pts), '-o', ...
                'Color', line_color, 'LineWidth', 2, ...
                'MarkerSize', 5, 'MarkerFaceColor', line_color);

            legend_handles(end+1) = h; %#ok<AGROW>
            legend_entries{end+1} = sprintf('%s (n=%d expts, %d flies)', ...
                geno, n_exps, total_flies); %#ok<AGROW>
        end

        %% Format axes
        % Zero reference line for delta metrics
        if ~auto_ylim
            plot([0.5 n_int+0.5], [0 0], 'k--', 'LineWidth', 0.8, ...
                'HandleVisibility', 'off');
        end

        set(ax, 'XTick', 1:n_int, ...
            'XTickLabel', arrayfun(@num2str, unique_int, 'UniformOutput', false));
        xlabel('Stimulus Intensity', 'FontSize', 11);
        if b == 1
            ylabel(y_label, 'FontSize', 11);
        end
        title(block_names{b}, 'FontSize', 13, 'FontWeight', 'bold', ...
            'Color', block_colors{b});
        xlim([0.5 n_int + 0.5]);
        grid on; box on;

        % Legend
        legend(legend_handles, legend_entries, ...
            'Location', 'northwestoutside', 'FontSize', 8);
    end

    sgtitle(sprintf('%s — %s', plot_title_prefix, protocol), ...
        'FontSize', 15, 'FontWeight', 'bold');

    %% Save
    if ~isempty(opts.SavePath)
        out_file = fullfile(opts.SavePath, sprintf('%s_%s.png', plot_suffix, protocol));
        saveas(fig, out_file);
        fprintf('  Saved plot: %s\n', out_file);
    end

    if opts.ShowPlots
        set(fig, 'Visible', 'on');
    else
        close(fig);
    end

end
