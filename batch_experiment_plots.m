%% batch_experiment_plots.m
% Generate per-experiment distance and latency plots for place learning
% protocols. Loads existing summary .mat files and creates 3 plot types
% for each metric:
%
%   1. Training all-cycles  — all 40 training cycles with block shading
%   2. Training blocks      — block averages (B1–B4)
%   3. Probes               — PP + B1.P–B4.P
%
% Optomotor cycles are excluded. Pre-probe and probes are on separate
% plots from training.
%
% Plots are saved into each experiment's analysis/ subfolder.
%
% Requires: distance_summary_*.mat, latency_summary_*.mat
%           (run batch_distance_summary.m and batch_latency_summary.m first)
%
% Author: Shubham Rathore

clear; clc;

ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

%% Only process place learning protocols
PL_PROTOCOLS = {'P003', 'P005', 'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P014', 'P015', 'P016'};

protocol_dirs = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocol_dirs = protocol_dirs([protocol_dirs.isdir]);
protocol_dirs = protocol_dirs(~cellfun('isempty', regexp({protocol_dirs.name}, '^P\d+$', 'once')));

total_plots = 0;

for p = 1:length(protocol_dirs)
    prot_name = protocol_dirs(p).name;
    prot_path = fullfile(ANALYSIS_DIR, prot_name);

    if ~ismember(upper(prot_name), PL_PROTOCOLS)
        continue;
    end

    fprintf('\n=== %s ===\n', prot_name);

    %% Load distance summary
    dist_file = fullfile(prot_path, sprintf('distance_summary_%s.mat', prot_name));
    has_distance = exist(dist_file, 'file');
    if has_distance
        loaded = load(dist_file, 'distance_summary');
        dist_T = loaded.distance_summary;
        fprintf('  Distance summary: %d rows\n', height(dist_T));
    else
        fprintf('  No distance summary found — skipping distance plots\n');
        dist_T = table();
    end

    %% Load latency summary
    lat_file = fullfile(prot_path, sprintf('latency_summary_%s.mat', prot_name));
    has_latency = exist(lat_file, 'file');
    if has_latency
        loaded = load(lat_file, 'latency_summary');
        lat_T = loaded.latency_summary;
        fprintf('  Latency summary: %d rows\n', height(lat_T));
    else
        fprintf('  No latency summary found — skipping latency plots\n');
        lat_T = table();
    end

    %% Get list of experiments (union of distance + latency)
    exp_names = {};
    if ~isempty(dist_T)
        exp_names = unique(dist_T.experiment);
    end
    if ~isempty(lat_T)
        exp_names = unique([exp_names; unique(lat_T.experiment)]);
    end

    fprintf('  Experiments: %d\n', length(exp_names));

    %% Determine if P008 (for arena diameter line on distance plots)
    is_P008 = strcmpi(prot_name, 'P008');

    for e = 1:length(exp_names)
        exp_name = exp_names{e};
        exp_path = fullfile(prot_path, exp_name);
        save_dir = fullfile(exp_path, 'analysis');

        if ~exist(save_dir, 'dir')
            fprintf('  [%d/%d] %s — no analysis folder, skipping\n', e, length(exp_names), exp_name);
            continue;
        end

        fprintf('  [%d/%d] %s\n', e, length(exp_names), exp_name);

        %% ---- DISTANCE PLOTS ----
        if has_distance
            exp_dist = dist_T(strcmp(dist_T.experiment, exp_name), :);
            if ~isempty(exp_dist)
                dist_save = fullfile(save_dir, 'distance');
                if ~exist(dist_save, 'dir'), mkdir(dist_save); end

                common_dist = {'MeanCol', 'mean_dist_mm', 'SEMCol', 'sem_dist_mm', ...
                    'YLabel', 'Distance (mm)', 'SavePath', dist_save, 'ShowPlots', false};
                arena_args = {};
                if is_P008
                    arena_args = {'ArenaDiameterMM', 150};
                end

                % Training all-cycles
                plot_exp_training_allcycles_local(exp_dist, prot_name, ...
                    common_dist{:}, 'PlotName', 'dist_train_allcycles', ...
                    arena_args{:});

                % Training block averages
                plot_exp_training_blocks_local(exp_dist, prot_name, ...
                    common_dist{:}, 'PlotName', 'dist_train_blocks');

                % Probes
                plot_exp_probes_local(exp_dist, prot_name, ...
                    common_dist{:}, 'PlotName', 'dist_probes');

                total_plots = total_plots + 3;
            end
        end

        %% ---- LATENCY PLOTS ----
        if has_latency
            exp_lat = lat_T(strcmp(lat_T.experiment, exp_name), :);
            if ~isempty(exp_lat)
                lat_save = fullfile(save_dir, 'latency');
                if ~exist(lat_save, 'dir'), mkdir(lat_save); end

                common_lat = {'MeanCol', 'mean_latency_s', 'SEMCol', 'sem_latency_s', ...
                    'YLabel', 'Latency to dark quadrant (s)', ...
                    'SavePath', lat_save, 'ShowPlots', false};

                % Training all-cycles
                plot_exp_training_allcycles_local(exp_lat, prot_name, ...
                    common_lat{:}, 'PlotName', 'lat_train_allcycles');

                % Training block averages
                plot_exp_training_blocks_local(exp_lat, prot_name, ...
                    common_lat{:}, 'PlotName', 'lat_train_blocks');

                % Probes
                plot_exp_probes_local(exp_lat, prot_name, ...
                    common_lat{:}, 'PlotName', 'lat_probes');

                total_plots = total_plots + 3;
            end
        end
    end
end

fprintf('\n========================================\n');
fprintf('Done: %d plots saved  (%s)\n\n', total_plots, datestr(now));
