%% MAIN - Acoustic DOA Localization Simulation
% Pipeline (matches the system architecture flowchart):
%   Audio Source --> Microphone Array --> Audio Acquisition & Noise
%   Filtering (Band-Pass + VAD) --> Feature Extraction (MUSIC, GCC-PHAT)
%   --> Estimated DOA Angle
%
%   1. Load array geometry                          (array_geometry.m)
%   2. Generate a synthetic "quiet - event - quiet" acoustic scene and
%      synchronized multichannel signals for a known true DOA
%   3. Band-pass filter + VAD                        (noise_filter.m)
%   4. Trim to the VAD-active region, then run:
%        - MUSIC DOA estimation (ReSpeaker 4-mic array)  (music_doa.m)
%        - GCC-PHAT TDOA/angle (vertical mic pair)        (gcc_phat.m)
%   5. Compare estimates against ground truth and visualize results
%
% Requires: Phased Array System Toolbox, Signal Processing Toolbox

clear; clc; close all;

%% --- Step 1: Load Array Geometry ---
geom = array_geometry();

%% --- Ground Truth Source Direction ---
az_true = 37;   % degrees
el_true = 40;   % degrees

az_rad = deg2rad(az_true);
el_rad = deg2rad(el_true);

% Unit vector pointing toward source (far-field plane wave assumption)
u = [cos(el_rad)*cos(az_rad);
     cos(el_rad)*sin(az_rad);
     sin(el_rad)];

%% --- Step 2: Simulate a "quiet - event - quiet" Acoustic Scene ---
duration = 1;                         % seconds
t  = (0:round(geom.fs*duration)-1)' / geom.fs;
N  = length(t);

event_start = 0.35;                     % seconds - abnormal acoustic event begins
event_end   = 0.65;                     % seconds - event ends

ambient_amp = 0.05;                     % background ambient noise level
event_amp   = 1.0;                      % event burst level

envelope = ambient_amp * ones(N,1);
envelope(t >= event_start & t <= event_end) = event_amp;

% Broadband source content (represents a generic abnormal acoustic event,
% e.g. an impact / shout / alarm - broadband rather than a pure tone so
% GCC-PHAT and the band-pass filter both have realistic content to work on)
rng(1);   % reproducible for presentation
source_signal = envelope .* randn(N,1);

%% --- Generate Synchronized ReSpeaker 4-Channel Signals (narrowband model) ---
% phased.MUSICEstimator2D expects a narrowband plane-wave signal generated
% via collectPlaneWave (phase-only steering at the operating frequency f0),
% not a broadband time-delayed signal - this matches MathWorks' own
% MUSICEstimator2D/MVDREstimator2D examples and is required for the
% estimator to detect the source.
sensor_SNR_dB = 20;
f0 = 1000;                             % source tone frequency (Hz) (used as target bin)[cite: 4]
x_clean = collectPlaneWave(geom.array, source_signal, [az_true; el_true], f0, geom.c);

mic_signals_raw = zeros(size(x_clean));
for i = 1:4
    mic_signals_raw(:,i) = awgn(x_clean(:,i), sensor_SNR_dB, 'measured');
end

%% --- Generate Synchronized Vertical Pair Signals ---
tau_vert = (geom.d_vert * sin(el_rad)) / geom.c;

mic_A_raw = awgn(source_signal, sensor_SNR_dB, 'measured');
mic_B_raw = awgn(delayseq(source_signal, tau_vert, geom.fs), sensor_SNR_dB, 'measured');

%% --- Step 3: Band-Pass Filter + VAD (noise_filter.m) ---
[mic_signals_f, vad_ura]  = noise_filter(mic_signals_raw, geom.fs);
[mic_vert_f,    vad_vert] = noise_filter([mic_A_raw mic_B_raw], geom.fs);

fprintf('--- VAD Detection (ReSpeaker array) ---\n');
fprintf('Active frames: %d / %d\n', numel(vad_ura.active_frames), numel(vad_ura.frame_mask));
fprintf('Active window: %.3f s - %.3f s (true event: %.3f - %.3f s)\n\n', ...
    (vad_ura.active_samples(1)-1)/geom.fs, (vad_ura.active_samples(2)-1)/geom.fs, ...
    event_start, event_end);

%% --- Step 4: Trim to VAD-Active Region ---
idxU = vad_ura.active_samples(1):vad_ura.active_samples(2);
idxV = vad_vert.active_samples(1):vad_vert.active_samples(2);

mic_signals_active = mic_signals_f(idxU, :);
mic_A = mic_vert_f(idxV, 1);
mic_B = mic_vert_f(idxV, 2);

%% --- Step 5a: MUSIC DOA Estimation (ReSpeaker Array) ---
f0 = 1000;   % target frequency bin, per architecture doc Step 5
[az_est, el_est, musicEstimator] = music_doa(mic_signals_active, geom, f0);

fprintf('--- MUSIC Estimation (ReSpeaker Quad Array) ---\n');
fprintf('True Azimuth   : %.2f deg | Estimated: %.2f deg\n', az_true, az_est);
fprintf('True Elevation : %.2f deg | Estimated: %.2f deg\n\n', el_true, el_est);

%% --- Step 5b: GCC-PHAT Estimation (Vertical Mic Pair) ---

%------------------------------





%-----------------------------

[tdoa_est, angle_est_deg, corr, lags] = gcc_phat(mic_A, mic_B, geom, geom.d_vert);


fprintf('--- GCC-PHAT Estimation (Vertical Mic Pair) ---\n');
fprintf('True TDOA      : %.6e s | Estimated: %.6e s\n', tau_vert, tdoa_est);
fprintf('True Elevation : %.2f deg | Estimated: %.2f deg\n\n', el_true, angle_est_deg);

%% --- Visualization ---

% Array geometry
figure;
viewArray(geom.array, 'ShowNormals', true, 'ShowIndex', 'All');
title('ReSpeaker Quad Mic Array Geometry');

% Raw vs band-pass filtered signal (Mic1), zoomed to the VAD-active region
margin = 0.03;   % seconds of padding around the detected active region
zoom_start = max(0,        (vad_ura.active_samples(1)-1)/geom.fs - margin);
zoom_end   = min(duration, (vad_ura.active_samples(2)-1)/geom.fs + margin);

figure;
subplot(2,1,1);
plot(t, mic_signals_raw(:,1));
xlabel('Time (s)'); ylabel('Amplitude'); grid on;
title('Raw Acquired Signal - Mic1 (zoomed to active region)');
xlim([zoom_start zoom_end]);
subplot(2,1,2);
plot(t, mic_signals_f(:,1));
xlabel('Time (s)'); ylabel('Amplitude'); grid on;
title('Band-Pass Filtered Signal - Mic1, 300-3400 Hz (zoomed to active region)');
xlim([zoom_start zoom_end]);

% Raw vs band-pass filtered signal (Mic1), zoomed to the VAD-active region
margin = 0.03;   % seconds of padding around the detected active region
zoom_start = max(0,        (vad_ura.active_samples(1)-1)/geom.fs - margin);
zoom_end   = min(duration, (vad_ura.active_samples(2)-1)/geom.fs + margin);

% Figure for raw acquired signal
figure;
plot(t, mic_signals_raw(:,1));
xlabel('Time (s)'); ylabel('Amplitude'); grid on;
title('Raw Acquired Signal - Mic1 (zoomed to active region)');
xlim([zoom_start zoom_end]);

% Separate figure for band-pass filtered signal
figure;
plot(t, mic_signals_f(:,1));
xlabel('Time (s)'); ylabel('Amplitude'); grid on;
title('Band-Pass Filtered Signal - Mic1, 300-3400 Hz (zoomed to active region)');
xlim([zoom_start zoom_end]);


% Band-pass filter frequency response
figure;
freqz(vad_ura.filter_b, vad_ura.filter_a, 2048, geom.fs);
title('Band-Pass Filter Frequency Response');

% VAD: frame energy vs threshold, with detected active region
figure;
plot(vad_ura.frame_times, 10*log10(vad_ura.frame_energy), 'b'); hold on;
thr_val = max(real(vad_ura.threshold), eps);   % ensure real and positive
thr_db  = 10*log10(thr_val);
yline(thr_db, 'r--', 'Threshold');
xline(event_start, 'g--', 'True event start');
xline(event_end,   'g--', 'True event end');
active = vad_ura.frame_mask;
plot(vad_ura.frame_times(active), 10*log10(vad_ura.frame_energy(active)), 'ro', 'MarkerSize', 4);
xlabel('Time (s)'); ylabel('Frame Energy (dB)');
title('VAD: Short-Term Energy and Detected Active Frames');
legend('Frame energy', 'Threshold', 'True event start', 'True event end', 'Detected active', 'Location', 'best');
grid on;

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
Method    = {'MUSIC (Azimuth)'; 'MUSIC (Elevation)'; 'GCC-PHAT (Elevation)'};
TrueValue = [az_true; el_true; el_true];
EstValue  = [az_est; el_est; angle_est_deg];
ErrorDeg  = abs(TrueValue - EstValue);

resultsTable = table(Method, TrueValue, EstValue, ErrorDeg)


%% --- Multi Ground-Truth Comparison Table ---
% Re-runs the SAME acquisition -> filtering -> VAD -> trimming ->
% MUSIC + GCC-PHAT pipeline used in the single-case experiment.
%
% IMPORTANT:
% The ReSpeaker microphone signals are generated using collectPlaneWave(),
% exactly as in the main single-case pipeline.
%
% Therefore:
%
%     mic_active
%
% inside run_doa_case() is processed in exactly the same way as the
% mic_signals_active variable in the main experiment.

test_cases = [ ...
     0    0;      % broadside
    30   10;
   -45   20;
    60  -15;
    15   35];

% Same parameters as the main experiment
params.duration      = duration;
params.event_start   = event_start;
params.event_end     = event_end;
params.ambient_amp   = ambient_amp;
params.event_amp     = event_amp;
params.sensor_SNR_dB = sensor_SNR_dB;
params.f0            = f0;

num_cases = size(test_cases, 1);

% Preallocate
AzTrue      = zeros(num_cases,1);
ElTrue      = zeros(num_cases,1);

AzEstMUSIC  = zeros(num_cases,1);
ElEstMUSIC  = zeros(num_cases,1);
ElEstGCC    = zeros(num_cases,1);

AzErrMUSIC  = zeros(num_cases,1);
ElErrMUSIC  = zeros(num_cases,1);
ElErrGCC    = zeros(num_cases,1);

% Separate reproducible random sequence for the sweep
rng(2);

for c = 1:num_cases

    fprintf('\n============================================\n');
    fprintf('Test Case %d / %d\n', c, num_cases);
    fprintf('True Azimuth   = %.2f deg\n', test_cases(c,1));
    fprintf('True Elevation = %.2f deg\n', test_cases(c,2));
    fprintf('============================================\n');

    r = run_doa_case( ...
        test_cases(c,1), ...
        test_cases(c,2), ...
        geom, ...
        params);

    % Store results
    AzTrue(c)      = r.az_true;
    ElTrue(c)      = r.el_true;

    AzEstMUSIC(c)  = r.az_est;
    ElEstMUSIC(c)  = r.el_est;
    ElEstGCC(c)    = r.gcc_angle_est;

    AzErrMUSIC(c)  = r.az_error;
    ElErrMUSIC(c)  = r.el_error_music;
    ElErrGCC(c)    = r.el_error_gcc;

    fprintf('MUSIC Azimuth   = %.2f deg | Error = %.2f deg\n', ...
        r.az_est, r.az_error);

    fprintf('MUSIC Elevation = %.2f deg | Error = %.2f deg\n', ...
        r.el_est, r.el_error_music);

    fprintf('GCC Elevation   = %.2f deg | Error = %.2f deg\n', ...
        r.gcc_angle_est, r.el_error_gcc);
end


%% --- Comparison Table ---

comparisonTable = table( ...
    AzTrue, ...
    ElTrue, ...
    AzEstMUSIC, ...
    ElEstMUSIC, ...
    AzErrMUSIC, ...
    ElErrMUSIC, ...
    ElEstGCC, ...
    ElErrGCC);

disp(' ');
disp('==============================================================');
disp('          MULTI GROUND-TRUTH DOA COMPARISON');
disp('==============================================================');

disp(comparisonTable);


%% --- Bar Chart of Estimation Errors ---

figure;

bar([AzErrMUSIC, ElErrMUSIC, ElErrGCC]);

set(gca, ...
    'XTick', 1:num_cases, ...
    'XTickLabel', arrayfun( ...
        @(c) sprintf('Az %d, El %d', ...
        test_cases(c,1), test_cases(c,2)), ...
        1:num_cases, ...
        'UniformOutput', false));

xtickangle(30);

xlabel('Ground-Truth Direction');
ylabel('Absolute Error (deg)');

legend( ...
    'MUSIC Azimuth Error', ...
    'MUSIC Elevation Error', ...
    'GCC-PHAT Elevation Error', ...
    'Location', 'best');

title('DOA Estimation Error Across Different Ground-Truth Directions');

grid on;


%% ======================= LOCAL FUNCTIONS ============================
%
% MATLAB requires local functions in a script to appear after all
% script-level commands.
%

function results = run_doa_case(az_true, el_true, geom, params)

% RUN_DOA_CASE
%
% Runs EXACTLY the same signal-processing pipeline as the main
% single-ground-truth experiment:
%
%   Source generation
%       ↓
%   collectPlaneWave()
%       ↓
%   AWGN
%       ↓
%   Band-pass filtering + VAD
%       ↓
%   VAD active-region trimming
%       ↓
%   mic_active
%       ↓
%   MUSIC
%
% In parallel:
%
%   Source
%       ↓
%   Vertical microphone pair
%       ↓
%   Band-pass filtering + VAD
%       ↓
%   VAD active-region trimming
%       ↓
%   GCC-PHAT


%% ---------------------------------------------------------------
% 1. Ground-truth direction
% ---------------------------------------------------------------

az_rad = deg2rad(az_true);
el_rad = deg2rad(el_true);

% Unit vector toward source
u = [ ...
    cos(el_rad)*cos(az_rad);
    cos(el_rad)*sin(az_rad);
    sin(el_rad)];


%% ---------------------------------------------------------------
% 2. Generate the SAME source signal as the main file
% ---------------------------------------------------------------

t = (0:round(geom.fs*params.duration)-1)' / geom.fs;

N = length(t);

% Quiet-event-quiet envelope
envelope = params.ambient_amp * ones(N,1);

envelope( ...
    t >= params.event_start & ...
    t <= params.event_end) = params.event_amp;

% Broadband source
src = envelope .* randn(N,1);


%% ---------------------------------------------------------------
% 3. ReSpeaker 4-channel acquisition
% ---------------------------------------------------------------
%
% THIS IS THE IMPORTANT CORRECTION.
%
% The original main file uses:
%
% x_clean = collectPlaneWave(...)
%
% Therefore the multi-case function MUST use exactly the same method.
%
% Do NOT use delayseq() for the ReSpeaker array here.
%

x_clean = collectPlaneWave( ...
    geom.array, ...
    src, ...
    [az_true; el_true], ...
    params.f0, ...
    geom.c);


%% ---------------------------------------------------------------
% 4. Add sensor noise exactly as in the main file
% ---------------------------------------------------------------

mic_signals_raw = zeros(size(x_clean));

for i = 1:4

    mic_signals_raw(:,i) = awgn( ...
        x_clean(:,i), ...
        params.sensor_SNR_dB, ...
        'measured');

end


%% ---------------------------------------------------------------
% 5. Generate vertical microphone pair
% ---------------------------------------------------------------
%
% This is also kept consistent with the main file.

tau_vert = ...
    (geom.d_vert * sin(el_rad)) / geom.c;

mic_A_raw = awgn( ...
    src, ...
    params.sensor_SNR_dB, ...
    'measured');

mic_B_raw = awgn( ...
    delayseq(src, tau_vert, geom.fs), ...
    params.sensor_SNR_dB, ...
    'measured');


%% ---------------------------------------------------------------
% 6. Band-pass filter + VAD
% ---------------------------------------------------------------
%
% EXACTLY the same function calls as the main file.

[mic_signals_f, vad_ura] = ...
    noise_filter(mic_signals_raw, geom.fs);

[mic_vert_f, vad_vert] = ...
    noise_filter([mic_A_raw mic_B_raw], geom.fs);


%% ---------------------------------------------------------------
% 7. Trim using VAD
% ---------------------------------------------------------------
%
% EXACTLY the same indexing method as the main file.

idxU = ...
    vad_ura.active_samples(1): ...
    vad_ura.active_samples(2);

idxV = ...
    vad_vert.active_samples(1): ...
    vad_vert.active_samples(2);


%% ---------------------------------------------------------------
% 8. Create mic_active
% ---------------------------------------------------------------
%
% This is IDENTICAL to:
%
% mic_signals_active = mic_signals_f(idxU, :);
%
% in the main file.

mic_active = mic_signals_f(idxU, :);


%% ---------------------------------------------------------------
% 9. Vertical pair after VAD
% ---------------------------------------------------------------

mic_A = mic_vert_f(idxV, 1);
mic_B = mic_vert_f(idxV, 2);


%% ---------------------------------------------------------------
% 10. MUSIC DOA estimation
% ---------------------------------------------------------------

[az_est, el_est, ~] = ...
    music_doa( ...
        mic_active, ...
        geom, ...
        params.f0);


%% ---------------------------------------------------------------
% 11. GCC-PHAT estimation
% ---------------------------------------------------------------

[~, gcc_angle_est, ~, ~] = ...
    gcc_phat( ...
        mic_A, ...
        mic_B, ...
        geom, ...
        geom.d_vert);


%% ---------------------------------------------------------------
% 12. Calculate errors
% ---------------------------------------------------------------

results.az_true = az_true;

results.el_true = el_true;

results.az_est = az_est;

results.el_est = el_est;

results.gcc_angle_est = gcc_angle_est;

results.az_error = ...
    abs(az_true - az_est);

results.el_error_music = ...
    abs(el_true - el_est);

results.el_error_gcc = ...
    abs(el_true - gcc_angle_est);

end