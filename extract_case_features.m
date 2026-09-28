function feat = extract_case_features(az_true, el_true, geom, params)
% EXTRACT_CASE_FEATURES
% Runs the signal-generation, filtering, VAD, MUSIC, GCC-PHAT,
% and signal-feature extraction pipeline for one known source direction.
%
% INPUTS
%   az_true  - Ground-truth azimuth (degrees)
%   el_true  - Ground-truth elevation used internally for signal generation
%   geom     - Microphone-array geometry structure
%   params   - Simulation parameters
%
% OUTPUT
%   feat - Structure containing azimuth-related features:
%
%       .az_true
%       .tx
%       .ty
%       .diagonal_pairs_tdoa_1
%       .diagonal_pairs_tdoa_2
%       .music_az
%       .gcc_az
%       .ild_dB
%       .rms_mean
%       .fft_peak_freq
%       .spec_entropy_norm
%
% NOTE
%   Elevation is used internally to generate the correct 3D source
%   direction, but no elevation quantity is returned as a feature.

%% ---------------------------------------------------------------
% 1. Ground-truth source direction
% ---------------------------------------------------------------

az_rad = deg2rad(az_true);
el_rad = deg2rad(el_true);

% 3D unit vector pointing toward the source.
u = [
    cos(el_rad) * cos(az_rad), ...
    cos(el_rad) * sin(az_rad), ...
    sin(el_rad)
];

%% ---------------------------------------------------------------
% 2. Generate broadband source signal
% ---------------------------------------------------------------

t = (0:round(geom.fs * params.duration) - 1)' / geom.fs;
N = length(t);

% Background amplitude
envelope = params.ambient_amp * ones(N, 1);

% Event amplitude
event_idx = t >= params.event_start & ...
            t <= params.event_end;

envelope(event_idx) = params.event_amp;

% Broadband source
src = envelope .* randn(N, 1);

%% ---------------------------------------------------------------
% 3. ReSpeaker 4-channel acquisition
% ---------------------------------------------------------------

% Simulate propagation to the 4-channel microphone array.
x_clean = collectPlaneWave( ...
    geom.array, ...
    src, ...
    [az_true; el_true], ...
    params.f0, ...
    geom.c);

% Add sensor noise.
mic_signals_raw = zeros(size(x_clean));

for i = 1:4
    mic_signals_raw(:, i) = awgn( ...
        x_clean(:, i), ...
        params.sensor_SNR_dB, ...
        'measured');
end

%% ---------------------------------------------------------------
% 4. Broadband microphone signals for GCC-PHAT
% ---------------------------------------------------------------

% Calculate propagation delay for each microphone.
tau_mic = (geom.r * u.') / geom.c;

% Remove common delay.
tau_mic = tau_mic - min(tau_mic);

% Generate delayed microphone signals.
mic_bb_raw = zeros(N, 4);

for i = 1:4

    delayed_signal = delayseq( ...
        src, ...
        tau_mic(i), ...
        geom.fs);

    mic_bb_raw(:, i) = awgn( ...
        delayed_signal, ...
        params.sensor_SNR_dB, ...
        'measured');
end

%% ---------------------------------------------------------------
% 5. Filtering and VAD
% ---------------------------------------------------------------

% Filtering/VAD for MUSIC and signal features.
[mic_signals_f, vad_ura] = ...
    noise_filter(mic_signals_raw, geom.fs);

% Filtering/VAD for GCC-PHAT.
[mic_bb_f, vad_bb] = ...
    noise_filter(mic_bb_raw, geom.fs);

% Check for valid active regions.
if isempty(vad_ura.active_samples) || ...
   isempty(vad_bb.active_samples)

    error('extract_case_features:noActivity', ...
        ['VAD detected no active region for ' ...
         'az=%.2f, el=%.2f.'], ...
         az_true, el_true);
end

%% ---------------------------------------------------------------
% 6. Extract VAD-active regions
% ---------------------------------------------------------------

idxU = vad_ura.active_samples(1): ...
       vad_ura.active_samples(2);

idxBB = vad_bb.active_samples(1): ...
        vad_bb.active_samples(2);

mic_active = mic_signals_f(idxU, :);
mic_bb_active = mic_bb_f(idxBB, :);

%% ---------------------------------------------------------------
% 7. Define GCC-PHAT microphone pairs
% ---------------------------------------------------------------

pairs = {
    2, 1, geom.d_ura,          'Pair 2->1'
    3, 4, geom.d_ura,          'Pair 3->4'
    4, 1, geom.d_ura,          'Pair 4->1'
    3, 2, geom.d_ura,          'Pair 3->2'
    1, 3, geom.d_ura*sqrt(2),  'Pair 1->3'
    2, 4, geom.d_ura*sqrt(2),  'Pair 2->4'
};

%% ---------------------------------------------------------------
% 8. MUSIC azimuth estimation
% ---------------------------------------------------------------

% Only retain the MUSIC azimuth.
[music_az, ~, ~] = ...
    music_doa(mic_active, geom, params.f0);

%% ---------------------------------------------------------------
% 9. Pairwise GCC-PHAT
% ---------------------------------------------------------------

tau_x = [];
tau_y = [];
diagonal_pairs_tdoa = [];

fprintf('\n========== PAIRWISE GCC-PHAT ==========\n');

for k = 1:size(pairs, 1)

    i = pairs{k, 1};
    j = pairs{k, 2};
    d = pairs{k, 3};

    % GCC-PHAT TDOA and angle for this microphone pair.
    [tdoa, angle_est, ~, ~] = gcc_phat( ...
        mic_bb_active(:, i), ...
        mic_bb_active(:, j), ...
        geom, ...
        d);

    % Theoretical TDOA.
    tdoa_true = ...
        ((geom.r(j,:) - geom.r(i,:)) * u.') / geom.c;

    fprintf('\n%s\n', pairs{k, 4});
    fprintf('TDOA Estimated : %+.3e s\n', tdoa);
    fprintf('TDOA True      : %+.3e s\n', tdoa_true);
    fprintf('GCC-PHAT Angle : %.2f deg\n', angle_est);

    % X-axis pairs
    if k <= 2

        tau_x(end+1) = tdoa;

    % Y-axis pairs
    elseif k <= 4

        tau_y(end+1) = tdoa;

    % Diagonal pairs
    else

        diagonal_pairs_tdoa(end+1) = tdoa;

    end
end

%% ---------------------------------------------------------------
% 10. Combined GCC-PHAT azimuth
% ---------------------------------------------------------------

tx = mean(tau_x);
ty = mean(tau_y);

gcc_az = atan2d(ty, tx);

fprintf('\nGCC-PHAT Azimuth : True %.2f deg | Estimated %.2f deg\n', ...
    az_true, gcc_az);

%% ---------------------------------------------------------------
% 11. Remaining signal features
% ---------------------------------------------------------------

% Inter-channel level difference.
ild_dB = ild_feature( ...
    mic_active(:, 2), ...
    mic_active(:, 1));

% RMS across microphone channels.
rms_vals = rms_feature(mic_active);
rms_mean = mean(rms_vals);

% Average microphone signal.
ref_channel = mean(mic_active, 2);

% FFT features.
fft_feat = fft_features( ...
    ref_channel, ...
    geom.fs);

% Normalized spectral entropy.
[~, spec_H_norm] = ...
    spectral_entropy(ref_channel, geom.fs);

%% ---------------------------------------------------------------
% 12. Sanity check
% ---------------------------------------------------------------

raw_vals = [
    music_az
    gcc_az
    tx
    ty
    diagonal_pairs_tdoa(:)
    ild_dB
    rms_mean
    fft_feat.peak_freq
    spec_H_norm
];

if any(isnan(raw_vals)) || any(isinf(raw_vals))

    error('extract_case_features:badFeature', ...
        ['Non-finite feature value for ' ...
         'az=%.2f, el=%.2f.'], ...
         az_true, el_true);
end

%% ---------------------------------------------------------------
% 13. Package output
% ---------------------------------------------------------------

feat.az_true = az_true;

% GCC-PHAT features
feat.tx = tx;
feat.ty = ty;
feat.diagonal_pairs_tdoa_1 = diagonal_pairs_tdoa(1);
feat.diagonal_pairs_tdoa_2 = diagonal_pairs_tdoa(2);
feat.gcc_az = gcc_az;

% MUSIC feature
feat.music_az = music_az;

% Signal features
feat.ild_dB = ild_dB;
feat.rms_mean = rms_mean;
feat.fft_peak_freq = fft_feat.peak_freq;
feat.spec_entropy_norm = spec_H_norm;

end