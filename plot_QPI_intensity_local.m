function plot_QPI_intensity_local(protocol, varargin)
% PLOT_QPI_INTENSITY_LOCAL  Intensity-response curve: control (L1) vs test genotypes
%
%   plot_QPI_intensity_local('P001')
%   plot_QPI_intensity_local('P001', 'Name', Value, ...)
%
%   Self-loading: loads QPI_summary_<protocol>.mat from AnalysisDir.
%   Plots mean QPI vs stimulus intensity, grouped by LED color block.
%   L1 is control (grey), other genotypes (L2A, L3A) are colored.
%   Shaded ribbons show ± SEM across experimental replicates.
%
%   NAME-VALUE PARAMETERS
%     'AnalysisDir' — root of protocol folders (default: ~/Documents/analysisdatalocal)
%     'SavePath'    — folder to save PNG/SVG/FIG (default: '' = auto)
%     'ShowPlots'   — keep figure visible (default: true)
%     'ControlGeno' — control genotype name (default: 'L1')
%     'Metric'      — 'mean_QPI_secondhalf' or 'mean_QPI_firsthalf' (default: secondhalf)

    %% Parse
    p = inputParser;
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    addParameter(p, 'ControlGeno', 'L1', @ischar);
    addParameter(p, 'Metric', 'mean_QPI_secondhalf', @ischar);
    addParameter(p, 'Genotypes', {}, @iscell);
    parse(p, protocol, varargin{:});
    opts = p.Results;

    %% Load QPI summary
    ADIR = opts.AnalysisDir;
    summary_file = fullfile(ADIR, protocol, sprintf('QPI_summary_%s.mat', protocol));
    if ~exist(summary_file, 'file')
        error('QPI summary not found: %s\nRun batch_QPI_summary first.', summary_file);
    end
    tmp = load(summary_file, 'QPI_summary');
    T = tmp.QPI_summary;
    if ~isempty(opts.Genotypes)
        T = T(ismember(T.genotype, opts.Genotypes), :);
    end
    CONTROL = opts.ControlGeno;
    METRIC  = opts.Metric;

    %% Default save path
    if isempty(opts.SavePath)
        opts.SavePath = fullfile(ADIR, protocol, 'QPI_summary');
    end

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

    % Unique intensities and mapping: which cycles map to which intensity
    unique_int = unique(intensities_per_block, 'sorted');
    n_int = length(unique_int);

    % For each unique intensity, find which cycle indices (within block) have it
    int_cycle_map = cell(n_int, 1);  % int_cycle_map{i} = indices into 1:cycles_per_block
    for i = 1:n_int
        int_cycle_map{i} = find(intensities_per_block == unique_int(i));
    end

    %% Identify genotypes
    all_genos = unique(T.genotype);
    is_control = strcmp(all_genos, CONTROL);
    test_genos = all_genos(~is_control);
    % Order: test genotypes first (colored), then control (grey) on top
    geno_order = [test_genos; all_genos(is_control)];

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

            % Get experiments for this genotype
            exps = unique(T.experiment(geno_rows));
            n_exps = length(exps);

            if n_exps == 0, continue; end

            % For each experiment, average the repeated cycles per intensity
            exp_means = NaN(n_exps, n_int);
            exp_nflies = zeros(n_exps, 1);  % total flies per experiment

            for ei = 1:n_exps
                exp_mask = strcmp(T.experiment, exps{ei});

                % Total flies = max n_flies in this block for this experiment
                block_mask = exp_mask & ismember(T.cycle, cycle_range);
                if any(block_mask)
                    exp_nflies(ei) = max(T.n_flies(block_mask));
                end

                for ii = 1:n_int
                    % Absolute cycle numbers for this intensity in this block
                    abs_cycles = cycle_range(int_cycle_map{ii});
                    row_mask = exp_mask & ismember(T.cycle, abs_cycles);

                    if any(row_mask)
                        vals = T.(METRIC)(row_mask);
                        exp_means(ei, ii) = mean(vals, 'omitnan');
                    end
                end
            end

            total_flies = sum(exp_nflies);

            % Mean ± SEM across experiments
            n_valid = sum(~isnan(exp_means), 1);
            m  = mean(exp_means, 1, 'omitnan');
            se = std(exp_means, 0, 1, 'omitnan') ./ sqrt(n_valid);

            % Colors — use consistent genotype colors
            if strcmp(geno, CONTROL)
                line_color = [0.5 0.5 0.5];
                fill_color = [0.8 0.8 0.8];
            else
                line_color = get_genotype_color(geno);
                fill_color = line_color * 0.4 + 0.6;  % lighter tint for ribbon
            end

            % X positions
            x = 1:n_int;

            % SEM ribbon
            ribbon_hi = m + se;
            ribbon_lo = m - se;
            % Handle NaN gaps for fill
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
        set(ax, 'FontSize', 16);
        set(ax, 'XTick', 1:n_int, ...
            'XTickLabel', arrayfun(@num2str, unique_int, 'UniformOutput', false));
        xlabel('Stimulus Intensity', 'FontSize', 18);
        if b == 1
            ylabel(sprintf('Mean QPI (%s)', strrep(METRIC, '_', ' ')), 'FontSize', 18);
        end
        title(block_names{b}, 'FontSize', 20, 'FontWeight', 'bold', ...
            'Color', block_colors{b});
        ylim_auto(ax);
        xlim([0.5 n_int + 0.5]);
        grid on; box on;

        % Legend
        legend(legend_handles, legend_entries, ...
            'Location', 'northwestoutside', 'FontSize', 14);
    end

    % Label indicating which half
    if contains(METRIC, 'firsthalf')
        half_label = 'First Half';
        half_suffix = 'firsthalf';
    else
        half_label = 'Second Half';
        half_suffix = 'secondhalf';
    end

    sgtitle(sprintf('QPI Intensity Response — %s (%s)', protocol, half_label), ...
        'FontSize', 20, 'FontWeight', 'bold');

    %% Save
    if ~isempty(opts.SavePath)
        if ~exist(opts.SavePath, 'dir'), mkdir(opts.SavePath); end
        out_file = fullfile(opts.SavePath, sprintf('QPI_intensity_%s_%s.png', protocol, half_suffix));
        exportgraphics(fig, out_file, 'Resolution', 200);
        saveas(fig, strrep(out_file, '.png', '.svg'));
        savefig(fig, strrep(out_file, '.png', '.fig'));
        fprintf('  Saved intensity plot: %s\n', out_file);
    end

    if opts.ShowPlots
        set(fig, 'Visible', 'on');
    else
        close(fig);
    end

end

%% ======== LOCAL HELPER ========
function ylim_auto(ax)
    yl = ylim(ax);
    if yl(1) >= 0
        ylim(ax, [0, max(yl(2)*1.12, 0.1)]);
    else
        ylim(ax, [yl(1)*1.12, max(yl(2)*1.12, 0.1)]);
    end
end
