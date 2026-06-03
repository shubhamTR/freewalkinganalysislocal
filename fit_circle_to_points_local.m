function [xc, yc, radius] = fit_circle_to_points_local(x, y)
% FIT_CIRCLE_TO_POINTS - Least squares circle fit
%
% USAGE:
%   [xc, yc, radius] = fit_circle_to_points(x, y)

    n = length(x);
    
    % Build matrix
    A = [x(:), y(:), ones(n, 1)];
    b = -(x(:).^2 + y(:).^2);
    
    % Solve
    params = A \ b;
    
    % Extract circle
    xc = -params(1) / 2;
    yc = -params(2) / 2;
    radius = sqrt(xc^2 + yc^2 - params(3));
end