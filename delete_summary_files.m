%% delete_summary_files.m
% Lists all summary .mat files and stale velocity PNG files across
% protocol folders and lets you selectively delete them before
% re-running batch scripts.
%
% Targets:
%   .mat — distance_summary_*.mat, latency_summary_*.mat, QPI_summary_*.mat
%   .png — vel_allcycles_*, vel_blocks_*, vel_probes_*,
%           delta_vel_onset_*, velocity_intensity_*
%
% Author: Shubham Rathore

clear; clc;

ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

%% Find all summary .mat files and stale velocity PNGs
protocol_dirs = dir(fullfile(ANALYSIS_DIR, 'P*'));
protocol_dirs = protocol_dirs([protocol_dirs.isdir]);

all_files = {};
for p = 1:length(protocol_dirs)
    prot_path = fullfile(ANALYSIS_DIR, protocol_dirs(p).name);

    % Summary .mat files
    mat_patterns = {'distance_summary_*.mat', 'latency_summary_*.mat', 'QPI_summary_*.mat'};
    for pi = 1:length(mat_patterns)
        matches = dir(fullfile(prot_path, mat_patterns{pi}));
        for m = 1:length(matches)
            all_files{end+1} = fullfile(prot_path, matches(m).name); 
        end
    end

    % Stale velocity PNG files (no longer generated)
    vel_patterns = {'vel_allcycles_*.png', 'vel_blocks_*.png', 'vel_probes_*.png', ...
                    'delta_vel_onset_*.png', 'velocity_intensity_*.png'};
    for pi = 1:length(vel_patterns)
        matches = dir(fullfile(prot_path, vel_patterns{pi}));
        for m = 1:length(matches)
            all_files{end+1} = fullfile(prot_path, matches(m).name); 
        end
    end
end

if isempty(all_files)
    fprintf('No summary .mat or stale velocity .png files found in %s\n', ANALYSIS_DIR);
    return;
end

%% Display numbered list
fprintf('\n=== Files found ===\n\n');
for i = 1:length(all_files)
    [~, fname, ext] = fileparts(all_files{i});
    % Show protocol folder + filename for clarity
    parts = strsplit(all_files{i}, filesep);
    prot_folder = parts{end-1};
    fprintf('  [%2d]  %s / %s%s\n', i, prot_folder, fname, ext);
end
fprintf('\n  Total: %d files\n\n', length(all_files));

%% Prompt for selection
fprintf('Options:\n');
fprintf('  - Enter numbers separated by spaces (e.g. "1 3 5") to delete specific files\n');
fprintf('  - Enter "all" to delete all listed files\n');
fprintf('  - Enter "q" to quit without deleting\n\n');

reply = input('Your choice: ', 's');
reply = strtrim(reply);

if strcmpi(reply, 'q') || isempty(reply)
    fprintf('No files deleted.\n');
    return;
end

if strcmpi(reply, 'all')
    to_delete = 1:length(all_files);
else
    to_delete = str2num(reply); %#ok<ST2NM>
    if isempty(to_delete)
        fprintf('Could not parse input — no files deleted.\n');
        return;
    end
    to_delete = to_delete(to_delete >= 1 & to_delete <= length(all_files));
end

%% Confirm
fprintf('\nFiles to delete:\n');
for i = 1:length(to_delete)
    idx = to_delete(i);
    [~, fname, ext] = fileparts(all_files{idx});
    parts = strsplit(all_files{idx}, filesep);
    prot_folder = parts{end-1};
    fprintf('  %s / %s%s\n', prot_folder, fname, ext);
end

confirm = input(sprintf('\nDelete %d file(s)? (y/n): ', length(to_delete)), 's');
if ~strcmpi(strtrim(confirm), 'y')
    fprintf('Cancelled.\n');
    return;
end

%% Delete
deleted = 0;
for i = 1:length(to_delete)
    idx = to_delete(i);
    try
        delete(all_files{idx});
        [~, fname, ext] = fileparts(all_files{idx});
        fprintf('  Deleted: %s%s\n', fname, ext);
        deleted = deleted + 1;
    catch ME
        fprintf('  FAILED: %s — %s\n', all_files{idx}, ME.message);
    end
end

fprintf('\nDone: %d of %d files deleted.\n', deleted, length(to_delete));
fprintf('You can now re-run batch_distance_summary.m, batch_latency_summary.m, and/or batch_QPI_summary.m\n');
