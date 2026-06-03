%% migrate_protocols_to_json.m
% -----------------------------------------------------------------------
% One-time migration script. Reads each existing protocol from the
% switch/case in get_protocol_config.m and saves it as a JSON file in
% protocols/<P>.json so that future calls use the JSON loader.
%
% Run this ONCE. After running, all P001-P025 have JSON files and the
% switch/case becomes a fallback only for truly unknown protocols.
% -----------------------------------------------------------------------

protocols = { ...
    'P001','P002','P003','P004','P005','P006','P007','P008','P009','P010', ...
    'P011','P012','P013','P014','P015','P016','P018','P019','P020','P021', ...
    'P022','P023','P024','P025' };
% P017 is excluded — already has a JSON from create_protocol_json.m

script_dir   = fileparts(mfilename('fullpath'));
protocol_dir = fullfile(script_dir, 'protocols');
if ~exist(protocol_dir, 'dir'), mkdir(protocol_dir); end

for k = 1:numel(protocols)
    p = protocols{k};

    % Temporarily rename any existing JSON so get_protocol_config uses switch/case
    json_path = fullfile(protocol_dir, [p '.json']);
    tmp_path  = fullfile(protocol_dir, [p '.json.bak']);
    renamed = false;
    if exist(json_path, 'file')
        movefile(json_path, tmp_path);
        renamed = true;
    end

    try
        cfg = get_protocol_config(p);
    catch ME
        fprintf('ERROR loading %s: %s\n', p, ME.message);
        if renamed, movefile(tmp_path, json_path); end
        continue;
    end

    % Restore any backup
    if renamed, delete(tmp_path); end

    % Build a clean JSON struct with only serializable fields
    j = struct();
    j.protocol_number   = cfg.protocol;
    j.num_cycles        = cfg.num_cycles;
    j.has_optomotor     = cfg.has_optomotor;
    j.is_place_learning = cfg.is_place_learning;
    j.is_intensity      = cfg.is_intensity;
    j.has_probes        = cfg.has_probes;
    j.pixels_per_mm     = cfg.pixels_per_mm;

    % Flags
    if isfield(cfg, 'is_single_quadrant')
        j.is_single_quadrant = cfg.is_single_quadrant;
    else
        j.is_single_quadrant = isfield(cfg, 'led_to_quad');
    end

    if isfield(cfg, 'led_to_quad'),        j.led_to_quad        = cfg.led_to_quad;        end
    if isfield(cfg, 'probe_target_quad'),  j.probe_target_quad  = cfg.probe_target_quad;  end
    if isfield(cfg, 'display_name'),       j.display_name       = cfg.display_name;       end
    if isfield(cfg, 'description'),        j.description        = cfg.description;        end
    if isfield(cfg, 'led_intensity_training'), j.led_intensity_training = cfg.led_intensity_training; end
    if isfield(cfg, 'led_intensity_probe'),    j.led_intensity_probe    = cfg.led_intensity_probe;    end
    if isfield(cfg, 'trial_duration_s'),   j.trial_duration_s   = cfg.trial_duration_s;   end
    if isfield(cfg, 'probe_duration_s'),   j.probe_duration_s   = cfg.probe_duration_s;   end

    % Arrays — stored as plain arrays in JSON (load_from_json converts back)
    j.labels        = cfg.labels(:)';
    j.quad_patterns = cfg.quad_patterns(:)';

    % Colors: cell of [1x3] → Nx3 matrix for clean JSON serialization
    nc = cfg.num_cycles;
    color_mat = zeros(nc, 3);
    for c = 1:nc
        color_mat(c, :) = cfg.colors{c};
    end
    j.colors = color_mat;

    % Sections
    nsec = numel(cfg.sections);
    sec_labels = cell(nsec, 1);
    sec_colors = zeros(nsec, 3);
    sec_start  = zeros(nsec, 1);
    sec_end    = zeros(nsec, 1);
    for s = 1:nsec
        sec_labels{s} = cfg.sections(s).label;
        sec_colors(s,:) = cfg.sections(s).color;
        sec_start(s) = cfg.sections(s).start_cycle;
        sec_end(s)   = cfg.sections(s).end_cycle;
    end
    j.section_labels      = sec_labels;
    j.section_colors      = sec_colors;
    j.section_start_cycle = sec_start;
    j.section_end_cycle   = sec_end;

    % Derived vectors
    j.probe_cycles    = cfg.probe_cycles;
    j.training_cycles = cfg.training_cycles;
    j.om_cycles       = cfg.om_cycles;
    j.num_blocks      = cfg.num_blocks;

    if ~isempty(cfg.block_probe_cycles)
        j.block_probe_cycles = cfg.block_probe_cycles;
    end
    if ~isempty(cfg.probe_labels)
        j.probe_labels = cfg.probe_labels(:)';
    end
    if ~isempty(cfg.block_labels)
        j.block_labels = cfg.block_labels(:)';
    end
    if ~isempty(cfg.all_probe_cycle_nums)
        j.all_probe_cycle_nums = cfg.all_probe_cycle_nums;
    end
    if ~isempty(cfg.preprobe_cycle)
        j.pp_cycle = cfg.preprobe_cycle;
    end
    if ~isempty(cfg.pretrain_cycle)
        j.ag_cycle = cfg.pretrain_cycle;
    end

    % training_blocks: cell of vectors → store as Nx(flips) matrix if uniform
    nb = cfg.num_blocks;
    if nb > 0 && ~isempty(cfg.training_blocks)
        lens = cellfun(@numel, cfg.training_blocks);
        if all(lens == lens(1)) && lens(1) > 0
            tb_mat = zeros(nb, lens(1));
            for b = 1:nb
                tb_mat(b,:) = cfg.training_blocks{b};
            end
            j.training_blocks = tb_mat;
        end
    end

    % Write JSON
    fid = fopen(json_path, 'w');
    fprintf(fid, '%s', jsonencode(j, 'PrettyPrint', true));
    fclose(fid);

    fprintf('Saved %s  (%d cycles)\n', json_path, cfg.num_cycles);
end

fprintf('\nDone. %d protocol JSON files written to %s\n', numel(protocols), protocol_dir);
