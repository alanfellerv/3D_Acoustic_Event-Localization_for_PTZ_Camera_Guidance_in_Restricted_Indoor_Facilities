%% GENERATE_DATASET
% Builds the labeled dataset for the azimuth SVM / Random-Forest classifier.
%
% For each Elevation sector, several ground-truth Elevation values are
% generated with random Azimuth and signal-condition jitter.
%
% Each sample is processed using extract_case_features.m.
%
% Azimuth is used internally during signal generation because the
% simulated microphone signals depend on the full 3D source direction.
% However, NO azimuth quantity is stored in the dataset.
%
% Output:
%   dataTable
%   dataset.mat
%   dataset.csv
%
% Dataset columns:
%
%   SampleID
%   El_true
%   ElSector
%   TX_TDOA
%   TY_TDOA
%   TZ_TDOA
%   MUSIC_El
%   GCC_El
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
% Step 3: Elevation sectors
% ---------------------------------------------------------------

% 0 to +90 degrees in 10-degree bins.
% This gives 8 elevation sectors.

el_edges = 0:10:90;

num_el = length(el_edges) - 1;

el_names = arrayfun( ...
    @(k) sprintf('el_%dto%d', el_edges(k), el_edges(k+1)), ...
    1:num_el, ...
    'UniformOutput', false);


%% ---------------------------------------------------------------
% Step 4: Azimuth used internally for signal generation
% ---------------------------------------------------------------

% Azimuth is NOT stored in the dataset.
% It is randomly varied so that the model does not only learn
% one fixed elevation condition.

az_range = [-90 90];


%% ---------------------------------------------------------------
% Step 5: Per-sample nuisance jitter
% ---------------------------------------------------------------

% Random sensor SNR for every sample.
snr_jitter_range = [15 25];      % dB

% Random source/operating frequency for every sample.
f0_jitter_range = [800 1200];    % Hz


%% ---------------------------------------------------------------
% Step 6: Samples per Elevation sector
% ---------------------------------------------------------------

samples_per_sector = 100;

% Number of retries if a randomly generated sample fails.
max_retries = 5;

% Total number of desired samples.
total_target = num_el * samples_per_sector;


%% ---------------------------------------------------------------
% Step 7: Preallocate dataset storage
% ---------------------------------------------------------------

SampleID = zeros(total_target, 1);

El_true = zeros(total_target, 1);

ElSector = strings(total_target, 1);

TX_TDOA = zeros(total_target, 1);
TY_TDOA = zeros(total_target, 1);
TZ_TDOA = zeros(total_target, 1);

MUSIC_El = zeros(total_target, 1);

GCC_El = zeros(total_target, 1);

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
fprintf('        Elevation DATASET GENERATION\n');
fprintf('==============================================\n');

fprintf(['Elevation sectors : %d\n' ...
         'Samples/sector : %d\n' ...
         'Target samples : %d\n\n'], ...
         num_el, samples_per_sector, total_target);


for a = 1:num_el

    % Current elevation sector limits.
    el_lo = el_edges(a);
    el_hi = el_edges(a + 1);


    for k = 1:samples_per_sector

        success = false;
        attempt = 0;
        %% Retry sample generation if the pipeline fails

        while ~success && attempt < max_retries

            attempt = attempt + 1;


            % ---------------------------------------------------
            % Random ground-truth elevation inside current sector
            % ---------------------------------------------------

            el_true = el_lo + ...
                rand() * (el_hi - el_lo);


            % ---------------------------------------------------
            % Random azimuth
            % ---------------------------------------------------
            %
            % Used only internally by extract_case_features().
            % It is NOT stored in the dataset.

            az_true = az_range(1) + ...
                rand() * diff(az_range);


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

% to be checked
            %% Run complete feature-extraction pipeline

            try

                feat = extract_case_features_elevation( ...
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
                        el_names{a}, ...
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

        El_true(row) = feat.el_true;

        ElSector(row) = el_names{a};


        % GCC-PHAT features

        TX_TDOA(row) = feat.tx;

        TY_TDOA(row) = feat.ty;
        % need correction  in extract feature

        TZ_TDOA(row) = feat.tz;

        % Elevation music

        MUSIC_El(row) = feat.music_el;


        % Combined GCC-PHAT Elevation

        GCC_El(row) = feat.gcc_el;


        % Signal features

        ILD_dB(row) = feat.ild_dB;

        RMS_mean(row) = feat.rms_mean;

        FFT_PeakFreq(row) = feat.fft_peak_freq;

        SpecEntropyNorm(row) = ...
            feat.spec_entropy_norm;

    end


    %% Progress information

    fprintf( ...
        'Elevation %-14s done (%d/%d rows)\n', ...
        el_names{a}, ...
        row, ...
        total_target);

end


%% ---------------------------------------------------------------
% Step 10: Trim unused preallocated rows
% ---------------------------------------------------------------

SampleID = SampleID(1:row);

El_true = El_true(1:row);

ElSector = ElSector(1:row);

TX_TDOA = TX_TDOA(1:row);

TY_TDOA = TY_TDOA(1:row);

TZ_TDOA = TZ_TDOA(1:row);

MUSIC_El = MUSIC_El(1:row);

GCC_El = GCC_El(1:row);

ILD_dB = ILD_dB(1:row);

RMS_mean = RMS_mean(1:row);

FFT_PeakFreq = FFT_PeakFreq(1:row);

SpecEntropyNorm = SpecEntropyNorm(1:row);




%% ---------------------------------------------------------------
% Step 11: Convert elevation sector to categorical
% ---------------------------------------------------------------

ElSector = categorical(ElSector);


%% ---------------------------------------------------------------
% Step 12: Assemble dataset table
% ---------------------------------------------------------------

dataTable = table( ...
    SampleID, ...
    El_true, ...
    ElSector, ...
    TX_TDOA, ...
    TY_TDOA, ...
    TZ_TDOA, ...
    MUSIC_El, ...
    GCC_El, ...
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

save('dataset_elevation.mat', 'dataTable');

writetable(dataTable, 'dataset_elevation.csv');

fprintf('\nSaved:\n');
fprintf('  dataset_elevation.mat\n');
fprintf('  dataset_elevation.csv\n');


%% ---------------------------------------------------------------
% Step 15: Class balance check
% ---------------------------------------------------------------

fprintf('\n');
fprintf('--- Samples per elevation sector ---\n');

summary(dataTable.ElSector);