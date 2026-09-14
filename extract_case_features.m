function feat = extract_case_features(az_true, el_true, geom, params)
% EXTRACT_CASE_FEATURES  Runs the full acquisition -> filter/VAD -> MUSIC
%                         -> GCC-PHAT -> feature-extraction pipeline for
%                         ONE ground-truth (az_true, el_true) direction
%                         and returns all 7 dataset features in a struct.
%
%   feat = EXTRACT_CASE_FEATURES(az_true, el_true, geom, params)
%
%   This is the same pipeline as main.m's single-case walkthrough
%   (and its local run_doa_case helper), pulled out into a standalone,
%   reusable function so it can be called directly from a
%   dataset-generation loop (see generate_dataset.m) without depending
%   on main.m or duplicating the pipeline code.
%
%   Pipeline (matches the system architecture flowchart):
%       Source -> collectPlaneWave (ReSpeaker 4ch) + vertical pair
%              -> AWGN sensor noise
%              -> noise_filter (band-pass + VAD)                 [block C]
%              -> VAD active-region trimming
%              -> music_doa      (D2: MUSIC Spectrum)
%              -> gcc_phat       (D1: GCC-PHAT Delay)
%              -> ild_feature    (D3: ILD)
%              -> rms_feature    (D4: RMS)
%              -> fft_features   (D5: FFT Features)
%              -> spectral_entropy (D6: Spectral Entropy)
%
%   Inputs:
%       az_true, el_true - ground-truth azimuth/elevation (degrees)
%       geom              - array geometry struct (see array_geometry.m)
%       params            - struct with fields:
%           .duration        - scene duration (s)
%           .event_start     - event onset time (s)
%           .event_end       - event offset time (s)
%           .ambient_amp     - background amplitude
%           .event_amp       - event burst amplitude
%           .sensor_SNR_dB   - AWGN sensor SNR (dB)
%           .f0              - source/operating frequency (Hz)
%
%   Output: struct `feat` with fields:
%       .az_true, .el_true      - ground truth passed through (for
%                                  spot-checking rows against labels)
%       .music_az               - MUSIC-estimated azimuth (deg)
%       .music_el               - MUSIC-estimated elevation (deg)
%       .gcc_angle               - GCC-PHAT-estimated elevation/broadside
%                                  angle from the vertical pair (deg)
%       .ild_dB                 - Interaural Level Difference (dB)
%       .rms_mean                - mean RMS across ReSpeaker channels
%       .fft_peak_freq            - FFT peak frequency (Hz)
%       .spec_entropy_norm        - normalized spectral entropy [0,1]
%
%   These 7 numeric fields (music_az, music_el, gcc_angle, ild_dB,
%   rms_mean, fft_peak_freq, spec_entropy_norm) are the "7 features"
%   used to build the labeled dataset table in generate_dataset.m.
%
%   Throws an error (propagated to the caller) if VAD detects no active
%   region or any estimator fails - the caller is expected to catch
%   this and resample, since occasional degenerate draws are expected
%   when azimuth/elevation are jittered near array-geometry edge cases.

%% ---------------------------------------------------------------
% 1. Ground-truth direction (radians)
% ---------------------------------------------------------------

az_rad = deg2rad(az_true);
el_rad = deg2rad(el_true);

%% ---------------------------------------------------------------
% 2. Generate the source "quiet - event - quiet" scene
% ---------------------------------------------------------------

t = (0:round(geom.fs * params.duration) - 1)' / geom.fs;
N = length(t);

envelope = params.ambient_amp * ones(N, 1);
envelope(t >= params.event_start & t <= params.event_end) = params.event_amp;

src = envelope .* randn(N, 1);   % broadband event content

%% ---------------------------------------------------------------
% 3. ReSpeaker 4-channel acquisition (narrowband plane-wave model)
% ---------------------------------------------------------------

x_clean = collectPlaneWave(geom.array, src, [az_true; el_true], ...
    params.f0, geom.c);

mic_signals_raw = zeros(size(x_clean));
for i = 1:4
    mic_signals_raw(:, i) = awgn(x_clean(:, i), params.sensor_SNR_dB, 'measured');
end

%% ---------------------------------------------------------------
% 4. Vertical microphone pair acquisition
% ---------------------------------------------------------------

tau_vert = (geom.d_vert * sin(el_rad)) / geom.c;

mic_A_raw = awgn(src, params.sensor_SNR_dB, 'measured');
mic_B_raw = awgn(delayseq(src, tau_vert, geom.fs), params.sensor_SNR_dB, 'measured');

%% ---------------------------------------------------------------
% 5. Band-pass filter + VAD (block C)
% ---------------------------------------------------------------

[mic_signals_f, vad_ura]  = noise_filter(mic_signals_raw, geom.fs);
[mic_vert_f,    vad_vert] = noise_filter([mic_A_raw mic_B_raw], geom.fs);

if isempty(vad_ura.active_frames) || isempty(vad_vert.active_frames)
    error('extract_case_features:noActivity', ...
        'VAD detected no active region for az=%.2f, el=%.2f.', az_true, el_true);
end

%% ---------------------------------------------------------------
% 6. Trim to VAD-active region
% ---------------------------------------------------------------

idxU = vad_ura.active_samples(1):vad_ura.active_samples(2);
idxV = vad_vert.active_samples(1):vad_vert.active_samples(2);

mic_active = mic_signals_f(idxU, :);
mic_A = mic_vert_f(idxV, 1);
mic_B = mic_vert_f(idxV, 2);

%% ---------------------------------------------------------------
% 7. MUSIC DOA estimation (D2)
% ---------------------------------------------------------------

[music_az, music_el, ~] = music_doa(mic_active, geom, params.f0);

%% ---------------------------------------------------------------
% 8. GCC-PHAT estimation (D1)
% ---------------------------------------------------------------

[~, gcc_angle, ~, ~] = gcc_phat(mic_A, mic_B, geom, geom.d_vert);

%% ---------------------------------------------------------------
% 9. Remaining features: ILD (D3), RMS (D4), FFT (D5), Entropy (D6)
% ---------------------------------------------------------------

ild_dB = ild_feature(mic_active(:, 2), mic_active(:, 1));   % left=Mic2, right=Mic1

rms_vals = rms_feature(mic_active);
rms_mean = mean(rms_vals);

ref_channel = mean(mic_active, 2);
fft_feat = fft_features(ref_channel, geom.fs);

[~, spec_H_norm] = spectral_entropy(ref_channel, geom.fs);

%% ---------------------------------------------------------------
% 10. Sanity check - reject degenerate draws so the caller can resample
% ---------------------------------------------------------------

raw_vals = [music_az, music_el, gcc_angle, ild_dB, rms_mean, ...
    fft_feat.peak_freq, spec_H_norm];

if any(isnan(raw_vals)) || any(isinf(raw_vals))
    error('extract_case_features:badFeature', ...
        'Non-finite feature value for az=%.2f, el=%.2f.', az_true, el_true);
end

%% ---------------------------------------------------------------
% 11. Package output
% ---------------------------------------------------------------

feat.az_true          = az_true;
feat.el_true          = el_true;
feat.music_az          = music_az;
feat.music_el          = music_el;
feat.gcc_angle          = gcc_angle;
feat.ild_dB             = ild_dB;
feat.rms_mean           = rms_mean;
feat.fft_peak_freq      = fft_feat.peak_freq;
feat.spec_entropy_norm  = spec_H_norm;

end
