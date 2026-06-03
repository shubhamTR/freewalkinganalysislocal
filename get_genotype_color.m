function [col, block_ramp, probe_ramp] = get_genotype_color(geno)
% GET_GENOTYPE_COLOR  Consistent genotype → color mapping across all plotters.
%
%   col = get_genotype_color('L1')        — returns base RGB color
%   [col, block_ramp, probe_ramp] = get_genotype_color('L1')
%       block_ramp: 4×3 matrix, light→dark shades for training blocks 1–4
%       probe_ramp: 5×3 matrix, [PP_grey; block1; block2; block3; block4]
%
%   Genotype mapping:
%       L1  → Blue        L2A → Red        L3A → Green
%       L0  → Grey        L3C → Orange     (others → Purple fallback)

    switch upper(geno)
        case 'L1'
            col = [0.00 0.45 0.70];                                  % blue
            block_ramp = [0.65 0.82 1.00;                            % light blue
                          0.30 0.60 0.90;
                          0.10 0.38 0.72;
                          0.00 0.20 0.50];                           % dark blue
        case 'L2A'
            col = [0.80 0.20 0.20];                                  % red
            block_ramp = [1.00 0.70 0.70;                            % light red
                          0.90 0.35 0.35;
                          0.72 0.15 0.15;
                          0.45 0.00 0.00];                           % dark red
        case 'L3A'
            col = [0.20 0.60 0.20];                                  % green
            block_ramp = [0.70 0.92 0.70;                            % light green
                          0.35 0.75 0.35;
                          0.15 0.55 0.15;
                          0.00 0.32 0.00];                           % dark green
        case 'L0'
            col = [0.40 0.40 0.40];                                  % grey
            block_ramp = [0.82 0.82 0.82;
                          0.60 0.60 0.60;
                          0.38 0.38 0.38;
                          0.18 0.18 0.18];
        case 'L3C'
            col = [0.70 0.40 0.00];                                  % orange
            block_ramp = [1.00 0.82 0.65;
                          0.90 0.58 0.28;
                          0.72 0.40 0.10;
                          0.50 0.25 0.00];
        otherwise
            col = [0.55 0.35 0.65];                                  % purple fallback
            block_ramp = [0.80 0.70 0.88;
                          0.60 0.42 0.72;
                          0.45 0.25 0.58;
                          0.30 0.12 0.42];
    end

    % Probe ramp: grey for PP, then block ramp colours
    if nargout >= 3
        probe_ramp = [0.60 0.60 0.60; block_ramp];
    end
end
