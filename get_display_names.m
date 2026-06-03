function [prot_display, geno_display] = get_display_names()
% GET_DISPLAY_NAMES  Canonical display-name maps for protocols and genotypes.
%
%   [prot_display, geno_display] = get_display_names()
%
%   Returns containers.Map objects mapping internal protocol/genotype codes
%   to human-readable display names for plot titles and legends.
%
%   Use with map_or_default(map, key) to safely look up names.

    prot_display = containers.Map();
    prot_display('P008') = 'Coupled';
    prot_display('P010') = 'Dark';
    prot_display('P011') = 'Uncoupled';
    prot_display('P017') = 'Coupled';
    prot_display('P019') = 'Dark';
    prot_display('P023') = 'Uncoupled';
    prot_display('P024') = 'Random Decoupled';
    prot_display('P025') = 'Coupled (Low Intensity)';

    geno_display = containers.Map();
    geno_display('L2A') = 'HotCell';
end
