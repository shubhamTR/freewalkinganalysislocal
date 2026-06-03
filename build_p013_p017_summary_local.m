function summary = build_p013_p017_summary_local(protocol, varargin)
% BUILD_P013_P017_SUMMARY_LOCAL  Aggregate QPI across experiments for P013/P017
%
%   summary = build_p013_p017_summary_local('P017')
%   summary = build_p013_p017_summary_local('P013', 'AnalysisDir', '/path/to/data')
%
%   Adapted from server pipeline's build_p013_summary.m.
%   Reads per-experiment QPI summaries from compute_QPI_summary_local,
%   groups by genotype, computes mean ± SEM across experiments.
%
%   Saves to: <protocol_dir>/<protocol>_summary.mat

    p = inputParser;
    addRequired(p, 'protocol', @ischar);
    addParameter(p, 'AnalysisDir', '/Users/rathores/Documents/analysisdatalocal', @ischar);
    addParameter(p, 'RecomputeQPI', false, @islogical);
    parse(p, protocol, varargin{:});

    analysis_dir = p.Results.AnalysisDir;
    recompute = p.Results.RecomputeQPI;

    prot_dir = fullfile(analysis_dir, protocol);
    cfg = get_protocol_config(protocol);
    num_cycles = cfg.num_cycles;

    %% Discover experiments
    exp_dirs = dir(prot_dir);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, ...
        {'.', '..', 'Summary_Plots', 'summary', 'QPI_summary'}) & ...
        contains({exp_dirs.name}, '_Rig'));

    fprintf('\n========================================\n');
    fprintf('  BUILD %s SUMMARY (LOCAL)\n', protocol);
    fprintf('  %s\n', datestr(now));
    fprintf('  Experiments: %d\n', length(exp_dirs));
    fprintf('========================================\n\n');

    %% Group by genotype
    genotype_map = containers.Map();

    for ei = 1:length(exp_dirs)
        exp_name = exp_dirs(ei).name;
        parts = split(exp_name, '_');
        geno = parts{1};

        if ~genotype_map.isKey(geno)
            genotype_map(geno) = {};
        end
        exp_list = genotype_map(geno);
        exp_list{end+1} = ei; %#ok<AGROW>
        genotype_map(geno) = exp_list;
    end

    genotypes = genotype_map.keys();

    %% Process each genotype
    summary = struct();

    for gi = 1:length(genotypes)
        geno = genotypes{gi};
        exp_indices = genotype_map(geno);
        num_exps = length(exp_indices);

        fprintf('--- %s (%d experiments) ---\n', geno, num_exps);

        %% First pass: compute QPI summaries if needed, validate, count
        valid_exps = true(num_exps, 1);
        n_flies_vec = zeros(num_exps, 1);

        for j = 1:num_exps
            ei = exp_indices{j};
            exp_name = exp_dirs(ei).name;
            exp_path = fullfile(prot_dir, exp_name);
            ad = fullfile(exp_path, 'analysis');

            % Check prerequisites
            if isempty(dir(fullfile(ad, 'arena_calib_*.mat'))) || ...
               isempty(dir(fullfile(ad, 'LED_detector_*.mat')))
                fprintf('  ✗ %s — missing calib/LED files, skipping\n', exp_name);
                valid_exps(j) = false;
                continue;
            end

            % Run compute_QPI_summary_local if needed
            if recompute
                try
                    s = compute_QPI_summary_local(exp_path, 'Protocol', protocol);
                catch ME
                    fprintf('  ✗ %s — QPI error: %s\n', exp_name, ME.message);
                    valid_exps(j) = false;
                    continue;
                end
                n_flies_vec(j) = s.num_flies_total;
            else
                % Try to run it anyway (it's fast, returns a struct)
                try
                    s = compute_QPI_summary_local(exp_path, 'Protocol', protocol);
                    n_flies_vec(j) = s.num_flies_total;
                catch ME
                    fprintf('  ✗ %s — QPI error: %s\n', exp_name, ME.message);
                    valid_exps(j) = false;
                    continue;
                end
            end

            fprintf('  ✓ %s — %d flies\n', exp_name, n_flies_vec(j));
        end

        num_valid = sum(valid_exps);

        %% Allocate
        qpi_secondhalf_per_exp = NaN(num_valid, num_cycles);
        qpi_firsthalf_per_exp  = NaN(num_valid, num_cycles);
        n_flies_per_exp_vec    = zeros(num_valid, 1);
        exp_names              = cell(num_valid, 1);

        %% Second pass: fill data
        valid_idx = 0;
        for j = 1:num_exps
            if ~valid_exps(j), continue; end
            valid_idx = valid_idx + 1;

            ei = exp_indices{j};
            exp_name = exp_dirs(ei).name;
            exp_path = fullfile(prot_dir, exp_name);
            exp_names{valid_idx} = exp_name;

            s = compute_QPI_summary_local(exp_path, 'Protocol', protocol);
            ct = s.cycle_table;
            nc = min(height(ct), num_cycles);

            qpi_secondhalf_per_exp(valid_idx, 1:nc) = ct.mean_QPI_secondhalf(1:nc)';
            qpi_firsthalf_per_exp(valid_idx, 1:nc)  = ct.mean_QPI_firsthalf(1:nc)';
            n_flies_per_exp_vec(valid_idx) = s.num_flies_total;
        end

        %% Compute per-cycle summary stats (mean ± SEM across experiments)
        cycle_num   = (1:num_cycles)';
        cycle_label = cfg.labels(:);

        mean_qpi_2nd = NaN(num_cycles, 1);
        sem_qpi_2nd  = NaN(num_cycles, 1);
        mean_qpi_1st = NaN(num_cycles, 1);
        sem_qpi_1st  = NaN(num_cycles, 1);

        for c = 1:num_cycles
            vals = qpi_secondhalf_per_exp(:, c);
            vals = vals(~isnan(vals));
            if ~isempty(vals)
                mean_qpi_2nd(c) = mean(vals);
                sem_qpi_2nd(c)  = std(vals) / sqrt(length(vals));
            end

            vals1 = qpi_firsthalf_per_exp(:, c);
            vals1 = vals1(~isnan(vals1));
            if ~isempty(vals1)
                mean_qpi_1st(c) = mean(vals1);
                sem_qpi_1st(c)  = std(vals1) / sqrt(length(vals1));
            end
        end

        per_cycle = table(cycle_num, cycle_label, ...
            mean_qpi_2nd, sem_qpi_2nd, mean_qpi_1st, sem_qpi_1st);

        %% Store genotype summary
        geno_summary = struct();
        geno_summary.qpi_secondhalf_per_exp = qpi_secondhalf_per_exp;
        geno_summary.qpi_firsthalf_per_exp  = qpi_firsthalf_per_exp;
        geno_summary.exp_names       = exp_names;
        geno_summary.num_flies_per_exp = n_flies_per_exp_vec;
        geno_summary.num_flies       = sum(n_flies_per_exp_vec);
        geno_summary.num_experiments = num_valid;
        geno_summary.cycle_labels    = cfg.labels;
        geno_summary.per_cycle       = per_cycle;

        summary.(geno) = geno_summary;

        fprintf('  Total: %d flies across %d experiments\n\n', sum(n_flies_per_exp_vec), num_valid);
    end

    %% Save
    summary.protocol = protocol;
    summary.genotypes = genotypes;
    summary.num_cycles = num_cycles;
    summary.cycle_labels = cfg.labels;
    summary.build_date = datestr(now);

    out_file = fullfile(prot_dir, sprintf('%s_summary.mat', lower(protocol)));
    save(out_file, 'summary', '-v7.3');
    fprintf('Saved: %s\n', out_file);
    fprintf('========================================\n\n');
end
