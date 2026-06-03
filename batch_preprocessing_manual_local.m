
function batch_preprocessing_manual_local(analysis_dir, varargin)
% BATCH_PREPROCESSING_MANUAL_LOCAL  Arena calibration + LED detection for local pipeline
%
%   Delegates to arena_led_pipeline_local() for each experiment.
%   Handles protocol-aware NumLEDs, calibration reuse, LED position
%   carry-forward, and protocol/genotype filtering.
%
%   USAGE
%     batch_preprocessing_manual_local(analysis_dir)
%     batch_preprocessing_manual_local(analysis_dir, 'Protocol', 'P019')
%     batch_preprocessing_manual_local(analysis_dir, 'RecomputeAll', true)
%
%   NAME-VALUE PARAMETERS
%     'Protocol'         — filter to one protocol (default: '' = all)
%     'Genotype'         — filter to one genotype (default: '' = all)
%     'SavedCalibration' — path to saved arena_calib .mat (default: '' = manual click)
%     'RecomputeAll'     — force reprocessing (default: false)
%     'NetworkRoot'      — network path to video root
%                          (default: '/Volumes/ReiserLab/Shubham/Projects/Feature learning/2026/board4/videos')
%     'SavedLEDPos'      — [Nx2] saved LED positions to skip clicking (default: [])

    p = inputParser;
    addParameter(p, 'Protocol', '', @ischar);
    addParameter(p, 'Genotype', '', @ischar);
    addParameter(p, 'SavedCalibration', '', @ischar);
    addParameter(p, 'RecomputeAll', false, @islogical);
    addParameter(p, 'NetworkRoot', '/Volumes/ReiserLab/Shubham/Projects/Feature learning/2026/board4/videos', @ischar);
    addParameter(p, 'SavedLEDPos', [], @isnumeric);
    parse(p, varargin{:});

    opts = p.Results;

    fprintf('\n========================================\n');
    fprintf('BATCH PREPROCESSING (LOCAL)\n');
    fprintf('========================================\n\n');

    experiments = find_all_experiments(analysis_dir, opts.Protocol, opts.Genotype);

    if isempty(experiments)
        fprintf('No experiments.\n');
        return;
    end

    fprintf('Found %d experiments\n\n', length(experiments));

    % Load saved arena calibration if provided
    saved_calib = [];
    if ~isempty(opts.SavedCalibration) && exist(opts.SavedCalibration, 'file')
        tmp = load(opts.SavedCalibration);
        if isfield(tmp, 'arena_calib')
            saved_calib = tmp.arena_calib;
        elseif isfield(tmp, 'saved_calib')
            saved_calib = tmp.saved_calib;
        else
            warning('SavedCalibration file does not contain arena_calib or saved_calib');
        end
        if ~isempty(saved_calib)
            fprintf('Using saved calibration from file\n\n');
        end
    end

    % Track saved LED positions across experiments
    saved_led_pos = opts.SavedLEDPos;

    processed = 0;
    skipped = 0;
    failed = 0;

    for i = 1:length(experiments)
        exp_path = experiments{i};

        try
            fprintf('[%d/%d] %s\n', i, length(experiments), basename(exp_path));

            % Determine NumLEDs from protocol (P001 = 3 RGB LEDs, all others = 1)
            [~, protocol_name] = fileparts(fileparts(exp_path));
            if strcmp(protocol_name, 'P001')
                num_leds = 3;
            else
                num_leds = 1;
            end

            % If RecomputeAll, clear existing analysis to force reprocessing
            % (arena_led_pipeline_local has per-step skip logic that checks
            %  for existing arena_calib_*.mat and LED_detector_*.mat)
            if opts.RecomputeAll
                ad = fullfile(exp_path, 'analysis');
                if exist(ad, 'dir')
                    delete(fullfile(ad, 'arena_calib_*.mat'));
                    delete(fullfile(ad, 'LED_detector_*.mat'));
                    delete(fullfile(ad, 'background_*.png'));
                    delete(fullfile(ad, 'quadrant_masks_*.png'));
                    delete(fullfile(ad, 'quadrant_masks_*.fig'));
                end
            end

            % Delegate to arena_led_pipeline_local
            results = arena_led_pipeline_local(exp_path, opts.NetworkRoot, ...
                'NumLEDs',     num_leds, ...
                'SavedLEDPos', saved_led_pos, ...
                'SavedCalib',  saved_calib, ...
                'ShowPlots',   false);

            % Handle skipped experiments
            if isfield(results, 'skipped') && results.skipped
                fprintf('  → Already preprocessed (skipped)\n\n');
                skipped = skipped + 1;
            else
                % After first manual calibration, offer to reuse
                if isempty(saved_calib) && i < length(experiments)
                    response = input('  Use this calibration for remaining experiments? (y/n): ', 's');
                    if strcmpi(response, 'y')
                        saved_calib = results.arena_calib;

                        response2 = input('  Save permanently? (y/n): ', 's');
                        if strcmpi(response2, 'y')
                            arena_calib = results.arena_calib; %#ok<NASGU>
                            save(fullfile(analysis_dir, 'saved_manual_calibration.mat'), 'arena_calib');
                            fprintf('  Saved to %s\n', fullfile(analysis_dir, 'saved_manual_calibration.mat'));
                        end
                    end
                end

                % Carry forward LED positions for subsequent experiments
                if isfield(results.LED_detector, 'LED_positions') && ...
                        ~isempty(results.LED_detector.LED_positions)
                    saved_led_pos = results.LED_detector.LED_positions;
                end

                fprintf('  ✓\n\n');
                processed = processed + 1;
            end

        catch ME
            fprintf('  ✗ %s\n\n', ME.message);
            failed = failed + 1;
        end
    end

    fprintf('========================================\n');
    fprintf('Done: %d processed, %d skipped, %d failed\n', processed, skipped, failed);
    fprintf('========================================\n\n');
end

function experiments = find_all_experiments(analysis_dir, pf, gf)
    experiments = {};

    if isempty(pf)
        pd = dir(fullfile(analysis_dir, 'P*'));
        pd = pd([pd.isdir]);
        pd = pd(~cellfun('isempty', regexp({pd.name}, '^P\d+$', 'once')));
        protocols = {pd.name};
    else
        protocols = {pf};
    end

    for p = 1:length(protocols)
        pp = fullfile(analysis_dir, protocols{p});
        if ~exist(pp, 'dir'), continue; end

        ed = dir(pp);
        ed = ed([ed.isdir] & ~ismember({ed.name}, {'.', '..', 'Summary_Plots'}));

        for e = 1:length(ed)
            if ~isempty(gf) && ~startsWith(ed(e).name, [gf, '_'])
                continue;
            end

            ep = fullfile(pp, ed(e).name);
            if exist(fullfile(ep, 'trx.mat'), 'file')
                experiments{end+1} = ep; %#ok<AGROW>
            end
        end
    end
end

function name = basename(path)
    [~, name] = fileparts(path);
end
