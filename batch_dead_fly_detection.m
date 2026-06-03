%% batch_dead_fly_detection.m
% Pre-compute dead fly detection for all experiments and save
% dead_fly_report.mat in each experiment's analysis/ folder.
%
% This eliminates redundant dead fly detection across compute functions
% (QPI, distance, latency, speed, onset velocity) which all check for
% dead_fly_report.mat before falling back to inline detection.
%
% Usage:
%   batch_dead_fly_detection                  % all protocols
%   batch_dead_fly_detection('P017', 'P019')  % specific protocols
%
% Output per experiment:
%   analysis/dead_fly_report.mat containing struct `dead_report` with:
%     .fly_alive          — [num_flies x num_cycles] logical
%     .num_flies          — total flies evaluated
%     .num_dead           — flies flagged dead by final cycle
%     .num_alive          — flies alive at final cycle
%     .dead_from_cycle    — [num_flies x 1], cycle flagged (Inf = alive)
%     .consecutive_cycles — detection window used
%     .move_thresh_px     — pixel threshold used
%     .fly_ids_original   — original trx indices of evaluated flies
%     .timestamp          — datestr of when report was generated
%
% Set FORCE_RECOMPUTE = true to regenerate all reports.
%
% Author: Shubham Rathore

function batch_dead_fly_detection(varargin)

    ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';
    FORCE_RECOMPUTE = false;

    %% Determine which protocols to process
    if nargin > 0
        protocols = varargin;
    else
        d = dir(fullfile(ANALYSIS_DIR, 'P*'));
        d = d([d.isdir]);
        d = d(~cellfun('isempty', regexp({d.name}, '^P\d+$', 'once')));
        protocols = {d.name};
    end

    nGenerated = 0;
    nSkipped   = 0;
    nFailed    = 0;
    failed_list = {};

    for pi = 1:length(protocols)
        prot = protocols{pi};
        prot_path = fullfile(ANALYSIS_DIR, prot);
        if ~exist(prot_path, 'dir')
            fprintf('Protocol %s not found — skipping\n', prot);
            continue;
        end

        exp_dirs = dir(prot_path);
        exp_dirs = exp_dirs([exp_dirs.isdir]);
        valid = ~cellfun(@isempty, regexp({exp_dirs.name}, '^\w+_Rig\d+_\d{8}_\d{6}$'));
        exp_dirs = exp_dirs(valid);

        fprintf('\n=== %s (%d experiments) ===\n', prot, length(exp_dirs));

        for ei = 1:length(exp_dirs)
            exp_name = exp_dirs(ei).name;
            exp_path = fullfile(prot_path, exp_name);
            analysis_dir = fullfile(exp_path, 'analysis');
            dead_fly_file = fullfile(analysis_dir, 'dead_fly_report.mat');

            % Skip if already exists (unless forced)
            if ~FORCE_RECOMPUTE && exist(dead_fly_file, 'file')
                fprintf('  [%d/%d] %s — report exists, skipping\n', ...
                    ei, length(exp_dirs), exp_name);
                nSkipped = nSkipped + 1;
                continue;
            end

            try
                %% Load trx
                trx_data = load(fullfile(exp_path, 'trx.mat'));
                trx = trx_data.trx;

                % Filter flies spanning full recording
                max_end = max([trx.endframe]);
                good = [];
                for k = 1:length(trx)
                    if trx(k).firstframe == 1 && trx(k).endframe >= (max_end - 30)
                        good = [good, k]; %#ok<AGROW>
                    end
                end
                trx = trx(good);
                fly_ids_original = good;

                if isempty(trx)
                    fprintf('  [%d/%d] %s — no valid flies, skipping\n', ...
                        ei, length(exp_dirs), exp_name);
                    nSkipped = nSkipped + 1;
                    continue;
                end

                %% Load LED detector
                led_files = dir(fullfile(analysis_dir, 'LED_detector_*.mat'));
                if isempty(led_files)
                    fprintf('  [%d/%d] %s — no LED detector, skipping\n', ...
                        ei, length(exp_dirs), exp_name);
                    nSkipped = nSkipped + 1;
                    continue;
                end
                led_data = load(fullfile(analysis_dir, led_files(end).name));
                LED = led_data.LED_detector;

                %% Run detection
                [~, dead_report] = detect_dead_flies_posture(trx, LED, 'Verbose', false);

                % Attach fly identity and timestamp
                dead_report.fly_ids_original = fly_ids_original;
                dead_report.timestamp = datestr(now);

                %% Save
                if ~exist(analysis_dir, 'dir'), mkdir(analysis_dir); end
                save(dead_fly_file, 'dead_report');

                fprintf('  [%d/%d] %s — %d/%d dead\n', ...
                    ei, length(exp_dirs), exp_name, ...
                    dead_report.num_dead, dead_report.num_flies);
                nGenerated = nGenerated + 1;

            catch ME
                fprintf('  [%d/%d] %s — Error: %s\n', ...
                    ei, length(exp_dirs), exp_name, ME.message);
                failed_list{end+1} = sprintf('[%s] %s: %s', prot, exp_name, ME.message); %#ok<AGROW>
                nFailed = nFailed + 1;
            end
        end
    end

    %% Summary
    fprintf('\n========================================\n');
    fprintf('DEAD FLY DETECTION BATCH SUMMARY\n');
    fprintf('========================================\n');
    fprintf('Generated: %d\n', nGenerated);
    fprintf('Skipped:   %d\n', nSkipped);
    fprintf('Failed:    %d\n', nFailed);
    if ~isempty(failed_list)
        fprintf('\nFailed experiments:\n');
        for fi = 1:length(failed_list)
            fprintf('  %s\n', failed_list{fi});
        end
    end
    fprintf('========================================\n');
    fprintf('Done: %s\n\n', datestr(now));
end
