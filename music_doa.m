function [az_est, el_est, musicEstimator] = music_doa(mic_signals, geom, freq)
% MUSIC_DOA  Estimates Direction of Arrival using phased.MUSICEstimator2D
%            on the 4-channel ReSpeaker Quad microphone array.

if nargin < 3
    freq = 1000;   % default single dominant frequency bin
end

%% --- Configure MUSIC Estimator ---
musicEstimator = phased.MUSICEstimator2D( ...
    'SensorArray', geom.array, ...
    'OperatingFrequency', freq, ...
    'PropagationSpeed', geom.c, ...
    'DOAOutputPort', true, ...
    'NumSignalsSource', 'Property', ...
    'NumSignals', 1, ...
    'AzimuthScanAngles', -90:1:90, ...
    'ElevationScanAngles', -45:1:45);

%% --- Extract Narrowband Complex Snapshots via STFT ---
N = size(mic_signals, 1);
winlen = 1024;
hop = 512;
w = hann(winlen, 'periodic');
Nfft = winlen;

% Pre-allocate snapshot matrix (4 x NumFrames)
num_frames = floor((N - winlen) / hop) + 1;
snapshots = zeros(4, num_frames);

% Find closest frequency bin to the target frequency
f_axis = (0:Nfft-1) * (geom.fs / Nfft);
[~, b] = min(abs(f_axis - freq));

% Populate snapshot matrix
for k = 1:num_frames
    start_idx = (k-1)*hop + 1;
    frame = mic_signals(start_idx : start_idx+winlen-1, :) .* w;
    Xf = fft(frame, Nfft, 1);               % Nfft x 4
    snapshots(:, k) = Xf(b, :).';           % 4 x 1 snapshot per frame
end

%% --- Run MUSIC Estimation ---
[~, doas] = musicEstimator(snapshots.');

az_est = doas(1);
el_est = -doas(2);

end