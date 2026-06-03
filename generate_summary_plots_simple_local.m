function generate_summary_plots_simple_local(analysis_dir, protocol, genotype, opts)
% GENERATE_SUMMARY_PLOTS_SIMPLE - Create summary plots
    
    % Collect all results for this protocol-genotype
    experiments = collect_protocol_genotype_experiments(analysis_dir, protocol, genotype);
    
    all_distance = [];
    all_latency = [];
    
    for i = 1:length(experiments)
        exp_path = experiments{i};
        analysis_subdir = fullfile(exp_path, 'analysis');
        
        dist_file = fullfile(analysis_subdir, 'distance_results.mat');
        if exist(dist_file, 'file')
            load(dist_file, 'distance_results');
            all_distance = [all_distance; distance_results.distance_mm];
        end
        
        lat_file = fullfile(analysis_subdir, 'latency_results.mat');
        if exist(lat_file, 'file')
            load(lat_file, 'latency_results');
            all_latency = [all_latency; latency_results.first_dark_entry];
        end
    end
    
    if isempty(all_distance)
        return;
    end
    
    % Create plots directory
    plots_dir = fullfile(analysis_dir, protocol, 'Summary_Plots');
    if ~exist(plots_dir, 'dir')
        mkdir(plots_dir);
    end
    
    % Plot distance
    plot_distance_summary(all_distance, protocol, genotype, plots_dir);
    
    % Plot latency
    if ~isempty(all_latency)
        plot_latency_summary(all_latency, protocol, genotype, plots_dir);
    end
end

function experiments = collect_protocol_genotype_experiments(analysis_dir, protocol, genotype)
    experiments = {};
    prot_path = fullfile(analysis_dir, protocol);
    if ~exist(prot_path, 'dir'), return; end
    
    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..', 'Summary_Plots'}));
    
    for e = 1:length(exp_dirs)
        if startsWith(exp_dirs(e).name, [genotype, '_'])
            exp_path = fullfile(prot_path, exp_dirs(e).name);
            experiments{end+1} = exp_path;
        end
    end
end

function plot_distance_summary(distance_matrix, protocol, genotype, plots_dir)
    [num_flies, num_cycles] = size(distance_matrix);
    
    figure('Position', [100 100 1400 600]);
    hold on;
    
    boxplot(distance_matrix, 'Colors', [0.5 0.5 0.5], 'Symbol', '');
    
    for c = 1:num_cycles
        x_jitter = c + (rand(num_flies, 1) - 0.5) * 0.3;
        scatter(x_jitter, distance_matrix(:, c), 30, [0.3 0.3 0.7], ...
            'filled', 'MarkerFaceAlpha', 0.3);
    end
    
    xlabel('Stimulus Cycle', 'FontSize', 14);
    ylabel('Distance (mm)', 'FontSize', 14);
    title(sprintf('%s - %s (n=%d)', protocol, genotype, num_flies), 'FontSize', 16, 'Interpreter', 'none');
    grid on; box on;
    
    saveas(gcf, fullfile(plots_dir, sprintf('Distance_%s_%s.png', protocol, genotype)));
    close(gcf);
end

function plot_latency_summary(latency_matrix, protocol, genotype, plots_dir)
    num_stims = size(latency_matrix, 2);
    training_trials = identify_training_trials(num_stims);
    
    if isempty(training_trials), return; end
    
    latency_training = latency_matrix(:, training_trials);
    
    figure('Position', [100 100 1400 600]);
    hold on;
    
    mean_lat = nanmean(latency_training, 1);
    se_lat = nanstd(latency_training, 0, 1) ./ sqrt(sum(~isnan(latency_training), 1));
    
    errorbar(training_trials, mean_lat, se_lat, 'o-', 'LineWidth', 2, ...
        'MarkerSize', 8, 'Color', [0 0.5 0], 'MarkerFaceColor', [0 0.7 0]);
    
    xlabel('Stimulus Cycle', 'FontSize', 14);
    ylabel('Latency (s)', 'FontSize', 14);
    title(sprintf('%s - %s', protocol, genotype), 'FontSize', 16, 'Interpreter', 'none');
    grid on; box on;
    
    saveas(gcf, fullfile(plots_dir, sprintf('Latency_%s_%s.png', protocol, genotype)));
    close(gcf);
end

function training_trials = identify_training_trials(num_stims)
    training_blocks = {3:12, 14:23, 25:34, 36:45};
    training_trials = [];
    
    for b = 1:length(training_blocks)
        block = training_blocks{b};
        valid = block(block <= num_stims);
        training_trials = [training_trials, valid];
    end
end