function [fly_alive, dead_report] = detect_dead_flies_posture(trx, LED_detector, varargin)
% DETECT_DEAD_FLIES_POSTURE - Flag flies that stop moving during the experiment
%
% Uses a sliding-window approach: for each fly, examines N consecutive LED
% cycles. If the fly's maximum displacement from its mean position stays
% below a pixel threshold for the entire window, it is flagged as dead from
% that cycle onward.
%
% USAGE:
%   fly_alive = detect_dead_flies_posture(trx, LED_detector)
%   [fly_alive, dead_report] = detect_dead_flies_posture(trx, LED_detector, ...
%       'ConsecutiveCycles', 3, 'MoveThreshPx', 5)
%
% INPUTS:
%   trx            — trajectory struct array (filtered, full-span flies only)
%   LED_detector   — struct with .on_times, .off_times
%
% NAME-VALUE PARAMETERS:
%   'ConsecutiveCycles' — number of consecutive cycles in the sliding window
%                         (default: 3). A fly must be stationary for this
%                         many cycles before being flagged.
%   'MoveThreshPx'      — maximum displacement from mean position (in pixels)
%                         below which a fly is considered stationary
%                         (default: 5)
%   'MinValidFrames'    — minimum valid (non-NaN) frames in window to
%                         evaluate (default: 10)
%   'Verbose'           — print summary to console (default: true)
%
% OUTPUTS:
%   fly_alive   — [num_flies x num_cycles] logical matrix
%                  true = alive (include in analysis), false = dead (exclude)
%   dead_report — struct with fields:
%     .num_flies         — total number of flies evaluated
%     .num_dead          — number flagged dead by the final cycle
%     .num_alive         — number still alive at the final cycle
%     .dead_from_cycle   — [num_flies x 1] vector, cycle at which each fly
%                          was flagged dead (Inf if never flagged)
%     .consecutive_cycles — window size used
%     .move_thresh_px    — threshold used
%
% NOTES:
%   - This function does NOT modify trx or save any files.
%   - Call once per experiment, then pass fly_alive to compute functions.
%   - The algorithm is conservative: a fly must be stationary for the full
%     window before being removed. Brief pauses are not penalized.

    %% Parse inputs
    p = inputParser;
    addRequired(p, 'trx', @isstruct);
    addRequired(p, 'LED_detector', @isstruct);
    addParameter(p, 'ConsecutiveCycles', 3, @isnumeric);
    addParameter(p, 'MoveThreshPx', 5, @isnumeric);
    addParameter(p, 'MinValidFrames', 10, @isnumeric);
    addParameter(p, 'Verbose', true, @islogical);
    parse(p, trx, LED_detector, varargin{:});

    CONSECUTIVE_CYCLES = p.Results.ConsecutiveCycles;
    MOVE_THRESH_PX     = p.Results.MoveThreshPx;
    MIN_VALID_FRAMES   = p.Results.MinValidFrames;
    verbose            = p.Results.Verbose;

    on_times  = LED_detector.on_times;
    off_times = LED_detector.off_times;
    num_cycles = length(on_times);
    num_flies  = length(trx);
    nframes    = length(trx(1).x);

    %% Initialize: all flies assumed alive for all cycles
    fly_alive      = true(num_flies, num_cycles);
    dead_from_cycle = inf(num_flies, 1);

    %% Sliding window detection
    for k = 1:num_flies
        xk = trx(k).x;
        yk = trx(k).y;

        for w = 1:(num_cycles - CONSECUTIVE_CYCLES + 1)
            % Frame range spanning CONSECUTIVE_CYCLES cycles
            fr_start = on_times(w);
            fr_end   = min(off_times(w + CONSECUTIVE_CYCLES - 1), nframes);

            if fr_start > nframes || fr_end < fr_start
                continue;
            end

            x_win = xk(fr_start:fr_end);
            y_win = yk(fr_start:fr_end);

            % Only evaluate if enough valid (non-NaN) frames
            valid = ~isnan(x_win) & ~isnan(y_win);
            if sum(valid) < MIN_VALID_FRAMES
                continue;
            end

            % Compute max displacement from mean position
            mx = mean(x_win(valid));
            my = mean(y_win(valid));
            displacements = sqrt((x_win(valid) - mx).^2 + (y_win(valid) - my).^2);

            if max(displacements) < MOVE_THRESH_PX
                % Flag as dead from this cycle onward
                fly_alive(k, w:end) = false;
                dead_from_cycle(k) = w;
                break;  % no need to check later windows
            end
        end
    end

    %% Build report
    num_dead  = sum(~fly_alive(:, end));
    num_alive = num_flies - num_dead;

    dead_report = struct();
    dead_report.num_flies          = num_flies;
    dead_report.num_dead           = num_dead;
    dead_report.num_alive          = num_alive;
    dead_report.dead_from_cycle    = dead_from_cycle;
    dead_report.consecutive_cycles = CONSECUTIVE_CYCLES;
    dead_report.move_thresh_px     = MOVE_THRESH_PX;
    dead_report.fly_alive          = fly_alive;

    %% Console output
    if verbose
        if num_dead == 0
            fprintf('      Dead fly detection: all %d flies alive\n', num_flies);
        else
            fprintf('      Dead fly detection: %d/%d dead, %d alive\n', ...
                num_dead, num_flies, num_alive);
            for k = 1:num_flies
                if dead_from_cycle(k) < Inf
                    fprintf('        Fly %d: dead from cycle %d\n', k, dead_from_cycle(k));
                end
            end
        end
    end
end
