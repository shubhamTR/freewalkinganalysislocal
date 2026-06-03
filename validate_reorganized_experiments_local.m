function validate_reorganized_experiments_local(analysis_dir, varargin)
% VALIDATE_REORGANIZED_EXPERIMENTS - Check fly counts in trx.mat
%
% USAGE:
%   validate_reorganized_experiments(analysis_dir)
%   validate_reorganized_experiments(analysis_dir, 'MinFlies', 1, 'MaxFlies', 15)

    p = inputParser;
    addParameter(p, 'MinFlies', 1, @isnumeric);
    addParameter(p, 'MaxFlies', 20, @isnumeric);
    parse(p, varargin{:});
    
    opts = p.Results;
    
    % Create log directory
    log_dir = fullfile(analysis_dir, 'Logs');
    if ~exist(log_dir, 'dir')
        mkdir(log_dir);
    end
    
    log_file = fullfile(log_dir, sprintf('fly_count_validation_%s.txt', datestr(now, 'yyyymmdd_HHMMSS')));
    log_fid = fopen(log_file, 'w');
    
    % Header
    header = sprintf([...
        '========================================\n', ...
        'FLY COUNT VALIDATION\n', ...
        '========================================\n', ...
        'Date: %s\n', ...
        'Directory: %s\n', ...
        'Acceptable range: %d-%d flies\n', ...
        '========================================\n\n'], ...
        datestr(now), analysis_dir, opts.MinFlies, opts.MaxFlies);
    
    fprintf('%s', header);
    fprintf(log_fid, '%s', header);
    
    % Find protocols
    protocols = dir(fullfile(analysis_dir, 'P*'));
    protocols = protocols([protocols.isdir]);
    
    total_exp = 0;
    valid_exp = 0;
    invalid_exp = 0;
    invalid_list = struct('exp_path', {}, 'num_flies', {}, 'reason', {});
    
    % Check each protocol
    for p = 1:length(protocols)
        protocol = protocols(p).name;
        protocol_path = fullfile(analysis_dir, protocol);
        
        fprintf('Protocol: %s\n', protocol);
        fprintf(log_fid, 'Protocol: %s\n', protocol);
        
        % Find experiments
        exp_folders = dir(protocol_path);
        exp_folders = exp_folders([exp_folders.isdir] & ~ismember({exp_folders.name}, {'.', '..', 'Summary_Plots'}));
        
        for e = 1:length(exp_folders)
            exp_name = exp_folders(e).name;
            exp_path = fullfile(protocol_path, exp_name);
            total_exp = total_exp + 1;
            
            % Check trx file
            trx_file = fullfile(exp_path, 'trx.mat');

            if ~exist(trx_file, 'file')
                fprintf('  ✗ %s - No trx file\n', exp_name);
                fprintf(log_fid, '  ✗ %s - MISSING trx\n', exp_name);
                invalid_exp = invalid_exp + 1;
                invalid_list(end+1).exp_path = exp_path;
                invalid_list(end).num_flies = 0;
                invalid_list(end).reason = 'Missing trx.mat';
                continue;
            end
            
            % Load and count flies
            try
                load(trx_file, 'trx');
                num_flies = length(trx);
                
                if num_flies < opts.MinFlies
                    fprintf('  ✗ %s - %d flies (too few)\n', exp_name, num_flies);
                    fprintf(log_fid, '  ✗ %s - %d flies (TOO FEW)\n', exp_name, num_flies);
                    invalid_exp = invalid_exp + 1;
                    invalid_list(end+1).exp_path = exp_path;
                    invalid_list(end).num_flies = num_flies;
                    invalid_list(end).reason = sprintf('Too few (%d < %d)', num_flies, opts.MinFlies);
                    
                elseif num_flies > opts.MaxFlies
                    fprintf('  ✗ %s - %d flies (too many)\n', exp_name, num_flies);
                    fprintf(log_fid, '  ✗ %s - %d flies (TOO MANY)\n', exp_name, num_flies);
                    invalid_exp = invalid_exp + 1;
                    invalid_list(end+1).exp_path = exp_path;
                    invalid_list(end).num_flies = num_flies;
                    invalid_list(end).reason = sprintf('Too many (%d > %d)', num_flies, opts.MaxFlies);
                    
                else
                    fprintf('  ✓ %s - %d flies\n', exp_name, num_flies);
                    fprintf(log_fid, '  ✓ %s - %d flies\n', exp_name, num_flies);
                    valid_exp = valid_exp + 1;
                end
                
            catch ME
                fprintf('  ✗ %s - Error: %s\n', exp_name, ME.message);
                fprintf(log_fid, '  ✗ %s - ERROR: %s\n', exp_name, ME.message);
                invalid_exp = invalid_exp + 1;
                invalid_list(end+1).exp_path = exp_path;
                invalid_list(end).num_flies = 0;
                invalid_list(end).reason = ME.message;
            end
        end
        
        fprintf('\n');
        fprintf(log_fid, '\n');
    end
    
    % Summary
    summary = sprintf([...
        '========================================\n', ...
        'VALIDATION SUMMARY\n', ...
        '========================================\n', ...
        'Total: %d\n', ...
        'Valid: %d (%.1f%%)\n', ...
        'Invalid: %d (%.1f%%)\n', ...
        '========================================\n\n'], ...
        total_exp, valid_exp, valid_exp/total_exp*100, ...
        invalid_exp, invalid_exp/total_exp*100);
    
    fprintf('%s', summary);
    fprintf(log_fid, '%s', summary);
    
    % List invalid experiments
    if invalid_exp > 0
        fprintf('Invalid Experiments:\n');
        fprintf(log_fid, 'Invalid Experiments:\n');
        
        for i = 1:length(invalid_list)
            detail = sprintf('  %d. %s (%d flies) - %s\n', ...
                i, basename(invalid_list(i).exp_path), ...
                invalid_list(i).num_flies, invalid_list(i).reason);
            fprintf('%s', detail);
            fprintf(log_fid, '%s', detail);
        end
        
        % Save
        invalid_file = fullfile(log_dir, 'invalid_fly_counts.mat');
        save(invalid_file, 'invalid_list');
        fprintf('\nSaved to: %s\n', invalid_file);
        fprintf(log_fid, '\nSaved to: %s\n', invalid_file);
    end
    
    fprintf('\nLog: %s\n\n', log_file);
    fclose(log_fid);
end

function name = basename(path)
    [~, name] = fileparts(path);
end