function quad_pref_results = compute_quadrant_preference_local(trx, all_masks, LED_detector_thresh, opts)
% COMPUTE_QUADRANT_PREFERENCE - Protocol-aware QPI computation
%   Standard protocols (diagonal pairs): QPI = (Q1+Q3 - Q2-Q4) / total
%   Single-quadrant protocols (P013, P017): QPI = (N_safe - N_other) / N_total

    num_flies = length(trx);
    on_times = LED_detector_thresh.on_times;
    off_times = LED_detector_thresh.off_times;
    num_stims = length(on_times);

    %% Get protocol config
    protocol = get_protocol_from_opts(opts);
    cfg = get_protocol_config(protocol);
    is_single_quadrant = isfield(cfg, 'led_to_quad') && ~isempty(cfg.led_to_quad);

    % Quad patterns: metadata is ground truth for randomized protocols
    % training_patterns gives the paired training LED for probes (correct safe quad)
    training_patterns = {};
    if isfield(opts, 'exp_path') && ~isempty(opts.exp_path)
        [quad_patterns, training_patterns] = parse_metadata_led_patterns(opts.exp_path);
    else
        quad_patterns = {};
    end
    if isempty(quad_patterns)
        quad_patterns = cfg.quad_patterns;
    end
    % For safe-quad lookup, prefer training_patterns (probes get paired training LED)
    safe_patterns = training_patterns;
    if isempty(safe_patterns)
        safe_patterns = quad_patterns;
    end

    %% Map to quadrants
    if ~isfield(trx, 'quad')
        for k = 1:num_flies
            x_inds = round(trx(k).x);
            y_inds = round(trx(k).y);
            quadrant_res = nan(length(x_inds), 1);

            for fr = 1:length(x_inds)
                if ~isnan(x_inds(fr)) && ~isnan(y_inds(fr)) && ...
                   x_inds(fr) >= 1 && x_inds(fr) <= size(all_masks, 2) && ...
                   y_inds(fr) >= 1 && y_inds(fr) <= size(all_masks, 1)
                    quadrant_res(fr) = all_masks(y_inds(fr), x_inds(fr));
                end
            end

            trx(k).quad = quadrant_res;
        end
    end

    %% Compute preference per fly per stimulus
    quad_PI = nan(num_flies, num_stims);

    for k = 1:num_flies
        for s = 1:num_stims
            fr_end = min(off_times(s), length(trx(k).quad));
            q_slice = trx(k).quad(on_times(s):fr_end);
            q_slice = q_slice(~isnan(q_slice) & q_slice > 0);

            if isempty(q_slice)
                continue;
            end

            if is_single_quadrant
                % Single-quadrant QPI: (N_safe - N_other) / N_total
                % Use safe_patterns (training-equivalent LED) to find the correct safe quad,
                % even for probe cycles where actual LED is '1111'
                if s <= length(safe_patterns)
                    qp = safe_patterns{s};
                else
                    qp = '1111';
                end
                dark_pos = find(qp == '0');
                if length(dark_pos) == 1
                    safe_quad = cfg.led_to_quad(dark_pos);
                    n_safe  = sum(q_slice == safe_quad);
                    n_total = length(q_slice);
                    n_other = n_total - n_safe;
                    if n_total > 0
                        quad_PI(k, s) = (n_safe - n_other) / n_total;
                    end
                elseif isfield(cfg, 'probe_target_quad')
                    % Last resort fallback — only if training_patterns unavailable
                    target_q = cfg.probe_target_quad;
                    n_safe  = sum(q_slice == target_q);
                    n_total = length(q_slice);
                    n_other = n_total - n_safe;
                    if n_total > 0
                        quad_PI(k, s) = (n_safe - n_other) / n_total;
                    end
                end
            else
                % Standard diagonal-pair QPI
                pair1 = sum(q_slice == 1) + sum(q_slice == 3);
                pair2 = sum(q_slice == 2) + sum(q_slice == 4);
                denom = pair1 + pair2;
                if denom > 0
                    quad_PI(k, s) = (pair1 - pair2) / denom;
                end
            end
        end
    end

    quad_pref_results = struct();
    quad_pref_results.quad_PI = quad_PI;
    quad_pref_results.num_flies = num_flies;
    quad_pref_results.num_stims = num_stims;
end

function protocol = get_protocol_from_opts(opts)
    if isfield(opts, 'Protocol') && ~isempty(opts.Protocol)
        protocol = opts.Protocol;
    elseif isfield(opts, 'protocol') && ~isempty(opts.protocol)
        protocol = opts.protocol;
    else
        protocol = 'unknown';
    end
end