function exclude_list = get_exclude_experiments()
% GET_EXCLUDE_EXPERIMENTS  Single source of truth for experiment exclusion list.
%
%   exclude_list = get_exclude_experiments()
%
%   Returns a cell array of experiment folder names that should be skipped
%   by all batch processing scripts. Add new entries here instead of
%   editing 7+ batch files individually.

    exclude_list = {
        'L3A_Rig1_20260315_130019'   % 03/15 replicate — anomalous
        'L2A_Rig1_20260514_120016'   % P017 — LED detector found 36/37 cycles, misaligned
        'L2A_Rig1_20260527_153048'   % P023 — 40 cycles detected instead of expected 37
    };
end
