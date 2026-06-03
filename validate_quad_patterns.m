function quad_patterns = validate_quad_patterns(exp_path, quad_patterns_config)
% VALIDATE_QUAD_PATTERNS  Compare config quad patterns with metadata ground truth.
%
%   quad_patterns = validate_quad_patterns(exp_path, quad_patterns_config)
%
%   Parses the experiment's metadata file to extract the actual LED patterns
%   used by the rig, and compares them with the hardcoded config patterns.
%   If they match, returns the config patterns unchanged.
%   If they differ, returns the METADATA patterns (ground truth) and warns.
%   If metadata cannot be parsed, returns config patterns with a warning.
%
%   This ensures that QPI, latency, distance-to-safe, and distance
%   computations always use the correct quadrant assignments, even when
%   the protocol uses randomized trial orders (e.g., P009).

    [~, exp_name] = fileparts(exp_path);

    % Parse metadata
    metadata_patterns = parse_metadata_led_patterns(exp_path);

    if isempty(metadata_patterns)
        fprintf('    WARNING: No metadata found for %s — using config patterns\n', exp_name);
        quad_patterns = quad_patterns_config;
        return;
    end

    % Compare lengths
    n_config = length(quad_patterns_config);
    n_meta   = length(metadata_patterns);

    if n_config ~= n_meta
        fprintf('    WARNING: Metadata has %d cycles, config has %d for %s — using metadata\n', ...
            n_meta, n_config, exp_name);
        quad_patterns = metadata_patterns;
        return;
    end

    % Compare each cycle
    mismatches = 0;
    for c = 1:n_config
        if ~strcmp(quad_patterns_config{c}, metadata_patterns{c})
            mismatches = mismatches + 1;
        end
    end

    if mismatches > 0
        fprintf('    WARNING: %d/%d quad pattern mismatches in %s — using metadata (ground truth)\n', ...
            mismatches, n_config, exp_name);
        quad_patterns = metadata_patterns;
    else
        quad_patterns = quad_patterns_config;
    end
end
