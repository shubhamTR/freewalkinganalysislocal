function batch_preprocessing_complete_local(analysis_dir, varargin)
% DEPRECATED — Use batch_preprocessing_manual_local() instead.
%   This function is kept for backward compatibility only.
%   batch_preprocessing_manual_local() delegates to arena_led_pipeline_local()
%   with protocol-aware NumLEDs, genotype filtering, and LED position carry-forward.
%
% BATCH_PREPROCESSING_COMPLETE - Arena calibration and LED detection
%
% Uses arena_led_pipeline to process all experiments
%
% USAGE:
%   batch_preprocessing_complete(analysis_dir)
    warning('batch_preprocessing_complete_local:deprecated', ...
        'DEPRECATED: Use batch_preprocessing_manual_local() instead.');

    p = inputParser;
    addParameter(p, 'Protocol', '', @ischar);
    addParameter(p, 'UseFlyTrackerCalib', true, @islogical);
    addParameter(p, 'RecomputeAll', false, @islogical);
    addParameter(p, 'Verbose', true, @islogical);
    parse(p, varargin{:});
    
    opts = p.Results;
    
    fprintf('\n========================================\n');
    fprintf('BATCH PREPROCESSING\n');
    fprintf('========================================\n\n');
    
    % Find experiments
    experiments = find_all_experiments(analysis_dir, opts.Protocol);
    
    if isempty(experiments)
        fprintf('No experiments found.\n');
        return;
    end
    
    fprintf('Found %d experiments\n\n', length(experiments));
    
    saved_calib = [];
    processed = 0;
    skipped = 0;
    
    for i = 1:length(experiments)
        exp_path = experiments{i};
        
        try
            % Check if already preprocessed
            if ~opts.RecomputeAll && is_preprocessed(exp_path)
                fprintf('[%d/%d] Already preprocessed: %s\n', i, length(experiments), basename(exp_path));
                skipped = skipped + 1;
                continue;
            end
            
            fprintf('[%d/%d] %s\n', i, length(experiments), basename(exp_path));
            
            % Run arena_led_pipeline
            if isempty(saved_calib)
                % First experiment - may need user input
                results = arena_led_pipeline_local(exp_path, 'UseFlyTrackerCalib', opts.UseFlyTrackerCalib);
                
                % Ask to reuse calibration
                if i < length(experiments)
                    response = input('  Use this calibration for remaining experiments? (y/n): ', 's');
                    if strcmpi(response, 'y')
                        saved_calib = results.arena_calib;
                    end
                end
            else
                % Use saved calibration
                results = apply_saved_calibration_to_experiment(exp_path, saved_calib);
            end
            
            fprintf('  ✓ Preprocessed\n');
            processed = processed + 1;
            
        catch ME
            fprintf('  ✗ Error: %s\n', ME.message);
        end
    end
    
    fprintf('\n========================================\n');
    fprintf('PREPROCESSING SUMMARY\n');
    fprintf('========================================\n');
    fprintf('Total: %d\n', length(experiments));
    fprintf('Processed: %d\n', processed);
    fprintf('Skipped: %d\n', skipped);
    fprintf('========================================\n\n');
end

function experiments = find_all_experiments(analysis_dir, protocol_filter)
    experiments = {};
    
    if isempty(protocol_filter)
        protocols = dir(fullfile(analysis_dir, 'P*'));
        protocols = protocols([protocols.isdir]);
        protocols = protocols(~cellfun('isempty', regexp({protocols.name}, '^P\d+$', 'once')));
        protocols = {protocols.name};
    else
        protocols = {protocol_filter};
    end
    
    for p = 1:length(protocols)
        prot_path = fullfile(analysis_dir, protocols{p});
        if ~exist(prot_path, 'dir'), continue; end
        
        exp_dirs = dir(prot_path);
        exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..', 'Summary_Plots'}));
        
        for e = 1:length(exp_dirs)
            exp_path = fullfile(prot_path, exp_dirs(e).name);
            if exist(fullfile(exp_path, 'trx.mat'), 'file')
                experiments{end+1} = exp_path;
            end
        end
    end
end

function is_done = is_preprocessed(exp_path)
    analysis_dir = fullfile(exp_path, 'analysis');
    if ~exist(analysis_dir, 'dir')
        is_done = false;
        return;
    end
    
    has_arena = ~isempty(dir(fullfile(analysis_dir, 'arena_calib_*.mat')));
    has_led = ~isempty(dir(fullfile(analysis_dir, 'LED_detector_*.mat')));
    is_done = has_arena && has_led;
end

function results = apply_saved_calibration_to_experiment(exp_path, saved_calib)
    % Apply saved calibration without user interaction

    % Create analysis directory
    analysis_dir = fullfile(exp_path, 'analysis');
    if ~exist(analysis_dir, 'dir')
        mkdir(analysis_dir);
    end

    % LED detection from video
    network_root = '/Volumes/ReiserLab/Shubham/Projects/2026/Feature learning/Board4';
    LED_detector = detect_LED_from_video(exp_path, network_root, ...
        'NumLEDs', 3, 'ShowPlots', false, 'SaveResults', false);
    
    % Save files with timestamp
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    
    arena_calib = saved_calib;
    save(fullfile(analysis_dir, sprintf('arena_calib_%s.mat', timestamp)), 'arena_calib');
    save(fullfile(analysis_dir, sprintf('LED_detector_%s.mat', timestamp)), 'LED_detector');

    results.arena_calib = arena_calib;
    results.LED_detector = LED_detector;
end

function LED_detector = process_indicator_data(ind_file)
    ind_data = load(ind_file);
    analog_signal = ind_data.analog_led_signal;
    iLED = ind_data.indicatorLED;
    nframes = numel(analog_signal);
    
    % Build LED state
    if isfield(iLED, 'indicatordigital')
        LED_state = iLED.indicatordigital(:) > 0;
    elseif isfield(iLED, 'starton') && isfield(iLED, 'endon')
        LED_state = false(nframes, 1);
        for k = 1:numel(iLED.starton)
            s = max(1, iLED.starton(k));
            e = min(nframes, iLED.endon(k));
            LED_state(s:e) = true;
        end
    else
        LED_state = analog_signal(:) > mean(analog_signal);
    end
    
    % Detect transitions
    on_times = find(diff(LED_state) == 1) + 1;
    off_times = find(diff(LED_state) == -1) + 1;
    
    max_frame = numel(LED_state);
    on_times(on_times > max_frame) = [];
    off_times(off_times > max_frame) = [];
    
    LED_detector = struct();
    LED_detector.LED_state = LED_state;
    LED_detector.on_times = on_times;
    LED_detector.off_times = off_times;
end

function name = basename(path)
    [~, name] = fileparts(path);
end