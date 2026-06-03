function [nCopied, nFailed, nSkipped] = copy_and_organize_flydisco_local(srcRoot, dstRoot, varargin)
% COPY_AND_ORGANIZE_FLYDISCO - Copy from network and organize by protocol
%
% USAGE:
%   copy_and_organize_flydisco(srcRoot, dstRoot)

    if nargin < 2
        error('copy_and_organize_flydisco requires srcRoot and dstRoot as inputs.');
    end

    p = inputParser;
    addParameter(p, 'TargetFiles', {...
        'movie-bg.mat', ...
        'trx.mat', ...
        'movie-calibration.mat', ...
        'movie-params.mat', ...
        }, @iscell);
    addParameter(p, 'LogDir', '', @ischar);
    addParameter(p, 'Verbose', true, @islogical);
    parse(p, varargin{:});
    
    opts = p.Results;
    
    % Fall back to dstRoot if LogDir was not specified
    if isempty(opts.LogDir)
        opts.LogDir = dstRoot;
    end
    
    % Create destination directory
    if ~exist(dstRoot, 'dir')
        fprintf('Creating destination: %s\n', dstRoot);
        mkdir(dstRoot);
    end
    
    % Create log directory
    if ~exist(opts.LogDir, 'dir')
        mkdir(opts.LogDir);
    end
    
    % Open log file
    log_file = fullfile(opts.LogDir, sprintf('copy_log_%s.txt', datestr(now, 'yyyymmdd_HHMMSS')));
    log_fid = fopen(log_file, 'w');
    
    % Header
    header = sprintf([...
        '\n========================================\n', ...
        'NETWORK COPY AND REORGANIZATION\n', ...
        '========================================\n', ...
        'Started: %s\n', ...
        'Source: %s\n', ...
        'Destination: %s\n', ...
        'Mode: %s\n', ...
        '========================================\n\n'], ...
        datestr(now), srcRoot, dstRoot, 'Destination-based');

    fprintf('%s', header);
    fprintf(log_fid, '%s', header);

    % Scan source
    fprintf('Scanning source...\n');
    fprintf(log_fid, 'Scanning source...\n');

    exp_folders = dir(fullfile(srcRoot, '*_*_*_P*'));
    exp_folders = exp_folders([exp_folders.isdir]);

    % Also search Rig subfolders
    rig_folders = dir(fullfile(srcRoot, 'Rig*'));
    rig_folders = rig_folders([rig_folders.isdir]);

    for r = 1:length(rig_folders)
        rig_path = fullfile(srcRoot, rig_folders(r).name);
        rig_exps = dir(fullfile(rig_path, '*_*_*_P*'));
        rig_exps = rig_exps([rig_exps.isdir]);
        exp_folders = [exp_folders; rig_exps];
    end

    fprintf('Found %d experiments on source\n\n', length(exp_folders));
    fprintf(log_fid, 'Found %d experiments on source\n\n', length(exp_folders));
    
    if isempty(exp_folders)
        fprintf('No new experiments!\n');
        fprintf(log_fid, 'No new experiments!\n');
        fclose(log_fid);
        nCopied = 0;
        nFailed = 0;
        nSkipped = 0;
        return;
    end
    
    % Initialize counters
    nCopied = 0;
    nFailed = 0;
    nSkipped = 0;
    
    start_time = tic;
    
    % Process each experiment
    for i = 1:length(exp_folders)
        folder_name = exp_folders(i).name;
        source_path = fullfile(exp_folders(i).folder, folder_name);
        
        try
            fprintf('[%d/%d] %s\n', i, length(exp_folders), folder_name);
            fprintf(log_fid, '[%d/%d] %s\n', i, length(exp_folders), folder_name);
            
            % Parse: YYYYMMDD_HHMMSS_Genotype_PXXX
            [timestamp, genotype, protocol, rig] = parse_experiment_folder(folder_name, source_path);

            if isempty(protocol)
                fprintf('  ✗ Parse failed\n');
                fprintf(log_fid, '  ERROR: Parse failed\n');
                nFailed = nFailed + 1;
                continue;
            end

            % Skip untracked experiments (no trx.mat anywhere in source)
            if isempty(dir(fullfile(source_path, '**', 'trx.mat')))
                fprintf('  → Not yet tracked (no trx.mat), skipping\n');
                fprintf(log_fid, '  SKIPPED: No trx.mat\n');
                nSkipped = nSkipped + 1;
                continue;
            end
            
            % New folder name: Genotype_Rig_YYYYMMDD_HHMMSS
            new_folder_name = sprintf('%s_%s_%s', genotype, rig, timestamp);
            
            % Target: Protocol/Genotype_Rig_Date_Time
            protocol_dir = fullfile(dstRoot, protocol);
            target_dir = fullfile(protocol_dir, new_folder_name);
            
            % Destination-based check: skip only if folder exists AND all target files present
            if exist(target_dir, 'dir')
                all_present = true;
                for f_chk = 1:length(opts.TargetFiles)
                    if ~exist(fullfile(target_dir, opts.TargetFiles{f_chk}), 'file')
                        all_present = false;
                        break;
                    end
                end
                if all_present
                    fprintf('  → Complete, skipping\n');
                    fprintf(log_fid, '  SKIPPED: Complete\n');
                    nSkipped = nSkipped + 1;
                    continue;
                else
                    fprintf('  → Incomplete destination, re-copying\n');
                    fprintf(log_fid, '  RE-COPY: Incomplete\n');
                    rmdir(target_dir, 's');
                end
            end
            
            % Create directories
            if ~exist(protocol_dir, 'dir')
                mkdir(protocol_dir);
            end
            mkdir(target_dir);
            
            % Copy files (search all subfolders recursively)
            files_copied = 0;
            for f = 1:length(opts.TargetFiles)
                % Search recursively for the file
                matches = dir(fullfile(source_path, '**', opts.TargetFiles{f}));
                if ~isempty(matches)
                    src = fullfile(matches(1).folder, matches(1).name);
                    dst = fullfile(target_dir, opts.TargetFiles{f});
                    copyfile(src, dst);
                    files_copied = files_copied + 1;
                end
            end
            
            % Copy perframe directory
            src_perframe = fullfile(source_path, 'perframe');
            if exist(src_perframe, 'dir')
                dst_perframe = fullfile(target_dir, 'perframe');
                mkdir(dst_perframe);
                copyfile(fullfile(src_perframe, '*'), dst_perframe);
                files_copied = files_copied + 1;
            end
            
            % Copy original metadata
            src_meta = fullfile(source_path, 'metadata.txt');
            if exist(src_meta, 'file')
                copyfile(src_meta, fullfile(target_dir, 'original_metadata.txt'));
            end
            
            % Create copy metadata
            create_copy_metadata(target_dir, source_path, folder_name, new_folder_name, ...
                timestamp, genotype, protocol, rig, files_copied);
            
            fprintf('  ✓ %d files → %s/%s\n', files_copied, protocol, new_folder_name);
            fprintf(log_fid, '  SUCCESS: %d files\n', files_copied);
            nCopied = nCopied + 1;
            
        catch ME
            fprintf('  ✗ %s\n', ME.message);
            fprintf(log_fid, '  ERROR: %s\n', ME.message);
            nFailed = nFailed + 1;
        end
    end
    
    % Cleanup: remove experiment folders missing any target files
    % SAFEGUARD: Only validate directories that look like experiment folders
    % (contain '_Rig' in their name). Summary directories, analysis output
    % folders, and any other non-experiment directories are NEVER touched.
    fprintf('\n--- Validating copied experiments ---\n');
    fprintf(log_fid, '\n--- Validating copied experiments ---\n');

    nRemoved = 0;
    protocol_dirs = dir(dstRoot);
    protocol_dirs = protocol_dirs([protocol_dirs.isdir] & ~ismember({protocol_dirs.name}, {'.', '..'}));

    % Protected directory name patterns — NEVER delete these
    PROTECTED_PATTERNS = {'summary', 'QPI', 'distance', 'latency', ...
        'dist_to_safe', 'speed', 'optomotor', 'trajectories', ...
        'probe', 'cumulative', 'occupancy'};

    for pd = 1:length(protocol_dirs)
        prot_path = fullfile(dstRoot, protocol_dirs(pd).name);
        exp_dirs = dir(prot_path);
        exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));

        for ed = 1:length(exp_dirs)
            dir_name = exp_dirs(ed).name;
            exp_path = fullfile(prot_path, dir_name);

            % SAFEGUARD: Only validate directories containing '_Rig' (experiment folders)
            if ~contains(dir_name, '_Rig')
                fprintf('  SKIPPING (not an experiment folder): %s/%s\n', ...
                    protocol_dirs(pd).name, dir_name);
                fprintf(log_fid, '  SKIPPED (not an experiment folder): %s/%s\n', ...
                    protocol_dirs(pd).name, dir_name);
                continue;
            end

            % SAFEGUARD: Double-check against protected patterns
            is_protected = false;
            for pp = 1:length(PROTECTED_PATTERNS)
                if contains(lower(dir_name), lower(PROTECTED_PATTERNS{pp}))
                    is_protected = true;
                    break;
                end
            end
            if is_protected
                fprintf('  SKIPPING (protected directory): %s/%s\n', ...
                    protocol_dirs(pd).name, dir_name);
                fprintf(log_fid, '  SKIPPED (protected directory): %s/%s\n', ...
                    protocol_dirs(pd).name, dir_name);
                continue;
            end

            % Check if all target files are present
            missing_files = {};
            for f = 1:length(opts.TargetFiles)
                if ~exist(fullfile(exp_path, opts.TargetFiles{f}), 'file')
                    missing_files{end+1} = opts.TargetFiles{f};
                end
            end

            if ~isempty(missing_files)
                fprintf('  REMOVING: %s/%s (missing: %s)\n', ...
                    protocol_dirs(pd).name, exp_dirs(ed).name, strjoin(missing_files, ', '));
                fprintf(log_fid, '  REMOVED: %s/%s (missing: %s)\n', ...
                    protocol_dirs(pd).name, exp_dirs(ed).name, strjoin(missing_files, ', '));
                rmdir(exp_path, 's');
                nRemoved = nRemoved + 1;
            end
        end

        % SAFEGUARD: Never remove protocol directories — only log if empty
        remaining = dir(prot_path);
        remaining = remaining([remaining.isdir] & ~ismember({remaining.name}, {'.', '..'}));
        if isempty(remaining)
            fprintf('  WARNING: Protocol folder is empty (NOT removing): %s\n', protocol_dirs(pd).name);
            fprintf(log_fid, '  WARNING: Protocol folder is empty (NOT removing): %s\n', protocol_dirs(pd).name);
        end
    end

    fprintf('Removed %d incomplete experiments\n', nRemoved);
    fprintf(log_fid, 'Removed %d incomplete experiments\n', nRemoved);

    elapsed = toc(start_time);

    % Summary
    summary = sprintf([...
        '\n========================================\n', ...
        'COPY SUMMARY\n', ...
        '========================================\n', ...
        'Total: %d\n', ...
        'Copied: %d\n', ...
        'Skipped: %d\n', ...
        'Failed: %d\n', ...
        'Removed (incomplete): %d\n', ...
        'Time: %.1f min\n', ...
        '========================================\n\n'], ...
        length(exp_folders), nCopied, nSkipped, nFailed, nRemoved, elapsed/60);

    fprintf('%s', summary);
    fprintf(log_fid, '%s', summary);
    fclose(log_fid);
end

function [timestamp, genotype, protocol, rig] = parse_experiment_folder(folder_name, folder_path)
    % Match: YYYYMMDD_HHMMSS_Genotype_PXXX  or  YYYYMMDD_HHMMSS_Genotype_PXXX_suffix
    pattern = '^(\d{8}_\d{6})_(.+)_(P\d+)(_\w+)?$';
    tokens = regexp(folder_name, pattern, 'tokens');

    if isempty(tokens)
        timestamp = '';
        genotype = '';
        protocol = '';
        rig = '';
        return;
    end

    timestamp = tokens{1}{1};
    genotype = tokens{1}{2};
    protocol = tokens{1}{3};
    
    [parent_path, ~] = fileparts(folder_path);
    [~, parent_name] = fileparts(parent_path);
    
    rig_pattern = '^Rig(\d+)$';
    rig_tokens = regexp(parent_name, rig_pattern, 'tokens');
    
    if ~isempty(rig_tokens)
        rig = parent_name;
    else
        metadata_file = fullfile(folder_path, 'metadata.txt');
        if exist(metadata_file, 'file')
            rig = extract_rig_from_metadata(metadata_file);
        else
            rig = 'RigUnknown';
        end
    end
end

function rig = extract_rig_from_metadata(metadata_file)
    try
        fid = fopen(metadata_file, 'r');
        if fid == -1
            rig = 'RigUnknown';
            return;
        end
        
        rig = 'RigUnknown';
        while ~feof(fid)
            line = fgetl(fid);
            if contains(line, 'Rig Number:')
                tokens = regexp(line, 'Rig Number:\s*(\d+)', 'tokens');
                if ~isempty(tokens)
                    rig = sprintf('Rig%s', tokens{1}{1});
                    break;
                end
            end
        end
        fclose(fid);
    catch
        rig = 'RigUnknown';
    end
end

function create_copy_metadata(target_dir, source_path, original_name, new_name, ...
    timestamp, genotype, protocol, rig, files_copied)
    
    meta_file = fullfile(target_dir, 'copy_metadata.txt');
    fid = fopen(meta_file, 'w');
    
    fprintf(fid, '========================================\n');
    fprintf(fid, 'NETWORK COPY METADATA\n');
    fprintf(fid, '========================================\n\n');
    fprintf(fid, 'Protocol: %s\n', protocol);
    fprintf(fid, 'Genotype: %s\n', genotype);
    fprintf(fid, 'Rig: %s\n', rig);
    fprintf(fid, 'Timestamp: %s\n\n', timestamp);
    fprintf(fid, 'Original Folder: %s\n', original_name);
    fprintf(fid, 'Renamed To: %s\n\n', new_name);
    fprintf(fid, 'Source Path: %s\n', source_path);
    fprintf(fid, 'Copy Date: %s\n', datestr(now));
    fprintf(fid, 'Files Copied: %d\n', files_copied);
    fprintf(fid, '========================================\n');
    
    fclose(fid);
end

function result = ternary(c, t, f)
    if c, result = t; else, result = f; end
end