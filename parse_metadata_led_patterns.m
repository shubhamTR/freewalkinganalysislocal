function [led_patterns, training_patterns] = parse_metadata_led_patterns(exp_path)
% PARSE_METADATA_LED_PATTERNS  Extract per-cycle LED patterns from metadata.
%
%   led_patterns = parse_metadata_led_patterns(exp_path)
%   [led_patterns, training_patterns] = parse_metadata_led_patterns(exp_path)
%
%   Reads original_metadata.txt from the experiment folder and extracts
%   the LED pattern (e.g., '0101', '1010', '1111') for each cycle.
%
%   OUTPUTS
%     led_patterns      — cell array of actual LED patterns per cycle
%                          (e.g., '1011' for training, '1111' for probes)
%     training_patterns — cell array same length as led_patterns.
%                          For training cycles: same as led_patterns.
%                          For probe cycles (LED=1111): the paired training
%                          LED pattern based on the probe's orientation,
%                          so downstream code can determine which quadrant
%                          was the "learned safe" zone during the probe.
%                          For OM cycles: '1111' (no paired pattern).
%
%   The pairing is determined from:
%     1. The "paired_LED=XXXX" field in probe lines (Randomized Orientation Log)
%     2. Or the "Pairing:" line (e.g., "ori 0->1101, ori 1->1011, ...")
%        combined with the probe's "ori=X" field
%     3. Or from the Block Schedule section for fixed-order protocols (P013)
%        where the Preprobe orientation's paired LED is inferred from the
%        ori-to-LED mapping in training trials.
%
%   Returns empty {} if metadata file not found or cannot be parsed.

    led_patterns = {};
    training_patterns = {};

    % Try original_metadata.txt first, fall back to copy_metadata.txt
    meta_file = fullfile(exp_path, 'original_metadata.txt');
    if ~exist(meta_file, 'file')
        meta_file = fullfile(exp_path, 'copy_metadata.txt');
    end
    if ~exist(meta_file, 'file')
        return;
    end

    fid = fopen(meta_file, 'r');
    if fid < 0, return; end
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'WhiteSpace', '');
    fclose(fid);
    lines = raw{1};

    %% Find the Block Schedule section
    schedule_start = 0;
    for li = 1:length(lines)
        if contains(lines{li}, 'Place Learning Block Schedule')
            schedule_start = li + 1;
            break;
        end
    end
    if schedule_start == 0
        return;
    end

    %% Determine if this protocol has optomotor (look for OM phase)
    has_opto = false;
    for li = 1:length(lines)
        if contains(lines{li}, 'Optomotor Mode') || contains(lines{li}, 'Phase 1: Red LED')
            has_opto = true;
            break;
        end
    end

    %% Parse ori-to-LED pairing from "Pairing:" line
    %   e.g., "Pairing: ori 0→1101, ori 1→1011, ori 2→0111, ori 3→1110"
    ori_to_led = containers.Map('KeyType', 'int32', 'ValueType', 'char');
    for li = 1:length(lines)
        ln = strtrim(lines{li});
        if startsWith(ln, 'Pairing:')
            % Parse all "ori N→XXXX" or "ori N->XXXX" pairs
            toks = regexp(ln, 'ori\s+(\d+)\s*[→\->]+\s*(\d{4})', 'tokens');
            for ti = 1:length(toks)
                ori_val = str2double(toks{ti}{1});
                led_val = toks{ti}{2};
                ori_to_led(int32(ori_val)) = led_val;
            end
            break;
        end
    end

    %% Try Randomized Orientation Log FIRST (ground truth for randomized protocols like P017)
    schedule_patterns = {};
    schedule_training = {};

    rand_start = 0;
    for li = 1:length(lines)
        if contains(lines{li}, 'Randomized Orientation Log')
            rand_start = li + 1;
            break;
        end
    end

    if rand_start > 0
        for li = rand_start:length(lines)
            ln = strtrim(lines{li});
            if isempty(ln), continue; end

            % Stop at next section
            if startsWith(ln, '===')
                break;
            end

            % Extract the primary LED pattern, skip "paired_LED=" in probe lines
            tok = regexp(ln, '(?<!_)LED=(\d{4})', 'tokens');
            if ~isempty(tok)
                actual_led = tok{1}{1};
                schedule_patterns{end+1} = actual_led; %#ok<AGROW>

                % Determine training-equivalent pattern
                if strcmp(actual_led, '1111')
                    % This is a probe (or preprobe) — find the paired training LED
                    paired = resolve_probe_training_led(ln, ori_to_led);
                    schedule_training{end+1} = paired; %#ok<AGROW>
                else
                    % Training cycle — training pattern = actual pattern
                    schedule_training{end+1} = actual_led; %#ok<AGROW>
                end
            end
        end
    end

    %% Fall back to Block Schedule section (P013 and older fixed-order protocols)
    if isempty(schedule_patterns)
        for li = schedule_start:length(lines)
            ln = strtrim(lines{li});
            if isempty(ln), continue; end

            % Stop at end of schedule (next section or timing info)
            if startsWith(ln, '===') || startsWith(ln, 'Place Learning start') || ...
               startsWith(ln, 'Place Learning end')
                break;
            end

            % Extract LED pattern
            tok = regexp(ln, '(?<!_)LED=(\d{4})', 'tokens');
            if ~isempty(tok)
                actual_led = tok{1}{1};
                schedule_patterns{end+1} = actual_led; %#ok<AGROW>

                if strcmp(actual_led, '1111')
                    paired = resolve_probe_training_led(ln, ori_to_led);
                    schedule_training{end+1} = paired; %#ok<AGROW>
                else
                    schedule_training{end+1} = actual_led; %#ok<AGROW>
                end
            end
        end
    end

    %% Build full cycle pattern list
    if has_opto
        % OM1 = cycle 1 (all quads lit), then schedule, then OM2 = last cycle
        led_patterns      = [{'1111'}, schedule_patterns, {'1111'}];
        training_patterns = [{'1111'}, schedule_training, {'1111'}];
    else
        % No optomotor — schedule IS the full cycle list
        led_patterns      = schedule_patterns;
        training_patterns = schedule_training;
    end
end

%% ======== LOCAL HELPER ========
function paired_led = resolve_probe_training_led(line_str, ori_to_led)
% Given a probe line, determine the paired training LED pattern.
%   1. Check for explicit "paired_LED=XXXX" in the line
%   2. Fall back to ori-to-LED mapping from the Pairing: line

    paired_led = '1111';  % default: unknown

    % Method 1: explicit paired_LED= field (P017 Randomized Orientation Log)
    tok = regexp(line_str, 'paired_LED=(\d{4})', 'tokens');
    if ~isempty(tok)
        paired_led = tok{1}{1};
        return;
    end

    % Method 2: look up ori= in the ori-to-LED mapping
    tok_ori = regexp(line_str, '(?<!_)ori=(\d+)', 'tokens');
    if ~isempty(tok_ori) && ~isempty(ori_to_led)
        ori_val = int32(str2double(tok_ori{1}{1}));
        if isKey(ori_to_led, ori_val)
            paired_led = ori_to_led(ori_val);
        end
    end
end
