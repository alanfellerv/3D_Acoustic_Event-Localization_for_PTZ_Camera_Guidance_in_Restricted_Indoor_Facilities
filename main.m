%% MAIN - 8-mic acoustic DOA simulation (MUSIC + GCC-PHAT from one signal set)
%
%   source -> 8 mic channels (4 bottom + 4 top) -> band-pass + VAD
%          -> MUSIC (bottom plane) and pairwise GCC-PHAT (all planes)
%          -> ILD / RMS / FFT features / spectral entropy -> plots
%
% Requires: Phased Array System Toolbox, Signal Processing Toolbox

clear; clc; close all;

%% 1. Geometry
geom = array_geometry();
P = [geom.r; geom.vert_positions];      % 8x3, rows 1-4 bottom, 5-8 top

%% 2. Ground truth
az_true = 50;   % deg
el_true = 30;   % deg

u = [cosd(el_true)*cosd(az_true);       % unit vector pointing toward the source
     cosd(el_true)*sind(az_true);
     sind(el_true)];

angErr = @(a, b) abs(mod(a - b + 180, 360) - 180);

%% 3. Source signal (quiet - event - quiet)
duration      = 1;
event_start   = 0.35;
event_end     = 0.65;
ambient_amp   = 0.05;
event_amp     = 1.0;
sensor_SNR_dB = 20;
f0            = 1000;                   % MUSIC operating frequency (Hz)

t = (0:round(geom.fs*duration)-1)' / geom.fs;
N = numel(t);

envelope = ambient_amp * ones(N,1);
envelope(t >= event_start & t <= event_end) = event_amp;

rng(1);
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

%% 7. Pairwise GCC-PHAT
% Each row is [A B]. A is the mic on the +axis side (top mic for Z pairs),
% so TDOA = tau_B - tau_A = (P_A - P_B).u / c is positive when the source
% lies on the A side. c*TDOA/spacing is then the source unit-vector
% component along that pair's axis.
pairs = [1 2;    % X
         4 3;    % X
         1 4;    % Y
         2 3;    % Y
         1 3;    % diagonal
         2 4;    % diagonal
         5 1;    % Z (top -> bottom)
         6 2;    % Z
         7 3;    % Z
         8 4];   % Z
idxX = 1:2;  idxY = 3:4;  idxZ = 7:10;

num_pairs = size(pairs, 1);
baseline  = zeros(num_pairs, 1);
tdoa_true = zeros(num_pairs, 1);
tdoa_est  = zeros(num_pairs, 1);
corr_all  = cell(num_pairs, 1);
lags_all  = cell(num_pairs, 1);

fprintf('--- GCC-PHAT (per pair) ---\n');
for k = 1:num_pairs
    A = pairs(k,1);
    B = pairs(k,2);

    baseline(k)  = norm(P(A,:) - P(B,:));
    tdoa_true(k) = tau(B) - tau(A);

    [tdoa_est(k), ~, corr_all{k}, lags_all{k}] = gcc_phat( ...
        mic_active(:,A), mic_active(:,B), geom, baseline(k));

    fprintf('Mic%d->Mic%d : true %+8.2f us | est %+8.2f us\n', ...
        A, B, tdoa_true(k)*1e6, tdoa_est(k)*1e6);
end

cu = geom.c * tdoa_est ./ baseline;     % unit-vector component per pair
ux = mean(cu(idxX));
uy = mean(cu(idxY));
uz = mean(cu(idxZ));

az_gcc = atan2d(uy, ux);
el_gcc = atan2d(uz, hypot(ux, uy));

fprintf('\nAzimuth   : true %.2f | est %.2f deg\n', az_true, az_gcc);
fprintf('Elevation : true %.2f | est %.2f deg\n\n', el_true, el_gcc);

%% 8. Features (ILD, RMS, FFT, spectral entropy) on the bottom plane
ild_dB = ild_feature(mic_active(:,2), mic_active(:,1));   % left = Mic2, right = Mic1

rms_vals = rms_feature(mic_active(:,1:4));
rms_mean = mean(rms_vals);

ref_channel = mean(mic_active(:,1:4), 2);
fft_feat    = fft_features(ref_channel, geom.fs);
[spec_H, spec_H_norm] = spectral_entropy(ref_channel, geom.fs);

fprintf('--- Features ---\n');
fprintf('ILD (Mic1 vs Mic2) : %.2f dB\n', ild_dB);
fprintf('RMS per channel    : %s\n', mat2str(rms_vals, 4));
fprintf('RMS (mean)         : %.4f\n', rms_mean);
fprintf('FFT peak frequency : %.1f Hz\n', fft_feat.peak_freq);
fprintf('Spectral centroid  : %.1f Hz\n', fft_feat.centroid);
fprintf('Spectral entropy   : %.4f bits (normalized %.4f)\n\n', spec_H, spec_H_norm);

%% 9. Summary
Method = {'MUSIC'; 'GCC-PHAT'};
AzEst  = [az_music; az_gcc];
ElEst  = [el_music; el_gcc];
AzErr  = angErr(AzEst, az_true);
ElErr  = abs(ElEst - el_true);
resultsTable = table(Method, AzEst, ElEst, AzErr, ElErr)

%% 10. Visualization

% Array geometry and source direction
figure;
scatter3(P(1:4,1), P(1:4,2), P(1:4,3), 80, 'b', 'filled'); hold on;
scatter3(P(5:8,1), P(5:8,2), P(5:8,3), 80, 'r', 'filled');
text(P(:,1), P(:,2), P(:,3), ...
    arrayfun(@(k) sprintf('  Mic%d', k), (1:8)', 'UniformOutput', false));
L = 4 * geom.d_ura;
quiver3(0, 0, geom.d_vert/2, L*u(1), L*u(2), L*u(3), 0, 'k', 'LineWidth', 2);
axis equal; grid on;
xlabel('x (m)'); ylabel('y (m)'); zlabel('z (m)');
legend('Bottom plane', 'Top plane', 'Source direction', 'Location', 'best');
title('8-Mic Array Geometry');

% Raw vs band-pass filtered signal (Mic1), zoomed to the active region
margin     = 0.03;
zoom_start = max(0,        (vad.active_samples(1)-1)/geom.fs - margin);
zoom_end   = min(duration, (vad.active_samples(2)-1)/geom.fs + margin);

figure;
subplot(2,1,1);
plot(t, mic_raw(:,1)); grid on; xlim([zoom_start zoom_end]);
xlabel('Time (s)'); ylabel('Amplitude');
title('Raw Signal - Mic1');
subplot(2,1,2);
plot(t, mic_f(:,1)); grid on; xlim([zoom_start zoom_end]);
xlabel('Time (s)'); ylabel('Amplitude');
title('Band-Pass Filtered Signal - Mic1 (300-3400 Hz)');

% Band-pass filter response
figure;
freqz(vad.filter_b, vad.filter_a, 2048, geom.fs);
title('Band-Pass Filter Frequency Response');

% VAD
figure;
plot(vad.frame_times, 10*log10(vad.frame_energy), 'b'); hold on;
yline(10*log10(max(real(vad.threshold), eps)), 'r--', 'Threshold');
xline(event_start, 'g--', 'True event start');
xline(event_end,   'g--', 'True event end');
plot(vad.frame_times(vad.frame_mask), ...
     10*log10(vad.frame_energy(vad.frame_mask)), 'ro', 'MarkerSize', 4);
xlabel('Time (s)'); ylabel('Frame Energy (dB)'); grid on;
title('VAD: Short-Term Energy and Detected Active Frames');
legend('Frame energy', 'Threshold', 'True event start', 'True event end', ...
       'Detected active', 'Location', 'best');

% MUSIC pseudo-spectrum
figure;
plotSpectrum(musicEstimator);
title('MUSIC Pseudo-Spectrum (2D)');

% GCC-PHAT correlation for every pair
figure;
tl = tiledlayout(5, 2, 'TileSpacing', 'compact');
title(tl, 'GCC-PHAT Cross-Correlation per Mic Pair');
for k = 1:num_pairs
    nexttile;
    plot(lags_all{k}*1e6, abs(corr_all{k}), 'b', 'DisplayName', '|GCC-PHAT|');
    hold on;
    xline(tdoa_true(k)*1e6, 'g--', 'DisplayName', 'True TDOA');
    xline(tdoa_est(k)*1e6,  'r-',  'DisplayName', 'Estimated TDOA');
    lim = 1.5 * baseline(k) / geom.c * 1e6;
    xlim([-lim lim]); grid on;
    title(sprintf('Mic%d -> Mic%d', pairs(k,1), pairs(k,2)));
    if k >= num_pairs - 1, xlabel('Lag (\mus)'); end
    if k == 1, legend('Location', 'best'); end
end

% FFT magnitude spectrum
figure;
plot(fft_feat.freq_axis, fft_feat.magnitude); hold on;
xline(fft_feat.peak_freq, 'r--', 'Peak');
xline(fft_feat.centroid,  'g--', 'Centroid');
xlabel('Frequency (Hz)'); ylabel('Magnitude'); grid on;
xlim([0 geom.fs/2]);
title('FFT Magnitude Spectrum (Active Region, Reference Channel)');

% Estimation error
figure;
bar([AzErr ElErr]);
set(gca, 'XTickLabel', Method);
ylabel('Absolute Error (deg)'); grid on;
legend('Azimuth error', 'Elevation error', 'Location', 'best');
title(sprintf('DOA Error (True Az %g, El %g)', az_true, el_true));