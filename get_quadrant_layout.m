function layout = get_quadrant_layout()
% GET_QUADRANT_LAYOUT  Single source of truth for quadrant spatial positions.
%
%   layout = get_quadrant_layout()
%
%   Returns a struct array (indexed 1:4) with the canonical spatial
%   properties of each quadrant. These match the mask built by
%   arena_led_pipeline_local.m (lines 200-209):
%
%     Q1 (mask=1): right_of_vert & ~below_horiz  → Top-Right
%     Q2 (mask=2): ~right_of_vert & ~below_horiz → Top-Left
%     Q3 (mask=3): ~right_of_vert & below_horiz  → Bottom-Left
%     Q4 (mask=4): right_of_vert & below_horiz   → Bottom-Right
%
%   Layout diagram:
%
%     Q2 (Top-Left)   | Q1 (Top-Right)
%     -----------------+-----------------
%     Q3 (Bottom-Left) | Q4 (Bottom-Right)
%
%   Fields per quadrant:
%     .name         — e.g. 'Q1'
%     .label        — e.g. 'Top-Right'
%     .sign_x       — +1 (right of center) or -1 (left of center)
%     .sign_y       — -1 (above center, image coords) or +1 (below center)
%     .offset_norm  — [sign_x, sign_y] normalised offset from arena center
%
%   Usage for placing text labels at quadrant centers:
%     layout = get_quadrant_layout();
%     for qi = 1:4
%         qx = xc + layout(qi).sign_x * radius * 0.45;
%         qy = yc + layout(qi).sign_y * radius * 0.45;
%         text(ax, qx, qy, layout(qi).name, ...);
%     end
%
%   ANY code that needs quadrant spatial positions MUST call this function.
%   Do NOT hardcode offsets, position arrays, or spatial assumptions elsewhere.
%
%   See also: led_pattern_to_quads, arena_led_pipeline_local

    layout(1).name   = 'Q1';
    layout(1).label  = 'Top-Right';
    layout(1).sign_x = +1;   % right of center
    layout(1).sign_y = -1;   % above center (image y-axis points down)

    layout(2).name   = 'Q2';
    layout(2).label  = 'Top-Left';
    layout(2).sign_x = -1;   % left of center
    layout(2).sign_y = -1;   % above center

    layout(3).name   = 'Q3';
    layout(3).label  = 'Bottom-Left';
    layout(3).sign_x = -1;   % left of center
    layout(3).sign_y = +1;   % below center

    layout(4).name   = 'Q4';
    layout(4).label  = 'Bottom-Right';
    layout(4).sign_x = +1;   % right of center
    layout(4).sign_y = +1;   % below center

    % Pre-compute normalised offset [x, y] for convenience
    for qi = 1:4
        layout(qi).offset_norm = [layout(qi).sign_x, layout(qi).sign_y];
    end
end
