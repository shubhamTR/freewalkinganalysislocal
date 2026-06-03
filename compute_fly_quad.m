function fly_quad = compute_fly_quad(trx, all_masks)
% COMPUTE_FLY_QUAD  Map each fly to its arena quadrant at every frame.
%
%   fly_quad = compute_fly_quad(trx, all_masks)
%
%   INPUTS
%     trx       — struct array from trx.mat (must have .x and .y fields)
%     all_masks — [H x W] quadrant mask image from arena_calib.all_masks
%                 (0 = outside arena, 1-4 = quadrant number)
%
%   OUTPUT
%     fly_quad  — [num_flies x nframes] matrix of quadrant assignments
%                 (0 = outside or NaN position, 1-4 = quadrant)

    num_flies = length(trx);
    nframes = length(trx(1).x);
    fly_quad = zeros(num_flies, nframes);

    for k = 1:num_flies
        x_inds = round(trx(k).x);
        y_inds = round(trx(k).y);
        for fr = 1:length(x_inds)
            xi = x_inds(fr);
            yi = y_inds(fr);
            if ~isnan(xi) && ~isnan(yi) && ...
               xi >= 1 && xi <= size(all_masks, 2) && ...
               yi >= 1 && yi <= size(all_masks, 1)
                fly_quad(k, fr) = all_masks(yi, xi);
            end
        end
    end
end
