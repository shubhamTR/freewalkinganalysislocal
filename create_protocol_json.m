%% create_protocol_json.m
% -----------------------------------------------------------------------
% PURPOSE: Generate a protocol JSON config file for the analysis pipeline.
%          Fill in the parameters below (copied from your recording script)
%          and run. The JSON is saved to protocols/<protocolNumber>.json.
%
% USAGE:
%   1. Copy the parameter values from your recording script (P026.m etc.)
%   2. Run this script
%   3. JSON is written to protocols/P026.json automatically
%
% The generated JSON is read by get_protocol_config.m so the new protocol
% is immediately available to the entire pipeline — no other edits needed.
% -----------------------------------------------------------------------

clear; close all;

%% ==================================================================
%  FILL IN THESE PARAMETERS FROM YOUR RECORDING SCRIPT
%  ==================================================================

% --- Identity ---
protocolNumber      = 'P017';
displayName         = 'Coupled';           % Short label for plots
experimentDescription = 'Optomotor_Mode2SD_PlaceLearning_SBD_ProbeIntensity6';

% --- Structure flags ---
hasOptomotor        = true;    % Does the protocol have OM1/OM2 phases?
isPlaceLearning     = true;    % Does it have training blocks + probes?
isSingleQuadrant    = true;    % Single dark quad (P013/P017/P019 style)?
                               %   false = diagonal pair (P008/P014 style)
isIntensityRamp     = false;   % Intensity ramp protocol (P001/P002 style)?

% --- Place learning structure ---
numBlocks           = 3;       % Number of training blocks
flipsPerBlock       = 10;      % Training trials per block
trialDuration_s     = 40;      % Training trial duration (seconds)
probeDuration_s     = 40;      % Probe trial duration (seconds)

% --- LED parameters ---
ledIntensityTraining  = 8;     % LED intensity during training + pre-agitation
ledIntensityProbe     = 6;     % LED intensity during preprobe + block probes
ledPatterns           = {'1101','1011','0111','1110'};  % one per orientation
                               % For diagonal-pair protocols use: {'1010','0101'}

% --- Single-quadrant mapping (only used if isSingleQuadrant = true) ---
% Maps LED pattern position (1-4) to quadrant number.
% From led_pattern_to_quads.m: pos1->Q2, pos2->Q3, pos3->Q4, pos4->Q1
% The '0' position in each pattern is the safe quadrant.
% e.g. '1101' has '0' at pos3 -> Q4 is safe.
ledToQuad           = [2, 3, 4, 1];   % hardware wiring, do not change
probeTargetQuad     = 2;              % default safe quad for probes without metadata

% --- Calibration ---
pixelsPerMM         = 8.21;    % from trx.pxpermm (use get_mean_pxpermm if unsure)
cameraFPS           = 30.1;

% --- Optomotor (only used if hasOptomotor = true) ---
optomotorDuration_s = 50;      % per direction (CW or CCW)
interDirectionPause_s = 5;

%% ==================================================================
%  DERIVED — cycle structure built automatically, do not edit
%% ==================================================================

% Validate
assert(~isempty(protocolNumber), 'protocolNumber must be set');
assert(isPlaceLearning || isIntensityRamp, ...
    'Protocol must be place learning or intensity ramp (or both flags wrong)');

% Build cycle index map
% Structure: [OM1] [PP] [Ag] [B1.1..B1.N B1.P] ... [BK.1..BK.N BK.P] [OM2]
cycleNum = 0;
cycleLabels   = {};
cycleColors   = {};   % 'r'=training, 'g'=probe, 'b'=optomotor, 'k'=PP/Ag
cycleSections = {};   % 'training'|'probe'|'optomotor'|'preprobe'|'agitation'

omCycles = [];
ppCycle  = [];
agCycle  = [];
trainingBlocks = {};   % cell of cycle index vectors, one per block
blockProbes    = [];   % one probe cycle index per block

if isPlaceLearning

    if hasOptomotor
        cycleNum = cycleNum + 1;
        cycleLabels{end+1}   = 'OM1';
        cycleColors{end+1}   = [0.5 0.5 0.5];
        cycleSections{end+1} = 'optomotor';
        omCycles(end+1)      = cycleNum;
    end

    % Preprobe
    cycleNum = cycleNum + 1;
    cycleLabels{end+1}   = 'PP';
    cycleColors{end+1}   = [0.8 0.8 0.0];
    cycleSections{end+1} = 'preprobe';
    ppCycle              = cycleNum;

    % Pre-agitation
    cycleNum = cycleNum + 1;
    cycleLabels{end+1}   = 'Ag';
    cycleColors{end+1}   = [1.0 0.5 0.0];
    cycleSections{end+1} = 'agitation';
    agCycle              = cycleNum;

    % Training blocks + probes
    for blk = 1:numBlocks
        blockCycles = zeros(1, flipsPerBlock);
        for t = 1:flipsPerBlock
            cycleNum = cycleNum + 1;
            cycleLabels{end+1}   = sprintf('B%d.%d', blk, t);
            cycleColors{end+1}   = [0.8 0.1 0.1];
            cycleSections{end+1} = 'training';
            blockCycles(t)       = cycleNum;
        end
        trainingBlocks{blk} = blockCycles;

        % Block probe
        cycleNum = cycleNum + 1;
        cycleLabels{end+1}   = sprintf('B%d.P', blk);
        cycleColors{end+1}   = [0.8 0.8 0.0];
        cycleSections{end+1} = 'probe';
        blockProbes(end+1)   = cycleNum;
    end

    if hasOptomotor
        cycleNum = cycleNum + 1;
        cycleLabels{end+1}   = 'OM2';
        cycleColors{end+1}   = [0.5 0.5 0.5];
        cycleSections{end+1} = 'optomotor';
        omCycles(end+1)      = cycleNum;
    end

end

numCycles = cycleNum;

% Convenience fields
allProbeCycles = [ppCycle, blockProbes];
probeLabels    = [{'PP'}, arrayfun(@(b) sprintf('B%d.P',b), 1:numBlocks, 'UniformOutput', false)];

fprintf('Protocol %s: %d cycles total\n', protocolNumber, numCycles);
fprintf('  OM:       %s\n', mat2str(omCycles));
fprintf('  PP:       %d\n', ppCycle);
fprintf('  Ag:       %d\n', agCycle);
for b = 1:numBlocks
    fprintf('  B%d train: %s  |  probe: %d\n', b, mat2str(trainingBlocks{b}), blockProbes(b));
end

%% ==================================================================
%  BUILD JSON STRUCT
%% ==================================================================

cfg = struct();
cfg.protocol_number       = protocolNumber;
cfg.display_name          = displayName;
cfg.description           = experimentDescription;
cfg.num_cycles            = numCycles;
cfg.has_optomotor         = hasOptomotor;
cfg.is_place_learning     = isPlaceLearning;
cfg.is_single_quadrant    = isSingleQuadrant;
cfg.is_intensity          = isIntensityRamp;
cfg.num_blocks            = numBlocks;
cfg.flips_per_block       = flipsPerBlock;
cfg.trial_duration_s      = trialDuration_s;
cfg.probe_duration_s      = probeDuration_s;
cfg.led_intensity_training = ledIntensityTraining;
cfg.led_intensity_probe    = ledIntensityProbe;
cfg.led_patterns           = ledPatterns;
cfg.pixels_per_mm          = pixelsPerMM;
cfg.camera_fps             = cameraFPS;

if isSingleQuadrant
    cfg.led_to_quad        = ledToQuad;
    cfg.probe_target_quad  = probeTargetQuad;
end

if hasOptomotor
    cfg.optomotor_duration_s      = optomotorDuration_s;
    cfg.inter_direction_pause_s   = interDirectionPause_s;
    cfg.om_cycles                 = omCycles;
end

cfg.pp_cycle              = ppCycle;
cfg.ag_cycle              = agCycle;
cfg.training_blocks       = trainingBlocks;
cfg.block_probe_cycles    = blockProbes;
cfg.all_probe_cycles      = allProbeCycles;
cfg.probe_labels          = probeLabels;
cfg.labels                = cycleLabels;
cfg.colors                = cycleColors;
cfg.sections              = cycleSections;

%% ==================================================================
%  WRITE JSON
%% ==================================================================

scriptDir   = fileparts(mfilename('fullpath'));
protocolDir = fullfile(scriptDir, 'protocols');
if ~exist(protocolDir, 'dir')
    mkdir(protocolDir);
    fprintf('Created protocols/ directory\n');
end

outFile = fullfile(protocolDir, sprintf('%s.json', protocolNumber));
fid = fopen(outFile, 'w');
fprintf(fid, '%s', jsonencode(cfg, 'PrettyPrint', true));
fclose(fid);

fprintf('\nSaved: %s\n', outFile);
fprintf('Protocol %s is now available to the pipeline.\n', protocolNumber);
