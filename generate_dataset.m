%% GENERATE_DATASET - Builds the labeled dataset (dataTable) for the
%                     SVM/Random-Forest azimuth+elevation sector
%                     classifiers.
%
%   For each (azimuth sector, elevation sector) cell in a 2D grid, draws
%   several jittered (az, el) ground-truth directions, runs the full
%   pipeline via extract_case_features.m, and assembles a table with all
%   7 features plus the azimuth/elevation sector labels.
%
%   Output: dataTable, saved to dataset.mat and dataset.csv
%
%   Columns:
%       SampleID, Az_true, El_true, AzSector, ElSector, Sector,
%       MUSIC_Az, MUSIC_El, GCC_Angle, ILD_dB, RMS_mean,
%       FFT_PeakFreq, SpecEntropyNorm
%
%   NOTE: music_doa.m's ElevationScanAngles was updated from -45:1:45 to
%   0:1:90 so MUSIC actually searches the elevation range used here -
%   without that change every sample above 45 deg would be estimated
%   against a scan grid that doesn't include the true angle.
%
% Requires: Phased Array System Toolbox, Signal Processing Toolbox

clear; clc;

%% --- Step 1: Array Geometry ---
geom = array_geometry();

%% --- Step 2: Fixed scene parameters (match main.m defaults) ---
params.duration      = 1;      % seconds
params.event_start   = 0.35;   % seconds
params.event_end     = 0.65;   % seconds
params.ambient_amp   = 0.05;
params.event_amp     = 1.0;
params.sensor_SNR_dB = 20;     % base SNR (dB); jittered per-sample below
params.f0             = 1000;   % base operating frequency (Hz); jittered below

%% --- Step 3: Azimuth sector boundaries ---
% -90 to +90 deg in 10 deg bins (18 sectors). Matches music_doa.m's
% AzimuthScanAngles range - the square ReSpeaker array can't resolve
% front/back ambiguity beyond +-90 deg anyway.
az_edges     = -90:10:90;                  % 19 edges -> 18 sectors
num_az       = length(az_edges) - 1;
az_names     = arrayfun(@(k) sprintf('Az_%dto%d', az_edges(k), az_edges(k+1)), ...
    1:num_az, 'UniformOutput', false);

%% --- Step 4: Elevation sector boundaries ---
% 0 to 90 deg in 10 deg bins (9 sectors). Requires music_doa.m's
% ElevationScanAngles to cover 0:90 (see note above) - it has been
% updated accordingly.
el_edges     = 0:10:90;                    % 10 edges -> 9 sectors
num_el       = length(el_edges) - 1;
el_names     = arrayfun(@(k) sprintf('El_%dto%d', el_edges(k), el_edges(k+1)), ...
    1:num_el, 'UniformOutput', false);

%% --- Step 5: Per-sample nuisance jitter ---
% Added on top of the (az, el) draw so the dataset captures realistic
% acoustic-scene variability rather than identical conditions repeated
% at different angles.
snr_jitter_range = [15 25];    % dB
f0_jitter_range  = [800 1200]; % Hz

%% --- Step 6: Samples per (azimuth, elevation) grid cell ---
% 18 x 9 = 162 grid cells. Kept modest by default since runtime scales
% with num_az * num_el * samples_per_cell - raise this once the pipeline
% has been verified to run cleanly end-to-end.
samples_per_cell = 10;         % -> 1620 rows total
max_retries       = 5;         % resample attempts if a draw is degenerate

%% --- Step 7: Preallocate row storage ---
total_target = num_az * num_el * samples_per_cell;

SampleID        = zeros(total_target, 1);
Az_true         = zeros(total_target, 1);
El_true         = zeros(total_target, 1);
AzSector        = strings(total_target, 1);
ElSector        = strings(total_target, 1);
MUSIC_Az        = zeros(total_target, 1);
MUSIC_El        = zeros(total_target, 1);
GCC_Angle       = zeros(total_target, 1);
ILD_dB          = zeros(total_target, 1);
RMS_mean        = zeros(total_target, 1);
FFT_PeakFreq    = zeros(total_target, 1);
SpecEntropyNorm = zeros(total_target, 1);

rng(42);   % reproducible dataset

%% --- Step 8: Generation loop ---
row = 0;
fprintf('Generating dataset: %d az sectors x %d el sectors x %d samples/cell = %d rows\n', ...
    num_az, num_el, samples_per_cell, total_target);

for a = 1:num_az

    az_lo = az_edges(a);
    az_hi = az_edges(a + 1);

    for e = 1:num_el

        el_lo = el_edges(e);
        el_hi = el_edges(e + 1);

        for k = 1:samples_per_cell

            success = false;
            attempt = 0;

            while ~success && attempt < max_retries
                attempt = attempt + 1;

                % Jitter az/el uniformly within their respective bins.
                az_true = az_lo + rand() * (az_hi - az_lo);
                el_true = el_lo + rand() * (el_hi - el_lo);

                % Per-sample nuisance jitter on SNR / operating frequency.
                params_k = params;
                params_k.sensor_SNR_dB = snr_jitter_range(1) + ...
                    rand() * diff(snr_jitter_range);
                params_k.f0 = f0_jitter_range(1) + rand() * diff(f0_jitter_range);

                try
                    feat = extract_case_features(az_true, el_true, geom, params_k);
                    success = true;
                catch ME
                    if attempt == max_retries
                        warning('generate_dataset:skipRow', ...
                            'Az %s / El %s sample %d failed after %d attempts (%s) - skipping.', ...
                            az_names{a}, el_names{e}, k, max_retries, ME.message);
                    end
                end
            end

            if ~success
                continue;   % leave preallocated row out at trim step
            end

            row = row + 1;

            SampleID(row)        = row;
            Az_true(row)         = feat.az_true;
            El_true(row)         = feat.el_true;
            AzSector(row)        = az_names{a};
            ElSector(row)        = el_names{e};
            MUSIC_Az(row)        = feat.music_az;
            MUSIC_El(row)        = feat.music_el;
            GCC_Angle(row)       = feat.gcc_angle;
            ILD_dB(row)          = feat.ild_dB;
            RMS_mean(row)        = feat.rms_mean;
            FFT_PeakFreq(row)    = feat.fft_peak_freq;
            SpecEntropyNorm(row) = feat.spec_entropy_norm;
        end
    end

    fprintf('  Azimuth %-14s done (%d/%d rows so far)\n', az_names{a}, row, total_target);
end

%% --- Step 9: Trim any unfilled rows (from skipped degenerate draws) ---
SampleID        = SampleID(1:row);
Az_true         = Az_true(1:row);
El_true         = El_true(1:row);
AzSector        = AzSector(1:row);
ElSector        = ElSector(1:row);
MUSIC_Az        = MUSIC_Az(1:row);
MUSIC_El        = MUSIC_El(1:row);
GCC_Angle       = GCC_Angle(1:row);
ILD_dB          = ILD_dB(1:row);
RMS_mean        = RMS_mean(1:row);
FFT_PeakFreq    = FFT_PeakFreq(1:row);
SpecEntropyNorm = SpecEntropyNorm(1:row);

AzSector = categorical(AzSector);
ElSector = categorical(ElSector);
Sector   = categorical(strcat(string(AzSector), '_', string(ElSector)));  % combined label

%% --- Step 10: Assemble dataTable ---
dataTable = table(SampleID, Az_true, El_true, AzSector, ElSector, Sector, ...
    MUSIC_Az, MUSIC_El, GCC_Angle, ILD_dB, RMS_mean, ...
    FFT_PeakFreq, SpecEntropyNorm);

fprintf('\nDataset generation complete: %d / %d rows kept.\n', row, total_target);
disp(dataTable(1:min(5, row), :));   % quick spot-check preview

%% --- Step 11: Save dataset ---
save('dataset.mat', 'dataTable');
writetable(dataTable, 'dataset.csv');
fprintf('Saved dataset.mat and dataset.csv (%d rows).\n', row);

%% --- Step 12: Class balance check ---
fprintf('\n--- Row count per azimuth sector (should be ~%d each) ---\n', samples_per_cell * num_el);
summary(dataTable.AzSector);
fprintf('\n--- Row count per elevation sector (should be ~%d each) ---\n', samples_per_cell * num_az);
summary(dataTable.ElSector);
