function run_all_analysis(varargin)
% RUN_ALL_ANALYSIS  Complete analysis pipeline — all metrics & plotters.
%
%   run_all_analysis()              — run all 15 steps
%   run_all_analysis('StartAt', 6)  — resume from step 6 (skip 1-5)
%   run_all_analysis('Only', [6 7 8]) — run only steps 6, 7, 8
%
% Runs every batch script in isolated function scope so that child
% scripts' clear/clc calls do not wipe the parent workspace.
% Closes stale figures between steps to prevent memory buildup.
%
% ┌─────────────────────────────────────────────────────────────────────┐
% │  STAGE 1: Per-experiment metrics (all protocols)                   │
% │     1. batch_QPI_summary          — QPI per cycle                  │
% │     2. batch_distance_summary     — distance per cycle             │
% │     3. batch_latency_summary      — latency per cycle              │
% │     4. batch_distance_to_safe_summary — dist to safe per cycle     │
% │     5. run_speed                  — speed per cycle + plots         │
% │                                                                     │
% │  STAGE 2: Per-experiment plots                                     │
% │     6. batch_plot_QPI             — QPI bar plots                  │
% │     7. batch_plot_distance        — distance plots + summaries     │
% │     8. batch_plot_latency         — latency plots + summaries      │
% │     9. batch_plot_speed           — per-experiment speed traces    │
% │                                                                     │
% │  STAGE 3: Per-genotype summaries                                   │
% │    10. summary_speed              — genotype speed overlays        │
% │    11. optomotor (analyze + trajectories)                          │
% │    12. probe visits + cumulative occupancy                         │
% │                                                                     │
% │  STAGE 4: Spatial analysis                                         │
% │    13. run_transit_density        — grid density + summaries       │
% │                                                                     │
% │  STAGE 5: Velocity traces                                         │
% │    14. batch_onset_velocity       — peri-stimulus velocity         │
% │                                                                     │
% │  STAGE 6: Cross-protocol comparisons                               │
% │    15. plot_condition_comparison  — Coupled/Uncoupled/Dark overlay  │
% └─────────────────────────────────────────────────────────────────────┘

    %% Parse options
    ip = inputParser;
    addParameter(ip, 'StartAt', 1, @isnumeric);
    addParameter(ip, 'Only', [], @isnumeric);
    parse(ip, varargin{:});
    start_at  = ip.Results.StartAt;
    only_steps = ip.Results.Only;


    t_start = tic;

    fprintf('══════════════════════════════════════════════════════════════\n');
    fprintf('  FULL ANALYSIS PIPELINE — All Metrics & Plotters\n');
    fprintf('  Started: %s\n', datestr(now));
    fprintf('══════════════════════════════════════════════════════════════\n\n');

    % Define all steps: {display_name, script(s) to run}
    steps = {
        'batch_QPI_summary',               {'batch_QPI_summary'}
        'batch_distance_summary',           {'batch_distance_summary'}
        'batch_latency_summary',            {'batch_latency_summary'}
        'batch_distance_to_safe_summary',   {'batch_distance_to_safe_summary'}
        'run_speed',                        {'run_speed'}
        'batch_plot_QPI',                   {'batch_plot_QPI'}
        'batch_plot_distance',              {'batch_plot_distance'}
        'batch_plot_latency',               {'batch_plot_latency'}
        'batch_plot_speed',                 {'batch_plot_speed'}
        'summary_speed',                    {'summary_speed'}
        'optomotor (analyze + trajectories)', {'analyze_optomotor', 'plot_optomotor_trajectories'}
        'probe visits + cumulative occupancy', {'analyze_probe_visits', 'cumulative_occupancy'}
        'run_transit_density',              {'run_transit_density'}
        'batch_onset_velocity',             {'batch_onset_velocity'}
        'condition_comparison (Coupled/Uncoupled/Dark)', {'plot_condition_comparison'}
    };

    nSteps = size(steps, 1);

    % Determine which steps to run
    if ~isempty(only_steps)
        run_mask = ismember(1:nSteps, only_steps);
        fprintf('  Running ONLY steps: %s\n\n', mat2str(only_steps));
    elseif start_at > 1
        run_mask = (1:nSteps) >= start_at;
        fprintf('  Starting from step %d (skipping 1-%d)\n\n', start_at, start_at-1);
    else
        run_mask = true(1, nSteps);
    end

    status_names  = cell(nSteps, 1);
    status_ok     = false(nSteps, 1);
    status_time   = zeros(nSteps, 1);
    status_errmsg = cell(nSteps, 1);
    status_ran    = false(nSteps, 1);

    stage_labels = {
        1, 'STAGE 1: Per-experiment metrics';
        6, 'STAGE 2: Per-experiment plots';
        10, 'STAGE 3: Per-genotype summaries';
        13, 'STAGE 4: Spatial analysis';
        14, 'STAGE 5: Velocity traces';
        15, 'STAGE 6: Cross-protocol comparisons';
    };
    next_stage = 1;

    for s = 1:nSteps
        % Print stage header if needed
        if next_stage <= size(stage_labels, 1) && s == stage_labels{next_stage, 1}
            fprintf('\n════ %s ════\n', stage_labels{next_stage, 2});
            next_stage = next_stage + 1;
        end

        step_name = steps{s, 1};
        script_list = steps{s, 2};
        status_names{s} = step_name;

        % Skip steps not in the run set
        if ~run_mask(s)
            fprintf('  [%d/%d] %s — SKIPPED\n', s, nSteps, step_name);
            status_errmsg{s} = 'skipped';
            continue;
        end

        status_ran(s) = true;
        fprintf('\n>>> [%d/%d] %s <<<\n\n', s, nSteps, step_name);

        % Close all open figures before each step to prevent memory buildup
        close all force;

        ts = tic;
        try
            for si = 1:length(script_list)
                run_isolated(script_list{si});
            end
            status_ok(s) = true;
            status_time(s) = toc(ts);
            status_errmsg{s} = '';
            fprintf('  %s completed in %.1f s\n', step_name, status_time(s));
        catch ME
            status_ok(s) = false;
            status_time(s) = toc(ts);
            status_errmsg{s} = ME.message;
            fprintf('  %s FAILED: %s\n', step_name, ME.message);
        end
    end

    % Final cleanup
    close all force;

    %% ════════════════════════════════════════════════════════════════════
    %  FINAL REPORT
    %  ════════════════════════════════════════════════════════════════════

    elapsed = toc(t_start);

    fprintf('\n══════════════════════════════════════════════════════════════\n');
    fprintf('  FULL ANALYSIS PIPELINE — REPORT\n');
    fprintf('══════════════════════════════════════════════════════════════\n\n');

    fprintf('  %-45s  %-8s  %8s\n', 'Step', 'Status', 'Time');
    fprintf('  %-45s  %-8s  %8s\n', repmat('-',1,45), '--------', '--------');

    n_ok = 0;  n_fail = 0;  n_skip = 0;

    for ri = 1:nSteps
        if ~status_ran(ri)
            tag = 'SKIP';
            n_skip = n_skip + 1;
        elseif status_ok(ri)
            tag = 'OK';
            n_ok = n_ok + 1;
        else
            tag = 'FAIL';
            n_fail = n_fail + 1;
        end
        fprintf('  %-45s  %-8s  %6.1f s\n', status_names{ri}, tag, status_time(ri));
    end

    fprintf('\n  Ran: %d | Passed: %d | Failed: %d | Skipped: %d\n', ...
        n_ok + n_fail, n_ok, n_fail, n_skip);

    if n_fail > 0
        fprintf('\n  Failed steps:\n');
        for ri = 1:nSteps
            if status_ran(ri) && ~status_ok(ri)
                fprintf('    [%d] %s: %s\n', ri, status_names{ri}, status_errmsg{ri});
            end
        end
        fprintf('\n  TIP: Resume with run_all_analysis(''StartAt'', <step>)\n');
    end

    fprintf('\n  Total time: %.1f minutes (%.0f seconds)\n', elapsed/60, elapsed);
    fprintf('  Finished: %s\n', datestr(now));
    fprintf('══════════════════════════════════════════════════════════════\n');
end


%% ========================================================================
%  run_isolated — Execute a script inside its own function workspace
%  so that the child script's clear/clc cannot wipe our variables.
%  ========================================================================
function run_isolated(script_name)
    eval(script_name);
end
