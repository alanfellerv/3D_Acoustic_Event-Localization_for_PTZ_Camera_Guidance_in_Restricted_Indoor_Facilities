% Define parameters
fs = 44100;                 % Sampling frequency (44.1 kHz)
t = (0:fs-1)'/fs;           % 1 second time vector
delay = 0.005;              % True delay of 5 milliseconds

% Generate a reference signal (white noise) and a delayed version
refsig = randn(size(t));
sig = delayseq(refsig, delay, fs); % Shift signal by the target delay

% Estimate the delay using GCC-PHAT
[estimated_delay, R, lags] = gccphat(sig, refsig, fs);

% Display results
fprintf('True Delay: %f seconds\n', delay);
fprintf('Estimated Delay: %f seconds\n', estimated_delay);

% Optional: Plot the sharp PHAT peak
plot(lags, R);
grid on;
title('GCC-PHAT Cross-Correlation');
xlabel('Lag (seconds)');
ylabel('Amplitude');


%old main
%% MAIN - Acoustic DOA Localization Simulation (MUSIC + GCC-PHAT)
% Requires: Phased Array System Toolbox
%
% Pipeline:
%   1. Load array geometry (array_geometry.m)
%   2. Generate synchronized synthetic mic signals for a known true DOA
%   3. Estimate DOA via MUSIC on the ReSpeaker 4-mic array (music_doa.m)
%   4. Estimate TDOA/angle via GCC-PHAT on the vertical mic pair (gcc_phat.m)
%   5. Compare estimates against ground truth and visualize results

clear; clc; close all;

%% --- Step 1: Load Array Geometry ---
geom = array_geometry();

%% --- Ground Truth Source Direction ---
az_true = 37;   % degrees
el_true = 12;   % degrees

az_rad = deg2rad(az_true);
el_rad = deg2rad(el_true);

% Unit vector pointing toward source (far-field plane wave assumption)
u = [cos(el_rad)*cos(az_rad);
     cos(el_rad)*sin(az_rad);
     sin(el_rad)];

%% --- Common Time Base & Source Signal ---
duration = 1;                          % seconds[cite: 4]
t = (0:geom.fs-1)'/geom.fs;           % 1 second time vector
N = length(t);
f_axis = (0:N-1)' * (geom.fs/N);

f0 = 1000;                             % source tone frequency (Hz) (used as target bin)[cite: 4]

% FIX: Replace pure sine wave with broadband noise to resolve GCC-PHAT ambiguity
source_signal = randn(N);           
X_src = fft(source_signal);

SNR_dB = 20;

%% --- Generate Synchronized ReSpeaker 4-Channel Signals (narrowband model) ---
% phased.MUSICEstimator2D expects a narrowband plane-wave signal generated
% via collectPlaneWave (phase-only steering at the operating frequency f0),
% not a broadband time-delayed signal - this matches MathWorks' own
% MUSICEstimator2D/MVDREstimator2D examples and is required for the
% estimator to detect the source.
x_clean = collectPlaneWave(geom.array, source_signal, [az_true; el_true], f0, geom.c);

mic_signals = zeros(size(x_clean));
for i = 1:4
    mic_signals(:,i) = awgn(x_clean(:,i), SNR_dB, 'measured');
end

%% ---- Generate Synchronized Vertical Pair Signals ----
tau_vert = (geom.d_vert * sin(el_rad)) / geom.c;
mic_A = source_signal;
mic_B = delayseq(source_signal, tau_vert, geom.fs);
%% --- Step 2: MUSIC DOA Estimation (ReSpeaker Array) ---
[az_est, el_est, musicEstimator] = music_doa(mic_signals, geom, f0);

fprintf('--- MUSIC Estimation (ReSpeaker Quad Array) ---\n');
fprintf('True Azimuth   : %.2f deg | Estimated: %.2f deg\n', az_true, az_est);
fprintf('True Elevation : %.2f deg | Estimated: %.2f deg\n\n', el_true, el_est);

%% --- Step 3: GCC-PHAT Estimation (Vertical Mic Pair) ---
[tdoa_est, angle_est_deg, corr, lags] = gcc_phat(mic_A, mic_B, geom, geom.d_vert);

fprintf('--- GCC-PHAT Estimation (Vertical Mic Pair) ---\n');
fprintf('True TDOA      : %.6e s | Estimated: %.6e s\n', tau_vert, tdoa_est);
fprintf('True Elevation : %.2f deg | Estimated: %.2f deg\n\n', el_true, angle_est_deg);
%% --- Visualization ---

% Array geometry
figure;
viewArray(geom.array, 'ShowNormals', true, 'ShowIndex', 'All');
title('ReSpeaker Quad Mic Array Geometry');

% Raw synchronized signals (first 200 samples)
figure;
plot(t(1:200), real(mic_signals(1:200,1)), 'DisplayName','Mic1'); hold on;
plot(t(1:200), real(mic_signals(1:200,2)), 'DisplayName','Mic2');
plot(t(1:200), real(mic_signals(1:200,3)), 'DisplayName','Mic3');
plot(t(1:200), real(mic_signals(1:200,4)), 'DisplayName','Mic4');
xlabel('Time (s)'); ylabel('Amplitude');
title('Simulated Synchronized 4-Channel Mic Acquisition');
legend show; grid on;

% MUSIC pseudo-spectrum
figure;
plotSpectrum(musicEstimator);
title('MUSIC Pseudo-Spectrum (2D) - ReSpeaker Quad Array');

% GCC-PHAT cross-correlation
figure;
plot(lags*1e3, abs(corr));
xlabel('Lag (ms)'); ylabel('GCC-PHAT Correlation');
title('GCC-PHAT Cross-Correlation (Vertical Mic Pair)');
grid on; hold on;
[~, peak_idx] = max(abs(corr));
plot(lags(peak_idx)*1e3, abs(corr(peak_idx)), 'ro', 'MarkerSize', 8, 'LineWidth', 1.5);
legend('GCC-PHAT', 'Peak (TDOA estimate)');

%% --- Summary Table for Presentation ---
Method      = {'MUSIC (Azimuth)'; 'MUSIC (Elevation)'; 'GCC-PHAT (Elevation)'};
TrueValue   = [az_true; el_true; el_true];
EstValue    = [az_est; el_est; angle_est_deg];
ErrorDeg    = abs(TrueValue - EstValue);

resultsTable = table(Method, TrueValue, EstValue, ErrorDeg)