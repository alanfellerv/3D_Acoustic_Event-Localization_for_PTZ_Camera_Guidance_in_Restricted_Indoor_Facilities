function feat = extract_case_features_elevation(az_true, el_true, geom, params)
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
%       .el_true
%       .tx
%       .ty
%       .tz
%       .music_el
%       .gcc_el
%       .ild_dB
%       .rms_mean
%       .fft_peak_freq
%       .spec_entropy_norm
%
% NOTE
%   Elevation is used internally to generate the correct 3D source
%   direction, but no elevation quantity is returned as a feature.


%% 1. Geometry
P = [geom.r; geom.vert_positions];      % 8x3, rows 1-4 bottom, 5-8 top

u = [cosd(el_true)*cosd(az_true);       % unit vector pointing toward the source
    cosd(el_true)*sind(az_true);
    sind(el_true)];

angErr = @(a, b) abs(mod(a - b + 180, 360) - 180);

%% 3. Source signal (quiet - event - quiet)
duration      = params.duration;
event_start   = params.event_start;
event_end     = params.event_end;
ambient_amp   = params.ambient_amp;
event_amp     = params.event_amp;
sensor_SNR_dB = params.sensor_SNR_dB;
f0            = params.f0;                   % MUSIC operating frequency (Hz)

t = (0:round(geom.fs*duration)-1)' / geom.fs;
N = numel(t);

envelope = ambient_amp * ones(N,1);
envelope(t >= event_start & t <= event_end) = event_amp;

source_signal = envelope .* randn(N,1);

%% 4. Simulate all 8 channels once (used by both MUSIC and GCC-PHAT)
% Far-field plane wave: a mic at position p receives s(t + p.u/c), so mics
% nearer the source hear it earlier. Delays are shifted to be >= 0, which
% does not change any TDOA.
tau = -(P * u) / geom.c;
tau = tau - min(tau);

mic_raw = zeros(N, 8);
for m = 1:8
    mic_raw(:,m) = awgn(delayseq(source_signal, tau(m), geom.fs), ...
        sensor_SNR_dB, 'measured');
end

%% 5. Band-pass filter + VAD
[mic_f, vad] = noise_filter(mic_raw, geom.fs);
mic_active   = mic_f(vad.active_samples(1):vad.active_samples(2), :);

fprintf('--- VAD ---\n');
fprintf('Active frames: %d / %d\n', numel(vad.active_frames), numel(vad.frame_mask));
fprintf('Active window: %.3f - %.3f s (true event: %.3f - %.3f s)\n\n', ...
    (vad.active_samples(1)-1)/geom.fs, (vad.active_samples(2)-1)/geom.fs, ...
    event_start, event_end);

%% 6. MUSIC (bottom plane)
[az_music, el_music, musicEstimator] = ...
    music_doa(mic_active(:, geom.music_idx), geom, f0);

fprintf('--- MUSIC ---\n');
fprintf('Azimuth   : true %.2f | est %.2f deg\n', az_true, az_music);
fprintf('Elevation : true %.2f | est %.2f deg\n\n', el_true, el_music);




%% GCC-PHAT: horizontal pairs -> ux, uy
xy_pairs = [1 2; 4 3;      % X
            1 4; 2 3];     % Y

cu = zeros(4, 1);
for k = 1:4
    A = xy_pairs(k,1);
    B = xy_pairs(k,2);
    baseline = norm(P(A,:) - P(B,:));
    tdoa = gcc_phat(mic_active(:,A), mic_active(:,B), geom, baseline);
    cu(k) = geom.c * tdoa / baseline;
end

ux = mean(cu(1:2));
uy = mean(cu(3:4));

%% GCC-PHAT: the four vertical pairs (top mic = reference side) -> uz
z_pairs = [5 1; 6 2; 7 3; 8 4];

vert_tdoa = zeros(1, 4);
cz        = zeros(1, 4);
for k = 1:4
    A = z_pairs(k,1);
    B = z_pairs(k,2);
    baseline = norm(P(A,:) - P(B,:));
    vert_tdoa(k) = gcc_phat(mic_active(:,A), mic_active(:,B), geom, baseline);
    cz(k) = geom.c * vert_tdoa(k) / baseline;
end

uz = mean(cz);
gcc_el = atan2d(uz, hypot(ux, uy));

%% Signal features (bottom plane)
bottom = mic_active(:, 1:4);

ild_dB   = ild_feature(bottom(:,2), bottom(:,1));      % left = Mic2, right = Mic1
rms_mean = mean(rms_feature(bottom));

ref_channel = mean(bottom, 2);
fft_feat = fft_features(ref_channel, geom.fs);
[~, spec_H_norm] = spectral_entropy(ref_channel, geom.fs);

%% Sanity check
vals = [el_music, gcc_el, vert_tdoa, ild_dB, rms_mean, ...
    fft_feat.peak_freq, spec_H_norm];
if any(~isfinite(vals))
    error('extract_case_features_elevation:badFeature', ...
        'Non-finite feature (az=%.2f, el=%.2f).', az_true, el_true);
end

%% Output
feat.el_true           = el_true;
feat.music_el          = el_music;
feat.tx                = ux;
feat.ty                = uy;
feat.tz                = uz;
feat.gcc_el            = gcc_el;
feat.ild_dB            = ild_dB;
feat.rms_mean          = rms_mean;
feat.fft_peak_freq     = fft_feat.peak_freq;
feat.spec_entropy_norm = spec_H_norm;

end
