%% summary_transit_density.m
% Per-genotype transit density summaries for all place-learning protocols.
%
% For each protocol:
%   1. Loads per-experiment transit_density_*.mat files
%   2. Validates matching grid/cycle structure
%   3. Sums FlyCountMap_Cycle across experiments within each genotype
%   4. Combines alternating training bouts within each block:
%        Odd trials (B_.1,3,5,7,9) → "B_.Odd"  (Q2/Q4 safe)
%        Even trials (B_.2,4,6,8,10) → "B_.Even" (Q1/Q3 safe)
%      Keeps OM1, PP, Ag, probes, OM2 as individual panels.
%   5. Generates condensed heatmap figure (~16 panels for P006–P010)
%      with blue → mustard yellow colormap
%   6. Saves combined .mat + .png + .svg to <PROTOCOL>/summary/transit_density/

% NOTE: clear/clc removed — this script is called from run_transit_density.
% Run standalone: do clear;clc manually before calling.


ANALYSIS_DIR = '/Users/rathores/Documents/analysisdatalocal';

protocols = {'P001', 'P002', 'P003', 'P005', 'P006', 'P007', 'P008', 'P009', 'P010', 'P011', 'P014'};

for p_idx = 1:length(protocols)
    PROTOCOL = protocols{p_idx};
    prot_path = fullfile(ANALYSIS_DIR, PROTOCOL);

    if ~exist(prot_path, 'dir')
        fprintf('Protocol %s directory not found, skipping.\n\n', PROTOCOL);
        continue;
    end

    summary_dir = fullfile(prot_path, 'summary', 'transit_density');
    if ~exist(summary_dir, 'dir'), mkdir(summary_dir); end

    fprintf('========================================\n');
    fprintf('  Summary Transit Density: %s\n', PROTOCOL);
    fprintf('========================================\n\n');

    %% Load all per-experiment transit_density .mat files
    exp_dirs = dir(prot_path);
    exp_dirs = exp_dirs([exp_dirs.isdir] & ~ismember({exp_dirs.name}, {'.', '..'}));

    % SAFEGUARD: Only process experiment directories (contain '_Rig' in name)
    exp_dirs = exp_dirs(contains({exp_dirs.name}, '_Rig'));

    all_data = {};
    for e = 1:length(exp_dirs)
        exp_name = exp_dirs(e).name;
        mat_file = fullfile(prot_path, exp_name, 'analysis', ...
                            sprintf('transit_density_%s.mat', exp_name));
        if ~exist(mat_file, 'file')
            fprintf('  %s — no transit_density .mat, skipping\n', exp_name);
            continue;
        end
        S = load(mat_file);
        all_data{end+1} = S; %#ok<AGROW>
        fprintf('  Loaded: %s (geno=%s, %d cycles, %d flies)\n', ...
            exp_name, S.genotype, size(S.DensityMap_Cycle, 3), S.num_flies_total);
    end

    nLoaded = length(all_data);
    fprintf('\nLoaded %d experiments for %s\n', nLoaded, PROTOCOL);
    if nLoaded == 0
        fprintf('No transit density data found. Run run_transit_density first.\n\n');
        continue;
    end

    %% Group by genotype
    genotypes = {};
    geno_idx  = {};
    for ei = 1:nLoaded
        geno = all_data{ei}.genotype;
        gi = find(strcmp(genotypes, geno), 1);
        if isempty(gi)
            genotypes{end+1} = geno; %#ok<AGROW>
            geno_idx{end+1}  = ei;   %#ok<AGROW>
        else
            geno_idx{gi} = [geno_idx{gi}, ei]; %#ok<AGROW>
        end
    end

    fprintf('Found %d genotypes: %s\n\n', length(genotypes), strjoin(genotypes, ', '));

    %% Process each genotype
    for gi = 1:length(genotypes)
        geno = genotypes{gi};
        exp_indices = geno_idx{gi};
        nExps = length(exp_indices);

        fprintf('  %s: %d experiments\n', geno, nExps);

        % Use first experiment as reference for grid/cycle dimensions
        ref = all_data{exp_indices(1)};
        nRows   = ref.nRows;
        nCols   = ref.nCols;
        nCycles = size(ref.DensityMap_Cycle, 3);

        % Initialize combined maps
        Combined_FlyCountMap = zeros(nRows, nCols, nCycles);
        Combined_PixelCount  = zeros(nRows, nCols);
        total_flies = 0;
        total_dead  = 0;
        exp_names   = {};

        for ei_idx = 1:nExps
            S = all_data{exp_indices(ei_idx)};

            % Validate dimensions
            if S.nRows ~= nRows || S.nCols ~= nCols
                fprintf('    WARNING: Grid mismatch in %s (%dx%d vs %dx%d), skipping\n', ...
                    S.experiment, S.nRows, S.nCols, nRows, nCols);
                continue;
            end
            nCyclesThis = size(S.DensityMap_Cycle, 3);
            if nCyclesThis ~= nCycles
                fprintf('    WARNING: Cycle mismatch in %s (%d vs %d), skipping\n', ...
                    S.experiment, nCyclesThis, nCycles);
                continue;
            end

            Combined_FlyCountMap = Combined_FlyCountMap + S.FlyCountMap_Cycle;
            Combined_PixelCount = max(Combined_PixelCount, S.PixelCountMap);
            total_flies = total_flies + S.num_flies_total;
            total_dead  = total_dead  + S.num_dead;
            exp_names{end+1} = S.experiment; %#ok<AGROW>
        end

        % Recompute density from combined counts
        Combined_DensityMap = zeros(nRows, nCols, nCycles);
        for c = 1:nCycles
            tmp = Combined_FlyCountMap(:,:,c) ./ Combined_PixelCount;
            tmp(isnan(tmp) | isinf(tmp)) = 0;
            Combined_DensityMap(:,:,c) = tmp;
        end

        %% Build condensed panels: combine alternate training bouts
        cycle_labels = ref.cycle_labels;
        [condensed_maps, condensed_labels] = condense_training_bouts( ...
            Combined_DensityMap, cycle_labels);

        %% Plot condensed heatmaps
        fig = plot_condensed_heatmaps(condensed_maps, condensed_labels, ...
                                      geno, PROTOCOL, nExps, total_flies);

        % Save figure
        png_file = fullfile(summary_dir, sprintf('transit_density_%s_%s.png', PROTOCOL, geno));
        svg_file = fullfile(summary_dir, sprintf('transit_density_%s_%s.svg', PROTOCOL, geno));

        exportgraphics(fig, png_file, 'Resolution', 300);
        print(fig, svg_file, '-dsvg');
        fprintf('    Saved: %s\n', png_file);
        fprintf('    Saved: %s\n', svg_file);
        close(fig);

        %% Save combined .mat (full per-cycle data preserved)
        combined = struct();
        combined.genotype            = geno;
        combined.protocol            = PROTOCOL;
        combined.nRows               = nRows;
        combined.nCols               = nCols;
        combined.nExperiments        = nExps;
        combined.experiment_names    = {exp_names};
        combined.total_flies         = total_flies;
        combined.total_dead          = total_dead;
        combined.FlyCountMap_Cycle   = Combined_FlyCountMap;
        combined.DensityMap_Cycle    = Combined_DensityMap;
        combined.PixelCountMap       = Combined_PixelCount;
        combined.cycle_labels        = cycle_labels;

        mat_file = fullfile(summary_dir, sprintf('transit_density_%s_%s.mat', PROTOCOL, geno));
        save(mat_file, '-struct', 'combined');
        fprintf('    Saved: %s\n', mat_file);
    end

    %% All-genotype comparison figure (condensed view)
    if length(genotypes) > 1
        ref = all_data{geno_idx{1}(1)};
        cycle_labels_ref = ref.cycle_labels;
        nGenos = length(genotypes);

        % Build condensed density for each genotype
        geno_condensed = cell(nGenos, 1);
        condensed_labels = {};
        global_max_all = 0;

        for gi = 1:nGenos
            exp_indices = geno_idx{gi};
            ref_g = all_data{exp_indices(1)};
            nR = ref_g.nRows; nC = ref_g.nCols;
            nCyc = size(ref_g.DensityMap_Cycle, 3);

            combined_fc = zeros(nR, nC, nCyc);
            combined_pc = zeros(nR, nC);
            for ei_idx = 1:length(exp_indices)
                S = all_data{exp_indices(ei_idx)};
                if S.nRows == nR && S.nCols == nC && size(S.DensityMap_Cycle, 3) == nCyc
                    combined_fc = combined_fc + S.FlyCountMap_Cycle;
                    combined_pc = max(combined_pc, S.PixelCountMap);
                end
            end
            combined_dens = zeros(nR, nC, nCyc);
            for c = 1:nCyc
                tmp = combined_fc(:,:,c) ./ combined_pc;
                tmp(isnan(tmp) | isinf(tmp)) = 0;
                combined_dens(:,:,c) = tmp;
            end

            [cond_maps, cond_labels] = condense_training_bouts(combined_dens, cycle_labels_ref);
            geno_condensed{gi} = cond_maps;
            condensed_labels = cond_labels;
            global_max_all = max(global_max_all, max(cond_maps(:)));
        end

        if global_max_all == 0, global_max_all = 1; end

        nPanels = size(geno_condensed{1}, 3);

        % Blue → Mustard Yellow colormap
        nColors = 256;
        cmap = [linspace(0.1,0.9,nColors)', ...
                linspace(0.1,0.75,nColors)', ...
                linspace(0.4,0.1,nColors)'];

        fig_all = figure('Units','normalized','Position',[0.01 0.01 0.98 0.95], 'Visible','off');
        t = tiledlayout(nGenos, nPanels, 'Padding','compact', 'TileSpacing','compact');

        for gi = 1:nGenos
            for si = 1:nPanels
                ax = nexttile;
                imagesc(geno_condensed{gi}(:,:,si));
                axis image off;
                colormap(ax, cmap);
                clim([0 global_max_all]);

                if gi == 1
                    title(condensed_labels{si}, 'FontSize', 9, 'FontWeight', 'bold');
                end
                if si == 1
                    ylabel(genotypes{gi}, 'FontSize', 11, 'FontWeight', 'bold');
                end
            end
        end

        hcb = colorbar;
        hcb.Layout.Tile = 'east';
        ylabel(hcb, 'Density');
        hcb.FontSize = 10;

        sgtitle(sprintf('Transit Density — %s (All Genotypes, Bouts Combined)', PROTOCOL), ...
            'FontSize', 13, 'FontWeight', 'bold');

        png_all = fullfile(summary_dir, sprintf('transit_density_%s_all_genotypes.png', PROTOCOL));
        exportgraphics(fig_all, png_all, 'Resolution', 300);
        fprintf('  Saved all-genotype comparison: %s\n', png_all);
        close(fig_all);
    end

    fprintf('\n  %s summary complete.\n\n', PROTOCOL);
end

fprintf('All protocols processed.\n');
fprintf('Done: %s\n\n', datestr(now));


%% ========================================================================
%  HELPER: Condense training bouts (average odd + even within each block)
%  ========================================================================
function [condensed_maps, condensed_labels] = condense_training_bouts(DensityMap_Cycle, cycle_labels)
% Combines alternate training bouts within each block.
%
% For place-learning protocols (P003/P005/P006-P010):
%   Odd  trials (B_.1, B_.3, B_.5, B_.7, B_.9) → averaged into "B_.Odd"
%   Even trials (B_.2, B_.4, B_.6, B_.8, B_.10) → averaged into "B_.Even"
%   Special cycles (OM1, PP, Ag, B_.P, OM2) kept as-is.
%
% For other protocols (P001/P002): all cycles shown individually.

    nCycles = size(DensityMap_Cycle, 3);
    nR = size(DensityMap_Cycle, 1);
    nC = size(DensityMap_Cycle, 2);

    % Check if this is a place-learning protocol with block structure
    has_blocks = any(contains(cycle_labels, 'B1.1'));

    if ~has_blocks
        % No block structure — return as-is
        condensed_maps = DensityMap_Cycle;
        condensed_labels = cycle_labels;
        return;
    end

    condensed_maps   = [];
    condensed_labels = {};

    ci = 1;
    while ci <= nCycles
        lbl = cycle_labels{ci};

        % Check if this is a training trial (B_.digit)
        tok = regexp(lbl, '^B(\d+)\.(\d+)$', 'tokens', 'once');

        if ~isempty(tok)
            % Start of a training block — collect all 10 trials + probe
            blk_num = str2double(tok{1});

            % Find all cycles for this block
            odd_idx  = [];
            even_idx = [];
            probe_ci = [];

            while ci <= nCycles
                lbl_i = cycle_labels{ci};
                tok_i = regexp(lbl_i, sprintf('^B%d\\.(\\d+)$', blk_num), 'tokens', 'once');
                if ~isempty(tok_i)
                    trial_num = str2double(tok_i{1});
                    if mod(trial_num, 2) == 1
                        odd_idx(end+1) = ci; %#ok<AGROW>
                    else
                        even_idx(end+1) = ci; %#ok<AGROW>
                    end
                    ci = ci + 1;
                elseif strcmp(lbl_i, sprintf('B%d.P', blk_num))
                    probe_ci = ci;
                    ci = ci + 1;
                    break;
                else
                    break;
                end
            end

            % Average odd trials
            if ~isempty(odd_idx)
                avg_odd = mean(DensityMap_Cycle(:,:,odd_idx), 3);
                condensed_maps = cat(3, condensed_maps, avg_odd);
                condensed_labels{end+1} = sprintf('B%d.Odd', blk_num);
            end

            % Average even trials
            if ~isempty(even_idx)
                avg_even = mean(DensityMap_Cycle(:,:,even_idx), 3);
                condensed_maps = cat(3, condensed_maps, avg_even);
                condensed_labels{end+1} = sprintf('B%d.Even', blk_num);
            end

            % Probe
            if ~isempty(probe_ci)
                condensed_maps = cat(3, condensed_maps, DensityMap_Cycle(:,:,probe_ci));
                condensed_labels{end+1} = sprintf('B%d.P', blk_num);
            end
        else
            % Non-training cycle (OM1, PP, Ag, OM2) — keep as-is
            condensed_maps = cat(3, condensed_maps, DensityMap_Cycle(:,:,ci));
            condensed_labels{end+1} = lbl;
            ci = ci + 1;
        end
    end
end


%% ========================================================================
%  HELPER: Plot condensed heatmaps (blue → mustard yellow)
%  ========================================================================
function fig = plot_condensed_heatmaps(condensed_maps, condensed_labels, geno, protocol, nExps, nFlies)
    nPanels = size(condensed_maps, 3);

    % Blue → Mustard Yellow colormap
    nColors = 256;
    cmap = [linspace(0.1,0.9,nColors)', ...
            linspace(0.1,0.75,nColors)', ...
            linspace(0.4,0.1,nColors)'];

    globalMax = max(condensed_maps(:));
    if globalMax == 0, globalMax = 1; end

    fig = figure('Units','normalized','Position',[0.02 0.1 0.95 0.55], 'Visible','off');

    maxCols = min(nPanels, 16);
    tiledCols = maxCols;
    tiledRows = ceil(nPanels / tiledCols);

    t = tiledlayout(tiledRows, tiledCols, 'Padding','compact', 'TileSpacing','compact');

    for c = 1:nPanels
        ax = nexttile;
        imagesc(condensed_maps(:,:,c));
        axis image off;

        lbl = condensed_labels{c};
        title(lbl, 'FontSize', 9, 'FontWeight', 'bold');

        colormap(ax, cmap);
        clim([0 globalMax]);
    end

    hcb = colorbar;
    hcb.Layout.Tile = 'east';
    ylabel(hcb, 'Density (Flies / Area)');
    hcb.FontSize = 10;

    sgtitle(sprintf('Transit Density — %s %s (n=%d expts, %d flies)', ...
        protocol, geno, nExps, nFlies), ...
        'FontSize', 13, 'FontWeight', 'bold');
end
