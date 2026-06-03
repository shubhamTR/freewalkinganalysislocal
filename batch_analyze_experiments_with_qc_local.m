function batch_analyze_experiments_with_qc_local(analysis_dir, varargin)
% BATCH_ANALYZE_EXPERIMENTS_WITH_QC - With better error reporting

    % Parse inputs
    p = inputParser;
    addParameter(p, 'Protocols', {}, @iscell);
    addParameter(p, 'Genotypes', {}, @iscell);
    addParameter(p, 'RecomputeAll', false, @islogical);
    addParameter(p, 'FPS', 30, @isnumeric);
    addParameter(p, 'Verbose', true, @islogical);
    addParameter(p, 'EnableQC', true, @islogical);
    addParameter(p, 'MinFlies', 1, @isnumeric);
    addParameter(p, 'MaxFlies', 20, @isnumeric);
    addParameter(p, 'ExpectedCycles', [], @isnumeric);
    parse(p, varargin{:});
    
    opts = p.Results;
    
    % DEBUG: Print opts type and contents
    fprintf('DEBUG: opts is a %s\n', class(opts));
    fprintf('DEBUG: opts fields: %s\n', strjoin(fieldnames(opts), ', '));
    
    % Create log
    log_dir = fullfile(analysis_dir, 'Logs');
    if ~exist(log_dir, 'dir')
        mkdir(log_dir);
    end
    
    log_file = fullfile(log_dir, sprintf('batch_analysis_%s.txt', datestr(now, 'yyyymmdd_HHMMSS')));
    log_fid = fopen(log_file, 'w');
    
    % Header
    fprintf('\n========================================\n');
    fprintf('BATCH ANALYSIS\n');
    fprintf('========================================\n');
    fprintf('QC Enabled: %s\n', ternary(opts.EnableQC, 'Yes', 'No'));
    fprintf('========================================\n\n');
    
    fprintf(log_fid, '========================================\n');
    fprintf(log_fid, 'BATCH ANALYSIS\n');
    fprintf(log_fid, 'Started: %s\n', datestr(now));
    fprintf(log_fid, '========================================\n\n');
    
    % Discover
    [protocols, genotypes] = discover_protocols_genotypes(analysis_dir, opts);
    
    total = 0;
    processed = 0;
    skipped = 0;
    qc_failed = 0;
    errors = 0;
    
    % Process
    for prot_idx = 1:length(protocols)
        protocol = protocols{prot_idx};
        
        for geno_idx = 1:length(genotypes)
            genotype = genotypes{geno_idx};
            
            experiments = collect_protocol_genotype_experiments(analysis_dir, protocol, genotype);
            
            if isempty(experiments)
                continue;
            end
            
            fprintf('\n=== %s / %s ===\n', protocol, genotype);
            fprintf('  %d experiments\n', length(experiments));
            
            total = total + length(experiments);
            
            for exp_idx = 1:length(experiments)
                exp_path = experiments{exp_idx};
                exp_name = basename(exp_path);
                
                try
                    % Skip if done
                    if ~opts.RecomputeAll && is_already_analyzed(exp_path)
                        fprintf('    [%d/%d] Already done: %s\n', exp_idx, length(experiments), exp_name);
                        skipped = skipped + 1;
                        continue;
                    end
                    
                    fprintf('    [%d/%d] %s\n', exp_idx, length(experiments), exp_name);
                    
                    % Pre-analysis QC
                    if opts.EnableQC
                        fprintf('      Pre-analysis QC...\n');
                        
                        try
                            % DEBUG: Show what we're passing
                            fprintf('      DEBUG: Calling validate_experiment_simple_local with opts type: %s\n', class(opts));
                            
                            qc_report = validate_experiment_simple_local(exp_path, 'pre_analysis', opts);
                            
                            if ~qc_report.passed
                                fprintf('      ✗ QC failed: %s\n', qc_report.errors{1});
                                qc_failed = qc_failed + 1;
                                continue;
                            end
                            fprintf('      ✓ QC passed\n');
                            
                        catch QC_ERR
                            fprintf('      ✗ QC Error: %s\n', QC_ERR.message);
                            fprintf('      Stack trace:\n%s\n', QC_ERR.getReport());
                            qc_failed = qc_failed + 1;
                            continue;
                        end
                    end
                    
                    % Run analysis (pass protocol and exp_path for QPI)
                    opts.Protocol = protocol;
                    opts.exp_path = exp_path;
                    analyze_single_experiment_local(exp_path, opts);
                    fprintf('      ✓ Analysis complete\n');
                    
                    processed = processed + 1;
                    
                catch ME
                    fprintf('      ✗ Error: %s\n', ME.message);
                    fprintf('      Full error:\n%s\n', ME.getReport());
                    errors = errors + 1;
                end
            end
            
            % Generate plots
            fprintf('  Generating plots...\n');
            try
                generate_summary_plots_simple_local(analysis_dir, protocol, genotype, opts);
                fprintf('  ✓ Plots saved\n');
            catch PLOT_ERR
                fprintf('  ✗ Plot error: %s\n', PLOT_ERR.message);
            end
        end
    end
    
    % Summary
    fprintf('\n========================================\n');
    fprintf('SUMMARY\n');
    fprintf('========================================\n');
    fprintf('Total: %d\n', total);
    fprintf('Processed: %d\n', processed);
    fprintf('Skipped: %d\n', skipped);
    fprintf('QC Failed: %d\n', qc_failed);
    fprintf('Errors: %d\n', errors);
    fprintf('========================================\n\n');
    
    fclose(log_fid);
end

%% Helper functions
function [protocols, genotypes] = discover_protocols_genotypes(analysis_dir, opts)
    prot_dirs = dir(fullfile(analysis_dir, 'P*'));
    prot_dirs = prot_dirs([prot_dirs.isdir]);
    prot_dirs = prot_dirs(~cellfun('isempty', regexp({prot_dirs.name}, '^P\d+$', 'once')));
    protocols = {prot_dirs.name};
    
    if ~isempty(opts.Protocols)
        protocols = opts.Protocols;
    end
    
    genotypes = {};
    for p = 1:length(protocols)
        prot_path = fullfile(analysis_dir, protocols{p});
        if ~exist(prot_path, 'dir'), continue; end
        
        exp_dirs = dir(prot_path);
        exp_dirs = exp_dirs([exp_dirs.isdir]);
        % Filter to valid experiment folders: must match GENOTYPE_RigN_YYYYMMDD_HHMMSS
        valid = ~cellfun(@isempty, regexp({exp_dirs.name}, '^\w+_Rig\d+_\d{8}_\d{6}$'));
        exp_dirs = exp_dirs(valid);

        for e = 1:length(exp_dirs)
            parts = split(exp_dirs(e).name, '_');
            if ~isempty(parts)
                geno = parts{1};
                if ~ismember(geno, genotypes)
                    genotypes{end+1} = geno;
                end
            end
        end
    end
    
    if ~isempty(opts.Genotypes)
        genotypes = opts.Genotypes;
    end
end

function experiments = collect_protocol_genotype_experiments(analysis_dir, protocol, genotype)
    experiments = {};
    prot_path = fullfile(analysis_dir, protocol);
    if ~exist(prot_path, 'dir'), return; end
    
    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir]);
    % Filter to valid experiment folders: must match GENOTYPE_RigN_YYYYMMDD_HHMMSS
    valid = ~cellfun(@isempty, regexp({exp_dirs.name}, '^\w+_Rig\d+_\d{8}_\d{6}$'));
    exp_dirs = exp_dirs(valid);

    % Filter out excluded experiments
    exclude_list = get_exclude_experiments();

    for e = 1:length(exp_dirs)
        if startsWith(exp_dirs(e).name, [genotype, '_']) && ...
                ~ismember(exp_dirs(e).name, exclude_list)
            exp_path = fullfile(prot_path, exp_dirs(e).name);
            experiments{end+1} = exp_path;
        end
    end
end

function is_done = is_already_analyzed(exp_path)
    analysis_dir = fullfile(exp_path, 'analysis');
    if ~exist(analysis_dir, 'dir')
        is_done = false;
        return;
    end
    
    has_dist = exist(fullfile(analysis_dir, 'distance_results.mat'), 'file');
    has_lat = exist(fullfile(analysis_dir, 'latency_results.mat'), 'file');
    is_done = has_dist && has_lat;
end

function name = basename(path)
    [~, name] = fileparts(path);
end

function result = ternary(c, t, f)
    if c, result = t; else, result = f; end
end