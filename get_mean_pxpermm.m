function pxpermm = get_mean_pxpermm(analysis_dir, protocol)
% GET_MEAN_PXPERMM  Average pixels_per_mm from trx.mat across experiments
%
%   pxpermm = get_mean_pxpermm(analysis_dir, protocol)
%
%   Scans all experiment folders under analysis_dir/protocol, reads
%   trx(1).pxpermm from each trx.mat, and returns the mean.
%   Falls back to get_protocol_config(protocol).pixels_per_mm if no
%   trx.mat files contain a valid pxpermm field.
%
%   INPUTS
%     analysis_dir — root analysis directory (e.g., '.../analysisdatalocal')
%     protocol     — protocol name (e.g., 'P008', 'P015')
%
%   OUTPUT
%     pxpermm — mean pixels per mm across experiments

    prot_path = fullfile(analysis_dir, protocol);
    if ~exist(prot_path, 'dir')
        warning('Protocol directory not found: %s', prot_path);
        cfg = get_protocol_config(protocol);
        pxpermm = cfg.pixels_per_mm;
        fprintf('  %s pxpermm: %.4f (fallback from config — no directory)\n', protocol, pxpermm);
        return;
    end

    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & contains({exp_dirs.name}, '_Rig'));

    vals = [];
    for i = 1:length(exp_dirs)
        trx_file = fullfile(prot_path, exp_dirs(i).name, 'trx.mat');
        if ~exist(trx_file, 'file'), continue; end
        try
            trx_tmp = load(trx_file, 'trx');
            if isfield(trx_tmp.trx, 'pxpermm') && ~isempty(trx_tmp.trx(1).pxpermm)
                val = trx_tmp.trx(1).pxpermm;
                if ~isnan(val) && val > 0
                    vals(end+1) = val; %#ok<AGROW>
                end
            end
        catch
        end
    end

    if ~isempty(vals)
        pxpermm = mean(vals);
        fprintf('  %s pxpermm: %.4f (mean of %d experiments, std=%.4f)\n', ...
            protocol, pxpermm, length(vals), std(vals));
    else
        cfg = get_protocol_config(protocol);
        pxpermm = cfg.pixels_per_mm;
        fprintf('  %s pxpermm: %.4f (fallback from config — no trx values found)\n', ...
            protocol, pxpermm);
    end
end
