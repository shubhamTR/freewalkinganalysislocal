function cfg = get_protocol_config(protocol)
% GET_PROTOCOL_CONFIG  Single source of truth for all protocol definitions.
%
%   cfg = get_protocol_config('P017')
%
%   Checks protocols/<PROTOCOL>.json first. If found, loads from JSON —
%   no code changes needed for new protocols, just create a JSON file with
%   create_protocol_json.m. Falls back to the hardcoded switch/case below
%   for protocols not yet converted to JSON.
%
%   Returns a struct with:
%     .protocol          — protocol name (char)
%     .num_cycles        — expected number of LED cycles
%     .labels            — {1 x num_cycles} cell of cycle labels
%     .colors            — {1 x num_cycles} cell of [R G B] per cycle
%     .quad_patterns     — {1 x num_cycles} cell of 4-char strings
%                          '1010' = Q1,Q3 lit; '0101' = Q2,Q4 lit; '1111' = all lit
%     .sections          — struct array with .label, .color, .start_cycle, .end_cycle
%     .probe_cycles      — vector of cycle indices that are probes
%     .training_cycles   — vector of cycle indices that are training
%     .om_cycles         — vector of cycle indices that are optomotor
%     .has_optomotor     — logical
%     .has_probes        — logical
%     .is_place_learning — logical
%     .is_intensity      — logical
%     .pixels_per_mm     — default calibration for this protocol
%     .preprobe_cycle    — cycle index labeled 'PP'
%     .pretrain_cycle    — cycle index labeled 'Ag'
%     .num_blocks        — number of training blocks
%     .training_blocks   — {num_blocks x 1} cell of training cycle index vectors
%     .block_probe_cycles— [B1.P, B2.P, ...] cycle indices
%     .probe_labels      — {'PP', 'B1.P', ...}
%     .all_probe_cycle_nums — [PP, B1.P, B2.P, ...] indices
%     .block_labels      — {'B1', 'B2', ...}
%
%   Optional fields (single-quadrant protocols only):
%     .led_to_quad       — [2 3 4 1] hardware wiring pos→quadrant
%     .probe_target_quad — default safe quad for probes without metadata
%     .is_single_quadrant— logical

    % ------------------------------------------------------------------
    % JSON LOADER — check protocols/<PROTOCOL>.json first
    % ------------------------------------------------------------------
    json_file = fullfile(fileparts(mfilename('fullpath')), 'protocols', ...
        [upper(protocol) '.json']);
    if exist(json_file, 'file')
        cfg = load_from_json(json_file, upper(protocol));
        return;
    end

    % ------------------------------------------------------------------
    % HARDCODED FALLBACK — protocols not yet converted to JSON
    % ------------------------------------------------------------------
    RED    = [1 0 0];
    GREEN  = [0 0.6 0];
    BLUE   = [0 0 1];
    GREY   = [0.5 0.5 0.5];
    ORANGE = [0.9 0.5 0];

    cfg = struct();
    cfg.protocol = upper(protocol);

    switch upper(protocol)
        case 'P001'
            % RGB intensity ramp: 3 colors x 14 intensity steps = 42 cycles
            intensities = [1, 1, 5, 5, 10, 10, 20, 20, 30, 30, 40, 40, 50, 50];
            n = length(intensities);
            color_letters = {'R', 'G', 'B'};
            color_rgbs    = {RED, GREEN, BLUE};
            color_names   = {'RED', 'GREEN', 'BLUE'};

            labels = {};
            colors = {};
            quad_patterns = {};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            for b = 1:3
                start_c = (b-1) * n + 1;
                for i = 1:n
                    labels{end+1} = sprintf('%s%d', color_letters{b}, intensities(i)); %#ok<AGROW>
                    colors{end+1} = color_rgbs{b}; %#ok<AGROW>
                    if mod(i, 2) == 1
                        quad_patterns{end+1} = '1010'; %#ok<AGROW>
                    else
                        quad_patterns{end+1} = '0101'; %#ok<AGROW>
                    end
                end
                sections(b).label = color_names{b};
                sections(b).color = color_rgbs{b};
                sections(b).start_cycle = start_c;
                sections(b).end_cycle   = start_c + n - 1;
            end

            cfg.num_cycles = 42;
            cfg.is_intensity = true;
            cfg.is_place_learning = false;
            cfg.has_optomotor = false;
            cfg.has_probes = false;
            cfg.pixels_per_mm = 9.20;

        case 'P002'
            % Red-only 3-chunk ramp: 14 steps x 3 reps = 42 cycles
            intensities = [10, 10, 12, 12, 15, 15, 18, 18, 20, 20, 25, 25, 30, 30];
            n = length(intensities);

            labels = {};
            colors = {};
            quad_patterns = {};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            for rep = 1:3
                start_c = (rep-1) * n + 1;
                for i = 1:n
                    labels{end+1} = sprintf('R%d', intensities(i)); %#ok<AGROW>
                    colors{end+1} = RED; %#ok<AGROW>
                    if mod(i, 2) == 1
                        quad_patterns{end+1} = '1010'; %#ok<AGROW>
                    else
                        quad_patterns{end+1} = '0101'; %#ok<AGROW>
                    end
                end
                sections(rep).label = sprintf('RED (rep %d)', rep);
                sections(rep).color = RED;
                sections(rep).start_cycle = start_c;
                sections(rep).end_cycle   = start_c + n - 1;
            end

            cfg.num_cycles = 42;
            cfg.is_intensity = true;
            cfg.is_place_learning = false;
            cfg.has_optomotor = false;
            cfg.has_probes = false;
            cfg.pixels_per_mm = 9.20;

        case {'P003', 'P005'}
            % Place learning: PP + Ag + 4 blocks x (10 training + 1 probe) = 46 cycles
            num_blocks = 4;
            flips_per_block = 10;
            orient_seq = repmat([0, 1], 1, flips_per_block / 2);
            led_map = {'0101', '1010'};

            labels = {'PP', 'Ag'};
            colors = {GREY, ORANGE};
            quad_patterns = {'1111', '1010'};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            for blk = 1:num_blocks
                blk_start = length(labels) + 1;
                for idx = 1:flips_per_block
                    ori = orient_seq(idx);
                    labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
                    colors{end+1} = RED; %#ok<AGROW>
                    quad_patterns{end+1} = led_map{ori + 1}; %#ok<AGROW>
                end
                labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
                colors{end+1} = GREY; %#ok<AGROW>
                quad_patterns{end+1} = '1111'; %#ok<AGROW>
                blk_end = length(labels);
                sections(blk).label = sprintf('Block %d', blk);
                sections(blk).color = RED;
                sections(blk).start_cycle = blk_start;
                sections(blk).end_cycle   = blk_end;
            end

            cfg.num_cycles = 46;
            cfg.is_intensity = false;
            cfg.is_place_learning = true;
            cfg.has_optomotor = false;
            cfg.has_probes = true;
            cfg.pixels_per_mm = 9.20;

        case 'P004'
            % Optomotor only — no LED quadrants
            labels = {};
            colors = {};
            quad_patterns = {};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            cfg.num_cycles = 0;
            cfg.is_intensity = false;
            cfg.is_place_learning = false;
            cfg.has_optomotor = true;
            cfg.has_probes = false;
            cfg.pixels_per_mm = 9.20;

        case {'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P012', 'P014', 'P015', 'P016'}
            % Optomotor + Place learning: OM1 + PP + Ag + 4 blocks + OM2 = 48 cycles
            num_blocks = 4;
            flips_per_block = 10;
            orient_seq = repmat([0, 1], 1, flips_per_block / 2);
            led_map = {'0101', '1010'};

            labels = {'OM1', 'PP', 'Ag'};
            colors = {GREY, GREY, ORANGE};
            quad_patterns = {'1111', '1111', '1010'};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            for blk = 1:num_blocks
                blk_start = length(labels) + 1;
                for idx = 1:flips_per_block
                    ori = orient_seq(idx);
                    labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
                    colors{end+1} = RED; %#ok<AGROW>
                    quad_patterns{end+1} = led_map{ori + 1}; %#ok<AGROW>
                end
                labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
                colors{end+1} = GREY; %#ok<AGROW>
                quad_patterns{end+1} = '1111'; %#ok<AGROW>
                blk_end = length(labels);
                sections(blk).label = sprintf('Block %d', blk);
                sections(blk).color = RED;
                sections(blk).start_cycle = blk_start;
                sections(blk).end_cycle   = blk_end;
            end
            labels{end+1} = 'OM2';
            colors{end+1} = GREY;
            quad_patterns{end+1} = '1111';

            cfg.num_cycles = 48;
            cfg.is_intensity = false;
            cfg.is_place_learning = true;
            cfg.has_optomotor = true;
            cfg.has_probes = true;
            cfg.pixels_per_mm = 8.21;

        case {'P013', 'P017', 'P023', 'P024'}
            % Optomotor + SBD Place learning: OM1 + PP + Ag + 3 blocks + OM2 = 37 cycles
            num_blocks = 3;
            flips_per_block = 10;
            orient_seq = mod(0:(flips_per_block-1), 4);
            led_map = {'1101', '1011', '0111', '1110'};

            labels = {'OM1', 'PP', 'Ag'};
            colors = {GREY, GREY, ORANGE};
            quad_patterns = {'1111', '1111', '1110'};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            for blk = 1:num_blocks
                blk_start = length(labels) + 1;
                for idx = 1:flips_per_block
                    ori = orient_seq(idx);
                    labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
                    colors{end+1} = RED; %#ok<AGROW>
                    quad_patterns{end+1} = led_map{ori + 1}; %#ok<AGROW>
                end
                labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
                colors{end+1} = GREY; %#ok<AGROW>
                quad_patterns{end+1} = '1111'; %#ok<AGROW>
                blk_end = length(labels);
                sections(blk).label = sprintf('Block %d', blk);
                sections(blk).color = RED;
                sections(blk).start_cycle = blk_start;
                sections(blk).end_cycle   = blk_end;
            end
            labels{end+1} = 'OM2';
            colors{end+1} = GREY;
            quad_patterns{end+1} = '1111';

            cfg.num_cycles = 37;
            cfg.is_intensity = false;
            cfg.is_place_learning = true;
            cfg.has_optomotor = true;
            cfg.has_probes = true;
            cfg.pixels_per_mm = 8.21;
            cfg.skip_analysis = false;
            cfg.led_to_quad = [2, 3, 4, 1];
            cfg.probe_target_quad = 2;

        case 'P025'
            % Optomotor + SBD Place learning: OM1 + PP + Ag + 2 blocks + OM2 = 26 cycles
            num_blocks = 2;
            flips_per_block = 10;
            orient_seq = mod(0:(flips_per_block-1), 4);
            led_map = {'1101', '1011', '0111', '1110'};

            labels = {'OM1', 'PP', 'Ag'};
            colors = {GREY, GREY, ORANGE};
            quad_patterns = {'1111', '1111', '1110'};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            for blk = 1:num_blocks
                blk_start = length(labels) + 1;
                for idx = 1:flips_per_block
                    ori = orient_seq(idx);
                    labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
                    colors{end+1} = RED; %#ok<AGROW>
                    quad_patterns{end+1} = led_map{ori + 1}; %#ok<AGROW>
                end
                labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
                colors{end+1} = GREY; %#ok<AGROW>
                quad_patterns{end+1} = '1111'; %#ok<AGROW>
                blk_end = length(labels);
                sections(blk).label = sprintf('Block %d', blk);
                sections(blk).color = RED;
                sections(blk).start_cycle = blk_start;
                sections(blk).end_cycle   = blk_end;
            end
            labels{end+1} = 'OM2';
            colors{end+1} = GREY;
            quad_patterns{end+1} = '1111';

            cfg.num_cycles = 26;
            cfg.is_intensity = false;
            cfg.is_place_learning = true;
            cfg.has_optomotor = true;
            cfg.has_probes = true;
            cfg.pixels_per_mm = 8.21;
            cfg.led_to_quad = [2, 3, 4, 1];
            cfg.probe_target_quad = 2;

        case {'P018', 'P022'}
            % Red-only intensity ramp: 14 steps x 3 reps = 42 cycles
            intensities = [1, 1, 5, 5, 10, 10, 20, 20, 30, 30, 40, 40, 50, 50];
            n = length(intensities);

            labels = {};
            colors = {};
            quad_patterns = {};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            for rep = 1:3
                start_c = (rep-1) * n + 1;
                for i = 1:n
                    labels{end+1} = sprintf('R%d', intensities(i)); %#ok<AGROW>
                    colors{end+1} = RED; %#ok<AGROW>
                    if mod(i, 2) == 1
                        quad_patterns{end+1} = '1010'; %#ok<AGROW>
                    else
                        quad_patterns{end+1} = '0101'; %#ok<AGROW>
                    end
                end
                sections(rep).label = sprintf('RED (rep %d)', rep);
                sections(rep).color = RED;
                sections(rep).start_cycle = start_c;
                sections(rep).end_cycle   = start_c + n - 1;
            end

            cfg.num_cycles = 42;
            cfg.is_intensity = true;
            cfg.is_place_learning = false;
            cfg.has_optomotor = false;
            cfg.has_probes = false;
            cfg.pixels_per_mm = 9.20;

        case 'P019'
            % Optomotor + SBD dark place learning: 37 cycles (same structure as P017)
            num_blocks = 3;
            flips_per_block = 10;
            orient_seq = mod(0:(flips_per_block-1), 4);
            led_map = {'1101', '1011', '0111', '1110'};

            labels = {'OM1', 'PP', 'Ag'};
            colors = {GREY, GREY, ORANGE};
            quad_patterns = {'1111', '1111', '1110'};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            for blk = 1:num_blocks
                blk_start = length(labels) + 1;
                for idx = 1:flips_per_block
                    ori = orient_seq(idx);
                    labels{end+1} = sprintf('B%d.%d', blk, idx); %#ok<AGROW>
                    colors{end+1} = RED; %#ok<AGROW>
                    quad_patterns{end+1} = led_map{ori + 1}; %#ok<AGROW>
                end
                labels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
                colors{end+1} = GREY; %#ok<AGROW>
                quad_patterns{end+1} = '1111'; %#ok<AGROW>
                blk_end = length(labels);
                sections(blk).label = sprintf('Block %d', blk);
                sections(blk).color = RED;
                sections(blk).start_cycle = blk_start;
                sections(blk).end_cycle   = blk_end;
            end
            labels{end+1} = 'OM2';
            colors{end+1} = GREY;
            quad_patterns{end+1} = '1111';

            cfg.num_cycles = 37;
            cfg.is_intensity = false;
            cfg.is_place_learning = true;
            cfg.has_optomotor = true;
            cfg.has_probes = true;
            cfg.pixels_per_mm = 8.21;
            cfg.led_to_quad = [2, 3, 4, 1];
            cfg.probe_target_quad = 2;

        case {'P020', 'P021'}
            % Red stepped-block intensity: 3 blocks x 8 trials = 24 cycles
            block_intensities = [1, 2; 3, 4; 5, 6];
            num_blocks = 3;
            trials_per_block = 8;

            labels = {};
            colors = {};
            quad_patterns = {};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            for blk = 1:num_blocks
                blk_start = length(labels) + 1;
                low_int  = block_intensities(blk, 1);
                high_int = block_intensities(blk, 2);
                for t = 1:trials_per_block
                    if t <= 4
                        labels{end+1} = sprintf('B%d.R%d', blk, low_int); %#ok<AGROW>
                    else
                        labels{end+1} = sprintf('B%d.R%d', blk, high_int); %#ok<AGROW>
                    end
                    colors{end+1} = RED; %#ok<AGROW>
                    if mod(t, 2) == 1
                        quad_patterns{end+1} = '1010'; %#ok<AGROW>
                    else
                        quad_patterns{end+1} = '0101'; %#ok<AGROW>
                    end
                end
                blk_end = length(labels);
                sections(blk).label = sprintf('Block %d (%d/%d%%)', blk, low_int, high_int);
                sections(blk).color = RED;
                sections(blk).start_cycle = blk_start;
                sections(blk).end_cycle   = blk_end;
            end

            cfg.num_cycles = 24;
            cfg.is_intensity = true;
            cfg.is_place_learning = false;
            cfg.has_optomotor = false;
            cfg.has_probes = false;
            cfg.pixels_per_mm = 9.20;

        otherwise
            warning('get_protocol_config: unknown protocol ''%s'' and no JSON file found in protocols/', protocol);
            labels = {};
            colors = {};
            quad_patterns = {};
            sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});

            cfg.num_cycles = 0;
            cfg.is_intensity = false;
            cfg.is_place_learning = false;
            cfg.has_optomotor = false;
            cfg.has_probes = false;
            cfg.pixels_per_mm = 11.54;
    end

    cfg.labels        = labels;
    cfg.colors        = colors;
    cfg.quad_patterns = quad_patterns;
    cfg.sections      = sections;

    if ~isfield(cfg, 'skip_analysis')
        cfg.skip_analysis = false;
    end

    cfg = add_derived_fields(cfg);
end

% =========================================================================
%  LOCAL: load_from_json
%  Reads protocols/<PROTOCOL>.json and returns a fully populated cfg struct.
%  Handles two JSON formats:
%    - Migration format (from migrate_protocols_to_json.m): has quad_patterns
%      and section_labels/section_colors/section_start_cycle/section_end_cycle
%    - create_protocol_json format: has led_patterns, training_blocks, colors as Nx3
% =========================================================================
function cfg = load_from_json(json_file, protocol)
    raw = jsondecode(fileread(json_file));

    cfg = struct();
    cfg.protocol          = protocol;
    cfg.num_cycles        = raw.num_cycles;
    cfg.has_optomotor     = raw.has_optomotor;
    cfg.is_place_learning = raw.is_place_learning;
    cfg.is_intensity      = raw.is_intensity;
    cfg.pixels_per_mm     = raw.pixels_per_mm;
    cfg.has_probes        = isfield(raw, 'has_probes') && raw.has_probes;
    cfg.skip_analysis     = false;

    % Optional metadata fields
    optional = {'display_name','description','led_intensity_training', ...
                'led_intensity_probe','trial_duration_s','probe_duration_s', ...
                'camera_fps','optomotor_duration_s','inter_direction_pause_s'};
    for k = 1:numel(optional)
        if isfield(raw, optional{k}), cfg.(optional{k}) = raw.(optional{k}); end
    end

    % Single-quadrant fields
    if isfield(raw, 'led_to_quad') && ~isempty(raw.led_to_quad)
        cfg.led_to_quad        = raw.led_to_quad(:)';
        cfg.is_single_quadrant = true;
    else
        cfg.is_single_quadrant = isfield(raw,'is_single_quadrant') && raw.is_single_quadrant;
    end
    if isfield(raw, 'probe_target_quad'), cfg.probe_target_quad = raw.probe_target_quad; end

    nc = raw.num_cycles;

    % --- Labels ---
    if iscell(raw.labels)
        labels = raw.labels(:)';
    else
        labels = cellstr(raw.labels)';
    end

    % --- Colors (Nx3 matrix in both formats) ---
    colors = cell(1, nc);
    for c = 1:nc
        colors{c} = raw.colors(c, :);
    end

    % --- quad_patterns ---
    % Migration format stores quad_patterns directly.
    % create_protocol_json format reconstructs from led_patterns.
    if isfield(raw, 'quad_patterns')
        if iscell(raw.quad_patterns)
            quad_patterns = raw.quad_patterns(:)';
        else
            quad_patterns = cellstr(raw.quad_patterns)';
        end
    else
        % Reconstruct from led_patterns
        if isfield(raw, 'led_patterns')
            if iscell(raw.led_patterns)
                led_pats = raw.led_patterns(:)';
            else
                led_pats = cellstr(raw.led_patterns)';
            end
        else
            led_pats = {'1010', '0101'};
        end
        quad_patterns = cell(1, nc);
        train_idx = 0;
        for c = 1:nc
            lbl = labels{c};
            if startsWith(lbl, 'OM') || strcmp(lbl, 'PP') || endsWith(lbl, '.P')
                quad_patterns{c} = '1111';
            elseif strcmp(lbl, 'Ag')
                quad_patterns{c} = led_pats{1};
            else
                train_idx = train_idx + 1;
                quad_patterns{c} = led_pats{mod(train_idx - 1, numel(led_pats)) + 1};
            end
        end
    end

    % --- Sections struct ---
    % Migration format stores section_labels / section_colors / section_start_cycle / section_end_cycle.
    % create_protocol_json format stores training_blocks + block_probe_cycles.
    sections = struct('label', {}, 'color', {}, 'start_cycle', {}, 'end_cycle', {});
    num_blocks = raw.num_blocks;

    if isfield(raw, 'section_labels')
        % Migration format
        for s = 1:num_blocks
            sections(s).label       = raw.section_labels{s};
            sections(s).color       = raw.section_colors(s, :);
            sections(s).start_cycle = raw.section_start_cycle(s);
            sections(s).end_cycle   = raw.section_end_cycle(s);
        end
    elseif isfield(raw, 'training_blocks') && num_blocks > 0
        % create_protocol_json format
        if isnumeric(raw.training_blocks)
            tb_cell = cell(num_blocks, 1);
            for b = 1:num_blocks
                tb_cell{b} = raw.training_blocks(b, :);
            end
        else
            tb_cell = raw.training_blocks;
        end
        bp = raw.block_probe_cycles(:)';
        for blk = 1:num_blocks
            sections(blk).label       = sprintf('Block %d', blk);
            sections(blk).color       = [0.8 0.1 0.1];
            sections(blk).start_cycle = tb_cell{blk}(1);
            sections(blk).end_cycle   = bp(blk);
        end
    end

    cfg.labels        = labels;
    cfg.colors        = colors;
    cfg.quad_patterns = quad_patterns;
    cfg.sections      = sections;

    cfg = add_derived_fields(cfg);
end

% =========================================================================
%  LOCAL: add_derived_fields
%  Derives convenience vectors and plotter fields from labels/quad_patterns/sections.
%  Called by both the JSON path and the switch/case path.
% =========================================================================
function cfg = add_derived_fields(cfg)
    labels        = cfg.labels;
    quad_patterns = cfg.quad_patterns;
    nc = length(quad_patterns);

    probe_cycles    = [];
    training_cycles = [];
    om_cycles       = [];

    for c = 1:nc
        lbl = '';
        if c <= length(labels), lbl = labels{c}; end
        qp = quad_patterns{c};

        if startsWith(lbl, 'OM')
            om_cycles = [om_cycles, c]; %#ok<AGROW>
        elseif strcmp(qp, '1111')
            probe_cycles = [probe_cycles, c]; %#ok<AGROW>
        elseif any(qp == '0')
            training_cycles = [training_cycles, c]; %#ok<AGROW>
        end
    end

    cfg.probe_cycles    = probe_cycles;
    cfg.training_cycles = training_cycles;
    cfg.om_cycles       = om_cycles;

    pp_idx = find(strcmp(labels, 'PP'), 1);
    cfg.preprobe_cycle = pp_idx;

    ag_idx = find(strcmp(labels, 'Ag'), 1);
    cfg.pretrain_cycle = ag_idx;

    num_blks = length(cfg.sections);
    cfg.num_blocks = num_blks;

    cfg.training_blocks = cell(num_blks, 1);
    for blk = 1:num_blks
        blk_all = cfg.sections(blk).start_cycle : cfg.sections(blk).end_cycle;
        cfg.training_blocks{blk} = intersect(blk_all, training_cycles);
    end

    blk_probes = [];
    for blk = 1:num_blks
        bp_lbl = sprintf('B%d.P', blk);
        bp_idx = find(strcmp(labels, bp_lbl), 1);
        if ~isempty(bp_idx)
            blk_probes(end+1) = bp_idx; %#ok<AGROW>
        end
    end
    cfg.block_probe_cycles = blk_probes;

    plabels = {};
    if ~isempty(pp_idx), plabels{end+1} = 'PP'; end
    for blk = 1:num_blks
        plabels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
    end
    cfg.probe_labels = plabels;

    cfg.all_probe_cycle_nums = [pp_idx, blk_probes];
    cfg.block_labels = arrayfun(@(b) sprintf('B%d', b), 1:num_blks, 'UniformOutput', false);
end
