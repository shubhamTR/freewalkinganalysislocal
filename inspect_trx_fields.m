%% inspect_trx_fields.m
% Quick inspection of trx.mat structure and available fields
clear; clc;

exp_path = '/Users/rathores/Documents/analysisdatalocal/P008/L2A_Rig1_20260409_122638';
d = load(fullfile(exp_path, 'trx.mat'));
trx = d.trx;

fprintf('Number of flies: %d\n\n', length(trx));
fprintf('Fields in trx:\n');
fnames = fieldnames(trx);
for i = 1:length(fnames)
    val = trx(1).(fnames{i});
    if isnumeric(val) || islogical(val)
        fprintf('  %-25s  size=[%s]  class=%s  range=[%.4f, %.4f]\n', ...
            fnames{i}, num2str(size(val)), class(val), min(val(:)), max(val(:)));
    else
        fprintf('  %-25s  class=%s\n', fnames{i}, class(val));
    end
end

% Check theta specifically
if isfield(trx, 'theta')
    fprintf('\n--- theta for fly 1 ---\n');
    fprintf('  Length: %d\n', length(trx(1).theta));
    fprintf('  Min: %.4f rad (%.1f deg)\n', min(trx(1).theta), rad2deg(min(trx(1).theta)));
    fprintf('  Max: %.4f rad (%.1f deg)\n', max(trx(1).theta), rad2deg(max(trx(1).theta)));
    fprintf('  Mean: %.4f rad (%.1f deg)\n', mean(trx(1).theta), rad2deg(mean(trx(1).theta)));
    fprintf('  Std: %.4f rad (%.1f deg)\n', std(trx(1).theta), rad2deg(std(trx(1).theta)));

    % Angular velocity
    dtheta = diff(trx(1).theta);
    % Unwrap to handle wrapping around ±pi
    dtheta_unwrapped = diff(unwrap(trx(1).theta));
    fprintf('\n--- angular velocity (diff(theta)) fly 1 ---\n');
    fprintf('  Raw dtheta — mean: %.4f rad/frame, std: %.4f\n', mean(dtheta), std(dtheta));
    fprintf('  Unwrapped  — mean: %.4f rad/frame, std: %.4f\n', mean(dtheta_unwrapped), std(dtheta_unwrapped));
    fprintf('  Unwrapped  — mean: %.2f deg/s (at 30.1 fps)\n', rad2deg(mean(dtheta_unwrapped)) * 30.1);
else
    fprintf('\n  *** theta NOT found in trx ***\n');
end

% Also check if heading can be derived from x,y
fprintf('\n--- heading from x,y for fly 1 ---\n');
dx = diff(trx(1).x);
dy = diff(trx(1).y);
heading = atan2(dy, dx);
fprintf('  Length: %d\n', length(heading));
fprintf('  Min: %.4f rad (%.1f deg)\n', min(heading), rad2deg(min(heading)));
fprintf('  Max: %.4f rad (%.1f deg)\n', max(heading), rad2deg(max(heading)));
