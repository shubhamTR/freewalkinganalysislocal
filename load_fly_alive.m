function fly_alive = load_fly_alive(analysis_dir, num_flies, num_cycles, trx, LED, varargin)
% LOAD_FLY_ALIVE  Load or compute dead fly status with standard fallback chain.
%
%   fly_alive = load_fly_alive(analysis_dir, num_flies, num_cycles, trx, LED)
%   fly_alive = load_fly_alive(..., 'FlyAlive', precomputed_matrix)
%   fly_alive = load_fly_alive(..., 'ConsecutiveCycles', 3, 'MoveThreshPx', 5)
%
%   Fallback chain:
%     1. Use 'FlyAlive' parameter if provided and non-empty
%     2. Load from dead_fly_report.mat in analysis_dir
%     3. Detect inline via detect_dead_flies_posture()
%
%   INPUTS
%     analysis_dir   — path to experiment's analysis/ folder
%     num_flies      — number of flies (for sizing)
%     num_cycles     — number of LED cycles (for sizing)
%     trx            — trx struct (needed for inline detection fallback)
%     LED            — LED_detector struct (needed for inline detection fallback)
%
%   NAME-VALUE PARAMETERS
%     'FlyAlive'           — precomputed [num_flies x num_cycles] logical (default: [])
%     'ConsecutiveCycles'  — dead fly detection window (default: 3)
%     'MoveThreshPx'       — dead fly pixel threshold (default: 5)
%
%   OUTPUT
%     fly_alive — [num_flies x num_cycles] logical matrix

    p = inputParser;
    addParameter(p, 'FlyAlive', [], @(x) islogical(x) || isempty(x));
    addParameter(p, 'ConsecutiveCycles', 3, @isnumeric);
    addParameter(p, 'MoveThreshPx', 5, @isnumeric);
    parse(p, varargin{:});

    fly_alive = p.Results.FlyAlive;

    % Fallback 1: passed-in value
    if ~isempty(fly_alive)
        fprintf('  Using provided fly_alive matrix\n');
        return;
    end

    % Fallback 2: dead_fly_report.mat
    dead_fly_file = fullfile(analysis_dir, 'dead_fly_report.mat');
    if exist(dead_fly_file, 'file')
        loaded = load(dead_fly_file, 'dead_report');
        fly_alive = loaded.dead_report.fly_alive;
        fprintf('  Using dead fly info from dead_fly_report.mat\n');
        return;
    end

    % Fallback 3: inline detection
    fprintf('  No dead fly source found — running detection\n');
    [fly_alive, ~] = detect_dead_flies_posture(trx, LED, ...
        'ConsecutiveCycles', p.Results.ConsecutiveCycles, ...
        'MoveThreshPx', p.Results.MoveThreshPx);
end
