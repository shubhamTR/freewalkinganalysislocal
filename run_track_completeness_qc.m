%% run_track_completeness_qc.m
%  Rerun QC validation to generate track_completeness .mat files and
%  updated tracking_gaps figures (with per-cycle heatmap panel).
%
%  Usage:
%    run_track_completeness_qc('P008', 'P010', 'P011')
%    run_track_completeness_qc('P017')
%
%  Output per experiment:
%    analysis/track_completeness_<exp>.mat
%    analysis/tracking_gaps.png + .fig

function run_track_completeness_qc(varargin)
    if nargin == 0
        error('Specify one or more protocols, e.g.: run_track_completeness_qc(''P008'', ''P010'')');
    end

    ADIR = '/Users/rathores/Documents/analysisdatalocal';
    protocols = varargin;

    opts.MinFlies = 1;
    opts.MaxFlies = 20;

    for pi = 1:length(protocols)
        prot = protocols{pi};
        prot_path = fullfile(ADIR, prot);
        if ~exist(prot_path, 'dir')
            fprintf('Protocol %s not found — skipping\n', prot);
            continue;
        end

        exp_dirs = dir(prot_path);
        exp_dirs = exp_dirs([exp_dirs.isdir]);
        valid = ~cellfun(@isempty, regexp({exp_dirs.name}, '^\w+_Rig\d+_\d{8}_\d{6}$'));
        exp_dirs = exp_dirs(valid);

        fprintf('\n=== %s: %d experiments ===\n', prot, length(exp_dirs));

        for ei = 1:length(exp_dirs)
            exp_path = fullfile(prot_path, exp_dirs(ei).name);
            fprintf('\n--- %s ---\n', exp_dirs(ei).name);

            try
                qc_report = validate_experiment_simple_local(exp_path, 'pre_analysis', opts);

                if ~isempty(qc_report.track_completeness) && ...
                   ~isempty(qc_report.track_completeness.valid_frac)
                    vf = qc_report.track_completeness.valid_frac;
                    thresh = qc_report.track_completeness.min_valid_frac;
                    n_bad = sum(vf(:) < thresh);
                    fprintf('  Summary: %d/%d fly-cycle pairs below %.0f%%\n', ...
                        n_bad, numel(vf), thresh * 100);
                    if n_bad > 0
                        fprintf('  Worst: %.1f%% valid\n', min(vf(:)) * 100);
                    end
                end
            catch ME
                fprintf('  FAILED: %s\n', ME.message);
            end
        end
    end

    fprintf('\nDone.\n');
end
