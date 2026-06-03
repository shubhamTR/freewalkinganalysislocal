function cfg = get_protocol_config(protocol)
% GET_PROTOCOL_CONFIG  Single source of truth for all protocol definitions.
%
%   cfg = get_protocol_config('P001')
%
%   Returns a struct with:
%     .protocol       — protocol name (char)
%     .num_cycles     — expected number of LED cycles
%     .labels         — {1 x num_cycles} cell of cycle labels
%     .colors         — {1 x num_cycles} cell of [R G B] per cycle
%     .quad_patterns  — {1 x num_cycles} cell of 4-char strings
%                       '1010' = Q1,Q3 lit; '0101' = Q2,Q4 lit; '1111' = all lit
%     .sections       — struct array with .label, .color, .start_cycle, .end_cycle
%     .probe_cycles   — vector of cycle indices that are probes ('1111' during learning)
%     .training_cycles— vector of cycle indices that are training ('0101' or '1010')
%     .om_cycles      — vector of cycle indices that are optomotor
%     .has_optomotor  — logical
%     .has_probes     — logical
%     .is_place_learning — logical (P003, P005-P010)
%     .is_intensity   — logical (P001, P002)
%     .pixels_per_mm  — default calibration for this protocol
%
%   Supported protocols: P001, P002, P003, P004, P005, P006, P007, P008,
%   P009, P010, P011, P012, P013, P014, P015, P016, P017, P018, P019,
%   P020, P021, P022, P023, P024, P025.
%
%   USAGE EXAMPLES:
%     cfg = get_protocol_config('P001');
%     fprintf('Protocol %s has %d cycles\n', cfg.protocol, cfg.num_cycles);
%     for c = 1:cfg.num_cycles
%         fprintf('  Cycle %d: %s  quad=%s\n', c, cfg.labels{c}, cfg.quad_patterns{c});
%     end

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
            % P011: Same as P008 but blank panels during training (visual only on probes)
            % P012: Same as P008 but optomotor at 120fps/50s, LED intensity 6, brightness 6
            % P014: Same as P008 but inverted pattern (dark on bright), bottom-aligned
            % P015: Same as P014 but lower LED intensities (training=6, probe=4)
            % P016: Same as P015 but all LED intensities at 4%
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
            % Uses 4 orientations and 3-of-4 quadrant LED patterns (1101/1011/0111/1110)
            % 3 training blocks (not 4), 10 flips per block
            %
            % Single-quadrant punishment (not diagonal pairs).
            % Compute functions detect this from quad_patterns and use:
            %   QPI = (N_safe - N_other) / N_total
            % where safe = the single dark quadrant per cycle.
            %
            % P013: SBD pattern, LED intensity unspecified, brightness 6
            % P017: SBD pattern, LED training=8 probe=6, brightness=6, probe intensity=6
            %       Randomized trial orientations (no consecutive repeats)
            %       NOTE: actual trial order varies per experiment — use metadata as ground truth
            % P023: Opto + SBD PL, UNCOUPLED arena (arena shifts opposite to LED ori).
            %       LED training=8 probe=6, SBD brightness=6. Arena shift: -(ori*48)+48
            % P024: Opto + SBD PL, RANDOMLY DECOUPLED arena (arena_ori independent,
            %       arena_ori ≠ led_ori). LED training=8 probe=6, SBD brightness=6.
            num_blocks = 3;
            flips_per_block = 10;
            orient_seq = mod(0:(flips_per_block-1), 4);  % cycles through [0,1,2,3,0,1,2,3,0,1]
            led_map = {'1101', '1011', '0111', '1110'};  % ori 0→1101, 1→1011, 2→0111, 3→1110

            labels = {'OM1', 'PP', 'Ag'};
            colors = {GREY, GREY, ORANGE};
            quad_patterns = {'1111', '1111', '1110'};  % Ag uses 1110
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
            % LED string position → arena quadrant mapping (verified empirically)
            %   LED pos 1 → Q2 (Top-Left)
            %   LED pos 2 → Q3 (Bottom-Left)
            %   LED pos 3 → Q4 (Bottom-Right)
            %   LED pos 4 → Q1 (Top-Right)
            % Results:
            %   '1101' (pos 3 = 0) → Q4 dark/safe
            %   '1011' (pos 2 = 0) → Q3 dark/safe
            %   '0111' (pos 1 = 0) → Q2 dark/safe
            %   '1110' (pos 4 = 0) → Q1 dark/safe
            cfg.led_to_quad = [2, 3, 4, 1];  % pos 1→Q2, pos 2→Q3, pos 3→Q4, pos 4→Q1
            cfg.probe_target_quad = 2;  % Q2 = correct visual stimulus during probes

        case 'P025'
            % Optomotor + SBD Place learning: OM1 + PP + Ag + 2 blocks + OM2 = 26 cycles
            % Same as P017 (coupled arena) but 2 blocks instead of 3, and reduced
            % LED intensities (training=3, probe=1) for V5 attenuator + thin diffuser.
            % SBD brightness=6.
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
            % Red-only intensity ramp: 7 intensities x 2 patterns x 3 reps = 42 cycles
            % P018: Base version with standard optics
            % P022: Same as P018 but with V11 attenuator + thin diffuser sandwich
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
            % Optomotor + SBD Place learning (same as P017 structure): 37 cycles
            % Same as P017 but with dark place learning (brightness=0 during training)
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
            % P020: Standard optics
            % P021: V11 attenuator + thin diffuser sandwich
            % Block 1: 4@1% + 4@2%, Block 2: 4@3% + 4@4%, Block 3: 4@5% + 4@6%
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
            warning('Unknown protocol: %s', protocol);
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

    cfg.labels = labels;
    cfg.colors = colors;
    cfg.quad_patterns = quad_patterns;
    cfg.sections = sections;

    % Default skip_analysis to false if not set by the protocol case
    if ~isfield(cfg, 'skip_analysis')
        cfg.skip_analysis = false;
    end

    %% Derive convenience vectors from quad_patterns
    nc = length(quad_patterns);

    probe_cycles = [];
    training_cycles = [];
    om_cycles = [];

    for c = 1:nc
        lbl = '';
        if c <= length(labels), lbl = labels{c}; end
        qp = quad_patterns{c};

        if startsWith(lbl, 'OM')
            om_cycles = [om_cycles, c]; %#ok<AGROW>
        elseif strcmp(qp, '1111')
            probe_cycles = [probe_cycles, c]; %#ok<AGROW>
        elseif any(qp == '0')
            % Any pattern with at least one dark quadrant is a training cycle
            % Covers diagonal pairs ('1010','0101') and single-quad ('1101','1011','0111','1110')
            training_cycles = [training_cycles, c]; %#ok<AGROW>
        end
    end

    cfg.probe_cycles = probe_cycles;
    cfg.training_cycles = training_cycles;
    cfg.om_cycles = om_cycles;

    %% Derive plotter convenience fields from labels
    % preprobe_cycle: cycle labeled 'PP'
    pp_idx = find(strcmp(labels, 'PP'), 1);
    cfg.preprobe_cycle = pp_idx;  % [] if no PP

    % pretrain_cycle: cycle labeled 'Ag'
    ag_idx = find(strcmp(labels, 'Ag'), 1);
    cfg.pretrain_cycle = ag_idx;  % [] if no Ag

    % num_blocks: number of training blocks (from sections)
    cfg.num_blocks = length(cfg.sections);

    % training_blocks: {[start end], ...} cycle ranges per block (training only)
    num_blks = cfg.num_blocks;
    cfg.training_blocks = cell(num_blks, 1);
    for blk = 1:num_blks
        blk_all = cfg.sections(blk).start_cycle : cfg.sections(blk).end_cycle;
        cfg.training_blocks{blk} = intersect(blk_all, training_cycles);
    end

    % block_probe_cycles: probe cycle per block [B1.P, B2.P, ...]
    blk_probes = [];
    for blk = 1:num_blks
        bp_lbl = sprintf('B%d.P', blk);
        bp_idx = find(strcmp(labels, bp_lbl), 1);
        if ~isempty(bp_idx)
            blk_probes(end+1) = bp_idx; %#ok<AGROW>
        end
    end
    cfg.block_probe_cycles = blk_probes;

    % probe_labels: {'PP', 'B1.P', 'B2.P', ...}
    plabels = {};
    if ~isempty(pp_idx), plabels{end+1} = 'PP'; end
    for blk = 1:num_blks
        plabels{end+1} = sprintf('B%d.P', blk); %#ok<AGROW>
    end
    cfg.probe_labels = plabels;

    % all_probe_cycle_nums: [PP, B1.P, B2.P, ...] cycle indices
    cfg.all_probe_cycle_nums = [pp_idx, blk_probes];

    % block_labels: {'B1', 'B2', ...}
    cfg.block_labels = arrayfun(@(b) sprintf('B%d', b), 1:num_blks, 'UniformOutput', false);
end
