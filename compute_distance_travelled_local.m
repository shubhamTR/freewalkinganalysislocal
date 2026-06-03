function distance_results = compute_distance_travelled_local(trx, LED_detector_thresh, opts)
% COMPUTE_DISTANCE_TRAVELLED - Calculate distance per fly per cycle
    
    on_times = LED_detector_thresh.on_times;
    off_times = LED_detector_thresh.off_times;
    num_cycles = length(on_times);
    num_flies = length(trx);
    pixels_per_mm = opts.PixelsPerMM;
    
    % Convert to mm
    for f = 1:num_flies
        trx(f).x_mm = trx(f).x / pixels_per_mm;
        trx(f).y_mm = trx(f).y / pixels_per_mm;
    end
    
    % Frame-to-frame distance
    for f = 1:num_flies
        dx = diff(trx(f).x_mm);
        dy = diff(trx(f).y_mm);
        trx(f).frame_distance = sqrt(dx.^2 + dy.^2);
    end
    
    % Sum per cycle
    distance_mm = nan(num_flies, num_cycles);
    velocity_mm_per_s = nan(num_flies, num_cycles);
    
    for f = 1:num_flies
        for c = 1:num_cycles
            frames = on_times(c):min(off_times(c)-1, length(trx(f).frame_distance));
            
            if ~isempty(frames)
                distance_mm(f, c) = nansum(trx(f).frame_distance(frames));
                
                if length(frames) > 1
                    dt = mean(diff(trx(f).timestamps(frames)), 'omitnan');
                    velocity_mm_per_s(f, c) = distance_mm(f, c) / (length(frames) * dt);
                end
            end
        end
    end
    
    distance_results = struct();
    distance_results.distance_mm = distance_mm;
    distance_results.velocity_mm_per_s = velocity_mm_per_s;
    distance_results.num_flies = num_flies;
    distance_results.num_cycles = num_cycles;
    distance_results.pixels_per_mm = pixels_per_mm;
end