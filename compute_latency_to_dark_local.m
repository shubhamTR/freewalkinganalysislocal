function latency_results = compute_latency_to_dark_local(trx, all_masks, LED_detector_thresh, opts)
% COMPUTE_LATENCY_TO_DARK - Find first entry to safe quadrant
%
% USAGE:
%   latency_results = compute_latency_to_dark(trx, all_masks, LED_detector_thresh, opts)

    fps = opts.FPS;
    num_flies = length(trx);
    on_times = LED_detector_thresh.on_times;
    off_times = LED_detector_thresh.off_times;
    num_stims = length(on_times);
    
    % Map to quadrants if not already done
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
    
    % Define stimulus protocol
    [stim_type, lit_quads] = define_stimulus_protocol(num_stims);
    
    % Initialize latency matrix
    first_dark_entry = nan(num_flies, num_stims);
    
    % Find first entry to dark quadrant for each stimulus
    for s = 1:num_stims
        stim_frames = on_times(s):off_times(s);
        
        % Determine which quadrants are dark (safe)
        if strcmp(stim_type{s}, 'training') || strcmp(stim_type{s}, 'pre-training')
            dark_quads = setdiff(1:4, lit_quads{s});
        else
            dark_quads = [2, 4];  % For probes
        end
        
        for k = 1:num_flies
            quad_traj = trx(k).quad(stim_frames);
            min_entry = inf;
            
            for q = dark_quads
                % Skip if fly starts in this quadrant
                if quad_traj(1) == q
                    continue;
                end
                
                % Find first frame in this quadrant
                entry_idx = find(quad_traj == q, 1, 'first');
                if ~isempty(entry_idx)
                    min_entry = min(min_entry, entry_idx);
                end
            end
            
            % Convert frame to seconds
            if min_entry < inf
                first_dark_entry(k, s) = (min_entry - 1) / fps;
            end
        end
    end
    
    % Package results
    latency_results = struct();
    latency_results.first_dark_entry = first_dark_entry;
    latency_results.stim_type = stim_type;
    latency_results.lit_quads = lit_quads;
    latency_results.num_flies = num_flies;
    latency_results.num_stims = num_stims;
end

function [stim_type, lit_quads] = define_stimulus_protocol(num_stims)
    % Define standard stimulus protocol
    
    stim_type = cell(num_stims, 1);
    lit_quads = cell(num_stims, 1);
    
    training_blocks = {3:12, 14:23, 25:34, 36:45};
    probe_stims = [1, 13, 24, 35, 46];
    
    for s = 1:num_stims
        if s == 1
            stim_type{s} = 'pre-probe';
            lit_quads{s} = [1 2 3 4];
        elseif s == 2
            stim_type{s} = 'pre-training';
            lit_quads{s} = [2 4];
        elseif ismember(s, probe_stims(2:end))
            stim_type{s} = 'probe';
            lit_quads{s} = [1 2 3 4];
        else
            in_training = false;
            for b = 1:length(training_blocks)
                if ismember(s, training_blocks{b})
                    in_training = true;
                    block_start = training_blocks{b}(1);
                    pos_in_block = s - block_start + 1;
                    
                    if mod(pos_in_block, 2) == 1
                        lit_quads{s} = [1 3];
                    else
                        lit_quads{s} = [2 4];
                    end
                    break;
                end
            end
            
            if in_training
                stim_type{s} = 'training';
            else
                stim_type{s} = 'other';
                lit_quads{s} = [1 2 3 4];
            end
        end
    end
end