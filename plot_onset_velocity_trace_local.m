function plot_onset_velocity_trace_local(all_results, protocol, varargin)
% PLOT_ONSET_VELOCITY_TRACE_LOCAL  Peri-stimulus velocity trace per genotype
%
%   plot_onset_velocity_trace_local(all_results, protocol)
%   plot_onset_velocity_trace_local(all_results, protocol, 'Name', Value, ...)
%
%   Plots mean velocity (mm/s) as a function of time aligned to LED onset,
%   averaged across all flies and cycles within each intensity level. One
%   subplot per LED color block. Control genotype (L1) in grey, test
%   genotypes in color. Shaded SEM ribbons. Vertical lines at LED onset
%   and offset.
%
%   INPUTS
%     all_results — struct array from compute_onset_velocity_trace_local
%     protocol    — 'P001' or 'P002'
%
%   NAME-VALUE PARAMETERS
%     'SavePath'    — folder to save PNG (default: '' = no save)
%     'ShowPlots'   — keep figure visible (default: true)
%     'ControlGeno' — control genotype name (default: 'L1')

    %% Parse
    p = inputParser;
    addRequired(p, 'all_results');
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'SavePath', '', @ischar);
    addParameter(p, 'ShowPlots', true, @islogical);
    addParameter(p, 'ControlGeno', 'L1', @ischar);
    parse(p, all_results, protocol, varargin{:});
    opts = p.Results;
    CONTROL = opts.ControlGeno;

    %% Protocol definitions — use get_protocol_config for gating (single source of truth)
    cfg = get_protocol_config(protocol);
    if ~cfg.is_intensity
        fprintf('  %s: Not an intensity-ramp protocol — skipping onset velocity plot.\n', protocol);
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

    %% Identify genotypes
    genos_all = unique({all_results.genotype});
    is_control = strcmp(genos_all, CONTROL);
    test_genos = genos_all(~is_control);
    geno_order = [test_genos, genos_all(is_control)];

    %% Get common time vector (from first result)
    time_vec = all_results(1).time_vec;
    T = length(time_vec);

    % LED duration for marking offset line
    led_dur = all_results(1).led_duration_sec;

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

            % Collect all velocity traces for this genotype and block
            % Each fly-cycle pair gives one trace. We pool all of them,
            % then compute mean +/- SEM at each timepoint.
            all_traces = [];  % will be [N x T]

            total_flies = 0;
            n_exps = 0;

            for ri = 1:length(all_results)
                r = all_results(ri);
                if ~strcmp(r.genotype, geno), continue; end

                n_exps = n_exps + 1;

                for c = cycle_range
                    if c > size(r.vel_traces, 3), continue; end
                    for f = 1:r.num_flies_total
                        if ~r.fly_alive(f, c), continue; end
                        trace = squeeze(r.vel_traces(f, :, c));  % [1 x T]
                        if all(isnan(trace)), continue; end
                        all_traces = [all_traces; trace]; %#ok<AGROW>
                    end
                end

                % Count alive flies (max across cycles in this block)
                block_cycles = cycle_range(cycle_range <= size(r.fly_alive, 2));
                if ~isempty(block_cycles)
                    total_flies = total_flies + max(sum(r.fly_alive(:, block_cycles), 1));
                end
            end

            if isempty(all_traces) || n_exps == 0, continue; end

            % Mean and SEM across all fly-cycle traces
            n_valid = sum(~isnan(all_traces), 1);
            m  = mean(all_traces, 1, 'omitnan');
            se = std(all_traces, 0, 1, 'omitnan') ./ sqrt(max(n_valid, 1));

            % Colors
            if strcmp(geno, CONTROL)
                line_color = [0.5 0.5 0.5];
                fill_color = [0.8 0.8 0.8];
            else
                line_color = get_genotype_color(geno);
                fill_color = line_color * 0.4 + 0.6;
            end

            % SEM ribbon
            ribbon_hi = m + se;
            ribbon_lo = m - se;
            valid_pts = ~isnan(m) & n_valid > 1;
            if sum(valid_pts) > 1
                tv = time_vec(valid_pts);
                fill([tv fliplr(tv)], ...
                    [ribbon_hi(valid_pts) fliplr(ribbon_lo(valid_pts))], ...
                    fill_color, 'EdgeColor', 'none', 'FaceAlpha', 0.3);
            end

            % Mean line
            h = plot(time_vec(valid_pts), m(valid_pts), '-', ...
                'Color', line_color, 'LineWidth', 1.5);

            legend_handles(end+1) = h; %#ok<AGROW>
            legend_entries{end+1} = sprintf('%s (n=%d expts, %d flies)', ...
                geno, n_exps, total_flies); %#ok<AGROW>
        end

        %% Vertical reference lines
        yl = ylim;
        % Onset line (t=0)
        plot([0 0], yl, 'k-', 'LineWidth', 1.5, 'HandleVisibility', 'off');
        % Offset line (t = LED duration)
        plot([led_dur led_dur], yl, 'k--', 'LineWidth', 1, 'HandleVisibility', 'off');

        % Shaded LED-on region
        fill([0 led_dur led_dur 0], [yl(1) yl(1) yl(2) yl(2)], ...
            [1 1 0.7], 'EdgeColor', 'none', 'FaceAlpha', 0.1, ...
            'HandleVisibility', 'off');

        ylim(yl);

        %% Format
        xlabel('Time from LED onset (s)', 'FontSize', 11);
        if b == 1
            ylabel('Velocity (mm/s)', 'FontSize', 11);
        end
        title(block_names{b}, 'FontSize', 13, 'FontWeight', 'bold', ...
            'Color', block_colors{b});
        grid on; box on;

        legend(legend_handles, legend_entries, ...
            'Location', 'northwestoutside', 'FontSize', 8);
    end

    sgtitle(sprintf('Peri-Stimulus Velocity Trace — %s', protocol), ...
        'FontSize', 15, 'FontWeight', 'bold');

    %% Save
    if ~isempty(opts.SavePath)
        out_file = fullfile(opts.SavePath, sprintf('onset_vel_trace_%s.png', protocol));
        saveas(fig, out_file);
        fprintf('  Saved plot: %s\n', out_file);
    end

    if opts.ShowPlots
        set(fig, 'Visible', 'on');
    else
        close(fig);
    end

end
