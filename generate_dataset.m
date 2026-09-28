%% GENERATE_DATASET
% Builds the labeled dataset for the azimuth SVM / Random-Forest classifier.
%
% For each azimuth sector, several ground-truth azimuth values are
% generated with random elevation and signal-condition jitter.
%
% Each sample is processed using extract_case_features.m.
%
% Elevation is used internally during signal generation because the
% simulated microphone signals depend on the full 3D source direction.
% However, NO elevation quantity is stored in the dataset.
%
% Output:
%   dataTable
%   dataset.mat
%   dataset.csv
%
% Dataset columns:
%
%   SampleID
%   Az_true
%   AzSector
%   TX_TDOA
%   TY_TDOA
%   Diagonal_TDOA_1
%   Diagonal_TDOA_2
%   MUSIC_Az
%   GCC_Az
%   ILD_dB
%   RMS_mean
%   FFT_PeakFreq
%   SpecEntropyNorm
%
% Requires:
%   Phased Array System Toolbox
%   Signal Processing Toolbox

clear;
clc;

%% ---------------------------------------------------------------
% Step 1: Array Geometry
% ---------------------------------------------------------------

geom = array_geometry();


%% ---------------------------------------------------------------
% Step 2: Fixed scene parameters
% ---------------------------------------------------------------

params.duration      = 1;       % seconds
params.event_start   = 0.35;    % seconds
params.event_end     = 0.65;    % seconds
params.ambient_amp   = 0.05;
params.event_amp     = 1.0;

% Base values. These are jittered for every sample.
params.sensor_SNR_dB = 20;
params.f0            = 1000;


%% ---------------------------------------------------------------
% Step 3: Azimuth sectors
% ---------------------------------------------------------------

% -90 to +90 degrees in 10-degree bins.
% This gives 18 azimuth sectors.

az_edges = -90:10:90;

num_az = length(az_edges) - 1;

az_names = arrayfun( ...
    @(k) sprintf('Az_%dto%d', az_edges(k), az_edges(k+1)), ...
    1:num_az, ...
    'UniformOutput', false);


%% ---------------------------------------------------------------
% Step 4: Elevation used internally for signal generation
% ---------------------------------------------------------------

% Elevation is NOT stored in the dataset.
% It is randomly varied so that the model does not only learn
% one fixed elevation condition.

el_range = [0 90];


%% ---------------------------------------------------------------
% Step 5: Per-sample nuisance jitter
% ---------------------------------------------------------------

% Random sensor SNR for every sample.
snr_jitter_range = [15 25];      % dB

% Random source/operating frequency for every sample.
f0_jitter_range = [800 1200];    % Hz


%% ---------------------------------------------------------------
% Step 6: Samples per azimuth sector
% ---------------------------------------------------------------

samples_per_sector = 100;

% Number of retries if a randomly generated sample fails.
max_retries = 5;

% Total number of desired samples.
total_target = num_az * samples_per_sector;


%% ---------------------------------------------------------------
% Step 7: Preallocate dataset storage
% ---------------------------------------------------------------

SampleID = zeros(total_target, 1);

Az_true = zeros(total_target, 1);

AzSector = strings(total_target, 1);

TX_TDOA = zeros(total_target, 1);
TY_TDOA = zeros(total_target, 1);

Diagonal_TDOA_1 = zeros(total_target, 1);
Diagonal_TDOA_2 = zeros(total_target, 1);

MUSIC_Az = zeros(total_target, 1);

GCC_Az = zeros(total_target, 1);

ILD_dB = zeros(total_target, 1);

RMS_mean = zeros(total_target, 1);

FFT_PeakFreq = zeros(total_target, 1);

SpecEntropyNorm = zeros(total_target, 1);


%% ---------------------------------------------------------------
% Step 8: Reproducible random generation
% ---------------------------------------------------------------

rng(42);


%% ---------------------------------------------------------------
% Step 9: Dataset generation
% ---------------------------------------------------------------

row = 0;

fprintf('\n');
fprintf('==============================================\n');
fprintf('        AZIMUTH DATASET GENERATION\n');
fprintf('==============================================\n');

fprintf(['Azimuth sectors : %d\n' ...
         'Samples/sector : %d\n' ...
         'Target samples : %d\n\n'], ...
         num_az, samples_per_sector, total_target);


for a = 1:num_az

    % Current azimuth sector limits.
    az_lo = az_edges(a);
    az_hi = az_edges(a + 1);


    for k = 1:samples_per_sector

        success = false;
        attempt = 0;


        %% Retry sample generation if the pipeline fails

        while ~success && attempt < max_retries

            attempt = attempt + 1;


            % ---------------------------------------------------
            % Random ground-truth azimuth inside current sector
            % ---------------------------------------------------

            az_true = az_lo + ...
                rand() * (az_hi - az_lo);


            % ---------------------------------------------------
            % Random elevation
            % ---------------------------------------------------
            %
            % Used only internally by extract_case_features().
            % It is NOT stored in the dataset.

            el_true = el_range(1) + ...
                rand() * diff(el_range);


            % ---------------------------------------------------
            % Random SNR
            % ---------------------------------------------------

            params_k = params;

            params_k.sensor_SNR_dB = ...
                snr_jitter_range(1) + ...
                rand() * diff(snr_jitter_range);


            % ---------------------------------------------------
            % Random operating frequency
            % ---------------------------------------------------

            params_k.f0 = ...
                f0_jitter_range(1) + ...
                rand() * diff(f0_jitter_range);


            %% Run complete feature-extraction pipeline

            try

                feat = extract_case_features( ...
                    az_true, ...
                    el_true, ...
                    geom, ...
                    params_k);

                success = true;

            catch ME

                if attempt == max_retries

                    warning( ...
                        'generate_dataset:skipRow', ...
                        ['Azimuth %s, sample %d failed after %d ' ...
                         'attempts (%s). Skipping sample.'], ...
                        az_names{a}, ...
                        k, ...
                        max_retries, ...
                        ME.message);

                end

            end

        end


        %% Skip sample if all retry attempts failed

        if ~success
            continue;
        end


        %% -------------------------------------------------------
        % Store successfully generated sample
        % --------------------------------------------------------

        row = row + 1;

        SampleID(row) = row;

        Az_true(row) = feat.az_true;

        AzSector(row) = az_names{a};


        % GCC-PHAT features

        TX_TDOA(row) = feat.tx;

        TY_TDOA(row) = feat.ty;

        Diagonal_TDOA_1(row) = ...
            feat.diagonal_pairs_tdoa_1;

        Diagonal_TDOA_2(row) = ...
            feat.diagonal_pairs_tdoa_2;


        % MUSIC azimuth

        MUSIC_Az(row) = feat.music_az;


        % Combined GCC-PHAT azimuth

        GCC_Az(row) = feat.gcc_az;


        % Signal features

        ILD_dB(row) = feat.ild_dB;

        RMS_mean(row) = feat.rms_mean;

        FFT_PeakFreq(row) = feat.fft_peak_freq;

        SpecEntropyNorm(row) = ...
            feat.spec_entropy_norm;

    end


    %% Progress information

    fprintf( ...
        'Azimuth %-14s done (%d/%d rows)\n', ...
        az_names{a}, ...
        row, ...
        total_target);

end


%% ---------------------------------------------------------------
% Step 10: Trim unused preallocated rows
% ---------------------------------------------------------------

SampleID = SampleID(1:row);

Az_true = Az_true(1:row);

AzSector = AzSector(1:row);

TX_TDOA = TX_TDOA(1:row);

TY_TDOA = TY_TDOA(1:row);

Diagonal_TDOA_1 = ...
    Diagonal_TDOA_1(1:row);

Diagonal_TDOA_2 = ...
    Diagonal_TDOA_2(1:row);

MUSIC_Az = MUSIC_Az(1:row);

GCC_Az = GCC_Az(1:row);

ILD_dB = ILD_dB(1:row);

RMS_mean = RMS_mean(1:row);

FFT_PeakFreq = FFT_PeakFreq(1:row);

SpecEntropyNorm = ...
    SpecEntropyNorm(1:row);


%% ---------------------------------------------------------------
% Step 11: Convert azimuth sector to categorical
% ---------------------------------------------------------------

AzSector = categorical(AzSector);


%% ---------------------------------------------------------------
% Step 12: Assemble dataset table
% ---------------------------------------------------------------

dataTable = table( ...
    SampleID, ...
    Az_true, ...
    AzSector, ...
    TX_TDOA, ...
    TY_TDOA, ...
    Diagonal_TDOA_1, ...
    Diagonal_TDOA_2, ...
    MUSIC_Az, ...
    GCC_Az, ...
    ILD_dB, ...
    RMS_mean, ...
    FFT_PeakFreq, ...
    SpecEntropyNorm);


%% ---------------------------------------------------------------
% Step 13: Display dataset information
% ---------------------------------------------------------------

fprintf('\n');
fprintf('==============================================\n');
fprintf('         DATASET GENERATION COMPLETE\n');
fprintf('==============================================\n');

fprintf('Rows kept : %d / %d\n\n', ...
    row, total_target);

disp(dataTable(1:min(5, row), :));


%% ---------------------------------------------------------------
% Step 14: Save dataset
% ---------------------------------------------------------------

save('dataset.mat', 'dataTable');

writetable(dataTable, 'dataset.csv');

fprintf('\nSaved:\n');
fprintf('  dataset.mat\n');
fprintf('  dataset.csv\n');


%% ---------------------------------------------------------------
% Step 15: Class balance check
% ---------------------------------------------------------------

fprintf('\n');
fprintf('--- Samples per azimuth sector ---\n');

summary(dataTable.AzSector);