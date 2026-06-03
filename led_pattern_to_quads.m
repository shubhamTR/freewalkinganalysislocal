function [lit_quads, safe_quads] = led_pattern_to_quads(qp)
% LED_PATTERN_TO_QUADS  Convert a 4-char LED pattern string to quadrant lists.
%
%   [lit_quads, safe_quads] = led_pattern_to_quads(qp)
%
%   Hardware mapping (verified from rig wiring + original_metadata.txt):
%     '1010' → Q2,Q4 lit   Q1,Q3 safe
%     '0101' → Q1,Q3 lit   Q2,Q4 safe
%     '1111' → all lit      none safe
%     '0000' → none lit     all safe
%
%   The LED string positions do NOT map directly to quadrant mask numbers.
%   The rig wiring maps (verified empirically from P013 single-quadrant patterns):
%     string pos 1 → Q2 (Top-Left)
%     string pos 2 → Q3 (Bottom-Left)
%     string pos 3 → Q4 (Bottom-Right)
%     string pos 4 → Q1 (Top-Right)
%
%   As diagonal pairs: pos 1,3 → Q2,Q4;  pos 2,4 → Q3,Q1
%
%   CANONICAL QUADRANT LAYOUT (from arena_led_pipeline_local.m):
%     Q2 (mask=2, Top-Left)   | Q1 (mask=1, Top-Right)
%     -------------------------+-------------------------
%     Q3 (mask=3, Bottom-Left) | Q4 (mask=4, Bottom-Right)
%
%   This layout is the SINGLE SOURCE OF TRUTH for all quadrant spatial
%   references in the pipeline. It matches the mask built by
%   arena_led_pipeline_local.m (lines 200-209). Any code that needs to
%   know where Q1-Q4 are positioned spatially MUST use get_quadrant_layout()
%   from this file — never hardcode offsets.
%
%   Returns:
%     lit_quads  — row vector of quadrant numbers that are lit (e.g. [2 4])
%     safe_quads — row vector of quadrant numbers that are dark/safe (e.g. [1 3])
%
%   See also: get_quadrant_layout

    if ~ischar(qp) || length(qp) ~= 4
        error('LED pattern must be a 4-character string (e.g. ''1010''), got: %s', mat2str(qp));
    end

    switch qp
        case '1010'
            lit_quads  = [2, 4];
            safe_quads = [1, 3];
        case '0101'
            lit_quads  = [1, 3];
            safe_quads = [2, 4];
        case '1111'
            lit_quads  = [1, 2, 3, 4];
            safe_quads = [];
        case '0000'
            lit_quads  = [];
            safe_quads = [1, 2, 3, 4];
        otherwise
            % Generic fallback for any pattern — use the hardware mapping
            % Verified empirically from P013 single-quadrant patterns:
            %   '1101' (pos3=0) → Q4 safe
            %   '1011' (pos2=0) → Q3 safe
            %   '0111' (pos1=0) → Q2 safe
            %   '1110' (pos4=0) → Q1 safe
            lit_quads  = [];
            safe_quads = [];
            % pos 1 → Q2
            if qp(1) == '1', lit_quads(end+1) = 2; else, safe_quads(end+1) = 2; end
            % pos 2 → Q3
            if qp(2) == '1', lit_quads(end+1) = 3; else, safe_quads(end+1) = 3; end
            % pos 3 → Q4
            if qp(3) == '1', lit_quads(end+1) = 4; else, safe_quads(end+1) = 4; end
            % pos 4 → Q1
            if qp(4) == '1', lit_quads(end+1) = 1; else, safe_quads(end+1) = 1; end
            lit_quads  = sort(lit_quads);
            safe_quads = sort(safe_quads);
    end
end
