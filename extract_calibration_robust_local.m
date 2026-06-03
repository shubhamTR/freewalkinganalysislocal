function pixels_per_mm = extract_calibration_robust_local(exp_path, trx)
% EXTRACT_CALIBRATION_ROBUST - Get pixels-per-mm from best available source
%
% Tries three sources in priority order:
%   1. trx(1).pxpermm  — set by FlyTracker during tracking
%   2. flytracker-calibration.mat  — calib.r (px) / calib.arena_r_mm (mm)
%   3. arena_calib radius / known arena size (assumes 63.5 mm radius arena)
%   4. Default fallback: 11.54 px/mm
%
% USAGE:
%   pixels_per_mm = extract_calibration_robust(exp_path, trx)
%
% INPUTS:
%   exp_path  — path to experiment folder
%   trx       — loaded trajectory struct array
%
% OUTPUT:
%   pixels_per_mm — calibration value (pixels per millimeter)

    DEFAULT_PXPERMM = 11.54;       % Fallback for HG1 rig
    ARENA_RADIUS_MM = 63.5;        % Known physical arena radius in mm

    % --- Source 1: trx struct field ---
    if isstruct(trx) && ~isempty(trx) && isfield(trx, 'pxpermm')
        val = trx(1).pxpermm;
        if ~isempty(val) && isfinite(val) && val > 0
            pixels_per_mm = val;
            fprintf('      Calibration: %.2f px/mm (from trx.pxpermm)\n', pixels_per_mm);
            return;
        end
    end

    % --- Source 2: flytracker-calibration.mat ---
    calib_file = fullfile(exp_path, 'flytracker-calibration.mat');
    if exist(calib_file, 'file')
        try
            ft = load(calib_file);
            if isfield(ft, 'calib')
                fc = ft.calib;
                if isfield(fc, 'r') && isfield(fc, 'arena_r_mm') && ...
                   fc.arena_r_mm > 0
                    pixels_per_mm = fc.r / fc.arena_r_mm;
                    fprintf('      Calibration: %.2f px/mm (from flytracker-calibration.mat)\n', pixels_per_mm);
                    return;
                elseif isfield(fc, 'r') && fc.r > 0
                    % Have pixel radius but no mm value — use known arena size
                    pixels_per_mm = fc.r / ARENA_RADIUS_MM;
                    fprintf('      Calibration: %.2f px/mm (flytracker radius / %.1f mm arena)\n', ...
                        pixels_per_mm, ARENA_RADIUS_MM);
                    return;
                end
            end
        catch ME
            fprintf('      Warning: Could not read flytracker calibration: %s\n', ME.message);
        end
    end

    % --- Source 3: arena_calib radius from preprocessing ---
    analysis_dir = fullfile(exp_path, 'analysis');
    arena_files = dir(fullfile(analysis_dir, 'arena_calib_*.mat'));
    if ~isempty(arena_files)
        try
            tmp = load(fullfile(analysis_dir, arena_files(1).name));
            if isfield(tmp, 'arena_calib') && isfield(tmp.arena_calib, 'radius')
                r_px = tmp.arena_calib.radius;
                if r_px > 0
                    pixels_per_mm = r_px / ARENA_RADIUS_MM;
                    fprintf('      Calibration: %.2f px/mm (arena_calib radius / %.1f mm arena)\n', ...
                        pixels_per_mm, ARENA_RADIUS_MM);
                    return;
                end
            end
        catch ME
            fprintf('      Warning: Could not read arena_calib: %s\n', ME.message);
        end
    end

    % --- Source 4: Default ---
    pixels_per_mm = DEFAULT_PXPERMM;
    fprintf('      Calibration: %.2f px/mm (DEFAULT — no calibration source found)\n', pixels_per_mm);
end
