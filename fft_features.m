function feat = fft_features(signal, fs)
% FFT_FEATURES  Computes basic frequency-domain features from a single
%               time-domain signal via FFT.
%               (Architecture doc block D5: "FFT Features")
%
%   feat = FFT_FEATURES(signal, fs)
%
%   Input:
%       signal - N x 1 time-domain signal (single channel; for a
%                multichannel matrix, pass one reference column, e.g.
%                mean(mic_signals_active, 2) or a specific mic channel)
%       fs     - sampling frequency (Hz)
%
%   Output: struct `feat` with fields:
%       .freq_axis  - frequency bins from 0 to fs/2 (Hz)
%       .magnitude  - single-sided FFT magnitude spectrum at those bins
%       .peak_freq  - frequency (Hz) of the largest magnitude bin
%       .peak_mag   - magnitude at that peak
%       .centroid   - spectral centroid (Hz): the "center of mass" of
%                     the magnitude spectrum, i.e. sum(f.*|X(f)|)/sum(|X(f)|)

    signal = signal(:);
    N = length(signal);

    X = abs(fft(signal));
    half_N = floor(N/2) + 1;
    X = X(1:half_N);
    f = (0:half_N-1)' * (fs / N);

    [peak_mag, peak_idx] = max(X);
    peak_freq = f(peak_idx);

    centroid = sum(f .* X) / max(sum(X), eps);

    feat.freq_axis = f;
    feat.magnitude = X;
    feat.peak_freq = peak_freq;
    feat.peak_mag  = peak_mag;
    feat.centroid  = centroid;

end
